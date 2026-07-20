const std = @import("std");
const c = @import("dm").c;
const style = @import("../core/style.zig");

/// Draw a black-glass 3D frame around a card surface of size (w,h).
///
/// The caller has already cleared the surface. This function paints, in order:
/// 1. A soft drop shadow cast toward the focused slide behind the card.
/// 2. A solid dark body fill inside the rounded outline.
/// 3. A black-glass vignette that darkens the edges and is transparent in the
///    middle, giving the card the appearance of receding thickness.
/// 4. Thin inner rim highlights / shadows on the top-left and bottom-right
///    edges so the card reads as beveled and popping forward.
/// 5. The original theme border stroke on the outside.
///
/// The clipping region is left set to the interior (inset by 1 px) so content
/// drawn after this call is contained by the rim.
pub fn drawBlackGlassFrame(
    cr: *c.cairo_t,
    tstyle: style.Style,
    w: f64,
    h: f64,
) void {
    const bg = tstyle.tray_bg_color;
    const rim = tstyle.color_card_border;

    const corner_depth: f64 = @min(14.0, @min(w, h) * 0.05);
    const stroke_w: f64 = 2.0;

    const bg4 = bg.toF64();
    const rim4 = rim.toF64();

    // 1. Solid body fill. The depth/falloff is drawn on the slide layer behind.
    roundedRect(cr, 0.0, 0.0, w, h, corner_depth);
    // Card body pinned at 91% opacity so content stays readable while still reading as glass.
    c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], 0.91);
    c.cairo_fill(cr);

    // 2. Inner rim lighting: bright top-left, dark bottom-right.
    c.cairo_save(cr);
    roundedRect(cr, 1.0, 1.0, w - 2.0, h - 2.0, @max(0.0, corner_depth - 1.0));
    c.cairo_clip(cr);

    // Top-left rim glow.
    const glow_w: f64 = 3.0;
    const tl = c.cairo_pattern_create_linear(0.0, 0.0, glow_w, glow_w).?;
    c.cairo_pattern_add_color_stop_rgba(tl, 0.0, 1.0, 1.0, 1.0, 0.22);
    c.cairo_pattern_add_color_stop_rgba(tl, 1.0, 1.0, 1.0, 1.0, 0.00);
    c.cairo_set_source(cr, tl);
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, 0.0, 0.0);
    c.cairo_line_to(cr, glow_w * 2.0, 0.0);
    c.cairo_line_to(cr, 0.0, glow_w * 2.0);
    c.cairo_close_path(cr);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(tl);

    // Bottom-right rim shadow.
    const br = c.cairo_pattern_create_linear(w - glow_w, h - glow_w, w, h).?;
    c.cairo_pattern_add_color_stop_rgba(br, 0.0, 0.0, 0.0, 0.0, 0.00);
    c.cairo_pattern_add_color_stop_rgba(br, 1.0, 0.0, 0.0, 0.0, 0.45);
    c.cairo_set_source(cr, br);
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, w, h);
    c.cairo_line_to(cr, w - glow_w * 2.0, h);
    c.cairo_line_to(cr, w, h - glow_w * 2.0);
    c.cairo_close_path(cr);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(br);

    c.cairo_restore(cr);

    // 3. Outer card rim.
    roundedRect(cr, 0.0, 0.0, w, h, corner_depth);
    c.cairo_set_source_rgba(cr, rim4[0], rim4[1], rim4[2], rim4[3]);
    c.cairo_set_line_width(cr, stroke_w);
    c.cairo_stroke(cr);

    // 6. Clip caller content to interior.
    roundedRect(cr, 1.0, 1.0, w - 2.0, h - 2.0, @max(0.0, corner_depth - 1.0));
    c.cairo_clip(cr);
}



pub fn drawCardShadow(
    cr: *c.cairo_t,
    tstyle: style.Style,
    box_w: f64,
    box_h: f64,
    card_w: f64,
    card_h: f64,
) void {
    _ = tstyle;

    // Clear to transparent.
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_paint(cr);

    const card_x = (box_w - card_w) * 0.5;
    const card_y = (box_h - card_h) * 0.5;

    // Light from top-left: the bottom/right gaps catch the most shadow,
    // the top/left gaps catch less. The sides actually meet at the corners
    // because the vertical and horizontal strips overlap, naturally darkening
    // the far (bottom-right) corner and lightening the near (top-left) one.
    const top_alpha: f64 = 0.38;
    const left_alpha: f64 = 0.38;
    const bottom_alpha: f64 = 0.82;
    const right_alpha: f64 = 0.82;

    // Helper: draw a rectangle filled with a two-stop linear gradient.
    const Strip = struct {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        x0: f64,
        y0: f64,
        x1: f64,
        y1: f64,
        inner_a: f64,
    };
    const strips = [_]Strip{
        .{ .x = 0.0, .y = 0.0, .w = card_x, .h = box_h, .x0 = 0.0,  .y0 = 0.0, .x1 = card_x, .y1 = 0.0,           .inner_a = left_alpha },
        .{ .x = card_x + card_w, .y = 0.0, .w = box_w - (card_x + card_w), .h = box_h, .x0 = card_x + card_w, .y0 = 0.0, .x1 = box_w, .y1 = 0.0, .inner_a = right_alpha },
        .{ .x = 0.0, .y = 0.0, .w = box_w, .h = card_y, .x0 = 0.0, .y0 = 0.0, .x1 = 0.0, .y1 = card_y,           .inner_a = top_alpha },
        .{ .x = 0.0, .y = card_y + card_h, .w = box_w, .h = box_h - (card_y + card_h), .x0 = 0.0, .y0 = card_y + card_h, .x1 = 0.0, .y1 = box_h, .inner_a = bottom_alpha },
    };
    for (strips) |s| {
        if (s.w <= 0.0 or s.h <= 0.0) continue;
        c.cairo_rectangle(cr, s.x, s.y, s.w, s.h);
        const grad = c.cairo_pattern_create_linear(s.x0, s.y0, s.x1, s.y1).?;
        // Use a power curve so the shadow hugs the card near the edge and
        // fades quickly in the first half of the gap, then gently out.
        c.cairo_pattern_add_color_stop_rgba(grad, 0.00, 0.0, 0.0, 0.0, 0.00);
        c.cairo_pattern_add_color_stop_rgba(grad, 0.55, 0.0, 0.0, 0.0, s.inner_a * 0.85);
        c.cairo_pattern_add_color_stop_rgba(grad, 1.00, 0.0, 0.0, 0.0, s.inner_a);
        c.cairo_set_source(cr, grad);
        c.cairo_fill(cr);
        c.cairo_pattern_destroy(grad);
    }
}
fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
    const radius = @min(r, w / 2.0, h / 2.0);
    if (radius <= 0.0) {
        c.cairo_rectangle(cr, x, y, w, h);
        return;
    }
    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, x + w - radius, y + radius, radius, -std.math.pi / 2.0, 0.0);
    c.cairo_arc(cr, x + w - radius, y + h - radius, radius, 0.0, std.math.pi / 2.0);
    c.cairo_arc(cr, x + radius, y + h - radius, radius, std.math.pi / 2.0, std.math.pi);
    c.cairo_arc(cr, x + radius, y + radius, radius, std.math.pi, 3.0 * std.math.pi / 2.0);
    c.cairo_close_path(cr);
}
