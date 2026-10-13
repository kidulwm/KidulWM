// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const wlr = @import("wlroots");
const cairo = @import("dm").c;
const Style = @import("../core/style.zig").Style;
const media_mod = @import("media.zig");
const DataBuffer = @import("../render/buffer.zig").DataBuffer;

/// Compositor-owned media player slide: one scene tree per output holding
/// the Cairo-rendered media UI as a single buffer. The slide is a REAL
/// deck.slides entry (kind .media_player, TASKCARD-3 stage 3) — it walks,
/// peeks, parks and quits through the stock paths; this struct carries only
/// the render state (tree + buffers + repaint guards) and the widget.
pub const MediaSlide = struct {
    tree: ?*wlr.SceneTree = null,
    card_buffer: ?*wlr.SceneBuffer = null,
    /// Widget state persists across open/close so the player remembers
    /// category/search/selection between visits.
    widget: media_mod.MediaWidget = undefined,
    widget_ready: bool = false,
    /// Card buffer geometry and content guard (verdict 17, 2026-09-12):
    /// mediaSlideRefresh is called from applyLayout on EVERY layout event
    /// (window focus, commit, etc.) while the slide is open. renderToBuffer
    /// allocates a 33MB ARGB32 surface each call; with many rapid re-fires
    /// the GPU pipeline holds multiple 33MB bufs simultaneously → ~20-35
    /// MB/s RSS growth in the prewarm window (active=false) → OOM.
    /// Guard: re-render only when the target rect changed OR card_dirty is
    /// set (set by any widget mutation that changes pixel content).
    /// The playing-branch already skips renderToBuffer entirely.
    card_last_w: i32 = 0,
    card_last_h: i32 = 0,
    card_dirty: bool = true,
    /// Widget state_generation at the last card render. When art loads or
    /// any widget mutation bumps state_generation, this diverges from the
    /// widget's current value and the guard treats it as dirty — so art
    /// appears on the card without needing explicit dirty-setting at every
    /// art-load call site. Initialised to max-value so the first render
    /// always fires (state_generation starts at 0 → always differs).
    card_last_gen: u32 = std.math.maxInt(u32),

    pub fn isOpen(self: *const MediaSlide) bool {
        return self.tree != null;
    }

    pub fn ensureWidget(self: *MediaSlide, allocator: std.mem.Allocator) *media_mod.MediaWidget {
        if (!self.widget_ready) {
            self.widget = media_mod.MediaWidget.init(allocator);
            self.widget_ready = true;
        }
        return &self.widget;
    }
};

/// Render the media widget into a wlroots buffer. Caller destroys the
/// intermediate cairo surface.
pub fn renderToBuffer(
    widget: *media_mod.MediaWidget,
    style_: Style,
    width: i32,
    height: i32,
    scale: u32,
    full_bleed: bool,
) ?*wlr.Buffer {
    const w_d: f64 = @floatFromInt(width * @as(i32, @intCast(scale)));
    const h_d: f64 = @floatFromInt(height * @as(i32, @intCast(scale)));
    const stride = cairo.cairo_format_stride_for_width(cairo.CAIRO_FORMAT_ARGB32, @intFromFloat(w_d));
    const surface = cairo.cairo_image_surface_create(cairo.CAIRO_FORMAT_ARGB32, @intFromFloat(w_d), @intFromFloat(h_d)) orelse return null;
    if (cairo.cairo_surface_status(surface) != cairo.CAIRO_STATUS_SUCCESS) {
        cairo.cairo_surface_destroy(surface);
        return null;
    }
    const cr = cairo.cairo_create(surface) orelse {
        cairo.cairo_surface_destroy(surface);
        return null;
    };
    defer cairo.cairo_destroy(cr);
    widget.renderCard(cr, w_d, h_d, style_, @floatFromInt(scale), null, full_bleed);
    cairo.cairo_surface_flush(surface);
    const data = cairo.cairo_image_surface_get_data(surface) orelse {
        cairo.cairo_surface_destroy(surface);
        return null;
    };
    const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intFromFloat(h_d));
    // DataBuffer copies pixels, so the surface can be destroyed right after.
    const buf = DataBuffer.create(data[0..buf_size], @intFromFloat(w_d), @intFromFloat(h_d), stride) catch {
        cairo.cairo_surface_destroy(surface);
        return null;
    };
    cairo.cairo_surface_destroy(surface);
    return buf;
}
