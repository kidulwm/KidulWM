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
};

fn setSource(cr: *c.cairo_t, color: Color, alpha: f64) void {
    const c4 = color.toF64();
    c.cairo_set_source_rgba(cr, c4[0], c4[1], c4[2], c4[3] * alpha);
}

fn chamferRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, d: f64) void {
    c.cairo_move_to(cr, x + d, y);
    c.cairo_line_to(cr, x + w - d, y);
    c.cairo_line_to(cr, x + w, y + d);
    c.cairo_line_to(cr, x + w, y + h - d);
    c.cairo_line_to(cr, x + w - d, y + h);
    c.cairo_line_to(cr, x + d, y + h);
    c.cairo_line_to(cr, x, y + h - d);
    c.cairo_line_to(cr, x, y + d);
    c.cairo_close_path(cr);
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

const EdgeOffset = struct { a: [2]f64, b: [2]f64 };

fn inwardOffsetEdge(p1: [2]f64, p2: [2]f64, inset: f64) EdgeOffset {
    const dx = p2[0] - p1[0];
    const dy = p2[1] - p1[1];
    const len = @sqrt(dx * dx + dy * dy);
    if (len < 0.001) return .{ .a = p1, .b = p2 };
    // left normal for CCW edge points inward
    const nx = -dy / len;
    const ny = dx / len;
    const ox = nx * inset;
    const oy = ny * inset;
    return .{
        .a = .{ p1[0] + ox, p1[1] + oy },
        .b = .{ p2[0] + ox, p2[1] + oy },
    };
}

fn lineIntersection(a1: [2]f64, a2: [2]f64, b1: [2]f64, b2: [2]f64) [2]f64 {
    const x1, const y1 = a1;
    const x2, const y2 = a2;
    const x3, const y3 = b1;
    const x4, const y4 = b2;
    const denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (@abs(denom) < 1e-9) return a2;
    const px = ((x1 * y2 - y1 * x2) * (x3 - x4) - (x1 - x2) * (x3 * y4 - y3 * x4)) / denom;
    const py = ((x1 * y2 - y1 * x2) * (y3 - y4) - (y1 - y2) * (x3 * y4 - y3 * x4)) / denom;
    return .{ px, py };
}

fn drawPolygon(cr: *c.cairo_t, points: []const [2]f64) void {
    if (points.len == 0) return;
    c.cairo_move_to(cr, points[0][0], points[0][1]);
    for (points[1..]) |pt| {
        c.cairo_line_to(cr, pt[0], pt[1]);
    }
    c.cairo_close_path(cr);
}

fn chamferInnerPolygon(w: f64, h: f64, depth: f64, straight_inset: f64, chamfer_inset: f64) [8][2]f64 {
    // Outer CCW chamfer polygon.
    const outer = [8][2]f64{
        .{ depth, 0.0 },
        .{ w - depth, 0.0 },
        .{ w, depth },
        .{ w, h - depth },
        .{ w - depth, h },
        .{ depth, h },
        .{ 0.0, h - depth },
        .{ 0.0, depth },
    };

    // Edge offsets: 0=top, 1=right-chamfer, 2=right, 3=bottom-chamfer,
    // 4=bottom, 5=left-chamfer, 6=left, 7=top-chamfer.
    const insets = [8]f64{
        straight_inset, chamfer_inset, straight_inset, chamfer_inset,
        straight_inset, chamfer_inset, straight_inset, chamfer_inset,
    };

    var offset_edges: [8]EdgeOffset = undefined;
    for (0..8) |i| {
        offset_edges[i] = inwardOffsetEdge(outer[i], outer[(i + 1) % 8], insets[i]);
    }

    var inner: [8][2]f64 = undefined;
    for (0..8) |i| {
        const e1 = offset_edges[i];
        const e2 = offset_edges[(i + 1) % 8];
        inner[i] = lineIntersection(e1.a, e1.b, e2.a, e2.b);
    }
    return inner;
}

fn windowPath(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, style: Style) void {
    switch (style.corner_style) {
        .cut => chamferRect(cr, x, y, w, h, style.corner_depth),
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

/// Render a window chrome overlay with transparent interior and shaped border.
/// `scale` is the output scale; width/height are logical pixels and the buffer
/// is rendered at scale*width x scale*height.
pub fn renderChrome(style: Style, width: i32, height: i32, focused: bool, scale: u32, edges: EdgeMode) ?*c.cairo_surface_t {
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
    const chamfer_border: f64 = @max(1.0, @as(f64, style.chamfer_border_width) * @as(f64, @floatFromInt(s)));
    const depth: f64 = @max(0.0, @as(f64, style.corner_depth) * @as(f64, @floatFromInt(s)));

    var scaled_style = style;
    scaled_style.border_width = @floatCast(border);
    scaled_style.chamfer_border_width = @floatCast(chamfer_border);
    scaled_style.corner_depth = @floatCast(depth);

    // Start transparent.
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_paint(cr);

    // Background mask and border ring.
    // Client surfaces are rectangular and may leak rounded corners/shadows into
    // the area outside the intended content shape. Fill that region with the
    // compositor background colour so the window edge is clean, then paint the
    // border ring on top.
    const use_variable = scaled_style.corner_style == .cut and depth > 0.0;
    const border_color = if (focused) style.color_border_focused else style.color_border;

    if (use_variable) {
        if (w > (border + chamfer_border + depth) * 2.0 and h > (border + chamfer_border + depth) * 2.0) {
            const inner = chamferInnerPolygon(w, h, depth, border, chamfer_border);

            // Mask: full window square minus inner chamfer shape.
            squareRect(cr, 0.0, 0.0, w, h);
            drawPolygon(cr, inner[0..]);
            c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_EVEN_ODD);
            setSource(cr, style.color_background, 1.0);
            c.cairo_fill(cr);

            // Border ring: outer chamfer minus inner chamfer.
            chamferRect(cr, 0.0, 0.0, w, h, depth);
            drawPolygon(cr, inner[0..]);
            c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_EVEN_ODD);
            setSource(cr, border_color, 1.0);
            c.cairo_fill(cr);
            c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_WINDING);
        } else {
            windowPath(cr, 0.0, 0.0, w, h, scaled_style);
            setSource(cr, border_color, 1.0);
            c.cairo_fill(cr);
        }
    } else {
        windowPath(cr, 0.0, 0.0, w, h, scaled_style);
        var inner_style = scaled_style;
        if (w > border * 3.0 and h > border * 3.0) {
            inner_style.corner_depth = @max(@as(f32, 0.0), @as(f32, @floatCast(depth - border)));
            windowPath(cr, border, border, w - border * 2.0, h - border * 2.0, inner_style);
        }
        // Mask: outer shape minus inner content shape.
        c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_EVEN_ODD);
        setSource(cr, style.color_background, 1.0);
        c.cairo_fill_preserve(cr);
        // Border ring on top.
        c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_EVEN_ODD);
        setSource(cr, border_color, 1.0);
        c.cairo_fill(cr);
        c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_WINDING);
    }

    // Trim borders on hidden/shared edges. Clear a strip that is wide enough
    // to remove both the straight border and the chamfer wedge at the seam.
    const clear_w = @min(w / 2.0, depth + @max(border, chamfer_border) + 1.0);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_DEST_OUT);
    if (!edges.left) c.cairo_rectangle(cr, 0.0, 0.0, clear_w, h);
    if (!edges.right) c.cairo_rectangle(cr, w - clear_w, 0.0, clear_w, h);
    if (!edges.top) c.cairo_rectangle(cr, 0.0, 0.0, w, clear_w);
    if (!edges.bottom) c.cairo_rectangle(cr, 0.0, h - clear_w, w, clear_w);
    c.cairo_fill(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    // Focused: inner glow line, just inside the inner border edge.
    if (focused) {
        const inset = border + @max(border, chamfer_border);
        const iw: f64 = w - inset * 2.0;
        const ih: f64 = h - inset * 2.0;
        if (iw > 1.0 and ih > 1.0) {
            var glow_style = scaled_style;
            glow_style.corner_depth = @max(@as(f32, 0.0), @as(f32, @floatCast(depth - inset)));
            windowPath(cr, inset, inset, iw, ih, glow_style);
            const glow = colorF64(style.color_glow);
            c.cairo_set_source_rgba(cr, glow[0], glow[1], glow[2], glow[3]);
            c.cairo_set_line_width(cr, 1.0 * @as(f64, @floatFromInt(s)));
            c.cairo_stroke(cr);
        }
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
