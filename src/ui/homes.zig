// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const wlr = @import("wlroots");
const cairo = @import("dm").c;
const style_mod = @import("../core/style.zig");
const Style = style_mod.Style;
const DataBuffer = @import("../render/buffer.zig").DataBuffer;

/// Compositor-owned Homes slide (docs/law/settings.md): the immutable door
/// that switches publicHome -> privateHome. Step 1 = the empty shell — a
/// "Homes" title and a "person" row. The "tap your key" surface (step 2)
/// replaces the person-row content; the key-entry is the door, the shell is
/// its frame. One scene tree per output; render state only (tree + buffer +
/// repaint guard). Follows the home_slide / gpb_slide compositor-slide
/// pattern.
pub const HomesSlide = struct {
    tree: ?*wlr.SceneTree = null,
    card_buffer: ?*wlr.SceneBuffer = null,
    /// Repaint guard: re-render only when the target rect changed.
    card_last_w: i32 = 0,
    card_last_h: i32 = 0,

    pub fn isOpen(self: *const HomesSlide) bool {
        return self.tree != null;
    }
};

/// Render the Homes shell (near-black bg + CFC gold "Homes" title + a
/// "person" row) into a wlroots buffer at physical pixels (logical × scale).
pub fn renderToBuffer(
    style: Style,
    width: i32,
    height: i32,
    scale: u32,
) ?*wlr.Buffer {
    if (width <= 0 or height <= 0) return null;
    const s: i32 = @max(1, @as(i32, @intCast(scale)));
    const pw: i32 = width * s;
    const ph: i32 = height * s;
    const surface = cairo.cairo_image_surface_create(cairo.CAIRO_FORMAT_ARGB32, pw, ph) orelse return null;
    if (cairo.cairo_surface_status(surface) != cairo.CAIRO_STATUS_SUCCESS) {
        cairo.cairo_surface_destroy(surface);
        return null;
    }
    const cr = cairo.cairo_create(surface) orelse {
        cairo.cairo_surface_destroy(surface);
        return null;
    };
    defer cairo.cairo_destroy(cr);

    const w: f64 = @floatFromInt(pw);
    const h: f64 = @floatFromInt(ph);
    const fs: f64 = @floatFromInt(s);

    // Background: near-black, fully opaque (matches the home-slide shell).
    const bg = style.tray_bg_color.toF64();
    cairo.cairo_set_source_rgba(cr, bg[0], bg[1], bg[2], 1.0);
    cairo.cairo_paint(cr);

    const gold = style.color_gold.toF64();
    const gold_dim = style.color_gold_dim.toF64();

    const title_size: f64 = @as(f64, style.font_size_l) * fs;
    const row_size: f64 = @as(f64, style.font_size_m) * fs;
    const house_gap: f64 = @as(f64, @floatFromInt(style_mod.layout.gap)) * fs * 3.0;

    var ext: cairo.cairo_text_extents_t = undefined;
    const total_h = title_size + house_gap + row_size;
    const y0 = (h - total_h) / 2.0;

    // Title (gold, large, bold, centered).
    cairo.cairo_select_font_face(cr, "JetBrains Mono", cairo.CAIRO_FONT_SLANT_NORMAL, cairo.CAIRO_FONT_WEIGHT_BOLD);
    cairo.cairo_set_font_size(cr, title_size);
    cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
    cairo.cairo_text_extents(cr, "Homes", &ext);
    cairo.cairo_move_to(cr, (w - ext.width) / 2.0 - ext.x_bearing, y0 + title_size);
    cairo.cairo_show_text(cr, "Homes");

    // "person" row (dim gold, medium, centered, below the title).
    cairo.cairo_select_font_face(cr, "JetBrains Mono", cairo.CAIRO_FONT_SLANT_NORMAL, cairo.CAIRO_FONT_WEIGHT_NORMAL);
    cairo.cairo_set_font_size(cr, row_size);
    cairo.cairo_set_source_rgba(cr, gold_dim[0], gold_dim[1], gold_dim[2], gold_dim[3]);
    cairo.cairo_text_extents(cr, "person", &ext);
    const row_y = y0 + title_size + house_gap;
    cairo.cairo_move_to(cr, (w - ext.width) / 2.0 - ext.x_bearing, row_y + row_size);
    cairo.cairo_show_text(cr, "person");

    cairo.cairo_surface_flush(surface);
    const data = cairo.cairo_image_surface_get_data(surface) orelse {
        cairo.cairo_surface_destroy(surface);
        return null;
    };
    const stride = cairo.cairo_image_surface_get_stride(surface);
    const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(ph));
    const buf = DataBuffer.create(data[0..buf_size], pw, ph, stride) catch {
        cairo.cairo_surface_destroy(surface);
        return null;
    };
    cairo.cairo_surface_destroy(surface);
    return buf;
}
