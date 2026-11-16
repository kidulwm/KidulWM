// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const wlr = @import("wlroots");
const c = @import("dm").c;
const style_mod = @import("../core/style.zig");
const Style = style_mod.Style;
const DataBuffer = @import("../render/buffer.zig").DataBuffer;

/// Compositor-owned Homes slide (docs/law/settings.md): the immutable door
/// that switches publicHome -> privateHome. Step 2 = the surface — a
/// Resident / Visitor pill bar (THE PILL, 2 segments) + a name list under the
/// focused seat + "+ add user", with "tap your key" on select. The roster
/// below is a SAMPLE placeholder; the real roster wires in step 3 (gate proof)
/// / 6 (claim). Thin by design — this must NOT grow media.zig-style.
///
/// Law: settings.md (Resident/Visitor seats), styles (THE PILL, CFC, INPUT
/// LAW ↑↓=focus ←→=move Enter=apply Esc=back, hard stops — no wrap).
const RESIDENT_NAMES = [_][:0]const u8{ "Owner", "Kid 1", "Kid 2" };
const VISITOR_NAMES = [_][:0]const u8{"Guest"};
const ADD_USER_LABEL: [:0]const u8 = "+ add user";

const PILL_SEG_W: f64 = 280.0;
const PILL_TRACK_H: f64 = 56.0;
const PILL_INSET: f64 = 5.0;
const PILL_COUNT: usize = 2;

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

const Seat = enum { resident, visitor };

/// The Homes slide's in-slide widget: the Resident / Visitor pill bar and the
/// focused seat's name list. Render state + focus only (the roster is a sample
/// until step 3).
pub const HomesBar = struct {
    seat: Seat = .resident,
    name_index: usize = 0,
    key_entry: bool = false,
    state_generation: u32 = 0,

    fn bump(self: *HomesBar) void {
        self.state_generation +%= 1;
    }

    fn names(self: *const HomesBar) []const [:0]const u8 {
        return if (self.seat == .resident) &RESIDENT_NAMES else &VISITOR_NAMES;
    }

    fn nameCount(self: *const HomesBar) usize {
        return self.names().len + 1; // +1 = "+ add user"
    }

    fn listLabel(self: *const HomesBar, i: usize) [:0]const u8 {
        const n = self.names();
        if (i < n.len) return n[i];
        return ADD_USER_LABEL;
    }

    fn focusedLabel(self: *const HomesBar) [:0]const u8 {
        return self.listLabel(self.name_index);
    }

    /// ←→ : switch Resident/Visitor (hard stop; resets list focus to 0).
    pub fn moveSeat(self: *HomesBar, step: i32) bool {
        if (self.key_entry) return false;
        const cur: i32 = if (self.seat == .resident) 0 else 1;
        const target = cur + step;
        if (target < 0 or target >= 2) return false;
        self.seat = if (target == 0) .resident else .visitor;
        self.name_index = 0;
        self.bump();
        return true;
    }

    /// ↑↓ : move focus down/up the name list (hard stop, no wrap).
    pub fn moveName(self: *HomesBar, step: i32) bool {
        if (self.key_entry) return false;
        const cur: i64 = @intCast(self.name_index);
        const target = cur + @as(i64, @intCast(step));
        if (target < 0 or target >= @as(i64, @intCast(self.nameCount()))) return false;
        self.name_index = @intCast(target);
        self.bump();
        return true;
    }

    /// Enter : select the focused entry -> "tap your key". Step 2 surface
    /// only; the gate proof (step 3) replaces the prompt with the challenge.
    pub fn select(self: *HomesBar) bool {
        if (self.key_entry) return false;
        self.key_entry = true;
        self.bump();
        return true;
    }

    /// Esc : back out of "tap your key" to the list (hard stop at the root).
    pub fn back(self: *HomesBar) bool {
        if (!self.key_entry) return false;
        self.key_entry = false;
        self.bump();
        return true;
    }

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

    pub fn renderCard(self: *HomesBar, cr: *c.cairo_t, w_d: f64, h_d: f64, style_: Style, scale_f: f64) void {
        const pad_x: f64 = 22.0 * scale_f;
        const content_w = w_d - 2.0 * pad_x;

        const seg_w = PILL_SEG_W * scale_f;
        const track_h = PILL_TRACK_H * scale_f;
        const track_w = seg_w * @as(f64, @floatFromInt(PILL_COUNT));
        const track_x = pad_x + @max(0.0, (content_w - track_w) * 0.5);
        const track_r = track_h * 0.5;
        const inset = PILL_INSET * scale_f;
        const pill_h = track_h - 2.0 * inset;
        const pill_r = pill_h * 0.5;
        const pill_w = seg_w - 2.0 * inset;

        // CFC: the interaction (pill track) is dead-centre; title above, list below.
        const track_y = (h_d - track_h) * 0.5;
        const title_font: f64 = @as(f64, style_.font_size_l) * 1.5 * scale_f;
        const list_font: f64 = @as(f64, style_.font_size_m) * scale_f;
        const list_gap: f64 = @as(f64, @floatFromInt(style_mod.layout.gap)) * scale_f;

        c.cairo_select_font_face(cr, "Fantasque Sans Mono", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);

        // ---- Title (filled gold, centered, above the track). ----
        {
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_set_font_size(cr, title_font);
            c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 1.0);
            c.cairo_text_extents(cr, "Homes", &ext);
            const tx = pad_x + (content_w - ext.width) * 0.5;
            const ty = track_y - 26.0 * scale_f - ext.height;
            c.cairo_move_to(cr, tx, ty);
            c.cairo_show_text(cr, "Homes");
        }

        if (self.key_entry) {
            // ---- "tap your key" (the one-prompt door). ----
            const sel = self.focusedLabel();
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_set_font_size(cr, list_font);
            c.cairo_set_source_rgba(cr, PILL_TEXT_ACTIVE.r, PILL_TEXT_ACTIVE.g, PILL_TEXT_ACTIVE.b, 1.0);
            c.cairo_text_extents(cr, sel.ptr, &ext);
            const sy = track_y + track_h + 22.0 * scale_f + ext.height;
            c.cairo_move_to(cr, pad_x + (content_w - ext.width) * 0.5, sy);
            c.cairo_show_text(cr, sel.ptr);

            var ext2: c.cairo_text_extents_t = undefined;
            c.cairo_set_font_size(cr, title_font * 0.6);
            c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 1.0);
            c.cairo_text_extents(cr, "tap your key", &ext2);
            const ky = sy + list_gap + ext2.height;
            c.cairo_move_to(cr, pad_x + (content_w - ext2.width) * 0.5, ky);
            c.cairo_show_text(cr, "tap your key");
            return;
        }

        // ---- The pill track (2 segments: Resident | Visitor). ----
        roundedRect(cr, track_x, track_y, track_w, track_h, track_r);
        c.cairo_set_source_rgba(cr, PILL_TRACK_FILL.r, PILL_TRACK_FILL.g, PILL_TRACK_FILL.b, 1.0);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, PILL_TRACK_BORDER.r, PILL_TRACK_BORDER.g, PILL_TRACK_BORDER.b, 1.0);
        c.cairo_set_line_width(cr, 1.5);
        c.cairo_stroke(cr);

        // Segment separator (one, between Resident and Visitor).
        c.cairo_set_source_rgba(cr, PILL_TRACK_BORDER.r, PILL_TRACK_BORDER.g, PILL_TRACK_BORDER.b, 90.0 / 255.0);
        c.cairo_set_line_width(cr, 1.0);
        {
            const sx = track_x + seg_w;
            c.cairo_move_to(cr, sx, track_y + 10.0 * scale_f);
            c.cairo_line_to(cr, sx, track_y + track_h - 10.0 * scale_f);
            c.cairo_stroke(cr);
        }

        const active: usize = if (self.seat == .resident) 0 else 1;

        // Floating inner pill on the focused seat (gold ring).
        {
            const pill_x = track_x + @as(f64, @floatFromInt(active)) * seg_w + inset;
            const pill_y = track_y + inset;
            roundedRect(cr, pill_x, pill_y, pill_w, pill_h, pill_r);
            c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 90.0 / 255.0);
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 200.0 / 255.0);
            c.cairo_set_line_width(cr, 1.5);
            c.cairo_stroke(cr);
        }

        // Seat labels.
        {
            const pill_font: f64 = @as(f64, style_.font_size_l) * scale_f;
            c.cairo_set_font_size(cr, pill_font);
            const labels = [_][:0]const u8{ "Resident", "Visitor" };
            for (0..PILL_COUNT) |i| {
                const seg_x = track_x + @as(f64, @floatFromInt(i)) * seg_w;
                var ext: c.cairo_text_extents_t = undefined;
                c.cairo_text_extents(cr, labels[i].ptr, &ext);
                const tcol = if (i == active) PILL_TEXT_ACTIVE else PILL_TEXT_DIM;
                c.cairo_set_source_rgba(cr, tcol.r, tcol.g, tcol.b, 1.0);
                c.cairo_move_to(cr, seg_x + (seg_w - ext.width) * 0.5, track_y + track_h * 0.5 + pill_font * 0.30);
                c.cairo_show_text(cr, labels[i].ptr);
            }
        }

        // ---- Name list below the track (the focused seat's names + add user).
        {
            c.cairo_set_font_size(cr, list_font);
            const count = self.nameCount();
            var i: usize = 0;
            while (i < count) : (i += 1) {
                const label = self.listLabel(i);
                var ext: c.cairo_text_extents_t = undefined;
                c.cairo_text_extents(cr, label.ptr, &ext);
                const focused = (i == self.name_index);
                const tcol = if (focused) PILL_TEXT_ACTIVE else PILL_TEXT_DIM;
                const ly = track_y + track_h + 22.0 * scale_f + ext.height +
                    @as(f64, @floatFromInt(i)) * (ext.height + list_gap * 0.5);
                c.cairo_set_source_rgba(cr, tcol.r, tcol.g, tcol.b, 1.0);
                c.cairo_move_to(cr, pad_x + (content_w - ext.width) * 0.5, ly);
                c.cairo_show_text(cr, label.ptr);
                if (focused) {
                    // Thin gold underline on the focused entry.
                    c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 1.0);
                    c.cairo_set_line_width(cr, 1.5);
                    c.cairo_move_to(cr, pad_x + (content_w - ext.width) * 0.5, ly + 4.0 * scale_f);
                    c.cairo_line_to(cr, pad_x + (content_w + ext.width) * 0.5, ly + 4.0 * scale_f);
                    c.cairo_stroke(cr);
                }
            }
        }
    }
};

/// Per-output scene state for the Homes slide (mirrors GpbSlide): tree +
/// buffer + the bar widget + repaint guards.
pub const HomesSlide = struct {
    tree: ?*wlr.SceneTree = null,
    card_buffer: ?*wlr.SceneBuffer = null,
    bar: HomesBar = .{},
    card_last_w: i32 = 0,
    card_last_h: i32 = 0,
    card_last_gen: u32 = std.math.maxInt(u32),
    card_dirty: bool = true,

    pub fn isOpen(self: *const HomesSlide) bool {
        return self.tree != null;
    }
};

/// Render the Homes slide into a wlroots buffer (mirrors gpb.renderToBuffer).
pub fn renderToBuffer(
    bar: *HomesBar,
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
// renderToBuffer fails the build, not the first runtime frame.
comptime {
    _ = renderToBuffer;
    _ = HomesBar.moveSeat;
}
