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
    const gold = tstyle.color_gold;

    const corner_depth: f64 = @min(14.0, @min(w, h) * 0.05);
    const stroke_w: f64 = 2.0;
    const shadow_offset: f64 = 4.0;
    const shadow_blur: f64 = 14.0;
    const vignette_inset: f64 = 18.0;

    const bg4 = bg.toF64();
    const gold4 = gold.toF64();

    // 1. Soft drop shadow, offset toward the focused slide behind the card.
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);
    const shadow_steps: usize = 6;
    var i: usize = 0;
    while (i < shadow_steps) : (i += 1) {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(shadow_steps - 1));
        const base_alpha: f64 = 0.32 * (1.0 - t * t);
        const sw = stroke_w + shadow_blur * (1.0 - t);
        roundedRect(cr, shadow_offset - sw, shadow_offset - sw, w + sw * 2.0, h + sw * 2.0, corner_depth + sw);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, base_alpha);
        c.cairo_fill(cr);
    }

    // 2. Body fill.
    roundedRect(cr, 0.0, 0.0, w, h, corner_depth);
    c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], bg4[3]);
    c.cairo_fill_preserve(cr);

    // 3. Black-glass edge vignette: dark near the rim, clear in the middle.
    // We clip to the body, then fill an inset shape with an even-odd gradient.
    c.cairo_save(cr);
    c.cairo_clip(cr);

    const inner_x = vignette_inset;
    const inner_y = vignette_inset;
    const inner_w = w - vignette_inset * 2.0;
    const inner_h = h - vignette_inset * 2.0;

    if (inner_w > 0.0 and inner_h > 0.0) {
        const inner_r = @max(0.0, corner_depth - vignette_inset);

        roundedRect(cr, 0.0, 0.0, w, h, corner_depth);
        roundedRect(cr, inner_x, inner_y, inner_w, inner_h, inner_r);
        c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_EVEN_ODD);

        const grad = c.cairo_pattern_create_linear(0.0, 0.0, w, h).?;
        c.cairo_pattern_add_color_stop_rgba(grad, 0.00, 0.02, 0.02, 0.02, 0.62);
        c.cairo_pattern_add_color_stop_rgba(grad, 0.25, 0.02, 0.02, 0.02, 0.30);
        c.cairo_pattern_add_color_stop_rgba(grad, 0.50, 0.02, 0.02, 0.02, 0.00);
        c.cairo_pattern_add_color_stop_rgba(grad, 0.75, 0.02, 0.02, 0.02, 0.30);
        c.cairo_pattern_add_color_stop_rgba(grad, 1.00, 0.02, 0.02, 0.02, 0.62);
        c.cairo_set_source(cr, grad);
        c.cairo_fill(cr);
        c.cairo_pattern_destroy(grad);

        c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_WINDING);
    }
    c.cairo_restore(cr);

    // 4. Inner rim lighting: bright top-left, dark bottom-right.
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

    // 5. Outer gold rim.
    roundedRect(cr, 0.0, 0.0, w, h, corner_depth);
    c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], gold4[3]);
    c.cairo_set_line_width(cr, stroke_w);
    c.cairo_stroke(cr);

    // 6. Clip caller content to interior.
    roundedRect(cr, 1.0, 1.0, w - 2.0, h - 2.0, @max(0.0, corner_depth - 1.0));
    c.cairo_clip(cr);
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
