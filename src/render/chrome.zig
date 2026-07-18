const std = @import("std");
const c = @import("../dm/c.zig").c;
const Style = @import("../core/style.zig").Style;
const Color = Style.Color;

pub const EdgeMode = struct {
    top: bool,
    right: bool,
    bottom: bool,
    left: bool,

    pub const all = EdgeMode{ .top = true, .right = true, .bottom = true, .left = true };
    // Side peek windows expose the edge that abuts the focused window and
    // hide the edge that points off-screen. This frames the focused window
    // with a border on each side while keeping the outer edges clean.
    pub const left_peek = EdgeMode{ .top = true, .right = true, .bottom = true, .left = false };
    pub const right_peek = EdgeMode{ .top = true, .right = false, .bottom = true, .left = true };

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

/// Render chrome overlay for a peek or focused window. Peeks get a full
/// dark glass fill with a hard 2 px border using the unfocused-slide border
/// color; focused windows keep the background mask and border ring.
pub fn renderChrome(style: Style, width: i32, height: i32, focused: bool, scale: u32, edges: EdgeMode, _: ?[]const u8) ?*c.cairo_surface_t {
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
    const is_peek = !edges.eql(EdgeMode.all);

    var scaled_style = style;
    scaled_style.border_width = @floatCast(border);
    scaled_style.corner_depth = @floatCast(depth);

    // Start transparent.
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_paint(cr);

    const border_color = if (focused) style.color_border_focused else if (is_peek) style.color_gold_dim else style.color_border;

    if (is_peek) {
        // Peek: full wrapper fill with black glass, then a hard 2 px border
        // on top. The overlay tree guarantees this is above the focused window.
        scaled_style.corner_style = .square;
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.85);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_rectangle(cr, 0.0, 0.0, w, h);
        c.cairo_fill(cr);

        const outer_border_w: f64 = 2.0 * @as(f64, @floatFromInt(s));
        c.cairo_set_line_width(cr, outer_border_w);
        setSource(cr, style.color_border, 1.0);
        c.cairo_rectangle(cr, outer_border_w / 2.0, outer_border_w / 2.0, w - outer_border_w, h - outer_border_w);
        c.cairo_stroke(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        // Trim off hidden off-screen edges.
        const clear_w = @min(w / 2.0, depth + border + 1.0);
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
    } else {
        // Focused / normal window: background mask and border ring.
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
    }

    return surface;
}

/// Render a dark shading overlay for unfocused side slides.
pub fn renderUnfocusedShade(style: Style, width: i32, height: i32, direction: i8, inner_alpha: f64, outer_alpha: f64) ?*c.cairo_surface_t {
    if (width <= 0 or height <= 0) return null;
    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, width, height) orelse return null;
    const cr = c.cairo_create(surface) orelse {
        c.cairo_surface_destroy(surface);
        return null;
    };
    defer c.cairo_destroy(cr);

    const w: f64 = @floatFromInt(width);
    const h: f64 = @floatFromInt(height);

    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_paint(cr);

    var x0: f64 = 0;
    var y0: f64 = 0;
    var x1: f64 = 0;
    var y1: f64 = 0;
    switch (direction) {
        -1 => { x0 = w; y0 = 0; x1 = 0; y1 = 0; },
        1 => { x0 = 0; y0 = 0; x1 = w; y1 = 0; },
        else => { x0 = 0; y0 = 0; x1 = 0; y1 = h; },
    }

    const grad = c.cairo_pattern_create_linear(x0, y0, x1, y1);
    defer c.cairo_pattern_destroy(grad);
    const bg = style.color_background.toF64();
    c.cairo_pattern_add_color_stop_rgba(grad, 0.0, bg[0], bg[1], bg[2], inner_alpha);
    c.cairo_pattern_add_color_stop_rgba(grad, 1.0, bg[0], bg[1], bg[2], outer_alpha);

    windowPath(cr, 0.0, 0.0, w, h, style);
    c.cairo_set_source(cr, grad);
    c.cairo_fill(cr);

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
