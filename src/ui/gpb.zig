// SPDX-License-Identifier: GPL-3.0-or-later
// The global pill bar (GPB) — the apps list: AI / Games / Library / Search /
// Homes. A compositor-owned TOP BAR (one render per output), the deck slides
// BELOW it. Follows the media_slide / media.zig render patterns.
//
// Law: environment.md ("the bar = the GPB ... its OWN SLIDE"), naming.md
// (title above = the product name, outline-only), styles (THE PILL spec).

const std = @import("std");
const wlr = @import("wlroots");
const c = @import("dm").c;
const Style = @import("../core/style.zig").Style;
const DataBuffer = @import("../render/buffer.zig").DataBuffer;

/// The five public apps on the GPB (naming.md + environment.md). Library is
/// centred (index 2) and is the fresh-boot default focus. The right-most pill
/// is Homes — the immutable key-entry door (settings.md): sign in, attach a
/// drive, the roster. The signed-in owner sees MORE pills later; the public
/// seat sees these five.
pub const GpbApp = enum { ai, games, library, search, homes };

pub fn appLabel(app: GpbApp) [:0]const u8 {
    return switch (app) {
        .ai => "AI",
        .games => "Games",
        .library => "Library",
        .search => "Search",
        .homes => "Homes",
    };
}

fn displayIndex(app: GpbApp) usize {
    return switch (app) {
        .ai => 0,
        .games => 1,
        .library => 2,
        .search => 3,
        .homes => 4,
    };
}

fn appFromIndex(i: usize) GpbApp {
    return switch (i) {
        0 => .ai,
        1 => .games,
        2 => .library,
        3 => .search,
        else => .homes,
    };
}

// ── THE PILL — brand-locked house spec (styles/pill-spec.md) ─────────────
// Geometry per segment matches media.zig: track h=56, inset 5, full stadium
// radius, 280px segments. The GPB uses FIVE segments, not three.
const PILL_SEG_W: f64 = 280.0;
const PILL_TRACK_H: f64 = 56.0;
const PILL_INSET: f64 = 5.0;
const PILL_COUNT: usize = 5;

const PillColor = struct { r: f64, g: f64, b: f64 };

fn pc(hex: u24) PillColor {
    return .{
        .r = @as(f64, @floatFromInt((hex >> 16) & 0xFF)) / 255.0,
        .g = @as(f64, @floatFromInt((hex >> 8) & 0xFF)) / 255.0,
        .b = @as(f64, @floatFromInt(hex & 0xFF)) / 255.0,
    };
}

const PILL_TRACK_FILL = pc(0x0a0a0a);
const PILL_TRACK_BORDER = pc(0x4d4a40);
const PILL_GOLD = pc(0x948e7b);
const PILL_TEXT_ACTIVE = pc(0xe8e6df);
const PILL_TEXT_DIM = pc(0x6a6354);

/// The system title above the GPB (naming.md) — the PRODUCT name, outline-only,
/// no logo/sig. "Kidul TV" for the TV device; per-device later (Kidul PC,
/// Router, Server). Configurable before long.
const GPB_TITLE: [:0]const u8 = "Kidul TV";

fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
    const rr = @min(r, w * 0.5, h * 0.5);
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + rr, y);
    c.cairo_line_to(cr, x + w - rr, y);
    c.cairo_arc(cr, x + w - rr, y + rr, rr, -std.math.pi * 0.5, 0);
    c.cairo_line_to(cr, x + w, y + h - rr);
    c.cairo_arc(cr, x + w - rr, y + h - rr, rr, 0, std.math.pi * 0.5);
    c.cairo_line_to(cr, x + rr, y + h);
    c.cairo_arc(cr, x + rr, y + h - rr, rr, std.math.pi * 0.5, std.math.pi);
    c.cairo_line_to(cr, x, y + rr);
    c.cairo_arc(cr, x + rr, y + rr, rr, std.math.pi, std.math.pi * 1.5);
    c.cairo_close_path(cr);
}

pub const GpbBar = struct {
    /// Focused app (the highlighted button). Boot focus = Library.
    focused: GpbApp = .library,
    /// Bumped on any state change; drives re-render (mirrors media widget).
    state_generation: u32 = 0,

    pub fn bumpGeneration(self: *GpbBar) void {
        self.state_generation +%= 1;
    }

    /// Move focus left/right between the five apps (HARD STOPS — no wrap,
    /// INPUT LAW / styles). Returns true if the focus changed.
    pub fn moveFocus(self: *GpbBar, step: i32) bool {
        const cur = displayIndex(self.focused);
        const target: i64 = @as(i64, @intCast(cur)) + @as(i64, @intCast(step));
        if (target < 0 or target >= PILL_COUNT) return false;
        self.focused = appFromIndex(@intCast(target));
        self.bumpGeneration();
        return true;
    }

    pub fn renderCard(self: *GpbBar, cr: *c.cairo_t, w_d: f64, h_d: f64, style_: Style, scale_f: f64) void {
        const pad_x: f64 = 22.0 * scale_f;
        const content_w = w_d - 2.0 * pad_x;

        const pb_seg_w = PILL_SEG_W * scale_f;
        const pb_track_h = PILL_TRACK_H * scale_f;
        const pb_track_w = pb_seg_w * @as(f64, @floatFromInt(PILL_COUNT));
        const pb_track_x = pad_x + @max(0.0, (content_w - pb_track_w) * 0.5);
        const pb_track_r = pb_track_h * 0.5;
        const pb_inset = PILL_INSET * scale_f;
        const pb_pill_h = pb_track_h - 2.0 * pb_inset;
        const pb_pill_r = pb_pill_h * 0.5;
        const pill_w = pb_seg_w - 2.0 * pb_inset;
        const active_display = displayIndex(self.focused);

        // CFC: the interaction (pill track) is DEAD-CENTRE. Title above, the
        // focused app's name below.
        const track_y = (h_d - pb_track_h) * 0.5;
        const title_font: f64 = @as(f64, style_.font_size_l) * 1.5 * scale_f;
        const below_font: f64 = @as(f64, style_.font_size_l) * scale_f;

        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);

        // ---- System title: outline-only, large, above the track. ----
        {
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_set_font_size(cr, title_font);
            c.cairo_text_extents(cr, GPB_TITLE.ptr, &ext);
            const tx = pad_x + (content_w - ext.width) * 0.5;
            const ty = track_y - 26.0 * scale_f - ext.height;
            c.cairo_move_to(cr, tx, ty);
            c.cairo_text_path(cr, GPB_TITLE.ptr);
            c.cairo_set_line_width(cr, 1.5 * scale_f);
            c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 1.0);
            c.cairo_stroke(cr);
        }

        // ---- The pill track: ONE stadium track, 5 segments. ----
        roundedRect(cr, pb_track_x, track_y, pb_track_w, pb_track_h, pb_track_r);
        c.cairo_set_source_rgba(cr, PILL_TRACK_FILL.r, PILL_TRACK_FILL.g, PILL_TRACK_FILL.b, 1.0);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, PILL_TRACK_BORDER.r, PILL_TRACK_BORDER.g, PILL_TRACK_BORDER.b, 1.0);
        c.cairo_set_line_width(cr, 1.5);
        c.cairo_stroke(cr);

        // Segment separators (soft, 10px end margin — browser pattern).
        c.cairo_set_source_rgba(cr, PILL_TRACK_BORDER.r, PILL_TRACK_BORDER.g, PILL_TRACK_BORDER.b, 90.0 / 255.0);
        c.cairo_set_line_width(cr, 1.0);
        var sep_i: usize = 1;
        while (sep_i < PILL_COUNT) : (sep_i += 1) {
            const sx = pb_track_x + @as(f64, @floatFromInt(sep_i)) * pb_seg_w;
            c.cairo_move_to(cr, sx, track_y + 10.0 * scale_f);
            c.cairo_line_to(cr, sx, track_y + pb_track_h - 10.0 * scale_f);
            c.cairo_stroke(cr);
        }

        // Floating inner pill on the focused segment (gold ring; the
        // environment-colour glow arrives in slice B).
        const pill_x = pb_track_x + @as(f64, @floatFromInt(active_display)) * pb_seg_w + pb_inset;
        const pill_y = track_y + pb_inset;
        roundedRect(cr, pill_x, pill_y, pill_w, pb_pill_h, pb_pill_r);
        c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 90.0 / 255.0);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 200.0 / 255.0);
        c.cairo_set_line_width(cr, 1.5);
        c.cairo_stroke(cr);

        // Segment labels.
        const pill_font: f64 = @as(f64, style_.font_size_l) * scale_f;
        c.cairo_set_font_size(cr, pill_font);
        for (0..PILL_COUNT) |i| {
            const app = appFromIndex(i);
            const seg_x = pb_track_x + @as(f64, @floatFromInt(i)) * pb_seg_w;
            const label = appLabel(app);
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, label.ptr, &ext);
            const tcol = if (i == active_display) PILL_TEXT_ACTIVE else PILL_TEXT_DIM;
            c.cairo_set_source_rgba(cr, tcol.r, tcol.g, tcol.b, 1.0);
            c.cairo_move_to(cr, seg_x + (pb_seg_w - ext.width) * 0.5, track_y + pb_track_h * 0.5 + pill_font * 0.30);
            c.cairo_show_text(cr, label.ptr);
        }

        // ---- Below-title: the focused app's generic name. ----
        {
            const below = appLabel(self.focused);
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_set_font_size(cr, below_font);
            c.cairo_text_extents(cr, below.ptr, &ext);
            const bx = pad_x + (content_w - ext.width) * 0.5;
            const by = track_y + pb_track_h + 22.0 * scale_f + ext.height;
            c.cairo_set_source_rgba(cr, PILL_TEXT_ACTIVE.r, PILL_TEXT_ACTIVE.g, PILL_TEXT_ACTIVE.b, 1.0);
            c.cairo_move_to(cr, bx, by);
            c.cairo_show_text(cr, below.ptr);
        }
    }
};

/// Per-output scene state for the GPB (mirrors MediaSlide): tree + buffer +
/// the bar widget + repaint guards.
pub const GpbSlide = struct {
    tree: ?*wlr.SceneTree = null,
    card_buffer: ?*wlr.SceneBuffer = null,
    bar: GpbBar = .{},
    card_last_w: i32 = 0,
    card_last_h: i32 = 0,
    card_last_gen: u32 = std.math.maxInt(u32),
    card_dirty: bool = true,

    pub fn isOpen(self: *const GpbSlide) bool {
        return self.tree != null;
    }
};

/// Render the GPB into a wlroots buffer (mirrors media_slide.renderToBuffer).
/// Caller destroys the intermediate cairo surface.
pub fn renderToBuffer(
    bar: *GpbBar,
    style_: Style,
    width: i32,
    height: i32,
    scale: u32,
) ?*wlr.Buffer {
    const w_d: f64 = @floatFromInt(width * @as(i32, @intCast(scale)));
    const h_d: f64 = @floatFromInt(height * @as(i32, @intCast(scale)));
    const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, @intFromFloat(w_d));
    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, @intFromFloat(w_d), @intFromFloat(h_d)) orelse return null;
    if (c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) {
        c.cairo_surface_destroy(surface);
        return null;
    }
    const cr = c.cairo_create(surface) orelse {
        c.cairo_surface_destroy(surface);
        return null;
    };
    defer c.cairo_destroy(cr);
    bar.renderCard(cr, w_d, h_d, style_, @floatFromInt(scale));
    c.cairo_surface_flush(surface);
    const data = c.cairo_image_surface_get_data(surface) orelse {
        c.cairo_surface_destroy(surface);
        return null;
    };
    const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intFromFloat(h_d));
    const buf = DataBuffer.create(data[0..buf_size], @intFromFloat(w_d), @intFromFloat(h_d), stride) catch {
        c.cairo_surface_destroy(surface);
        return null;
    };
    c.cairo_surface_destroy(surface);
    return buf;
}

// Force compile-time analysis of the render path so a typo in renderCard /
// renderToBuffer fails the build, not the first runtime frame. Remove once the
// bar is wired into the render loop (they get called there anyway).
comptime {
    _ = renderToBuffer;
    _ = GpbBar.moveFocus;
}
