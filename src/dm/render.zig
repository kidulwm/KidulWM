// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const c = @import("c.zig").c;
const Style = @import("style.zig").Style;
const Color = Style.Color;

fn setSource(cr: *c.cairo_t, color: Color, alpha_mult: f64) void {
    const c4 = color.toF64();
    c.cairo_set_source_rgba(cr, c4[0], c4[1], c4[2], c4[3] * alpha_mult);
}

fn moveTo(cr: *c.cairo_t, x: f64, y: f64) void {
    c.cairo_move_to(cr, x, y);
}

fn lineTo(cr: *c.cairo_t, x: f64, y: f64) void {
    c.cairo_line_to(cr, x, y);
}

/// Chamfered rectangle path, clockwise from top-left
fn chamferRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, d: f64) void {
    moveTo(cr, x + d, y);
    lineTo(cr, x + w - d, y);
    lineTo(cr, x + w, y + d);
    lineTo(cr, x + w, y + h - d);
    lineTo(cr, x + w - d, y + h);
    lineTo(cr, x + d, y + h);
    lineTo(cr, x, y + h - d);
    lineTo(cr, x, y + d);
    c.cairo_close_path(cr);
}

/// Stroke a chamfered rectangle with a gradient that runs from dim gold
/// through gold and back to dim. `focus_t` is focus pulse 0..1
fn strokeChamferBorder(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, d: f64, style: Style, focus_t: f64) void {
    _ = d;
    const grad = c.cairo_pattern_create_linear(x, y, x + w, y + h);
    defer c.cairo_pattern_destroy(grad);

    const dim = style.color_gold_dim.toF64();
    const gold = style.color_gold.toF64();
    const soft = style.color_gold_soft.toF64();

    const pulse = 0.5 + 0.5 * focus_t;

    c.cairo_pattern_add_color_stop_rgba(grad, 0.0, dim[0], dim[1], dim[2], dim[3] * focus_t);
    c.cairo_pattern_add_color_stop_rgba(grad, 0.20, soft[0], soft[1], soft[2], soft[3] * pulse);
    c.cairo_pattern_add_color_stop_rgba(grad, 0.50, gold[0], gold[1], gold[2], gold[3] * pulse);
    c.cairo_pattern_add_color_stop_rgba(grad, 0.80, soft[0], soft[1], soft[2], soft[3] * pulse);
    c.cairo_pattern_add_color_stop_rgba(grad, 1.0, dim[0], dim[1], dim[2], dim[3] * focus_t);

    c.cairo_set_source(cr, grad);
    c.cairo_set_line_width(cr, style.border_width);
    c.cairo_stroke(cr);
}

fn drawCornerHighlights(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, d: f64, style: Style, alpha: f64) void {
    const hw = style.corner_highlight_width;
    const corners = [_]struct { cx: f64, cy: f64, color: Color }{
        .{ .cx = x + d * 0.5, .cy = y + d * 0.5, .color = style.color_purple },
        .{ .cx = x + w - d * 0.5, .cy = y + d * 0.5, .color = style.color_blue },
        .{ .cx = x + w - d * 0.5, .cy = y + h - d * 0.5, .color = style.color_turquoise },
        .{ .cx = x + d * 0.5, .cy = y + h - d * 0.5, .color = style.color_gold },
    };

    c.cairo_set_line_width(cr, hw);
    for (corners) |corner| {
        setSource(cr, corner.color, 0.90 * alpha);
        c.cairo_arc(cr, corner.cx, corner.cy, d * 0.28, 0.0, 2.0 * std.math.pi);
        c.cairo_stroke(cr);
    }
}

fn drawLogo(cr: *c.cairo_t, style: Style, cw: i32, ch: i32, alpha: f64, size: f64, y_offset: f64) void {
    const logo_path = "/home/dad/dev/KidulWM/rkt-dashboard/assets/bobHat.png";
    const surface = c.cairo_image_surface_create_from_png(logo_path.ptr);
    defer c.cairo_surface_destroy(surface);

    if (c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) {
        // Fallback: draw a small gold hexagon
        const cx = @as(f64, @floatFromInt(cw)) / 2.0;
        const cy = @as(f64, @floatFromInt(ch)) / 2.0 + y_offset;
        const r = size * 0.5;
        c.cairo_move_to(cr, cx + r, cy);
        for (1..6) |i| {
            const a = @as(f64, @floatFromInt(i)) * 2.0 * std.math.pi / 6.0;
            c.cairo_line_to(cr, cx + r * @cos(a), cy + r * @sin(a));
        }
        c.cairo_close_path(cr);
        setSource(cr, style.color_gold, alpha);
        c.cairo_set_line_width(cr, 2.0);
        c.cairo_stroke(cr);
        return;
    }

    const img_w: f64 = @floatFromInt(c.cairo_image_surface_get_width(surface));
    const img_h: f64 = @floatFromInt(c.cairo_image_surface_get_height(surface));
    const scale = size / @max(img_w, img_h);
    const draw_w = img_w * scale;
    const draw_h = img_h * scale;
    const cx = @as(f64, @floatFromInt(cw)) / 2.0;
    const cy = @as(f64, @floatFromInt(ch)) / 2.0 + y_offset;
    const x = cx - draw_w / 2.0;
    const y = cy - draw_h / 2.0;

    c.cairo_save(cr);
    c.cairo_translate(cr, x, y);
    c.cairo_scale(cr, scale, scale);
    c.cairo_set_source_surface(cr, surface, 0.0, 0.0);
    c.cairo_paint_with_alpha(cr, alpha);
    c.cairo_restore(cr);
}

fn drawInputField(cr: *c.cairo_t, x: f64, y: f64, w: f64, prompt: []const u8, value: []const u8, style: Style, alpha: f64, focused: bool) void {
    c.cairo_select_font_face(cr, "JetBrains Mono", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
    c.cairo_set_font_size(cr, 13.0);

    // Prompt label
    setSource(cr, style.color_gold_dim, alpha);
    c.cairo_move_to(cr, x, y);
    c.cairo_show_text(cr, prompt.ptr);

    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, prompt.ptr, &ext);
    const prompt_w = ext.width + 12.0;

    const input_x = x + prompt_w;
    _ = w - prompt_w;

    // Underline
    c.cairo_move_to(cr, input_x, y + 8.0);
    c.cairo_line_to(cr, x + w, y + 8.0);
    c.cairo_set_line_width(cr, if (focused) 1.5 else 1.0);
    setSource(cr, if (focused) style.color_gold else style.color_gold_dim, if (focused) alpha else 0.45 * alpha);
    c.cairo_stroke(cr);

    // Typed value glyphs
    if (value.len > 0) {
        setSource(cr, style.color_text, alpha);
        c.cairo_move_to(cr, input_x, y - 2.0);
        c.cairo_show_text(cr, value.ptr);
    } else if (focused) {
        // Blinking caret placeholder
        setSource(cr, style.color_gold, 0.75 * alpha);
        c.cairo_rectangle(cr, input_x, y - 10.0, 8.0, 14.0);
        c.cairo_fill(cr);
    }

    // Focus dot
    if (focused) {
        setSource(cr, style.color_gold, alpha);
        c.cairo_arc(cr, input_x + 4.0, y - 6.0, 2.5, 0.0, 2.0 * std.math.pi);
        c.cairo_fill(cr);
    }
}

fn drawCard(cr: *c.cairo_t, style: Style, cw: i32, ch: i32, alpha: f64) void {
    const w: f64 = style.card_width;
    const h: f64 = style.card_height;
    const x = (@as(f64, @floatFromInt(cw)) - w) / 2.0;
    const y = (@as(f64, @floatFromInt(ch)) - h) / 2.0;
    const d = style.corner_cut;

    c.cairo_save(cr);
    chamferRect(cr, x + 4.0, y + 4.0, w, h, d);
    setSource(cr, style.color_gold_soft, 0.35 * alpha);
    c.cairo_fill(cr);
    c.cairo_restore(cr);

    c.cairo_save(cr);
    chamferRect(cr, x, y, w, h, d);
    setSource(cr, style.color_card_bg, 0.96 * alpha);
    c.cairo_fill_preserve(cr);

    const overlay = c.cairo_pattern_create_linear(x, y, x, y + h);
    defer c.cairo_pattern_destroy(overlay);
    const bg = style.color_card_bg.toF64();
    const bg2 = style.color_bg.toF64();
    c.cairo_pattern_add_color_stop_rgba(overlay, 0.0, bg[0], bg[1], bg[2], 0.0);
    c.cairo_pattern_add_color_stop_rgba(overlay, 1.0, bg2[0], bg2[1], bg2[2], 0.22 * alpha);
    c.cairo_set_source(cr, overlay);
    c.cairo_fill_preserve(cr);

    strokeChamferBorder(cr, x, y, w, h, d, style, alpha);
    drawCornerHighlights(cr, x, y, w, h, d, style, alpha);

    // Title
    c.cairo_select_font_face(cr, "JetBrains Mono", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
    c.cairo_set_font_size(cr, 18.0);
    const title = "kidul";
    var text_ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, title, &text_ext);
    setSource(cr, style.color_gold, alpha);
    const tx = x + (w - text_ext.width) / 2.0;
    c.cairo_move_to(cr, tx, y + 48.0);
    c.cairo_show_text(cr, title);

    // Input field stubs
    const line_y = y + 110.0;
    const line_margin = 36.0;
    const line_w = w - 2.0 * line_margin;
    drawInputField(cr, x + line_margin, line_y, line_w, "user:", "kidul", style, alpha, true);
    drawInputField(cr, x + line_margin, line_y + 54.0, line_w, "pass:", "", style, alpha, false);

    c.cairo_restore(cr);
}

fn drawAuroraBand(cr: *c.cairo_t, style: Style, cw: i32, alpha: f64) void {
    const w = @as(f64, @floatFromInt(cw));
    const grad = c.cairo_pattern_create_linear(0.0, 0.0, w, 0.0);
    defer c.cairo_pattern_destroy(grad);

    const p = style.color_purple.toF64();
    const b = style.color_blue.toF64();
    const t = style.color_turquoise.toF64();

    c.cairo_pattern_add_color_stop_rgba(grad, 0.0, p[0], p[1], p[2], 0.0);
    c.cairo_pattern_add_color_stop_rgba(grad, 0.20, p[0], p[1], p[2], 0.35 * alpha);
    c.cairo_pattern_add_color_stop_rgba(grad, 0.50, b[0], b[1], b[2], 0.50 * alpha);
    c.cairo_pattern_add_color_stop_rgba(grad, 0.80, t[0], t[1], t[2], 0.35 * alpha);
    c.cairo_pattern_add_color_stop_rgba(grad, 1.0, t[0], t[1], t[2], 0.0);

    c.cairo_save(cr);
    c.cairo_set_source(cr, grad);
    c.cairo_rectangle(cr, 0.0, 0.0, w, 4.0);
    c.cairo_fill(cr);
    c.cairo_restore(cr);
}

pub fn drawFrame(cr: *c.cairo_t, style: Style, cw: i32, ch: i32, alpha: f64) void {
    c.cairo_save(cr);
    setSource(cr, style.color_bg, 1.0);
    c.cairo_paint(cr);
    c.cairo_restore(cr);

    drawAuroraBand(cr, style, cw, alpha);
    drawLogo(cr, style, cw, ch, alpha, 96.0, -90.0);
    drawCard(cr, style, cw, ch, alpha);
}

pub fn drawSplash(cr: *c.cairo_t, style: Style, cw: i32, ch: i32, alpha: f64) void {
    c.cairo_save(cr);
    setSource(cr, style.color_bg, 1.0);
    c.cairo_paint(cr);
    c.cairo_restore(cr);

    drawAuroraBand(cr, style, cw, alpha);
    drawLogo(cr, style, cw, ch, alpha, 160.0, 0.0);

    c.cairo_select_font_face(cr, "JetBrains Mono", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
    c.cairo_set_font_size(cr, 14.0);
    const text = "KidulWM";
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, text, &ext);

    const cx = @as(f64, @floatFromInt(cw)) / 2.0;
    const cy = @as(f64, @floatFromInt(ch)) / 2.0 + 105.0;
    setSource(cr, style.color_gold_dim, alpha);
    c.cairo_move_to(cr, cx - ext.width / 2.0, cy);
    c.cairo_show_text(cr, text);
}
