const std = @import("std");
const c = @import("dm").c;
const Style = @import("../core/style.zig").Style;
const Color = Style.Color;

pub const EdgeMode = struct {
    top: bool,
    right: bool,
    bottom: bool,
    left: bool,

    pub const all = EdgeMode{ .top = true, .right = true, .bottom = true, .left = true };

    pub fn eql(self: EdgeMode, other: EdgeMode) bool {
        return self.top == other.top and
            self.right == other.right and
            self.bottom == other.bottom and
            self.left == other.left;
    }
};

fn setSource(cr: *c.cairo_t, color: Color, alpha: f64) void {
    const c4 = color.toF64();
    c.cairo_set_source_rgba(cr, c4[0], c4[1], c4[2], c4[3] * alpha);
}

fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
    const radius = @min(r, w / 2.0, h / 2.0);
    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, x + w - radius, y + radius, radius, -std.math.pi / 2.0, 0.0);
    c.cairo_arc(cr, x + w - radius, y + h - radius, radius, 0.0, std.math.pi / 2.0);
    c.cairo_arc(cr, x + radius, y + h - radius, radius, std.math.pi / 2.0, std.math.pi);
    c.cairo_arc(cr, x + radius, y + radius, radius, std.math.pi, 3.0 * std.math.pi / 2.0);
    c.cairo_close_path(cr);
}

fn squareRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64) void {
    c.cairo_rectangle(cr, x, y, w, h);
}

fn chamferRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, d: f64) void {
    const depth = @min(d, w / 2.0, h / 2.0);
    c.cairo_new_sub_path(cr);
    c.cairo_move_to(cr, x + depth, y);
    c.cairo_line_to(cr, x + w - depth, y);
    c.cairo_line_to(cr, x + w, y + depth);
    c.cairo_line_to(cr, x + w, y + h - depth);
    c.cairo_line_to(cr, x + w - depth, y + h);
    c.cairo_line_to(cr, x + depth, y + h);
    c.cairo_line_to(cr, x, y + h - depth);
    c.cairo_line_to(cr, x, y + depth);
    c.cairo_close_path(cr);
}

fn windowPath(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, style: Style) void {
    switch (style.corner_style) {
        .round => roundedRect(cr, x, y, w, h, style.corner_depth),
        .chamfer => chamferRect(cr, x, y, w, h, style.corner_depth),
        .square => squareRect(cr, x, y, w, h),
    }
}

/// Render the compositor-drawn chrome overlay for a focused window.
/// Draws a border ring using the theme's border width and corner style.
/// The background mask fills the ring area; the interior is transparent
/// so the client surface shows through.
pub fn renderChrome(style: Style, width: i32, height: i32, focused: bool, scale: u32, edges: EdgeMode, _: ?[]const u8) ?*c.cairo_surface_t {
    _ = focused; // always focused now — no peek path
    if (width <= 0 or height <= 0) return null;
    const s: i32 = @max(1, @as(i32, @intCast(scale)));
    const bw: i32 = width * s;
    const bh: i32 = height * s;
    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, bw, bh) orelse return null;
    const cr = c.cairo_create(surface) orelse {
        c.cairo_surface_destroy(surface);
        return null;
    };
    defer c.cairo_destroy(cr);

    const w: f64 = @floatFromInt(bw);
    const h: f64 = @floatFromInt(bh);
    const border: f64 = @max(1.0, @as(f64, style.border_width) * @as(f64, @floatFromInt(s)));
    const depth: f64 = @max(0.0, @as(f64, style.corner_depth) * @as(f64, @floatFromInt(s)));

    var scaled_style = style;
    scaled_style.border_width = @floatCast(border);
    scaled_style.corner_depth = @floatCast(depth);

    // Start transparent.
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_paint(cr);

    const border_color = style.color_border_focused;

    // Focused window: background mask and border ring.
    windowPath(cr, 0.0, 0.0, w, h, scaled_style);
    if (w > border * 3.0 and h > border * 3.0) {
        var inner_style = scaled_style;
        const inner_depth = @max(@as(f32, 0.0), @as(f32, @floatCast(depth - border)));
        inner_style.corner_depth = inner_depth;
        windowPath(cr, border, border, w - border * 2.0, h - border * 2.0, inner_style);
    }

    c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_EVEN_ODD);
    setSource(cr, style.color_background, 1.0);
    c.cairo_fill_preserve(cr);

    c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_EVEN_ODD);
    setSource(cr, border_color, 1.0);
    c.cairo_fill(cr);
    c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_WINDING);

    // Trim off hidden off-screen edges (for future use — currently all edges visible).
    const clear_w = if (scaled_style.corner_style == .square)
        border + 1.0
    else
        @min(w / 2.0, depth + border + 1.0);
    const clear_left = if (!edges.left) clear_w else 0.0;
    const clear_right = if (!edges.right) clear_w else 0.0;
    const clear_top = if (!edges.top) clear_w else 0.0;
    const clear_bottom = if (!edges.bottom) clear_w else 0.0;

    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_DEST_OUT);
    if (clear_left > 0.0) c.cairo_rectangle(cr, 0.0, 0.0, clear_left, h);
    if (clear_right > 0.0) c.cairo_rectangle(cr, w - clear_right, 0.0, clear_right, h);
    if (clear_top > 0.0) c.cairo_rectangle(cr, 0.0, 0.0, w, clear_top);
    if (clear_bottom > 0.0) c.cairo_rectangle(cr, 0.0, h - clear_bottom, w, clear_bottom);
    c.cairo_fill(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    return surface;
}

/// Render the overview mini focus ring in the double-border language:
/// light outer ring (gold) wrapping a dark inner ring, transparent interior.
/// Non-focused minis get nothing — the ring IS the focus indicator.
/// Rings are STROKED, not filled — an even-odd fill over two nested paths
/// self-cancels and renders nothing.
pub fn renderMiniRing(style: Style, width: i32, height: i32, scale: u32) ?*c.cairo_surface_t {
    if (width <= 0 or height <= 0) return null;
    const s: i32 = @max(1, @as(i32, @intCast(scale)));
    const bw: i32 = width * s;
    const bh: i32 = height * s;
    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, bw, bh) orelse return null;
    const cr = c.cairo_create(surface) orelse {
        c.cairo_surface_destroy(surface);
        return null;
    };
    defer c.cairo_destroy(cr);

    const w: f64 = @floatFromInt(bw);
    const h: f64 = @floatFromInt(bh);
    const sf: f64 = @floatFromInt(s);
    const outer_w: f64 = @max(1.0, @as(f64, style.double_border_outer_w) * sf);
    const inner_w: f64 = @max(1.0, @as(f64, style.double_border_inner_w) * sf);
    const depth: f64 = @max(0.0, @as(f64, style.corner_depth) * sf * 0.5); // tighter corners at mini scale

    // Transparent start.
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_paint(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    var ring_style = style;
    ring_style.corner_depth = @floatCast(depth);

    // Outer light ring: stroke centered on the outer_w/2 inset path.
    var outer_style = ring_style;
    outer_style.corner_depth = @floatCast(@max(0.0, depth - outer_w * 0.5));
    const oi = outer_w * 0.5;
    windowPath(cr, oi, oi, w - outer_w, h - outer_w, outer_style);
    setSource(cr, style.double_border_outer, 1.0);
    c.cairo_set_line_width(cr, outer_w);
    c.cairo_stroke(cr);

    // Dark inner ring: stroke centered just inside it.
    var inner_style = ring_style;
    inner_style.corner_depth = @floatCast(@max(0.0, depth - outer_w - inner_w * 0.5));
    const ii = outer_w + inner_w * 0.5;
    windowPath(cr, ii, ii, w - ii * 2.0, h - ii * 2.0, inner_style);
    setSource(cr, style.double_border_inner, 1.0);
    c.cairo_set_line_width(cr, inner_w);
    c.cairo_stroke(cr);

    return surface;
}

/// Return the raw ARGB32 pixel slice and stride for a Cairo surface.
pub fn surfacePixels(surface: *c.cairo_surface_t) struct { pixels: []const u8, width: i32, height: i32, stride: i32 } {
    const stride = c.cairo_image_surface_get_stride(surface);
    const width = c.cairo_image_surface_get_width(surface);
    const height = c.cairo_image_surface_get_height(surface);
    const data = c.cairo_image_surface_get_data(surface);
    const bytes = @as([*]u8, @ptrCast(data))[0..@intCast(stride * height)];
    return .{ .pixels = bytes, .width = width, .height = height, .stride = stride };
}
