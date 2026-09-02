const std = @import("std");
const wlr = @import("wlroots");
const cairo = @import("dm").c;
const Style = @import("../core/style.zig").Style;
const media_mod = @import("media.zig");
const DataBuffer = @import("../render/buffer.zig").DataBuffer;

/// Compositor-owned media player slide: one scene tree per output holding
/// the Cairo-rendered media UI as a single buffer. Lives on the virtual
/// before_first deck slot (sibling of the after_last overview sentinel).
/// Not a window, never parked, INPUT LAW applies while open.
pub const MediaSlide = struct {
    tree: ?*wlr.SceneTree = null,
    card_buffer: ?*wlr.SceneBuffer = null,
    /// Widget state persists across open/close so the player remembers
    /// category/search/selection between visits.
    widget: media_mod.MediaWidget = undefined,
    widget_ready: bool = false,
    /// Last DISPLAY-edge serial we copied into the video scene buffer for;
    /// the frame handler ticks the player every vsync and only refreshes
    /// the video buffer when this moves.
    last_display_serial: u64 = 0,
    /// Dedicated scene buffer for the live video frame. Updated per-frame
    /// from Player.currentFrame(); the card buffer above carries only chrome.
    video_buffer: ?*wlr.SceneBuffer = null,
    video_wlr_buf: ?*wlr.Buffer = null,
    video_pixels: []u8 = &.{},

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
    widget.renderCard(cr, w_d, h_d, style_, @floatFromInt(scale), null);
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
