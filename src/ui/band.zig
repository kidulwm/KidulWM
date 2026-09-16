const std = @import("std");
const wlr = @import("wlroots");
const c = @import("dm").c;
const linux = std.os.linux;
const Style = @import("../core/style.zig").Style;
const DataBuffer = @import("../render/buffer.zig").DataBuffer;

/// BAND (TASKCARD-3 stage 1, session-and-deck-spec two-species law):
/// permanent per-output edge furniture, left + right peek bands. EXIT dots
/// and slide counts (signage) plus widget readouts (clock v1; weather /
/// signals / session charge are placeholder hooks — wire nothing).
///
/// Bands NEVER hide, never focus, never walk. Rendered from the first frame
/// on every output, empty deck or full. There is deliberately NO hide API —
/// the widgets-off-in-fullscreen law is repealed.
///
/// Geometry law is ported from the spyglass pack's exit_dots skin:
/// peek_fraction 0.06 of the output width; EXIT dots sit 1 char-space from
/// the slide border (inner peek edge); the slide-count digit sits 1
/// char-space from the screen edge. One click router: click = walk to the
/// neighbor on that side.
pub const peek_fraction: f64 = 0.06;

const icon_size: u32 = 20; // px tall (unscaled), signage strip height
const exit_dots_w: u32 = 72; // px wide for the EXIT dot-matrix itself
const num_font_scale: f64 = 0.9;
const clock_h: u32 = 28; // px tall (unscaled) for the clock readout

pub const Side = enum { left, right };

pub const Band = struct {
    overlay_tree: *wlr.SceneTree,
    style: Style,

    left_tree: ?*wlr.SceneTree = null,
    right_tree: ?*wlr.SceneTree = null,
    left_signage: ?*wlr.SceneBuffer = null,
    right_signage: ?*wlr.SceneBuffer = null,
    /// Clock readout in the right band (widget painter v1).
    clock_buffer: ?*wlr.SceneBuffer = null,

    output_width: u32 = 0,
    output_height: u32 = 0,
    scale: u32 = 1,
    /// Output's global layout origin — scene coords are layout-global, so
    /// the per-output band nodes carry this offset.
    box_x: i32 = 0,
    box_y: i32 = 0,

    has_left: bool = false,
    has_right: bool = false,
    left_count: u32 = 0,
    right_count: u32 = 0,
    last_minute: i64 = -1,

    pub fn init(overlay_tree: *wlr.SceneTree, style: Style) Band {
        return .{ .overlay_tree = overlay_tree, .style = style };
    }

    pub fn deinit(self: *Band) void {
        if (self.left_tree) |t| t.node.destroy();
        if (self.right_tree) |t| t.node.destroy();
        self.* = .{ .overlay_tree = self.overlay_tree, .style = self.style };
    }

    /// Born on output birth / mode change: the trees exist from the first
    /// frame and are NEVER disabled afterwards (no hide API).
    pub fn updateOutput(self: *Band, width: u32, height: u32, scale: u32, box_x: i32, box_y: i32) void {
        self.output_width = width;
        self.output_height = height;
        self.scale = @max(1, scale);
        self.box_x = box_x;
        self.box_y = box_y;
        if (self.left_tree == null) {
            self.left_tree = self.overlay_tree.createSceneTree() catch null;
        }
        if (self.right_tree == null) {
            self.right_tree = self.overlay_tree.createSceneTree() catch null;
        }
        self.renderSignage(.left);
        self.renderSignage(.right);
        self.refreshClock();
    }

    /// Neighbor availability + counts changed (deck walk): repaint signage.
    pub fn setNeighbors(self: *Band, has_left: bool, has_right: bool, left_count: u32, right_count: u32) void {
        if (self.has_left == has_left and self.has_right == has_right and
            self.left_count == left_count and self.right_count == right_count) return;
        self.has_left = has_left;
        self.has_right = has_right;
        self.left_count = left_count;
        self.right_count = right_count;
        self.renderSignage(.left);
        self.renderSignage(.right);
    }

    /// Clock painter: refreshed on the minute (called from a server timer).
    pub fn refreshClock(self: *Band) void {
        const minute = currentMinute();
        if (minute == self.last_minute and self.clock_buffer != null) return;
        self.last_minute = minute;
        const tree = self.right_tree orelse return;

        const s: i32 = @max(1, @as(i32, @intCast(self.scale)));
        const out_w: i32 = @intCast(self.output_width);
        const peek_w: i32 = @intFromFloat(@as(f64, @floatFromInt(out_w)) * peek_fraction);
        if (peek_w <= 0) return;
        const px_w: i32 = peek_w * s;
        const px_h: i32 = @as(i32, @intCast(clock_h)) * s;

        const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, px_w, px_h) orelse return;
        if (c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) {
            c.cairo_surface_destroy(surface);
            return;
        }
        const cr = c.cairo_create(surface) orelse {
            c.cairo_surface_destroy(surface);
            return;
        };
        defer c.cairo_destroy(cr);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        // HH:MM, dim gold, centered in the band.
        var buf: [8]u8 = undefined;
        const text = formatClock(&buf);
        const gold = self.style.color_gold.toF64();
        c.cairo_select_font_face(cr, "JetBrains Mono", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
        const fs: f64 = @floatFromInt(px_h);
        c.cairo_set_font_size(cr, fs * 0.62);
        var ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, text.ptr, &ext);
        const wf: f64 = @floatFromInt(px_w);
        c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.86);
        c.cairo_move_to(cr, (wf - ext.width) / 2.0 - ext.x_bearing, (fs - ext.height) / 2.0 - ext.y_bearing);
        c.cairo_show_text(cr, text.ptr);
        c.cairo_surface_flush(surface);

        const data = c.cairo_image_surface_get_data(surface) orelse {
            c.cairo_surface_destroy(surface);
            return;
        };
        const stride = c.cairo_image_surface_get_stride(surface);
        const bytes = @as([*]u8, @ptrCast(data))[0..@intCast(stride * px_h)];
        const buf2 = DataBuffer.create(bytes, px_w, px_h, stride) catch {
            c.cairo_surface_destroy(surface);
            return;
        };
        c.cairo_surface_destroy(surface);
        const sb = tree.createSceneBuffer(buf2) catch {
            wlr.Buffer.drop(buf2);
            return;
        };
        wlr.Buffer.drop(buf2);
        sb.setDestSize(@intCast(peek_w), @intCast(clock_h));
        // Pin to the right band, just below the vertical-center signage.
        const x = self.box_x + out_w - peek_w;
        const y = self.box_y + @divFloor(@as(i32, @intCast(self.output_height)), 2) +
            @as(i32, @intCast(icon_size));
        sb.node.setPosition(x, y);
        if (self.clock_buffer) |old| old.node.destroy();
        self.clock_buffer = sb;
    }

    fn renderSignage(self: *Band, side: Side) void {
        const tree = switch (side) {
            .left => self.left_tree orelse return,
            .right => self.right_tree orelse return,
        };
        const enabled = switch (side) {
            .left => self.has_left,
            .right => self.has_right,
        };
        const count = switch (side) {
            .left => self.left_count,
            .right => self.right_count,
        };

        const old = switch (side) {
            .left => self.left_signage,
            .right => self.right_signage,
        };
        if (old) |o| o.node.destroy();
        switch (side) {
            .left => self.left_signage = null,
            .right => self.right_signage = null,
        }
        // No neighbor on this side: the band is empty (but the TREE lives —
        // bands never hide; only their signage is absent at the row ends,
        // which is exactly the EXIT-sign law: ends are where the sign is
        // loudest, and a missing sign means "nowhere to walk").
        if (!enabled) return;

        const s: i32 = @max(1, @as(i32, @intCast(self.scale)));
        const out_w: i32 = @intCast(self.output_width);
        const peek_w: i32 = @intFromFloat(@as(f64, @floatFromInt(out_w)) * peek_fraction);
        if (peek_w <= 0) return;
        const px_w: i32 = peek_w * s;
        const px_h: i32 = @as(i32, @intCast(icon_size)) * s;

        const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, px_w, px_h) orelse return;
        if (c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) {
            c.cairo_surface_destroy(surface);
            return;
        }
        const cr = c.cairo_create(surface) orelse {
            c.cairo_surface_destroy(surface);
            return;
        };
        defer c.cairo_destroy(cr);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);
        c.cairo_set_source_rgba(cr, 0.30, 0.29, 0.25, 0.86);

        const wf: f64 = @floatFromInt(px_w);
        const hf: f64 = @floatFromInt(px_h);
        const sf: f64 = @floatFromInt(s);
        paintExitDotsSkin(cr, wf, hf, sf, side, count);
        c.cairo_surface_flush(surface);

        const data = c.cairo_image_surface_get_data(surface) orelse {
            c.cairo_surface_destroy(surface);
            return;
        };
        const stride = c.cairo_image_surface_get_stride(surface);
        const bytes = @as([*]u8, @ptrCast(data))[0..@intCast(stride * px_h)];
        const buf = DataBuffer.create(bytes, px_w, px_h, stride) catch {
            c.cairo_surface_destroy(surface);
            return;
        };
        c.cairo_surface_destroy(surface);
        const sb = tree.createSceneBuffer(buf) catch {
            wlr.Buffer.drop(buf);
            return;
        };
        wlr.Buffer.drop(buf);
        sb.setDestSize(@intCast(peek_w), @intCast(icon_size));
        const x: i32 = switch (side) {
            .left => self.box_x,
            .right => self.box_x + out_w - peek_w,
        };
        const y = self.box_y + @divFloor(@as(i32, @intCast(self.output_height)) - @as(i32, @intCast(icon_size)), 2);
        sb.node.setPosition(x, y);
        switch (side) {
            .left => self.left_signage = sb,
            .right => self.right_signage = sb,
        }
    }

    /// One click router: click = walk to the neighbor on that side.
    /// Output-local coords; returns the side clicked, or null.
    pub fn handleClick(self: *const Band, x: f64, y: f64) ?Side {
        const out_w: f64 = @floatFromInt(self.output_width);
        const out_h: f64 = @floatFromInt(self.output_height);
        const peek_w: f64 = out_w * peek_fraction;
        if (y < 0 or y >= out_h) return null;
        if (self.has_left and x >= 0 and x < peek_w) return .left;
        if (self.has_right and x >= out_w - peek_w and x < out_w) return .right;
        return null;
    }

    // ── Placeholder widget hooks (later cards — wire nothing) ────────────
    // pub fn refreshWeather(self: *Band) void  — weather readout, right band.
    // pub fn refreshSignals(self: *Band) void  — signals readout, right band.
    // pub fn refreshCharge(self: *Band) void   — session charge, beside clock.
};

fn currentMinute() i64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(linux.CLOCK.REALTIME, &ts);
    return @divFloor(@as(i64, ts.sec), 60);
}

fn formatClock(buf: *[8]u8) [:0]const u8 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(linux.CLOCK.REALTIME, &ts);
    // Kernel REALTIME is UTC; apply the host's local offset via libc
    // localtime_r (tm_gmtoff) — no TZ parsing on our side.
    const off = localOffsetSeconds(@as(i64, ts.sec));
    const local_secs: u64 = @intCast(@max(0, @as(i64, ts.sec) + off));
    const lh = (local_secs % 86400) / 3600;
    const lm = (local_secs % 3600) / 60;
    return std.fmt.bufPrintZ(buf, "{d:0>2}:{d:0>2}", .{ lh, lm }) catch "--:--";
}

extern "c" fn localtime_r(timep: *const i64, result: *Tm) ?*Tm;
const Tm = extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
    tm_gmtoff: i64,
    tm_zone: ?[*:0]const u8,
};

fn localOffsetSeconds(now: i64) i64 {
    var tm: Tm = undefined;
    if (localtime_r(&now, &tm) == null) return 0;
    return tm.tm_gmtoff;
}

// ── exit_dots skin (ported verbatim from spyglass.zig — the skin source) ──

fn paintExitDotsSkin(cr: *c.cairo_t, w: f64, h: f64, s: f64, side: Side, slide_count: u32) void {
    const dots_f: f64 = @as(f64, @floatFromInt(exit_dots_w)) * s;
    const char_sp: f64 = measureCharSpace(cr, h);
    const num_w: f64 = measureSlideCount(cr, h, slide_count);

    // EXIT dots: 1 char-space in from the slide-border side.
    const dots_x: f64 = if (side == .left) w - char_sp - dots_f else char_sp;
    c.cairo_save(cr);
    c.cairo_translate(cr, dots_x, 0.0);
    paintExitDots(cr, dots_f, h, s);
    c.cairo_restore(cr);

    // Digit: 1 char-space in from the screen-edge side.
    if (num_w > 0) {
        const num_x: f64 = if (side == .left) char_sp else w - char_sp - num_w;
        drawSlideCount(cr, h, slide_count, num_x);
    }
}

fn measureSlideCount(cr: *c.cairo_t, h: f64, count: u32) f64 {
    if (count == 0) return 0;
    var buf: [8]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, "{d}", .{count}) catch return 0;
    c.cairo_save(cr);
    c.cairo_set_font_size(cr, h * num_font_scale);
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, text.ptr, &ext);
    c.cairo_restore(cr);
    return ext.width;
}

fn measureCharSpace(cr: *c.cairo_t, h: f64) f64 {
    c.cairo_save(cr);
    c.cairo_set_font_size(cr, h * num_font_scale);
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, "0", &ext);
    c.cairo_restore(cr);
    return ext.x_advance;
}

fn drawSlideCount(cr: *c.cairo_t, h: f64, count: u32, tx: f64) void {
    var buf: [8]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, "{d}", .{count}) catch return;
    c.cairo_save(cr);
    c.cairo_set_font_size(cr, h * num_font_scale);
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, text.ptr, &ext);
    const ty: f64 = (h - ext.height) / 2.0 - ext.y_bearing;
    c.cairo_move_to(cr, tx - ext.x_bearing, ty);
    c.cairo_show_text(cr, text.ptr);
    c.cairo_restore(cr);
}

/// EXIT dot-matrix — 4x5 gold dots spelling E-X-I-T.
/// Theater exit signage. Same dot language as the kmedia helix balls.
fn paintExitDots(cr: *c.cairo_t, w: f64, h: f64, _: f64) void {
    const dot_r: f64 = @min(w, h) * 0.05;
    const dot_spacing: f64 = dot_r * 3.0;
    const letter_w: f64 = 5.0 * dot_spacing;
    const letter_h: f64 = 6.0 * dot_spacing;
    const letter_gap: f64 = dot_spacing * 0.8;

    const total_w: f64 = 4.0 * letter_w + 3.0 * letter_gap;
    const start_x: f64 = (w - total_w) / 2.0;
    const start_y: f64 = (h - letter_h) / 2.0;

    const e = [6][5]u8{
        .{ 1, 1, 1, 1, 1 },
        .{ 1, 0, 0, 0, 0 },
        .{ 1, 1, 1, 1, 0 },
        .{ 1, 0, 0, 0, 0 },
        .{ 1, 0, 0, 0, 0 },
        .{ 1, 1, 1, 1, 1 },
    };
    const x_l = [6][5]u8{
        .{ 1, 0, 0, 0, 1 },
        .{ 0, 1, 0, 1, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 1, 0, 1, 0 },
        .{ 1, 0, 0, 0, 1 },
    };
    const i_l = [6][5]u8{
        .{ 0, 1, 1, 1, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 1, 1, 1, 0 },
    };
    const t_l = [6][5]u8{
        .{ 1, 1, 1, 1, 1 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
    };

    const letters = [_][6][5]u8{ e, x_l, i_l, t_l };

    for (letters, 0..) |letter, li| {
        const lx = start_x + @as(f64, @floatFromInt(li)) * (letter_w + letter_gap);
        for (letter, 0..) |row, ri| {
            for (row, 0..) |on, ci| {
                if (on == 1) {
                    const cx = lx + @as(f64, @floatFromInt(ci)) * dot_spacing + dot_r;
                    const cy = start_y + @as(f64, @floatFromInt(ri)) * dot_spacing + dot_r;
                    c.cairo_arc(cr, cx, cy, dot_r, 0.0, 2.0 * std.math.pi);
                    c.cairo_fill(cr);
                }
            }
        }
    }
}
