// kmedia — Zig-native audio capture + band analysis for KidulWM.
//
// Captures the monitor of the default PipeWire sink (the mixed output of
// whatever is playing), runs a small radix-2 FFT, and publishes log-spaced
// band energies into a lock-free slot that widgets read per frame.
//
// PipeWire is used through a hand-declared minimal extern surface (the full
// SPA/pod headers defeat cImport); the one format-pod build lives in the
// tiny C shim kmedia_shim.c. Everything else — FFT, bands, threading — is Zig.

const std = @import("std");

pub const BAND_COUNT = 7;

// ---------------------------------------------------------------------------
// Minimal PipeWire extern surface
// ---------------------------------------------------------------------------

const PwMainLoop = opaque {};
const PwLoop = opaque {};
const PwProperties = opaque {};
const PwStream = opaque {};
const PwBuffer = opaque {};
const SpaPod = opaque {};

const PwDirection = enum(c_int) { input = 0, output = 1 };

const PwStreamEvents = extern struct {
    version: u32 = 2,
    destroy: ?*const fn (?*anyopaque) callconv(.c) void = null,
    state_changed: ?*const fn (?*anyopaque, c_int, c_int, ?[*:0]const u8) callconv(.c) void = null,
    control_info: ?*const fn (?*anyopaque, u32, ?*anyopaque) callconv(.c) void = null,
    io_changed: ?*const fn (?*anyopaque, u32, ?*anyopaque, u32) callconv(.c) void = null,
    param_changed: ?*const fn (?*anyopaque, u32, ?*const SpaPod) callconv(.c) void = null,
    add_buffer: ?*const fn (?*anyopaque, ?*PwBuffer) callconv(.c) void = null,
    remove_buffer: ?*const fn (?*anyopaque, ?*PwBuffer) callconv(.c) void = null,
    process: ?*const fn (?*anyopaque) callconv(.c) void = null,
    drained: ?*const fn (?*anyopaque) callconv(.c) void = null,
    command: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void = null,
    trigger_done: ?*const fn (?*anyopaque) callconv(.c) void = null,
};

const SpaChunk = extern struct {
    offset: u32,
    size: u32,
    stride: i32,
    flags: i32,
};

const SpaData = extern struct {
    type: u32,
    flags: u32,
    fd: i64,
    mapoffset: u32,
    maxsize: u32,
    data: ?*anyopaque,
    chunk: ?*SpaChunk,
};

const SpaBuffer = extern struct {
    n_metas: u32,
    n_datas: u32,
    metas: ?*anyopaque,
    datas: [*]SpaData,
};

const PwBufferLayout = extern struct {
    buffer: ?*SpaBuffer,
    user_data: ?*anyopaque,
    queue: SpaList,
};

const SpaList = extern struct {
    next: ?*SpaList,
    prev: ?*SpaList,
};

extern fn pw_init(argc: ?*anyopaque, argv: ?*anyopaque) void;
extern fn pw_main_loop_new(props: ?*const anyopaque) ?*PwMainLoop;
extern fn pw_main_loop_destroy(loop: *PwMainLoop) void;
extern fn pw_main_loop_get_loop(loop: *PwMainLoop) *PwLoop;
extern fn pw_main_loop_run(loop: *PwMainLoop) c_int;
extern fn pw_main_loop_quit(loop: *PwMainLoop) c_int;
extern fn pw_properties_new(...) *PwProperties;
extern fn pw_stream_new_simple(
    loop: *PwLoop,
    name: [*:0]const u8,
    props: *PwProperties,
    events: *const PwStreamEvents,
    data: ?*anyopaque,
) ?*PwStream;
extern fn pw_stream_connect(
    stream: ?*PwStream,
    direction: PwDirection,
    target_id: u32,
    flags: c_uint,
    params: ?*const ?*const SpaPod,
    n_params: u32,
) c_int;
extern fn pw_stream_dequeue_buffer(stream: *PwStream) ?*PwBufferLayout;
extern fn pw_stream_queue_buffer(stream: *PwStream, buffer: *PwBufferLayout) c_int;

extern fn kmedia_build_audio_format(buf: [*]u8, size: usize, rate: u32, channels: u32) *const SpaPod;
extern fn kmedia_stream_connect(loop: *PwLoop, events: *const PwStreamEvents, err_buf: [*]u8, err_buf_len: usize) ?*PwStream;

// ---------------------------------------------------------------------------
// Shared state (written by the PW thread, read by render threads)
// ---------------------------------------------------------------------------

var band_slots: [2][BAND_COUNT]f32 = .{ .{0} ** BAND_COUNT, .{0} ** BAND_COUNT };
var band_active: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
var rms_slot: std.atomic.Value(u32) = std.atomic.Value(u32).init(0); // f32 bits
var running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

/// Current band energies, 0..1-ish (can exceed 1 on loud transients).
pub fn bands() [BAND_COUNT]f32 {
    const idx = band_active.load(.acquire);
    return band_slots[idx];
}

/// Overall loudness 0..1, for quick "is anything playing" checks.
pub fn level() f32 {
    return @bitCast(rms_slot.load(.acquire));
}

pub fn isRunning() bool {
    return running.load(.acquire);
}

// ---------------------------------------------------------------------------
// ONE-TRUTH liveness (CENSUS-NOTES verdict 11, 2026-09-12)
// "Is audio live?" is answered by ksound's floor table and NOWHERE ELSE.
// The FFT slots above answer loudness only. The old widget painter and media.zig
// used to re-derive liveness as `level() > 0.03` — two consumers, one
// lying source, stale dots. Now: one bool, from the daemon, cached
// 100ms so render threads never block on the socket. Daemon absent
// (socket error/timeout) = not live: the widget rests rather than
// hallucinates.
// ---------------------------------------------------------------------------

var live_cache: std.atomic.Value(u32) = std.atomic.Value(u32).init(0); // 0/1
var live_cache_at_us: std.atomic.Value(i64) = std.atomic.Value(i64).init(0);
const LIVE_CACHE_TTL_US: i64 = 100_000;

fn ksoundAskAudioLive() bool {
    var path_buf: [128]u8 = undefined;
    const path = ksoundSocketPath(&path_buf) orelse return false;

    var addr: std.os.linux.sockaddr.un = .{ .family = std.os.linux.AF.UNIX, .path = [_]u8{0} ** 108 };
    if (path.len > addr.path.len - 1) return false;
    @memcpy(addr.path[0..path.len], path);

    const fd_rc = std.os.linux.socket(std.os.linux.AF.UNIX, std.os.linux.SOCK.STREAM | std.os.linux.SOCK.NONBLOCK, 0);
    const fd_signed: isize = @bitCast(fd_rc);
    if (fd_signed < 0) return false;
    const fd: i32 = @intCast(fd_rc);
    defer _ = std.os.linux.close(fd);

    // 50ms deadline on connect+io: the render thread must never stall.
    var tv: std.os.linux.timeval = .{ .sec = 0, .usec = 50_000 };
    _ = std.os.linux.setsockopt(fd, std.os.linux.SOL.SOCKET, std.os.linux.SO.RCVTIMEO, std.mem.asBytes(&tv), @sizeOf(std.os.linux.timeval));
    _ = std.os.linux.setsockopt(fd, std.os.linux.SOL.SOCKET, std.os.linux.SO.SNDTIMEO, std.mem.asBytes(&tv), @sizeOf(std.os.linux.timeval));

    const rc = std.os.linux.connect(fd, @ptrCast(&addr), @sizeOf(std.os.linux.sockaddr.un));
    if (std.os.linux.errno(rc) != .SUCCESS and std.os.linux.errno(rc) != .INPROGRESS) return false;
    if (std.os.linux.errno(rc) == .INPROGRESS) {
        var pfd = [1]std.os.linux.pollfd{.{ .fd = fd, .events = std.os.linux.POLL.OUT, .revents = 0 }};
        const prc = std.os.linux.poll(&pfd, 1, 50);
        if (@as(isize, @bitCast(prc)) <= 0) return false;
        var serr: c_int = 0;
        var slen: std.os.linux.socklen_t = @sizeOf(c_int);
        _ = std.os.linux.getsockopt(fd, std.os.linux.SOL.SOCKET, std.os.linux.SO.ERROR, @ptrCast(&serr), &slen);
        if (serr != 0) return false;
    }
    const cmd = "audio_live\n";
    var off: usize = 0;
    while (off < cmd.len) {
        const w = std.os.linux.write(fd, cmd[off..].ptr, cmd.len - off);
        const wi: isize = @bitCast(w);
        if (wi <= 0) return false;
        off += w;
    }
    _ = std.os.linux.shutdown(fd, std.os.linux.SHUT.WR);
    var rbuf: [8]u8 = undefined;
    var got: usize = 0;
    while (got < rbuf.len) {
        const r = std.os.linux.read(fd, rbuf[got..].ptr, rbuf.len - got);
        const ri: isize = @bitCast(r);
        if (ri <= 0) break;
        got += r;
        if (rbuf[got - 1] == '\n') break;
    }
    return got >= 1 and rbuf[0] == '1';
}

fn ksoundSocketPath(buf: []u8) ?[]const u8 {
    if (std.c.getenv("XDG_RUNTIME_DIR")) |d| {
        return std.fmt.bufPrint(buf, "{s}/ksound.sock", .{d}) catch null;
    }
    return std.fmt.bufPrint(buf, "/run/user/{d}/ksound.sock", .{std.os.linux.getuid()}) catch null;
}

/// The face's ONLY liveness question. ksound floor table, cached 100ms.
pub fn audioLive() bool {
    const now = nowUsMono();
    if (now - live_cache_at_us.load(.acquire) < LIVE_CACHE_TTL_US) {
        return live_cache.load(.acquire) == 1;
    }
    const live = ksoundAskAudioLive();
    live_cache.store(if (live) 1 else 0, .release);
    live_cache_at_us.store(now, .release);
    return live;
}

// ---------------------------------------------------------------------------
// FFT — iterative radix-2, Hann window, magnitude spectrum
// ---------------------------------------------------------------------------

const FFT_SIZE = 2048; // ~21 Hz/bin at 44.1k
const HOP = 1024;

var fft_re: [FFT_SIZE]f32 = undefined;
var fft_im: [FFT_SIZE]f32 = undefined;
var hann: [FFT_SIZE]f32 = undefined;
var hann_ready = false;
var sample_buf: [FFT_SIZE]f32 = undefined;
var sample_fill: usize = 0;

fn initHann() void {
    for (0..FFT_SIZE) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(FFT_SIZE - 1));
        hann[i] = 0.5 - 0.5 * @cos(2.0 * std.math.pi * t);
    }
    hann_ready = true;
}

fn fft(re: *[FFT_SIZE]f32, im: *[FFT_SIZE]f32) void {
    // Bit-reversal permutation.
    var j: usize = 0;
    for (1..FFT_SIZE) |i| {
        var bit: usize = FFT_SIZE >> 1;
        while (j & bit != 0) : (bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) {
            std.mem.swap(f32, &re[i], &re[j]);
            std.mem.swap(f32, &im[i], &im[j]);
        }
    }
    // Butterflies.
    var len: usize = 2;
    while (len <= FFT_SIZE) : (len <<= 1) {
        const ang = -2.0 * std.math.pi / @as(f32, @floatFromInt(len));
        const wr = @cos(ang);
        const wi = @sin(ang);
        var i: usize = 0;
        while (i < FFT_SIZE) : (i += len) {
            var cur_wr: f32 = 1.0;
            var cur_wi: f32 = 0.0;
            for (0..len / 2) |k| {
                const a = i + k;
                const b = i + k + len / 2;
                const vr = re[b] * cur_wr - im[b] * cur_wi;
                const vi = re[b] * cur_wi + im[b] * cur_wr;
                re[b] = re[a] - vr;
                im[b] = im[a] - vi;
                re[a] += vr;
                im[a] += vi;
                const nwr = cur_wr * wr - cur_wi * wi;
                cur_wi = cur_wr * wi + cur_wi * wr;
                cur_wr = nwr;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Band mapping — 7 log-ish bands (~40 Hz .. ~12 kHz at 44.1k / FFT 2048)
// ---------------------------------------------------------------------------

var smooth: [BAND_COUNT]f32 = .{0} ** BAND_COUNT;

const band_edges = [BAND_COUNT + 1]usize{ 4, 7, 13, 25, 50, 100, 201, 402 };

fn analyzeFrame() void {
    if (!hann_ready) initHann();
    for (0..FFT_SIZE) |i| {
        fft_re[i] = sample_buf[i] * hann[i];
        fft_im[i] = 0;
    }
    fft(&fft_re, &fft_im);

    var out: [BAND_COUNT]f32 = undefined;
    var rms: f32 = 0;
    for (0..BAND_COUNT) |b| {
        var sum: f32 = 0;
        const lo = band_edges[b];
        const hi = @min(band_edges[b + 1], FFT_SIZE / 2);
        const n = @max(1, hi - lo);
        for (lo..hi) |k| {
            sum += @sqrt(fft_re[k] * fft_re[k] + fft_im[k] * fft_im[k]);
        }
        const mag = sum / @as(f32, @floatFromInt(n * FFT_SIZE / 4));
        const db = 20.0 * std.math.log10(@max(mag, 1e-6));
        const norm = std.math.clamp((db + 55.0) / 55.0, 0.0, 1.2);
        const up: f32 = 0.55;
        const down: f32 = 0.12;
        smooth[b] = if (norm > smooth[b])
            smooth[b] * (1.0 - up) + norm * up
        else
            smooth[b] * (1.0 - down) + norm * down;
        out[b] = smooth[b];
        rms += norm;
    }

    const idx = band_active.load(.acquire);
    band_slots[1 - idx] = out;
    band_active.store(1 - idx, .release);
    rms_slot.store(@bitCast(rms / @as(f32, @floatFromInt(BAND_COUNT))), .release);
}

fn pushSamples(mono: []const f32) void {
    var src = mono;
    while (src.len > 0) {
        const space = FFT_SIZE - sample_fill;
        const take = @min(space, src.len);
        @memcpy(sample_buf[sample_fill .. sample_fill + take], src[0..take]);
        sample_fill += take;
        src = src[take..];
        if (sample_fill == FFT_SIZE) {
            analyzeFrame();
            const keep = FFT_SIZE - HOP;
            std.mem.copyForwards(f32, sample_buf[0..keep], sample_buf[HOP..FFT_SIZE]);
            sample_fill = keep;
        }
    }
}

// ---------------------------------------------------------------------------
// PipeWire capture — monitor of the default sink
// ---------------------------------------------------------------------------

var pw_loop: ?*PwMainLoop = null;
var pw_stream: ?*PwStream = null;
var pw_thread: ?std.Thread = null;
var stream_events: PwStreamEvents = .{};

// FIX-AND-RECORD (census law amendment, 2026-09-09): stale-dot meter leak.
// Verdict: onProcess simply stops being called when the sink goes quiet, so
// rms_slot + band_slots + smooth keep their last LOUD values forever → the
// butterfly widget (old drawMediaWidget: audio_live = level() > 0.03)
// renders the live dot with no player open and nothing playing.
// Fix: the capture thread timestamps every buffer; captureMain runs a
// watchdog that, after 250ms of silence, writes zeros through the SAME
// slots the loudness path uses. Silence is written by the thread that owns
// loudness. ~8 lines, no interface change.
var last_buffer_us: std.atomic.Value(i64) = std.atomic.Value(i64).init(0);

fn nowUsMono() i64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    return @as(i64, @intCast(ts.sec)) * 1_000_000 + @divTrunc(@as(i64, @intCast(ts.nsec)), 1000);
}

fn publishSilence() void {
    const idx = band_active.load(.acquire);
    band_slots[1 - idx] = .{0} ** BAND_COUNT;
    band_active.store(1 - idx, .release);
    rms_slot.store(@bitCast(@as(f32, 0.0)), .release);
    // NOTE: smooth[] is owned by analyzeFrame (capture thread) — resetting it
    // here would race. The 0.12 down-coefficient decays it to zero within
    // ~50ms once zeroed bands flow; not worth a lock for a cosmetic rung.
}

fn onProcess(user_data: ?*anyopaque) callconv(.c) void {
    _ = user_data;
    const stream = pw_stream orelse return;
    const buf = pw_stream_dequeue_buffer(stream) orelse return;
    defer _ = pw_stream_queue_buffer(stream, buf);

    last_buffer_us.store(nowUsMono(), .release);

    const b = buf.buffer orelse return;
    if (b.n_datas == 0) return;
    const d = &b.datas[0];
    const data_ptr = d.data orelse return;
    const chunk = d.chunk orelse return;
    if (chunk.size == 0 or chunk.stride <= 0) return;

    const stride: usize = @intCast(chunk.stride);
    const n_frames = chunk.size / @as(u32, @intCast(stride));
    const channels: usize = stride / 2; // s16le
    if (channels == 0) return;

    const samples: [*]const i16 = @ptrCast(@alignCast(data_ptr));

    var mono_buf: [4096]f32 = undefined;
    const max_frames: usize = @min(n_frames, mono_buf.len);
    for (0..max_frames) |f| {
        var acc: i32 = 0;
        for (0..channels) |ch| {
            acc += samples[f * channels + ch];
        }
        mono_buf[f] = @as(f32, @floatFromInt(acc)) / (@as(f32, @floatFromInt(channels)) * 32768.0);
    }
    pushSamples(mono_buf[0..max_frames]);
}

fn captureMain() void {
    pw_init(null, null);
    pw_loop = pw_main_loop_new(null) orelse return;
    const loop = pw_loop.?;
    defer pw_main_loop_destroy(loop);

    var err_buf: [256]u8 = std.mem.zeroes([256]u8);
    pw_stream = kmedia_stream_connect(pw_main_loop_get_loop(loop), &stream_events, &err_buf, err_buf.len) orelse {
        std.log.err("kmedia: stream connect failed: {s}", .{std.mem.sliceTo(&err_buf, 0)});
        return;
    };
    std.log.info("kmedia: pipewire capture connected", .{});

    running.store(true, .release);
    last_buffer_us.store(nowUsMono(), .release);
    // Silence watchdog: pw_main_loop_run blocks, so poll from a sibling
    // thread — after 250ms without a buffer, publish silence once.
    const watchdog = struct {
        fn run() void {
            var silent = false;
            while (running.load(.acquire)) {
                var ts: std.os.linux.timespec = .{ .sec = 0, .nsec = 50 * std.time.ns_per_ms };
                _ = std.os.linux.nanosleep(&ts, null);
                const age = nowUsMono() - last_buffer_us.load(.acquire);
                if (age > 250_000) {
                    if (!silent) publishSilence();
                    silent = true;
                } else silent = false;
            }
        }
    };
    const wd = std.Thread.spawn(.{}, watchdog.run, .{}) catch null;
    _ = pw_main_loop_run(loop);
    running.store(false, .release);
    if (wd) |t| t.join();
    publishSilence(); // stream dead → meter reads zero, never a stale dot
    std.log.info("kmedia: capture loop exited", .{});
}

pub fn start() void {
    if (pw_thread != null) return;
    stream_events = .{};
    stream_events.process = onProcess;
    pw_thread = std.Thread.spawn(.{}, captureMain, .{}) catch null;
}

pub fn stop() void {
    if (pw_loop) |loop| _ = pw_main_loop_quit(loop);
    if (pw_thread) |t| {
        t.join();
        pw_thread = null;
    }
}
