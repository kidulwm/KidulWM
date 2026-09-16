const std = @import("std");
const wlr = @import("wlroots");
const cairo = @import("dm").c;
const style_mod = @import("../core/style.zig");
const Style = style_mod.Style;
const chrome_renderer = @import("../render/chrome.zig");
const DataBuffer = @import("../render/buffer.zig").DataBuffer;

/// Compositor-owned tray/home slide (tray-slide birth, stage 1): one scene
/// tree per output holding the home card. Lives on the virtual before_first
/// deck slot (sentinel sibling of the after_last overview slide). Not a
/// client window, never parked, NOT in deck.slides — window-count invariants
/// stay intact.
///
/// A1 PROPER SLIDE: real border + background via the STOCK chrome renderer —
/// the same border/background every focused slide gets. Specialness is the
/// content only: CFC'd cairo text, centered both axes, sections stacked with
/// the house gap. v1 = static section lines; real feeds wire in later stages.
pub const TraySlide = struct {
    tree: ?*wlr.SceneTree = null,
    /// Background + gold section lines (content of the slide).
    card_buffer: ?*wlr.SceneBuffer = null,
    /// Stock chrome border ring (render/chrome.zig — A1).
    chrome_buffer: ?*wlr.SceneBuffer = null,
    /// Repaint guard: re-render only when the target rect changed.
    card_last_w: i32 = 0,
    card_last_h: i32 = 0,

    pub fn isOpen(self: *const TraySlide) bool {
        return self.tree != null;
    }

    pub const Section = struct {
        label: []const u8,
        line: []const u8,
    };

    /// v1 content: placeholder section lines (spec stage 1 — no real feeds).
    pub const sections = [_]Section{
        .{ .label = "MEDIA", .line = "nothing playing" },
        .{ .label = "WEATHER", .line = "no data" },
        .{ .label = "SIGNALS", .line = "no data" },
        .{ .label = "NOTIFICATIONS", .line = "none" },
    };
};

/// Render the home card (near-black bg + CFC gold text, centered both axes,
/// sections stacked with the house gap) into a wlroots buffer. Rendered at
/// physical pixels (logical size × scale), like the media slide card.
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

    // Background: kfiles near-black token, fully opaque (A1 — the stock
    // chrome background ring sits on top; transparency is a future alpha
    // constant, not this stage).
    const bg = style.tray_bg_color.toF64();
    cairo.cairo_set_source_rgba(cr, bg[0], bg[1], bg[2], 1.0);
    cairo.cairo_paint(cr);

    // CFC: sections stacked, centered both axes, house gap between blocks.
    const label_size: f64 = @as(f64, style.font_size_m) * fs;
    const line_size: f64 = @as(f64, style.font_size_l) * fs;
    const house_gap: f64 = @as(f64, @floatFromInt(style_mod.layout.gap)) * fs * 3.0;
    const block_gap: f64 = house_gap / 3.0;

    const n: f64 = @floatFromInt(TraySlide.sections.len);
    const block_h = label_size + block_gap + line_size;
    const total_h = n * block_h + (n - 1.0) * house_gap;
    var y = (h - total_h) / 2.0;

    const gold = style.color_gold.toF64();
    const gold_dim = style.color_gold_dim.toF64();

    var ext: cairo.cairo_text_extents_t = undefined;
    for (TraySlide.sections) |section| {
        // Section label (dim gold, small, centered).
        cairo.cairo_select_font_face(cr, "JetBrains Mono", cairo.CAIRO_FONT_SLANT_NORMAL, cairo.CAIRO_FONT_WEIGHT_NORMAL);
        cairo.cairo_set_font_size(cr, label_size);
        cairo.cairo_text_extents(cr, section.label.ptr, &ext);
        cairo.cairo_set_source_rgba(cr, gold_dim[0], gold_dim[1], gold_dim[2], gold_dim[3]);
        cairo.cairo_move_to(cr, (w - ext.width) / 2.0 - ext.x_bearing, y + label_size);
        cairo.cairo_show_text(cr, section.label.ptr);
        y += label_size + block_gap;

        // Section line (gold, large, centered).
        cairo.cairo_select_font_face(cr, "JetBrains Mono", cairo.CAIRO_FONT_SLANT_NORMAL, cairo.CAIRO_FONT_WEIGHT_BOLD);
        cairo.cairo_set_font_size(cr, line_size);
        cairo.cairo_text_extents(cr, section.line.ptr, &ext);
        cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
        cairo.cairo_move_to(cr, (w - ext.width) / 2.0 - ext.x_bearing, y + line_size);
        cairo.cairo_show_text(cr, section.line.ptr);
        y += line_size + house_gap;
    }

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

/// Render the STOCK chrome border ring (A1) into a wlroots buffer, same
/// render the per-window chrome path uses.
pub fn renderChromeToBuffer(
    style: Style,
    width: i32,
    height: i32,
    scale: u32,
) ?*wlr.Buffer {
    const surface = chrome_renderer.renderChrome(style, width, height, true, scale, chrome_renderer.EdgeMode.all, null) orelse return null;
    defer cairo.cairo_surface_destroy(surface);
    const pixels = chrome_renderer.surfacePixels(surface);
    return DataBuffer.create(pixels.pixels, pixels.width, pixels.height, pixels.stride) catch null;
}
