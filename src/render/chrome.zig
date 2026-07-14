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

fn windowPath(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, style: Style) void {
    switch (style.corner_style) {
        .classic => roundedRect(cr, x, y, w, h, style.corner_depth),
        .none => squareRect(cr, x, y, w, h),
    }
}

fn colorF64(color: Color) [4]f64 {
    return .{
        @as(f64, @floatFromInt(color.r)) / 255.0,
        @as(f64, @floatFromInt(color.g)) / 255.0,
        @as(f64, @floatFromInt(color.b)) / 255.0,
        @as(f64, @floatFromInt(color.a)) / 255.0,
    };
}

/// Render black glass + label + border for a peek window, or just the border
/// overlay for a focused window. If `label` is non-null and edges is not `all`,
/// the glass gradient and gold program label are drawn behind the border ring.
pub fn renderChrome(style: Style, width: i32, height: i32, focused: bool, scale: u32, edges: EdgeMode, label: ?[]const u8) ?*c.cairo_surface_t {
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

    const border_color = if (focused) style.color_border_focused else style.color_border;

    if (is_peek) {
        // Draw the glass into an area guaranteed to survive the outer-edge trim.
        // Peeks hide the outer edge and trim the seam, so keep glass inset from
        // those sides. Leave the top/bottom border margin too.
        const inset = @max(border + depth + 1.0, @as(f64, @floatFromInt(style.peek_label_inset)));
        const glass_x = 0.0 + inset;
        const glass_y = 0.0 + border;
        const glass_w = w - inset * 2.0;
        const glass_h = h - border * 2.0;
        // Don't let a tiny sliver produce negative glass rect.
        if (glass_w > 4.0 and glass_h > 4.0) {
            drawPeekGlass(cr, glass_x, glass_y, glass_w, glass_h, style, edges, label);
        }
    }

    // Background mask and border ring.
    // Client surfaces are rectangular and may leak rounded corners/shadows into
    // the area outside the intended content shape. Fill that region with the
    // compositor background colour so the window edge is clean, then paint the
    // border ring on top.
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

    // Trim borders on hidden/shared edges. Clear a strip that is wide enough
    // to remove both the straight border and the corner arc at the seam.
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

    return surface;
}

fn drawPeekGlass(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, style: Style, edges: EdgeMode, label: ?[]const u8) void {
    // Clip to the glass rectangle only; don't touch corners/seams.
    c.cairo_save(cr);
    c.cairo_rectangle(cr, x, y, w, h);
    c.cairo_clip(cr);

    // 1. Vertical gradient: more solid at top/bottom, more transparent mid.
    const v_grad = c.cairo_pattern_create_linear(x, y, x, y + h);
    defer c.cairo_pattern_destroy(v_grad);
    c.cairo_pattern_add_color_stop_rgba(v_grad, 0.0, 0.0, 0.0, 0.0, style.peek_glass_alpha_top);
    c.cairo_pattern_add_color_stop_rgba(v_grad, 0.5, 0.0, 0.0, 0.0, style.peek_glass_alpha_mid);
    c.cairo_pattern_add_color_stop_rgba(v_grad, 1.0, 0.0, 0.0, 0.0, style.peek_glass_alpha_top);

    c.cairo_rectangle(cr, x, y, w, h);
    c.cairo_set_source(cr, v_grad);
    c.cairo_fill(cr);

    // 2. Horizontal fade: inner edge (by focused window) stays as-is; outer edge
    //    gets an extra darker overlay so it's less transparent than the middle.
    //    For left/right peeks the outer edge is the hidden one, so on the visible
    //    sliver the gradient ramps from inner (less extra) to outer (more extra).
    var x0: f64 = x + w;
    var x1: f64 = x;
    if (edges.left) {
        // left peek visible left; outer = left; inner = right
        x0 = x;
        x1 = x + w;
    }
    const h_grad = c.cairo_pattern_create_linear(x0, y, x1, y);
    defer c.cairo_pattern_destroy(h_grad);
    c.cairo_pattern_add_color_stop_rgba(h_grad, 0.0, 0.0, 0.0, 0.0, style.peek_glass_alpha_outer);
    c.cairo_pattern_add_color_stop_rgba(h_grad, 1.0, 0.0, 0.0, 0.0, style.peek_glass_alpha_inner);

    c.cairo_rectangle(cr, x, y, w, h);
    c.cairo_set_source(cr, h_grad);
    c.cairo_fill(cr);

    // 3. Program-name label at the top, anchored toward the inner (visible) edge.
    if (label) |text| {
        const font_size: f64 = @max(8.0, @as(f64, style.peek_label_font_size));
        c.cairo_select_font_face(cr, "FantasqueSansM Nerd Font", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
        c.cairo_set_font_size(cr, font_size);

        var extents: c.cairo_text_extents_t = undefined;
        if (text.len > 0) {
            c.cairo_text_extents(cr, text.ptr, &extents);
        }
        const pad: f64 = @as(f64, @floatFromInt(style.peek_label_inset));
        const label_x = if (edges.left) x + pad else x + w - extents.width - pad;
        const label_y = y + pad + font_size;

        // Subtle dark drop shadow for legibility over any content.
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.8);
        c.cairo_move_to(cr, label_x + 1.0, label_y + 1.0);
        c.cairo_show_text(cr, text.ptr);

        const gold = colorF64(style.color_gold);
        c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 1.0);
        c.cairo_move_to(cr, label_x, label_y);
        c.cairo_show_text(cr, text.ptr);
    }

    c.cairo_restore(cr);
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
    const bg = colorF64(style.color_background);
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
