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

const band_edges = [BAND_COUNT + 1]usize{ 2, 5, 12, 30, 75, 186, 372, 558 };

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

fn onProcess(user_data: ?*anyopaque) callconv(.c) void {
    _ = user_data;
    const stream = pw_stream orelse return;
    const buf = pw_stream_dequeue_buffer(stream) orelse return;
    defer _ = pw_stream_queue_buffer(stream, buf);

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
    _ = pw_main_loop_run(loop);
    running.store(false, .release);
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
