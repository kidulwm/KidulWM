const std = @import("std");
const c = @import("dm").c;
const c_std = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("dirent.h");
    @cInclude("time.h");
});
const style = @import("../core/style.zig");
const theme_mod = @import("../core/theme.zig");
const card_frame = @import("card_frame.zig");

pub const NetworkState = enum {
    none,
    disconnected,
    connected,
};

pub const NetworkCard = struct {
    open: bool = false,

    pub fn toggle(self: *NetworkCard) void {
        self.open = !self.open;
    }

    pub fn close(self: *NetworkCard) void {
        self.open = false;
    }
};

pub const NetworkWidget = struct {
    allocator: std.mem.Allocator,
    card: NetworkCard = .{},
    state: NetworkState = .none,
    last_scan_ms: u64 = 0,

    const scan_interval_ms: u64 = 2000;
    const brightness_step_ratio: f64 = 0.05;

    pub fn init(allocator: std.mem.Allocator) NetworkWidget {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *NetworkWidget) void {
        _ = self;
    }

    pub fn toggleCard(self: *NetworkWidget) void {
        self.card.toggle();
    }

    pub fn closeCard(self: *NetworkWidget) void {
        self.card.close();
    }

    pub fn isCardOpen(self: *const NetworkWidget) bool {
        return self.card.open;
    }

    fn nowMs() u64 {
        var ts: std.os.linux.timespec = undefined;
        if (std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts) != 0) {
            return 0;
        }
        return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / 1_000_000;
    }

    pub fn update(self: *NetworkWidget) void {
        const now = nowMs();
        if (now -% self.last_scan_ms >= scan_interval_ms) {
            self.scanState();
            self.last_scan_ms = now;
        }
    }

    pub fn needsRedraw(self: *const NetworkWidget) bool {
        // The icon shape is determined entirely by state, and the state is polled
        // internally.  The tray redraw loop already re-runs every frame the tray
        // is moving/visible, so a state change will be picked up on the next pass.
        // Returning true here once per scan would be useful but is not required for
        // a Granny-simple proof-of-life.
        _ = self;
        return false;
    }

    fn scanState(self: *NetworkWidget) void {
        var any_iface: bool = false;
        var any_up: bool = false;

        const dir = c_std.opendir("/sys/class/net");
        if (dir == null) {
            self.state = .none;
            return;
        }
        defer _ = c_std.closedir(dir);

        var entry: ?*c_std.dirent = null;
        while (true) {
            entry = c_std.readdir(dir);
            if (entry == null) break;
            const name = std.mem.sliceTo(&entry.?.d_name, 0);
            if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..") or std.mem.eql(u8, name, "lo")) {
                continue;
            }

            any_iface = true;

            var path_buf: [256:0]u8 = undefined;
            @memset(&path_buf, 0);
            const path = std.fmt.bufPrintZ(&path_buf, "/sys/class/net/{s}/operstate", .{name}) catch continue;
            const f = c_std.fopen(path, "r");
            if (f == null) continue;
            defer _ = c_std.fclose(f);

            var line_buf: [32:0]u8 = undefined;
            @memset(&line_buf, 0);
            if (c_std.fgets(&line_buf, @intCast(line_buf.len), f) != null) {
                const line = std.mem.sliceTo(&line_buf, 0);
                if (std.mem.startsWith(u8, line, "up")) {
                    any_up = true;
                    break;
                }
            }
        }

        if (any_up) {
            self.state = .connected;
        } else if (any_iface) {
            self.state = .disconnected;
        } else {
            self.state = .none;
        }
    }

    pub const PeekBox = struct {
        x: i32,
        y: i32,
        width: i32,
        height: i32,
    };

    pub fn renderPeek(self: *const NetworkWidget, cr: *c.cairo_t, box: PeekBox, style_: style.Style, scale: f32) void {
        const w_d: f64 = @floatFromInt(box.width);
        const h_d: f64 = @floatFromInt(box.height);
        if (w_d < 8.0 or h_d < 8.0) return;

        const scale_f: f64 = @as(f64, scale);
        const gold = style_.color_border_focused.toF64();
        const muted = style_.color_text_muted.toF64();

        // Kapitayan sun: same visual footprint as the weather moon icon.
        const margin: f64 = 4.0 * scale_f;
        const sun_r = @max(5.0 * scale_f, @min(w_d * 0.36, 11.0 * scale_f, (h_d - margin * 2.0) * 0.45));
        if (sun_r < 4.0 * scale_f) return;

        const cx = w_d * 0.5;
        const cy = margin + sun_r;
        const center_r = @max(5.0 * scale_f, sun_r * 0.28);
        const beam_outer = sun_r;

        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);
        c.cairo_set_line_cap(cr, c.CAIRO_LINE_CAP_ROUND);
        c.cairo_set_line_join(cr, c.CAIRO_LINE_JOIN_ROUND);

        // Draw beams first so the center circle sits cleanly on top.
        switch (self.state) {
            .connected => {
                // All four corner beams in gold, with a subtle glow.
                drawBeams(cr, cx, cy, center_r, beam_outer, true, true, true, true, gold, 4.0 * scale_f);
                drawBeams(cr, cx, cy, center_r, beam_outer, true, true, true, true, gold, 1.5 * scale_f);
            },
            .disconnected => {
                // Missing top beams; remaining beams + centre in burnt orange.
                const burnt = [4]f64{ @as(f64, 0xD9) / 255.0, @as(f64, 0x72) / 255.0, @as(f64, 0x2E) / 255.0, 0.85 };
                drawBeams(cr, cx, cy, center_r, beam_outer, false, false, true, true, burnt, 1.5 * scale_f);
            },
            .none => {
                // No beams; just a quiet centre circle.
            },
        }

        // Centre circle.
        const center_color = switch (self.state) {
            .connected => gold,
            .disconnected => [4]f64{ @as(f64, 0xD9) / 255.0, @as(f64, 0x72) / 255.0, @as(f64, 0x2E) / 255.0, 0.85 },
            .none => muted,
        };
        c.cairo_new_path(cr);
        c.cairo_arc(cr, cx, cy, center_r, 0, 2.0 * std.math.pi);
        c.cairo_set_source_rgba(cr, center_color[0], center_color[1], center_color[2], center_color[3]);
        c.cairo_fill(cr);
    }

    fn drawBeams(
        cr: *c.cairo_t,
        cx: f64,
        cy: f64,
        inner: f64,
        outer: f64,
        nw: bool,
        ne: bool,
        sw: bool,
        se: bool,
        color: [4]f64,
        width: f64,
    ) void {
        c.cairo_set_source_rgba(cr, color[0], color[1], color[2], color[3]);
        c.cairo_set_line_width(cr, width);
        const delta = outer - inner;

        if (nw) drawBeam(cr, cx, cy, -1.0, -1.0, inner, delta);
        if (ne) drawBeam(cr, cx, cy, 1.0, -1.0, inner, delta);
        if (sw) drawBeam(cr, cx, cy, -1.0, 1.0, inner, delta);
        if (se) drawBeam(cr, cx, cy, 1.0, 1.0, inner, delta);
    }

    fn drawBeam(cr: *c.cairo_t, cx: f64, cy: f64, sx: f64, sy: f64, inner: f64, len: f64) void {
        const dx = sx * 0.70710678118;
        const dy = sy * 0.70710678118;
        const x1 = cx + dx * inner;
        const y1 = cy + dy * inner;
        const x2 = cx + dx * (inner + len);
        const y2 = cy + dy * (inner + len);
        c.cairo_move_to(cr, x1, y1);
        c.cairo_line_to(cr, x2, y2);
        c.cairo_stroke(cr);
    }

    pub fn renderCard(self: *const NetworkWidget, cr: *c.cairo_t, w_d: f64, h_d: f64, style_: style.Style, scale: f32) void {
        _ = scale;
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        card_frame.Registry.default.drawNamed(cr, style_, w_d, h_d);

        const gold = style_.color_border_focused.toF64();
        const muted = style_.color_text_muted.toF64();

        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
        const title_size: f64 = @as(f64, style_.font_size_l) * 1.2;
        c.cairo_set_font_size(cr, title_size);

        var title_ext: c.cairo_text_extents_t = undefined;
        const title = "Network";
        c.cairo_text_extents(cr, title, &title_ext);
        const title_x = (w_d - title_ext.width) * 0.5;
        const title_y = h_d * 0.25 + title_ext.height * 0.5;
        c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
        c.cairo_move_to(cr, title_x, title_y);
        c.cairo_show_text(cr, title);

        const status_str = switch (self.state) {
            .none => "No connection configured",
            .disconnected => "Configured but not connected",
            .connected => "Connected",
        };
        const body_size: f64 = @as(f64, style_.font_size_m);
        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
        c.cairo_set_font_size(cr, body_size);

        var status_ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, status_str, &status_ext);
        const status_x = (w_d - status_ext.width) * 0.5;
        const status_y = title_y + title_size * 1.6;
        c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
        c.cairo_move_to(cr, status_x, status_y);
        c.cairo_show_text(cr, status_str);
    }

    pub fn adjustBrightness(self: *NetworkWidget, delta: f64) void {
        _ = self;
        const dir: i32 = if (delta > 0.0) 1 else -1;

        var controller_buf: [128:0]u8 = undefined;
        @memset(&controller_buf, 0);
        if (!findBacklightController(&controller_buf)) {
            std.log.info("KidulWM: no backlight controller found; brightness scroll stubbed", .{});
            return;
        }
        const controller = std.mem.sliceTo(&controller_buf, 0);

        var max_path: [256:0]u8 = undefined;
        @memset(&max_path, 0);
        const max_path_z = std.fmt.bufPrintZ(&max_path, "/sys/class/backlight/{s}/max_brightness", .{controller}) catch return;
        const max = readIntFile(max_path_z);
        if (max <= 0) {
            std.log.info("KidulWM: backlight {s} max_brightness unreadable", .{controller});
            return;
        }

        var cur_path: [256:0]u8 = undefined;
        @memset(&cur_path, 0);
        const cur_path_z = std.fmt.bufPrintZ(&cur_path, "/sys/class/backlight/{s}/brightness", .{controller}) catch return;
        const current = readIntFile(cur_path_z);

        const step: i64 = @max(1, @divFloor(max, 20));
        const new_val: i64 = std.math.clamp(current + @as(i64, dir) * step, 1, max);

        const f = c_std.fopen(cur_path_z, "w");
        if (f == null) {
            std.log.info("KidulWM: cannot open backlight brightness for writing", .{});
            return;
        }
        defer _ = c_std.fclose(f);
        var write_buf: [32:0]u8 = undefined;
        @memset(&write_buf, 0);
        const write_str = std.fmt.bufPrintZ(&write_buf, "{d}", .{new_val}) catch return;
        _ = c_std.fputs(write_str, f);
        std.log.info("KidulWM: brightness adjusted to {d}/{d}", .{ new_val, max });
    }

    fn findBacklightController(out: *[128:0]u8) bool {
        const dir = c_std.opendir("/sys/class/backlight");
        if (dir == null) return false;
        defer _ = c_std.closedir(dir);

        var entry: ?*c_std.dirent = null;
        while (true) {
            entry = c_std.readdir(dir);
            if (entry == null) break;
            const name = std.mem.sliceTo(&entry.?.d_name, 0);
            if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            @memset(out, 0);
            @memcpy(out[0..name.len], name);
            return true;
        }
        return false;
    }

    fn readIntFile(path: [*:0]const u8) i64 {
        const f = c_std.fopen(path, "r");
        if (f == null) return -1;
        defer _ = c_std.fclose(f);
        var buf: [64:0]u8 = undefined;
        @memset(&buf, 0);
        if (c_std.fgets(&buf, @intCast(buf.len), f) == null) return -1;
        const line = std.mem.sliceTo(&buf, 0);
        return std.fmt.parseInt(i64, std.mem.trim(u8, line, " \t\r\n"), 10) catch -1;
    }
};
