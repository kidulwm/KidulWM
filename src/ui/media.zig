const std = @import("std");
const c = @import("dm").c;
const style = @import("../core/style.zig");

const unistd = @cImport({
    @cInclude("unistd.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("fcntl.h");
    @cInclude("time.h");
});

const c_posix = std.posix;
const c_linux = std.os.linux;

pub const MediaState = struct {
    available: bool = false,
    playing: bool = false,
    position: f64 = 0,
    duration: f64 = 0,
    title: [64:0]u8 = std.mem.zeroes([64:0]u8),
    artist: [64:0]u8 = std.mem.zeroes([64:0]u8),
    album: [64:0]u8 = std.mem.zeroes([64:0]u8),
};

pub const MediaCard = struct {
    open: bool = false,

    pub fn toggle(self: *MediaCard) void {
        self.open = !self.open;
    }
};

pub const ControlFocus = enum { prev, play, next, search };

pub const MediaWidget = struct {
    allocator: std.mem.Allocator,
    card: MediaCard = .{},
    ipc_path: [128:0]u8 = std.mem.zeroes([128:0]u8),
    mpv_pid: ?i32 = null,
    last_poll_us: u64 = 0,
    poll_fail_count: u32 = 0,
    cached: MediaState = .{},
    helix_phase: f64 = 0,
    last_energy: f64 = 0,
    last_helix_us: u64 = 0,

    focus: ControlFocus = .play,
    search_buf: [128:0]u8 = std.mem.zeroes([128:0]u8),
    search_len: usize = 0,
    search_focused: bool = false,
    search_caret: usize = 0,
    last_caret_blink_us: u64 = 0,
    show_caret: bool = true,

    pub fn init(allocator: std.mem.Allocator) MediaWidget {
        const ipc = "/run/user/1000/kidulwm-mpv.sock";
        var self = MediaWidget{ .allocator = allocator };
        @memcpy(self.ipc_path[0..ipc.len], ipc);
        self.ipc_path[ipc.len] = 0;
        return self;
    }

    pub fn deinit(self: *MediaWidget) void {
        self.ensureStopped();
    }

    pub fn toggleCard(self: *MediaWidget) void {
        self.card.toggle();
        if (self.card.open) {
            self.focus = .play;
            self.search_focused = false;
        }
    }

    pub fn setCardOpen(self: *MediaWidget, open: bool) void {
        self.card.open = open;
        if (open) {
            self.focus = .play;
            self.search_focused = false;
        }
    }

    pub fn isCardOpen(self: *const MediaWidget) bool {
        return self.card.open;
    }

    pub fn focusControl(self: *MediaWidget, ctl: ControlFocus) void {
        self.focus = ctl;
        self.search_focused = ctl == .search;
        if (self.search_focused) {
            self.search_caret = self.search_len;
        }
    }

    pub fn moveFocus(self: *MediaWidget, delta: i32) void {
        const order = [_]ControlFocus{ .prev, .play, .next, .search };
        var idx: i32 = 1;
        for (order, 0..) |o, i| {
            if (o == self.focus) {
                idx = @intCast(i);
                break;
            }
        }
        idx = @mod(idx + delta, @as(i32, @intCast(order.len)));
        self.focusControl(order[@intCast(idx)]);
    }

    pub fn focusSearch(self: *MediaWidget) void {
        self.focusControl(.search);
    }

    pub fn clearSearch(self: *MediaWidget) void {
        @memset(&self.search_buf, 0);
        self.search_len = 0;
        self.search_caret = 0;
    }

    pub fn appendSearch(self: *MediaWidget, ch: u8) void {
        if (self.search_len >= self.search_buf.len - 1) return;
        if (self.search_caret < self.search_len) {
            var i: usize = self.search_len;
            while (i > self.search_caret) : (i -= 1) {
                self.search_buf[i] = self.search_buf[i - 1];
            }
        }
        self.search_buf[self.search_caret] = ch;
        self.search_caret += 1;
        self.search_len += 1;
        self.search_buf[self.search_len] = 0;
    }

    pub fn backspaceSearch(self: *MediaWidget) void {
        if (self.search_caret == 0) return;
        var i = self.search_caret - 1;
        while (i < self.search_len - 1) : (i += 1) {
            self.search_buf[i] = self.search_buf[i + 1];
        }
        self.search_caret -= 1;
        self.search_len -= 1;
        self.search_buf[self.search_len] = 0;
    }

    pub fn deleteSearch(self: *MediaWidget) void {
        if (self.search_caret >= self.search_len) return;
        var i = self.search_caret;
        while (i < self.search_len - 1) : (i += 1) {
            self.search_buf[i] = self.search_buf[i + 1];
        }
        self.search_len -= 1;
        self.search_buf[self.search_len] = 0;
    }

    pub fn moveSearchCaret(self: *MediaWidget, delta: i32) void {
        const new = @as(i32, @intCast(self.search_caret)) + delta;
        self.search_caret = @intCast(@max(0, @min(new, @as(i32, @intCast(self.search_len)))));
    }

    pub fn searchText(self: *const MediaWidget) []const u8 {
        return if (self.search_len > 0) self.search_buf[0..self.search_len] else "";
    }

    pub fn acceptSearch(self: *MediaWidget) []const u8 {
        const text = self.searchText();
        self.clearSearch();
        self.focusControl(.play);
        return text;
    }

    pub fn cancelSearch(self: *MediaWidget) void {
        self.clearSearch();
        self.focusControl(.play);
    }

    fn ensureStopped(self: *MediaWidget) void {
        if (self.mpv_pid) |pid| {
            _ = c_linux.kill(pid, c_linux.SIG.TERM);
            var status: u32 = 0;
            _ = c_linux.waitpid(@intCast(pid), &status, c_linux.W.NOHANG);
            self.mpv_pid = null;
        }
    }

    pub fn play(self: *MediaWidget, path: []const u8) void {
        self.ensureStopped();
        _ = unistd.unlink(@ptrCast(&self.ipc_path[0]));

        var path_z: [4096:0]u8 = std.mem.zeroes([4096:0]u8);
        const copy_len = @min(path.len, path_z.len - 1);
        @memcpy(path_z[0..copy_len], path[0..copy_len]);
        path_z[copy_len] = 0;

        const pid = unistd.fork();
        if (pid < 0) {
            std.log.err("media: fork failed for mpv", .{});
            return;
        }
        if (pid == 0) {
            _ = unistd.setsid();
            const devnull = unistd.open("/dev/null", unistd.O_RDWR);
            if (devnull >= 0) {
                _ = unistd.dup2(devnull, 0);
                _ = unistd.dup2(devnull, 1);
                _ = unistd.dup2(devnull, 2);
                if (devnull > 2) _ = unistd.close(devnull);
            }
            const argv = [_:null]?[*:0]const u8{
                "mpv".ptr,
                "--no-video".ptr,
                "--really-quiet".ptr,
                "--idle=no".ptr,
                "--force-window=no".ptr,
                "--ao=alsa,pulse,null".ptr,
                "--input-ipc-server=/run/user/1000/kidulwm-mpv.sock".ptr,
                "--".ptr,
                @ptrCast(&path_z[0]),
                null,
            };
            _ = unistd.execvp("mpv", @ptrCast(argv[0..].ptr));
            unistd._exit(127);
        }
        self.mpv_pid = pid;
        self.cached = .{};
        self.cached.available = true;
        self.last_poll_us = 0;
        self.poll_fail_count = 0;
    }

    pub fn playPause(self: *MediaWidget) void {
        self.sendSimpleCommand("cycle", &.{"pause"});
    }

    pub fn next(self: *MediaWidget) void {
        self.sendSimpleCommand("playlist-next", &.{});
    }

    pub fn prev(self: *MediaWidget) void {
        self.sendSimpleCommand("playlist-prev", &.{});
    }

    pub fn seek(self: *MediaWidget, seconds: f64) void {
        var sbuf: [64:0]u8 = std.mem.zeroes([64:0]u8);
        const s = std.fmt.bufPrintZ(&sbuf, "{d:.3}", .{seconds}) catch return;
        self.sendSimpleCommand("seek", &.{s});
    }

    fn sendSimpleCommand(self: *MediaWidget, name: []const u8, args: []const []const u8) void {
        if (self.mpv_pid == null) return;
        const fd = self.connectIpc() orelse return;
        defer _ = c_linux.close(fd);

        var json: [512]u8 = undefined;
        var j: usize = 0;
        const parts = [_][]const u8{
            "{\"command\":[\"",
            "\"",
            ",\"",
            "\"]}\n",
        };
        @memcpy(json[j..j + parts[0].len], parts[0]); j += parts[0].len;
        @memcpy(json[j..j + name.len], name); j += name.len;
        @memcpy(json[j..j + parts[1].len], parts[1]); j += parts[1].len;
        for (args) |a| {
            @memcpy(json[j..j + a.len], a); j += a.len;
            @memcpy(json[j..j + parts[2].len], parts[2]); j += parts[2].len;
        }
        if (args.len == 0) {
            @memcpy(json[j..j + parts[3].len], parts[3]); j += parts[3].len;
        } else {
            const tail = "]}\n";
            @memcpy(json[j..j + tail.len], tail); j += tail.len;
        }
        _ = c_linux.write(fd, &json, j);
    }

    fn connectIpc(self: *MediaWidget) ?i32 {
        const fd_i: i32 = @intCast(c_linux.socket(c_linux.AF.UNIX, c_linux.SOCK.STREAM, 0));
        if (fd_i < 0) return null;

        var addr: c_posix.sockaddr.un = std.mem.zeroes(c_posix.sockaddr.un);
        addr.family = c_linux.AF.UNIX;
        var path_buf: [128:0]u8 = std.mem.zeroes([128:0]u8);
        var path_slice = std.mem.sliceTo(&self.ipc_path, 0);
        if (path_slice.len == 0) {
            const default_path = "/run/user/1000/kidulwm-mpv.sock";
            @memcpy(path_buf[0..default_path.len], default_path);
            path_buf[default_path.len] = 0;
            path_slice = std.mem.sliceTo(&path_buf, 0);
        }
        const path_len = @min(path_slice.len, addr.path.len - 1);
        @memcpy(addr.path[0..path_len], path_slice[0..path_len]);
        addr.path[path_len] = 0;
        const addr_len: u32 = @intCast(@offsetOf(c_posix.sockaddr.un, "path") + path_len + 1);
        if (c_linux.connect(fd_i, @ptrCast(&addr), addr_len) != 0) {
            _ = c_linux.close(fd_i);
            return null;
        }
        return fd_i;
    }

    fn sendAndRead(self: *MediaWidget, command_json: []const u8, out: []u8) ?usize {
        if (self.mpv_pid == null) return null;
        const fd = self.connectIpc() orelse return null;
        defer _ = c_linux.close(fd);
        _ = c_linux.write(fd, command_json.ptr, command_json.len);

        const flags = unistd.fcntl(fd, unistd.F_GETFL, @as(c_int, 0));
        if (flags >= 0) {
            _ = unistd.fcntl(fd, unistd.F_SETFL, @as(c_int, @intCast(flags)) | unistd.O_NONBLOCK);
        }

        var total: usize = 0;
        var attempts: u8 = 0;
        while (attempts < 20 and total < out.len) {
            const rc = c_linux.read(fd, out.ptr + total, out.len - total);
            if (rc == 0) break;
            if (@as(i64, @bitCast(rc)) < 0) {
                if (c_linux.errno(rc) == .AGAIN) {
                    _ = unistd.usleep(10_000);
                    attempts += 1;
                    continue;
                }
                break;
            }
            total += rc;
            attempts = 0;
        }
        return if (total > 0) total else null;
    }

    fn parseBoolField(haystack: []const u8, key: []const u8) ?bool {
        var kbuf: [128]u8 = undefined;
        const K = std.fmt.bufPrint(&kbuf, "\"{s}\":", .{key}) catch return null;
        const idx = std.mem.indexOf(u8, haystack, K) orelse return null;
        const rest = haystack[idx + K.len..];
        if (std.mem.startsWith(u8, rest, "true")) return true;
        if (std.mem.startsWith(u8, rest, "false")) return false;
        return null;
    }

    fn parseStringField(haystack: []const u8, key: []const u8, out: []u8) void {
        var kbuf: [128]u8 = undefined;
        const K = std.fmt.bufPrint(&kbuf, "\"{s}\":\"", .{key}) catch return;
        const start = std.mem.indexOf(u8, haystack, K) orelse return;
        const rest = haystack[start + K.len..];
        const end = std.mem.indexOfScalar(u8, rest, '"') orelse return;
        const len = @min(end, out.len - 1);
        @memcpy(out[0..len], rest[0..len]);
        out[len] = 0;
    }

    fn parseFloatField(_: *MediaWidget, haystack: []const u8, key: []const u8) ?f64 {
        var kbuf: [128]u8 = undefined;
        const K = std.fmt.bufPrint(&kbuf, "\"{s}\":", .{key}) catch return null;
        const start = std.mem.indexOf(u8, haystack, K) orelse return null;
        const rest = haystack[start + K.len..];
        const end = for (rest, 0..) |ch, i| {
            if (ch == ',' or ch == '}' or ch == ']' or std.ascii.isWhitespace(ch)) break i;
        } else rest.len;
        return std.fmt.parseFloat(f64, rest[0..end]) catch null;
    }

    pub fn update(self: *MediaWidget) void {
        if (self.mpv_pid == null) {
            self.cached.playing = false;
            return;
        }
        const now = animationNowUs();
        if (now -% self.last_poll_us < 1_000_000) return;
        self.last_poll_us = now;

        var buf: [8192]u8 = std.mem.zeroes([8192]u8);
        const cmd = "{\"command\":[\"get_property\",\"playback-time\"]}\n" ++
                    "{\"command\":[\"get_property\",\"duration\"]}\n" ++
                    "{\"command\":[\"get_property\",\"pause\"]}\n" ++
                    "{\"command\":[\"get_property\",\"metadata\"]}\n";
        const n = self.sendAndRead(cmd, &buf) orelse {
            self.poll_fail_count += 1;
            if (self.poll_fail_count > 10) {
                self.cached.playing = false;
                self.cached.available = false;
            }
            return;
        };
        self.poll_fail_count = 0;
        const resp = buf[0..n];

        const pos = parseFloatField(self, resp, "playback-time");
        self.cached.position = pos orelse self.cached.position;
        const dur = parseFloatField(self, resp, "duration");
        self.cached.duration = dur orelse self.cached.duration;
        if (parseBoolField(resp, "pause")) |paused| {
            self.cached.playing = !paused;
        }
        parseStringField(resp, "title", &self.cached.title);
        if (self.cached.title[0] == 0) parseStringField(resp, "TITLE", &self.cached.title);
        if (self.cached.title[0] == 0) parseStringField(resp, "icy-title", &self.cached.title);
        parseStringField(resp, "artist", &self.cached.artist);
        parseStringField(resp, "album", &self.cached.album);
    }

    pub fn needsRedraw(self: *const MediaWidget) bool {
        // Helix progress handled by tray when card open or playing.
        _ = self;
        return true;
    }

    pub const PeekBox = struct { x: i32, y: i32, width: i32, height: i32 };

    pub fn renderPeek(self: *MediaWidget, cr: *c.cairo_t, box: PeekBox, style_: style.Style, scale: f32) void {
        const w_d: f64 = @floatFromInt(box.width);
        const h_d: f64 = @floatFromInt(box.height);
        if (w_d < 8.0 or h_d < 8.0) return;

        const border = style_.color_border_focused.toF64();
        const muted = style_.color_text_muted.toF64();
        const scale_f: f64 = @as(f64, scale);
        const playing = self.cached.playing;

        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        const margin: f64 = 6.0 * scale_f;
        const band_w = w_d - margin * 2.0;
        const lane_h = h_d - margin * 2.0;
        const cx = margin + band_w * 0.5;
        const cy = margin + lane_h * 0.5;

        const now = animationNowUs();
        const dt = if (self.last_helix_us == 0) 0.0 else @as(f64, @floatFromInt(now -% self.last_helix_us)) / 1_000_000.0;
        self.last_helix_us = now;
        const helix_speed: f64 = if (playing) 1.8 else 0.35;
        self.helix_phase += dt * helix_speed;
        const energy = if (playing) 0.6 + 0.4 * @sin(self.helix_phase * 2.0) else 0.12;
        self.last_energy = self.last_energy * 0.92 + energy * 0.08;

        const amp = @max(2.0 * scale_f, lane_h * 0.28 * self.last_energy);
        const marker_count: usize = 5;

        c.cairo_set_line_width(cr, @max(1.0, 1.4 * scale_f));

        for (0..2) |strand| {
            const strand_offset: f64 = @as(f64, @floatFromInt(strand)) * std.math.pi;
            c.cairo_new_path(cr);
            var t: f64 = 0;
            const steps: usize = 60;
            var first = true;
            while (t <= 1.0001) : (t += 1.0 / @as(f64, @floatFromInt(steps))) {
                const y = cy - lane_h * 0.5 + t * lane_h;
                const wave = @sin(t * std.math.pi * 4.0 - self.helix_phase + strand_offset);
                const x = cx + wave * amp;
                if (first) {
                    c.cairo_move_to(cr, x, y);
                    first = false;
                } else {
                    c.cairo_line_to(cr, x, y);
                }
            }
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], if (playing) 0.85 else 0.55);
            c.cairo_stroke(cr);
        }

        const alpha_pulse = 0.45 + 0.55 * self.last_energy;
        const marker_r = @max(3.0 * scale_f, lane_h * 0.09);
        var mi: usize = 0;
        while (mi <= marker_count) : (mi += 1) {
            const t = @as(f64, @floatFromInt(mi)) / @as(f64, @floatFromInt(marker_count));
            const y = margin + t * lane_h;
            const wave = @sin(t * std.math.pi * 4.0 - self.helix_phase);
            const x = cx + wave * amp;
            c.cairo_new_path(cr);
            c.cairo_arc(cr, x, y, marker_r, 0, std.math.pi * 2.0);
            if (playing) {
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], alpha_pulse);
            } else {
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.22);
            }
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.55);
            c.cairo_set_line_width(cr, @max(0.5, 0.7 * scale_f));
            c.cairo_stroke(cr);
        }

        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
        const txt = if (self.cached.title[0] != 0) std.mem.sliceTo(&self.cached.title, 0) else "No media";
        const font_h: f64 = @as(f64, style_.font_size_s) * 0.7 * scale_f;
        c.cairo_set_font_size(cr, font_h);
        var ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, txt.ptr, &ext);
        if (ext.width < band_w - 4.0 * scale_f) {
            c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.75);
            c.cairo_move_to(cr, margin, h_d - margin);
            c.cairo_show_text(cr, txt.ptr);
        }

        if (self.cached.available) {
            const dot_r = @max(2.5 * scale_f, 4.0 * scale_f);
            c.cairo_new_path(cr);
            c.cairo_arc(cr, w_d - margin - dot_r, margin + dot_r, dot_r, 0, std.math.pi * 2.0);
            if (playing) {
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.9);
            } else {
                c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.45);
            }
            c.cairo_fill(cr);
        }
    }

    pub fn renderCard(self: *MediaWidget, cr: *c.cairo_t, w_d: f64, h_d: f64, style_: style.Style, scale: f32, out_click: ?*CardClick) void {
        const border = style_.color_border_focused.toF64();
        const muted = style_.color_text_muted.toF64();
        const scale_f: f64 = @as(f64, scale);

        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        const card_frame_mod = @import("card_frame.zig");
        card_frame_mod.Registry.default.drawNamed(cr, style_, w_d, h_d);

        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);

        const pad_x: f64 = 22.0 * scale_f;
        const pad_y: f64 = 18.0 * scale_f;
        const content_w = w_d - 2.0 * pad_x;
        const top_y = pad_y;

        const btn_r: f64 = @max(14.0 * scale_f, content_w * 0.045);
        // Cluster the three transport controls together, centered.
        const btn_gap: f64 = @max(44.0 * scale_f, content_w * 0.12);
        const cy_btns = top_y + btn_r + 4.0 * scale_f;
        const mid = w_d * 0.5;
        const centers = [_]f64{
            mid - btn_gap,
            mid,
            mid + btn_gap,
        };

        // Draw the three buttons with focus rings.
        for (centers, 0..) |cx, i| {
            const tag: ControlFocus = switch (i) {
                0 => .prev,
                1 => .play,
                2 => .next,
                else => unreachable,
            };
            const focused = self.focus == tag;

            if (focused) {
                c.cairo_new_path(cr);
                c.cairo_arc(cr, cx, cy_btns, btn_r + 3.5 * scale_f, 0, std.math.pi * 2.0);
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.30);
                c.cairo_fill_preserve(cr);
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 1.0);
                c.cairo_set_line_width(cr, 2.0);
                c.cairo_stroke(cr);
            }

            c.cairo_new_path(cr);
            c.cairo_arc(cr, cx, cy_btns, btn_r, 0, std.math.pi * 2.0);
            // Black glass button body — top sheen / bottom shadow.
            const btn_grad = c.cairo_pattern_create_linear(cx, cy_btns - btn_r, cx, cy_btns + btn_r).?;
            c.cairo_pattern_add_color_stop_rgba(btn_grad, 0.0, border[0], border[1], border[2], 0.14);
            c.cairo_pattern_add_color_stop_rgba(btn_grad, 0.45, border[0], border[1], border[2], 0.05);
            c.cairo_pattern_add_color_stop_rgba(btn_grad, 1.0, 0.0, 0.0, 0.0, 0.25);
            c.cairo_set_source(cr, btn_grad);
            c.cairo_fill_preserve(cr);
            c.cairo_pattern_destroy(btn_grad);
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.45);
            c.cairo_set_line_width(cr, 1.0);
            c.cairo_stroke(cr);

            // Cinematic black-glass glyph: subtle top highlight + bottom shadow.
            if (i == 0) {
                const s = btn_r * 0.42;
                c.cairo_new_path(cr);
                c.cairo_move_to(cr, cx + s * 0.5, cy_btns - s);
                c.cairo_line_to(cr, cx - s * 0.5, cy_btns);
                c.cairo_line_to(cr, cx + s * 0.5, cy_btns + s);
                c.cairo_close_path(cr);
            } else if (i == 1) {
                const s = btn_r * 0.48;
                if (self.cached.playing) {
                    c.cairo_new_path(cr);
                    c.cairo_rectangle(cr, cx - s * 0.35, cy_btns - s, s * 0.55, s * 2.0);
                    c.cairo_rectangle(cr, cx + s * 0.15, cy_btns - s, s * 0.55, s * 2.0);
                } else {
                    c.cairo_new_path(cr);
                    c.cairo_move_to(cr, cx - s * 0.35, cy_btns - s);
                    c.cairo_line_to(cr, cx + s * 0.65, cy_btns);
                    c.cairo_line_to(cr, cx - s * 0.35, cy_btns + s);
                    c.cairo_close_path(cr);
                }
            } else {
                const s = btn_r * 0.42;
                c.cairo_new_path(cr);
                c.cairo_move_to(cr, cx - s * 0.5, cy_btns - s);
                c.cairo_line_to(cr, cx + s * 0.5, cy_btns);
                c.cairo_line_to(cr, cx - s * 0.5, cy_btns + s);
                c.cairo_close_path(cr);
            }

            // Base glyph in muted border tone.
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.90);
            c.cairo_fill_preserve(cr);

            // Whispery top highlight (glass sheen) clipped to glyph shape.
            c.cairo_save(cr);
            c.cairo_clip_preserve(cr);
            const gy0 = cy_btns - btn_r * 0.9;
            const gy1 = cy_btns + btn_r * 0.9;
            const grad = c.cairo_pattern_create_linear(cx - btn_r, gy0, cx - btn_r, gy1).?;
            c.cairo_pattern_add_color_stop_rgba(grad, 0.0, 1.0, 1.0, 1.0, 0.28);
            c.cairo_pattern_add_color_stop_rgba(grad, 0.40, 1.0, 1.0, 1.0, 0.0);
            c.cairo_pattern_add_color_stop_rgba(grad, 0.85, 0.0, 0.0, 0.0, 0.0);
            c.cairo_pattern_add_color_stop_rgba(grad, 1.0, 0.0, 0.0, 0.0, 0.18);
            c.cairo_set_source(cr, grad);
            c.cairo_paint(cr);
            c.cairo_pattern_destroy(grad);
            c.cairo_restore(cr);

            // Fine outline for crispness.
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.55);
            c.cairo_set_line_width(cr, 0.7);
            c.cairo_stroke(cr);
        }

        const bar_y = cy_btns + btn_r + 22.0 * scale_f;
        const bar_h = @max(4.0 * scale_f, 5.0 * scale_f);
        const bar_r = bar_h * 0.5;
        const bar_w = content_w;
        const bar_x = pad_x;
        roundedRect(cr, bar_x, bar_y, bar_w, bar_h, bar_r);
        c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.15);
        c.cairo_fill(cr);

        const pct = if (self.cached.duration > 0) @min(1.0, @max(0.0, self.cached.position / self.cached.duration)) else 0;
        if (pct > 0) {
            roundedRect(cr, bar_x, bar_y, bar_w * pct, bar_h, bar_r);
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.85);
            c.cairo_fill(cr);
        }

        const handle_r = @max(4.0 * scale_f, 5.5 * scale_f);
        c.cairo_new_path(cr);
        c.cairo_arc(cr, bar_x + bar_w * pct, bar_y + bar_h * 0.5, handle_r, 0, std.math.pi * 2.0);
        c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 1.0);
        c.cairo_fill(cr);

        var tbuf: [32:0]u8 = std.mem.zeroes([32:0]u8);
        const pos_s = @as(i32, @intFromFloat(@floor(self.cached.position)));
        const dur_s = if (self.cached.duration > 0) @as(i32, @intFromFloat(@floor(self.cached.duration))) else 0;
        const tstr = std.fmt.bufPrintZ(&tbuf, "{d}:{d:0>2} / {d}:{d:0>2}", .{ @divTrunc(@max(0, pos_s), 60), @mod(@max(0, pos_s), 60), @divTrunc(@max(0, dur_s), 60), @mod(@max(0, dur_s), 60) }) catch "0:00 / 0:00";
        c.cairo_set_font_size(cr, @as(f64, style_.font_size_s) * scale_f);
        var ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, tstr.ptr, &ext);
        c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.8);
        c.cairo_move_to(cr, bar_x, bar_y + bar_h + ext.height + 8.0 * scale_f);
        c.cairo_show_text(cr, tstr.ptr);

        const meta_y = bar_y + bar_h + 28.0 * scale_f;
        const title_size = @as(f64, style_.font_size_m) * 1.05 * scale_f;
        c.cairo_set_font_size(cr, title_size);
        c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.95);
        const title = if (self.cached.title[0] != 0) std.mem.sliceTo(&self.cached.title, 0) else "No media";
        self.drawCenteredText(cr, title, w_d * 0.5, meta_y, content_w);

        const artist_size = @as(f64, style_.font_size_s) * scale_f;
        c.cairo_set_font_size(cr, artist_size);
        c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.8);
        const artist = std.mem.sliceTo(&self.cached.artist, 0);
        self.drawCenteredText(cr, if (artist.len > 0) artist else "", w_d * 0.5, meta_y + artist_size * 1.6, content_w);

        // ---- Bottom dual-purpose search / now-playing line ----
        const album = std.mem.sliceTo(&self.cached.album, 0);
        const search_h = @max(28.0 * scale_f, 24.0 * scale_f);
        const search_y = h_d - pad_y - search_h;
        const search_w = content_w * 0.25;
        const search_x = pad_x + (content_w - search_w) * 0.5;
        const search_r = 6.0 * scale_f;

        if (out_click) |click| {
            click.search_x = @intFromFloat(search_x);
            click.search_y = @intFromFloat(search_y);
            click.search_w = @intFromFloat(search_w);
            click.search_h = @intFromFloat(search_h);
            click.btn_r = @intFromFloat(btn_r);
            for (centers, 0..) |cx, i| {
                click.btn_x[i] = @intFromFloat(cx);
            }
            click.btn_y = @intFromFloat(cy_btns);
        }

        roundedRect(cr, search_x, search_y, search_w, search_h, search_r);
        if (self.search_focused or self.focus == .search) {
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.18);
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 1.0);
            c.cairo_set_line_width(cr, 2.0);
            c.cairo_stroke(cr);
        } else if (self.cached.playing) {
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.08);
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.35);
            c.cairo_set_line_width(cr, 1.0);
            c.cairo_stroke(cr);
        } else {
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.06);
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.25);
            c.cairo_set_line_width(cr, 1.0);
            c.cairo_stroke(cr);
        }

        const search_margin: f64 = 10.0 * scale_f;
        const search_text_x = search_x + search_margin;
        const search_text_w = search_w - 2.0 * search_margin;
        const search_font = @as(f64, style_.font_size_s) * 0.92 * scale_f;
        c.cairo_set_font_size(cr, search_font);

        var sbuf: [256:0]u8 = std.mem.zeroes([256:0]u8);
        const display_text: []const u8 = blk: {
            if (self.search_focused or self.search_len > 0) {
                break :blk if (self.search_len > 0)
                    std.mem.sliceTo(&self.search_buf, 0)
                else
                    "";
            }
            if (self.cached.playing and self.cached.title[0] != 0) {
                const t = std.mem.sliceTo(&self.cached.title, 0);
                const prefix = "now playing: ";
                const copy = @min(t.len, sbuf.len - prefix.len - 1);
                @memcpy(sbuf[0..prefix.len], prefix);
                @memcpy(sbuf[prefix.len .. prefix.len + copy], t[0..copy]);
                sbuf[prefix.len + copy] = 0;
                break :blk std.mem.sliceTo(&sbuf, 0);
            }
            break :blk "search library...";
        };

        if (self.search_focused or self.focus == .search or self.cached.playing) {
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.95);
        } else {
            c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.55);
        }

        var text_ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, display_text.ptr, &text_ext);
        var clip_text = display_text;
        if (text_ext.width > search_text_w) {
            while (clip_text.len > 3) {
                clip_text = clip_text[0..clip_text.len - 1];
                const tmp = std.fmt.allocPrint(std.heap.page_allocator, "{s}...", .{clip_text}) catch clip_text;
                defer std.heap.page_allocator.free(tmp);
                c.cairo_text_extents(cr, tmp.ptr, &text_ext);
                if (text_ext.width <= search_text_w) {
                    clip_text = tmp;
                    break;
                }
            }
        }
        c.cairo_move_to(cr, search_text_x, search_y + search_h * 0.5 + search_font * 0.35);
        c.cairo_show_text(cr, clip_text.ptr);

        // Blinking caret when search is focused.
        if (self.search_focused) {
            const now = animationNowUs();
            if (now -% self.last_caret_blink_us > 500_000) {
                self.show_caret = !self.show_caret;
                self.last_caret_blink_us = now;
            }
            if (self.show_caret) {
                var caret_buf: [128:0]u8 = std.mem.zeroes([128:0]u8);
                const caret_copy = @min(self.search_caret, self.search_len);
                if (caret_copy > 0) {
                    @memcpy(caret_buf[0..caret_copy], self.search_buf[0..caret_copy]);
                }
                caret_buf[caret_copy] = 0;
                var caret_ext: c.cairo_text_extents_t = undefined;
                c.cairo_text_extents(cr, caret_buf[0..caret_copy :0].ptr, &caret_ext);
                const caret_x = search_text_x + caret_ext.width;
                const caret_y0 = search_y + 6.0 * scale_f;
                const caret_y1 = search_y + search_h - 6.0 * scale_f;
                c.cairo_new_path(cr);
                c.cairo_move_to(cr, caret_x, caret_y0);
                c.cairo_line_to(cr, caret_x, caret_y1);
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.95);
                c.cairo_set_line_width(cr, @max(1.0, 1.3 * scale_f));
                c.cairo_stroke(cr);
            }
        } else {
            self.show_caret = true;
        }

        if (album.len > 0) {
            c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.55);
            self.drawCenteredText(cr, album, w_d * 0.5, meta_y + artist_size * 3.0, content_w);
        }
    }

    pub const CardClick = struct {
        btn_x: [3]i32 = .{ 0, 0, 0 },
        btn_y: i32 = 0,
        btn_r: i32 = 0,
        search_x: i32 = 0,
        search_y: i32 = 0,
        search_w: i32 = 0,
        search_h: i32 = 0,
    };

    fn drawCenteredText(_: *MediaWidget, cr: *c.cairo_t, txt: []const u8, cx: f64, y: f64, max_w: f64) void {
        var ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, txt.ptr, &ext);
        var draw_txt = txt;
        while (ext.width > max_w and draw_txt.len > 3) {
            draw_txt = draw_txt[0..draw_txt.len - 1];
            const tmp = std.fmt.allocPrint(std.heap.page_allocator, "{s}...", .{draw_txt}) catch draw_txt;
            defer std.heap.page_allocator.free(tmp);
            c.cairo_text_extents(cr, tmp.ptr, &ext);
            if (ext.width <= max_w) {
                c.cairo_move_to(cr, cx - ext.width * 0.5, y);
                c.cairo_show_text(cr, tmp.ptr);
                return;
            }
        }
        c.cairo_move_to(cr, cx - ext.width * 0.5, y);
        c.cairo_show_text(cr, draw_txt.ptr);
    }

    fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
        const rr = @min(r, w * 0.5, h * 0.5);
        c.cairo_new_path(cr);
        c.cairo_move_to(cr, x + rr, y);
        c.cairo_line_to(cr, x + w - rr, y);
        c.cairo_arc(cr, x + w - rr, y + rr, rr, -std.math.pi * 0.5, 0);
        c.cairo_line_to(cr, x + w, y + h - rr);
        c.cairo_arc(cr, x + w - rr, y + h - rr, rr, 0, std.math.pi * 0.5);
        c.cairo_line_to(cr, x + rr, y + h);
        c.cairo_arc(cr, x + rr, y + h - rr, rr, std.math.pi * 0.5, std.math.pi);
        c.cairo_line_to(cr, x, y + rr);
        c.cairo_arc(cr, x + rr, y + rr, rr, std.math.pi, std.math.pi * 1.5);
        c.cairo_close_path(cr);
    }
};

fn animationNowUs() u64 {
    var ts: unistd.timespec = std.mem.zeroes(unistd.timespec);
    if (unistd.clock_gettime(unistd.CLOCK_MONOTONIC, &ts) != 0) return 0;
    return @as(u64, @intCast(ts.tv_sec)) * 1_000_000 + @as(u64, @intCast(ts.tv_nsec)) / 1000;
}
