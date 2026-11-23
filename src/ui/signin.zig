// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const wlr = @import("wlroots");
const c = @import("dm").c;
const style_mod = @import("../core/style.zig");
const Style = style_mod.Style;
const DataBuffer = @import("../render/buffer.zig").DataBuffer;

/// Compositor-owned Sign In slide (docs/law/settings.md): the immutable door.
/// Two doors, deliberately asymmetric:
///   - Residents (OwnersFam): a name LIST — who LIVES here. → consents on a
///     name -> the key prompt -> local + external + networked.
///   - KidulCrew: NO list — who DROPS BY. ↓ steps straight into the key prompt
///     -> approved external access only, their drive rides in with the key.
/// "Family you live with → Crew you hang with." The key prompt is the SAME
/// surface for both; only the drive scoping differs (step 4). "Dip your toe
/// in": ↓ steps in, ↑ steps back out, nothing commits until the key does.
/// Sample roster is a placeholder until step 3 (gate proof) / 6 (claim). Thin
/// by design — must NOT grow media.zig-style. No add-user/+VIP: the roster is
/// managed from the owner's own settings, never this surface (settings.md).
///
/// Law: settings.md (two doors), styles (THE PILL, CFC, INPUT LAW), naming.md
/// (SystemFam / OwnersFam / KidulCrew).
const RESIDENT_NAMES = [_][:0]const u8{ "Owner", "Kid 1", "Kid 2" };

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

const Seat = enum { residents, kidulcrew };
const Level = enum { pill, list, prompt };

/// The proof verdict, surfaced in the key prompt (settings.md step 3 KUSHD
/// ROUTE). The slide never owns the gate — it cues kushd and renders whatever
/// verdict comes back: waiting (tap pending), trusted (the resolved role), or
/// untrusted ("no access").
pub const Verdict = enum { waiting, trusted, untrusted };

const ROLE_BUF_LEN = 32;

/// The Sign In slide's in-slide widget: the Residents / KidulCrew pill bar and
/// the focused door's content (a name list for Residents, a sign-in for
/// KidulCrew, or the shared key prompt). Render state + focus only (the roster
/// is a sample until step 3).
pub const SignInBar = struct {
    seat: Seat = .residents,
    level: Level = .pill,
    name_index: usize = 0,
    state_generation: u32 = 0,

    // KUSHD ROUTE verdict (step 3). The slide renders it; kushd computes it.
    verdict: Verdict = .waiting,
    role: [ROLE_BUF_LEN]u8 = undefined,
    role_len: usize = 0,

    /// Record the proof verdict kushd relayed back. `role` is the roster role
    /// ("owner", "child-1", ...) on TRUSTED; ignored otherwise. Bumps the
    /// generation so the slide repaints.
    pub fn setVerdict(self: *SignInBar, v: Verdict, role: []const u8) void {
        self.verdict = v;
        self.role_len = @min(role.len, ROLE_BUF_LEN);
        if (self.role_len > 0) @memcpy(self.role[0..self.role_len], role[0..self.role_len]);
        self.bump();
    }

    /// Reset to "waiting" — called when the slide backs out of the prompt so a
    /// re-entry starts a fresh proof.
    pub fn resetVerdict(self: *SignInBar) void {
        if (self.verdict == .waiting and self.role_len == 0) return;
        self.verdict = .waiting;
        self.role_len = 0;
        self.bump();
    }

    fn bump(self: *SignInBar) void {
        self.state_generation +%= 1;
    }

    fn nameCount(self: *const SignInBar) usize {
        _ = self; // roster is a compile-time sample until step 3
        return RESIDENT_NAMES.len;
    }

    fn listLabel(self: *const SignInBar, i: usize) [:0]const u8 {
        _ = self; // roster is a compile-time sample until step 3
        return RESIDENT_NAMES[i];
    }

    fn descend(self: *SignInBar) bool {
        // .pill -> .list (Residents) or .prompt (KidulCrew).
        if (self.level != .pill) return false;
        if (self.seat == .residents) {
            self.level = .list;
            self.name_index = 0;
        } else {
            self.level = .prompt;
        }
        self.bump();
        return true;
    }

    fn consent(self: *SignInBar) bool {
        // .list -> .prompt (right arrow on a name).
        if (self.level != .list) return false;
        self.level = .prompt;
        self.bump();
        return true;
    }

    fn ascend(self: *SignInBar) bool {
        switch (self.level) {
            .pill => return false, // hard stop at the root
            .list => {
                self.level = .pill;
                self.bump();
                return true;
            },
            .prompt => {
                self.level = if (self.seat == .residents) .list else .pill;
                self.bump();
                return true;
            },
        }
    }

    /// ← : at the pill level, move the seat left (hard stop at the left edge);
    /// below the pill, step back up one level.
    pub fn moveLeft(self: *SignInBar) bool {
        switch (self.level) {
            .pill => {
                if (self.seat == .kidulcrew) {
                    self.seat = .residents;
                    self.bump();
                    return true;
                }
                return false;
            },
            .list, .prompt => return self.ascend(),
        }
    }

    /// → : at the pill level, move the seat right (hard stop at the right
    /// edge); in the Residents list, consent (open the key prompt).
    pub fn moveRight(self: *SignInBar) bool {
        switch (self.level) {
            .pill => {
                if (self.seat == .residents) {
                    self.seat = .kidulcrew;
                    self.bump();
                    return true;
                }
                return false;
            },
            .list => return self.consent(),
            .prompt => return false, // waiting for the tap
        }
    }

    /// ↑ : walk the list up (ascend at the top); back out of the prompt; hard
    /// stop at the pill.
    pub fn moveUp(self: *SignInBar) bool {
        switch (self.level) {
            .pill => return false,
            .list => {
                if (self.name_index == 0) return self.ascend();
                self.name_index -= 1;
                self.bump();
                return true;
            },
            .prompt => return self.ascend(),
        }
    }

    /// ↓ : descend (pill -> list/prompt); walk the list down (hard stop at the
    /// bottom); no-op while waiting for the tap.
    pub fn moveDown(self: *SignInBar) bool {
        switch (self.level) {
            .pill => return self.descend(),
            .list => {
                if (self.name_index + 1 >= self.nameCount()) return false;
                self.name_index += 1;
                self.bump();
                return true;
            },
            .prompt => return false,
        }
    }

    /// Enter : keyboard alias — descend at the pill, consent in the list.
    pub fn confirm(self: *SignInBar) bool {
        switch (self.level) {
            .pill => return self.descend(),
            .list => return self.consent(),
            .prompt => return false,
        }
    }

    /// Esc : step back up one level, hard stop at the pill (back-home.md).
    pub fn back(self: *SignInBar) bool {
        return self.ascend();
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

    fn drawKey(cr: *c.cairo_t, cx: f64, cy: f64, s: f64, col: PillColor, alpha: f64) void {
        // Minimal kidulKey glyph: ring head + stem + one tooth.
        const head_r = s * 0.30;
        c.cairo_set_source_rgba(cr, col.r, col.g, col.b, alpha);
        c.cairo_set_line_width(cr, s * 0.09);
        c.cairo_arc(cr, cx, cy, head_r, 0.0, std.math.pi * 2.0);
        c.cairo_stroke(cr);
        c.cairo_move_to(cr, cx, cy + head_r);
        c.cairo_line_to(cr, cx, cy + s);
        c.cairo_stroke(cr);
        c.cairo_move_to(cr, cx, cy + s * 0.82);
        c.cairo_line_to(cr, cx + head_r, cy + s * 0.82);
        c.cairo_stroke(cr);
    }

    pub fn renderCard(self: *SignInBar, cr: *c.cairo_t, w_d: f64, h_d: f64, style_: Style, scale_f: f64) void {
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

        // CFC: the interaction (pill track) is dead-centre; title above, content below.
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
            c.cairo_text_extents(cr, "Sign In", &ext);
            const tx = pad_x + (content_w - ext.width) * 0.5;
            const ty = track_y - 26.0 * scale_f - ext.height;
            c.cairo_move_to(cr, tx, ty);
            c.cairo_show_text(cr, "Sign In");
        }

        // ---- The pill track (2 segments: Residents | KidulCrew). ----
        roundedRect(cr, track_x, track_y, track_w, track_h, track_r);
        c.cairo_set_source_rgba(cr, PILL_TRACK_FILL.r, PILL_TRACK_FILL.g, PILL_TRACK_FILL.b, 1.0);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, PILL_TRACK_BORDER.r, PILL_TRACK_BORDER.g, PILL_TRACK_BORDER.b, 1.0);
        c.cairo_set_line_width(cr, 1.5);
        c.cairo_stroke(cr);

        // Segment separator (one, between the two doors).
        c.cairo_set_source_rgba(cr, PILL_TRACK_BORDER.r, PILL_TRACK_BORDER.g, PILL_TRACK_BORDER.b, 90.0 / 255.0);
        c.cairo_set_line_width(cr, 1.0);
        {
            const sx = track_x + seg_w;
            c.cairo_move_to(cr, sx, track_y + 10.0 * scale_f);
            c.cairo_line_to(cr, sx, track_y + track_h - 10.0 * scale_f);
            c.cairo_stroke(cr);
        }

        const active: usize = if (self.seat == .residents) 0 else 1;

        // Floating inner pill on the focused door (gold ring).
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

        // Door labels.
        {
            const pill_font: f64 = @as(f64, style_.font_size_l) * scale_f;
            c.cairo_set_font_size(cr, pill_font);
            const labels = [_][:0]const u8{ "Residents", "KidulCrew" };
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

        // ---- Content below the track, by state. ----
        if (self.level == .prompt) {
            // The shared key prompt (KUSHD ROUTE step 3): the glyph + a status
            // line driven by the verdict kushd relayed back.
            const glyph_s = 44.0 * scale_f;
            const glyph_cx = pad_x + content_w * 0.5;
            const glyph_cy = track_y + track_h + 36.0 * scale_f;
            const glyph_col = if (self.verdict == .trusted) PILL_TEXT_ACTIVE else PILL_GOLD;
            drawKey(cr, glyph_cx, glyph_cy, glyph_s, glyph_col, 1.0);

            // Context above the glyph (the chosen name for Residents).
            if (self.seat == .residents) {
                const label = self.listLabel(self.name_index);
                var ext: c.cairo_text_extents_t = undefined;
                c.cairo_set_font_size(cr, list_font);
                c.cairo_set_source_rgba(cr, PILL_TEXT_ACTIVE.r, PILL_TEXT_ACTIVE.g, PILL_TEXT_ACTIVE.b, 1.0);
                c.cairo_text_extents(cr, label.ptr, &ext);
                c.cairo_move_to(cr, pad_x + (content_w - ext.width) * 0.5, glyph_cy - 16.0 * scale_f);
                c.cairo_show_text(cr, label.ptr);
            }

            // Status line below the glyph: verdict-dependent.
            var status_buf: [64]u8 = undefined;
            const status: [:0]const u8 = switch (self.verdict) {
                .waiting => "waiting for tap",
                .trusted => blk: {
                    const s = std.fmt.bufPrint(&status_buf, "TRUSTED role={s}", .{self.role[0..self.role_len]}) catch "trusted";
                    status_buf[s.len] = 0;
                    break :blk status_buf[0..s.len :0];
                },
                .untrusted => "no access",
            };
            var ext2: c.cairo_text_extents_t = undefined;
            c.cairo_set_font_size(cr, list_font);
            const stat_col: PillColor = switch (self.verdict) {
                .waiting => PILL_GOLD,
                .trusted => PILL_TEXT_ACTIVE,
                .untrusted => PILL_TEXT_DIM,
            };
            c.cairo_set_source_rgba(cr, stat_col.r, stat_col.g, stat_col.b, 1.0);
            c.cairo_text_extents(cr, status.ptr, &ext2);
            c.cairo_move_to(cr, pad_x + (content_w - ext2.width) * 0.5, glyph_cy + glyph_s + 18.0 * scale_f + ext2.height);
            c.cairo_show_text(cr, status.ptr);
        } else if (self.seat == .residents) {
            // ---- Residents: the name list (focus only while inside the list).
            c.cairo_set_font_size(cr, list_font);
            const count = self.nameCount();
            const focus_active = (self.level == .list);
            var i: usize = 0;
            while (i < count) : (i += 1) {
                const label = self.listLabel(i);
                var ext: c.cairo_text_extents_t = undefined;
                c.cairo_text_extents(cr, label.ptr, &ext);
                const focused = focus_active and (i == self.name_index);
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
        } else {
            // ---- KidulCrew, at the pill: a sign-in (dim key + "sign in").
            const glyph_s = 44.0 * scale_f;
            const glyph_cx = pad_x + content_w * 0.5;
            const glyph_cy = track_y + track_h + 36.0 * scale_f;
            drawKey(cr, glyph_cx, glyph_cy, glyph_s, PILL_GOLD, 120.0 / 255.0);
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_set_font_size(cr, list_font);
            c.cairo_set_source_rgba(cr, PILL_TEXT_DIM.r, PILL_TEXT_DIM.g, PILL_TEXT_DIM.b, 1.0);
            c.cairo_text_extents(cr, "sign in", &ext);
            c.cairo_move_to(cr, pad_x + (content_w - ext.width) * 0.5, glyph_cy + glyph_s + 18.0 * scale_f + ext.height);
            c.cairo_show_text(cr, "sign in");
        }
    }
};

/// Per-output scene state for the Sign In slide (mirrors UserHomeSlide): tree +
/// buffer + the bar widget + repaint guards.
pub const SignInSlide = struct {
    tree: ?*wlr.SceneTree = null,
    card_buffer: ?*wlr.SceneBuffer = null,
    bar: SignInBar = .{},
    card_last_w: i32 = 0,
    card_last_h: i32 = 0,
    card_last_gen: u32 = std.math.maxInt(u32),
    card_dirty: bool = true,

    pub fn isOpen(self: *const SignInSlide) bool {
        return self.tree != null;
    }
};

/// Render the Sign In slide into a wlroots buffer (mirrors users_bar.renderToBuffer).
pub fn renderToBuffer(
    bar: *SignInBar,
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
    _ = SignInBar.moveDown;
}
