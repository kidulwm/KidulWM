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

// ---- claim ceremony constants (build order 3) ----
const NAME_MAX: usize = 24; // the alias cap — a name, not a novel
const FILL_QUARTER: u8 = 25; // quarter-jump tap step (¼ ½ ¾ full)
const FILL_FINE: u8 = 1; // hold-to-fine 1%-per-repeat walk (accel is a later knob)

/// The letter walk's fixed slots: A..Z in order, then two action slots. The
/// actions are authored as sentinel chars the input path maps to backspace /
/// commit; the render prints them as ⌫ and "done".
const LETTER_SLOTS = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "<", "✔" };
const LETTER_BACK: usize = LETTER_SLOTS.len - 2; // "<" backspace
const LETTER_DONE: usize = LETTER_SLOTS.len - 1; // "✔" commit

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

/// The claim ceremony's own sub-ladder (claim-carve.draft.md build order 3).
/// Active ONLY when verdict == .claim (a first-tap on an empty roster). The two
/// doors (pill/list/prompt) are meaningless on an empty roster — there is no one
/// to list and no one to be "crew" yet — so claim REPLACES the Level ladder with
/// name -> size -> consent, exactly one run, never re-entered once a real home
/// exists (a claimed boot routes to the two doors, ruling E).
pub const ClaimStage = enum { name, size, consent };

/// The outcome of a consent-stage confirm, returned to the server so it can fire
/// the carve (commit) or reset the surface (cancel). `.none` = the state machine
/// advanced internally (size->consent, or the full-extra-beat) — nothing for the
/// caller to do yet.
pub const ClaimCommit = enum { none, cancel, commit };

/// The proof verdict, surfaced in the key prompt (settings.md step 3 KUSHD
/// ROUTE). The slide never owns the gate — it cues kushd and renders whatever
/// verdict comes back: waiting (tap pending), trusted (the resolved role),
/// claim (empty-roster first-tap — the claim ceremony entry), or untrusted
/// ("no access").
pub const Verdict = enum { waiting, trusted, claim, untrusted };

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

    // ---- claim ceremony state (build order 3) — active when verdict == .claim.
    claim_stage: ClaimStage = .name,

    // Name field (Q A: ONE name field, TWO surfaces — the pill-walk and the
    // keyboard write into this same buffer; last surface used wins the stroke).
    name_buf: [NAME_MAX]u8 = undefined,
    name_len: usize = 0,

    // The letter pill-walk (Q A): a sorted A..Z walk + two actions (⌫ done),
    // cursored by <>/enter. letter_index walks the fixed 28-slot alphabet+action
    // array; the render scrolls a window over it so it reads as one smooth walk,
    // not 28 stops. The action slots commit/backspace rather than append.
    letter_index: usize = 0,

    // Size fill bar (settings.md §182-203): percent is the single source of
    // truth. quarter taps step by FILL_QUARTER, hold walks FILL_FINE per repeat,
    // keyboard types an exact number. TV default = 50 (ruling C: sharing is
    // caring). hard stops at 0 and 100, no wrap.
    size_pct: u8 = 50,

    // The exact-% keyboard path ("type the exact %"): digits accumulate into a
    // small buffer (shown while typing) and commit into size_pct on Enter. A
    // backspace clears it; walking the arrows clears it too (the fill bar takes
    // over — last surface used wins, Q A's one rule applied to size as well).
    pct_buf: [3]u8 = undefined,
    pct_len: usize = 0,

    // Consent (settings.md: consent-on-consent): defaults to CANCEL; "full"
    // (100%) gets an extra beat — the one choice that can eat the system.
    consent_cancel: bool = true,
    consent_full_beat: bool = false,

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

    // ---- claim ceremony input (build order 3) — active only when verdict == .claim.

    /// True while a claim candidate is on the slide (verdict == .claim): the
    /// claim ladder owns the arrows/enter, NOT the two-door ladder.
    pub fn inClaim(self: *const SignInBar) bool {
        return self.verdict == .claim;
    }

    /// Append a keyboard-typed character to the name field (Q A: the keyboard
    /// path writes the SAME name_buf as the pill-walk). Lower-bound only
    /// a-z/space — the TV keyboard set. Returns true when the stroke landed.
    pub fn nameChar(self: *SignInBar, ch: u8) bool {
        if (self.claim_stage != .name) return false;
        const lower = std.ascii.toLower(ch);
        const ok = (lower >= 'a' and lower <= 'z') or lower == ' ';
        if (!ok) return false;
        if (self.name_len >= NAME_MAX) return false;
        self.name_buf[self.name_len] = lower;
        self.name_len += 1;
        self.bump();
        return true;
    }

    pub fn nameBackspace(self: *SignInBar) bool {
        if (self.name_len == 0) return false;
        self.name_len -= 1;
        self.bump();
        return true;
    }

    /// Append the focused letter slot (pill-walk). The two action slots do not
    /// append: BACK backspaces, DONE advances to the size stage.
    pub fn claimLetterConfirm(self: *SignInBar) bool {
        if (self.claim_stage != .name) return false;
        switch (self.letter_index) {
            LETTER_BACK => return self.nameBackspace(),
            LETTER_DONE => {
                if (self.name_len == 0) return false; // a claim needs a name
                self.claim_stage = .size;
                self.letter_index = 0;
                self.bump();
                return true;
            },
            else => {
                const ch = LETTER_SLOTS[self.letter_index][0];
                return self.nameChar(ch);
            },
        }
    }

    /// ←→ on the name stage walk the letter slots (hard stop at both ends, no
    /// wrap); on the size stage they step the fill bar (quarter per press).
    pub fn claimMove(self: *SignInBar, delta: isize) bool {
        switch (self.claim_stage) {
            .name => {
                const ni: isize = @intCast(self.letter_index);
                const next = ni + delta;
                if (next < 0 or next >= @as(isize, @intCast(LETTER_SLOTS.len))) return false;
                self.letter_index = @intCast(next);
                self.bump();
                return true;
            },
            .size => {
                self.pctClear(); // an arrow walk hands the bar back from the keyboard
                const step: i16 = @intCast(FILL_QUARTER * @as(u8, @intCast(@abs(delta))));
                if (delta > 0) {
                    if (self.size_pct >= 100) return false;
                    self.size_pct = @min(100, self.size_pct + @as(u8, @intCast(step)));
                } else {
                    if (self.size_pct == 0) return false;
                    self.size_pct = @max(0, self.size_pct -| @as(u8, @intCast(step)));
                }
                self.bump();
                return true;
            },
            .consent => {
                // consent: ←→ flip the CANCEL/CONFIRM ball (hard stops both ways).
                if (delta > 0 and self.consent_cancel) {
                    self.consent_cancel = false;
                    self.bump();
                    return true;
                }
                if (delta < 0 and !self.consent_cancel) {
                    self.consent_cancel = true;
                    self.bump();
                    return true;
                }
                return false;
            },
        }
    }

    /// Hold-to-fine on the size stage: a repeat press (auto-repeat on) walks 1%
    /// per event. Only meaningful while the arrow is held; distinguished from a
    /// quarter-tap by the caller (server tracks press-vs-repeat, or simply lets
    /// the first press do the quarter and repeats do the fine). For now the
    /// slide exposes the FINE step directly; the server routes repeats here.
    pub fn claimHoldFine(self: *SignInBar, delta: isize) bool {
        if (self.claim_stage != .size) return false;
        self.pctClear(); // a held arrow walks the bar; drop any pending keyboard %
        if (delta > 0) {
            if (self.size_pct >= 100) return false;
            self.size_pct += FILL_FINE;
        } else {
            if (self.size_pct == 0) return false;
            self.size_pct -= FILL_FINE;
        }
        self.bump();
        return true;
    }

    /// Keyboard exact-% (settings.md §193): append a digit to the pending
    /// buffer. At most 3 digits (0-100); a leading 0 is allowed so "000" is 0
    /// and "050" is 50. Returns true when the stroke landed.
    pub fn pctDigit(self: *SignInBar, digit: u8) bool {
        if (self.claim_stage != .size) return false;
        if (self.pct_len >= 3) return false;
        self.pct_buf[self.pct_len] = '0' + digit;
        self.pct_len += 1;
        self.bump();
        return true;
    }

    /// Commit the pending exact-% buffer into size_pct (clamped 0-100), then
    /// clear it. Called on Enter at the size stage. Returns the parsed value.
    fn pctCommit(self: *SignInBar) void {
        if (self.pct_len == 0) return;
        var v: u16 = 0;
        for (self.pct_buf[0..self.pct_len]) |ch| {
            v = v * 10 + @as(u16, ch - '0');
            if (v > 100) v = 100;
        }
        self.size_pct = @intCast(@min(100, v));
        self.pct_len = 0;
    }

    /// Clear a pending exact-% buffer (an arrow walk or a backspace on the size
    /// stage hands the fill bar back to the arrow-native control).
    fn pctClear(self: *SignInBar) void {
        if (self.pct_len == 0) return;
        self.pct_len = 0;
        self.bump();
    }

    /// ↓/Enter on size -> consent; on consent -> commit (CONFIRM) or abort
    /// (CANCEL). Full (100%) forces the extra beat: first confirm reveals the
    /// "full" warning and re-defaults to cancel rather than committing.
    pub fn claimConfirm(self: *SignInBar) ClaimCommit {
        switch (self.claim_stage) {
            .name => {
                _ = self.claimLetterConfirm();
                return .none;
            },
            .size => {
                self.pctCommit(); // fold a typed exact-% into size_pct first
                self.claim_stage = .consent;
                self.consent_cancel = true;
                self.consent_full_beat = self.size_pct >= 100;
                self.bump();
                return .none;
            },
            .consent => {
                if (self.consent_cancel) return .cancel;
                if (self.consent_full_beat) {
                    // the extra beat: surface the warning once, re-default cancel
                    self.consent_full_beat = false;
                    self.consent_cancel = true;
                    self.bump();
                    return .none;
                }
                return .commit;
            },
        }
    }

    /// Esc/↑ on the claim ladder: step back one stage (consent -> size defaulting
    /// back; size -> name; name is a hard floor — a claim candidate can only
    /// leave the surface by closing the slide).
    pub fn claimBack(self: *SignInBar) bool {
        switch (self.claim_stage) {
            .name => return false,
            .size => {
                self.claim_stage = .name;
                self.bump();
                return true;
            },
            .consent => {
                self.claim_stage = .size;
                self.bump();
                return true;
            },
        }
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
        // Claim mode replaces the two-door surface entirely (build order 3): an
        // empty roster has no residents and no crew, only the first-tap claim.
        if (self.inClaim()) {
            self.renderClaimCard(cr, w_d, h_d, style_, scale_f);
            return;
        }

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
                .claim => "welcome — claim your home",
                .untrusted => "no access",
            };
            var ext2: c.cairo_text_extents_t = undefined;
            c.cairo_set_font_size(cr, list_font);
            const stat_col: PillColor = switch (self.verdict) {
                .waiting => PILL_GOLD,
                .trusted => PILL_TEXT_ACTIVE,
                .claim => PILL_GOLD,
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

    /// Render the claim ceremony surface (build order 3). Reuses the house pill
    /// chrome and CFC (title top, interaction centre, content below) but draws a
    /// three-stage ladder — name (letter walk + the typed field), size (fill
    /// bar), consent (cancel-default nag) — instead of the two doors.
    fn renderClaimCard(self: *SignInBar, cr: *c.cairo_t, w_d: f64, h_d: f64, style_: Style, scale_f: f64) void {
        const pad_x: f64 = 22.0 * scale_f;
        const content_w = w_d - 2.0 * pad_x;
        const title_font: f64 = @as(f64, style_.font_size_l) * 1.5 * scale_f;
        const body_font: f64 = @as(f64, style_.font_size_m) * scale_f;

        c.cairo_select_font_face(cr, "Fantasque Sans Mono", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);

        // ---- Title, by stage (CFC: title above the interaction). ----
        const title: []const u8 = switch (self.claim_stage) {
            .name => "Claim your home",
            .size => "How much space?",
            .consent => "Make it so?",
        };
        {
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_set_font_size(cr, title_font);
            c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 1.0);
            c.cairo_text_extents(cr, title.ptr, &ext);
            c.cairo_move_to(cr, pad_x + (content_w - ext.width) * 0.5, 56.0 * scale_f);
            c.cairo_show_text(cr, title.ptr);
        }

        switch (self.claim_stage) {
            .name => self.renderClaimName(cr, w_d, h_d, body_font, scale_f),
            .size => self.renderClaimSize(cr, w_d, h_d, body_font, scale_f),
            .consent => self.renderClaimConsent(cr, w_d, h_d, body_font, scale_f),
        }
    }

    fn renderClaimName(self: *SignInBar, cr: *c.cairo_t, w_d: f64, h_d: f64, font: f64, scale_f: f64) void {
        const pad_x: f64 = 22.0 * scale_f;
        const content_w = w_d - 2.0 * pad_x;

        // ---- The name field (CFC centre): the typed alias or a placeholder. ----
        const field_y = (h_d - PILL_TRACK_H * scale_f) * 0.5 - 20.0 * scale_f;
        {
            const label: []const u8 = if (self.name_len > 0) self.name_buf[0..self.name_len] else "your name";
            const tcol = if (self.name_len > 0) PILL_TEXT_ACTIVE else PILL_TEXT_DIM;
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_set_font_size(cr, font);
            c.cairo_set_source_rgba(cr, tcol.r, tcol.g, tcol.b, 1.0);
            c.cairo_text_extents(cr, label.ptr, &ext);
            c.cairo_move_to(cr, pad_x + (content_w - ext.width) * 0.5, field_y + ext.height);
            c.cairo_show_text(cr, label.ptr);
        }

        // ---- The letter walk (a pill track window over LETTER_SLOTS). ----
        const seg_w = PILL_SEG_W * scale_f;
        const track_h = PILL_TRACK_H * scale_f;
        const inset = PILL_INSET * scale_f;
        const pill_h = track_h - 2.0 * inset;
        const pill_r = pill_h * 0.5;
        const pill_w = seg_w - 2.0 * inset;
        const track_r = track_h * 0.5;

        // A sliding window of 5 slots; the focused slot sits centre. Window start
        // clamps at the ends (hard stops; the bar never scrolls past them). The
        // render draws a fixed-width 5-slot track so the focused letter walks
        // across as one smooth motion rather than 28 discrete stops.
        const WINDOW: usize = 5;
        var win_start: isize = @as(isize, @intCast(self.letter_index)) - 2;
        if (win_start < 0) win_start = 0;
        const max_start: isize = @as(isize, @intCast(LETTER_SLOTS.len)) - @as(isize, @intCast(WINDOW));
        if (win_start > max_start) win_start = max_start;

        const track_w = seg_w * @as(f64, @floatFromInt(WINDOW));
        const track_x = pad_x + @max(0.0, (content_w - track_w) * 0.5);
        const track_y = (h_d - track_h) * 0.5 + 16.0 * scale_f;

        roundedRect(cr, track_x, track_y, track_w, track_h, track_r);
        c.cairo_set_source_rgba(cr, PILL_TRACK_FILL.r, PILL_TRACK_FILL.g, PILL_TRACK_FILL.b, 1.0);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, PILL_TRACK_BORDER.r, PILL_TRACK_BORDER.g, PILL_TRACK_BORDER.b, 1.0);
        c.cairo_set_line_width(cr, 1.5);
        c.cairo_stroke(cr);

        // Separators between the window slots.
        c.cairo_set_source_rgba(cr, PILL_TRACK_BORDER.r, PILL_TRACK_BORDER.g, PILL_TRACK_BORDER.b, 90.0 / 255.0);
        c.cairo_set_line_width(cr, 1.0);
        var s: usize = 1;
        while (s < WINDOW) : (s += 1) {
            const sx = track_x + @as(f64, @floatFromInt(s)) * seg_w;
            c.cairo_move_to(cr, sx, track_y + 10.0 * scale_f);
            c.cairo_line_to(cr, sx, track_y + track_h - 10.0 * scale_f);
            c.cairo_stroke(cr);
        }

        // Floating inner pill on the focused slot (gold ring), then the labels.
        const focused_slot: isize = @as(isize, @intCast(self.letter_index)) - win_start;
        if (focused_slot >= 0 and focused_slot < WINDOW) {
            const pill_x = track_x + @as(f64, @floatFromInt(focused_slot)) * seg_w + inset;
            roundedRect(cr, pill_x, track_y + inset, pill_w, pill_h, pill_r);
            c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 90.0 / 255.0);
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 200.0 / 255.0);
            c.cairo_set_line_width(cr, 1.5);
            c.cairo_stroke(cr);
        }
        c.cairo_set_font_size(cr, font);
        var i: usize = 0;
        while (i < WINDOW) : (i += 1) {
            const slot: isize = win_start + @as(isize, @intCast(i));
            const label = LETTER_SLOTS[@intCast(slot)];
            const focused = (slot == self.letter_index);
            const tcol = if (focused) PILL_TEXT_ACTIVE else PILL_TEXT_DIM;
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, label.ptr, &ext);
            const seg_x = track_x + @as(f64, @floatFromInt(i)) * seg_w;
            c.cairo_set_source_rgba(cr, tcol.r, tcol.g, tcol.b, 1.0);
            c.cairo_move_to(cr, seg_x + (seg_w - ext.width) * 0.5, track_y + track_h * 0.5 + font * 0.30);
            c.cairo_show_text(cr, label.ptr);
        }

        // Hint line under the walk.
        c.cairo_set_font_size(cr, font);
        c.cairo_set_source_rgba(cr, PILL_TEXT_DIM.r, PILL_TEXT_DIM.g, PILL_TEXT_DIM.b, 1.0);
        var ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, "walk, enter a letter, done when ready", &ext);
        c.cairo_move_to(cr, pad_x + (content_w - ext.width) * 0.5, track_y + track_h + 26.0 * scale_f + ext.height);
        c.cairo_show_text(cr, "walk, enter a letter, done when ready");
    }

    fn renderClaimSize(self: *SignInBar, cr: *c.cairo_t, w_d: f64, h_d: f64, font: f64, scale_f: f64) void {
        const pad_x: f64 = 22.0 * scale_f;
        const content_w = w_d - 2.0 * pad_x;
        const track_h = PILL_TRACK_H * scale_f;
        const track_r = track_h * 0.5;
        const inset = PILL_INSET * scale_f;
        const ball_r = (track_h - 2.0 * inset) * 0.5;

        // One fill bar (the "no-slider slider"): taken % shaded gold, ball at the
        // edge, the % value CFC'd above. Wide enough to read, capped to content.
        const bar_w = @min(content_w, 840.0 * scale_f);
        const bar_x = pad_x + (content_w - bar_w) * 0.5;
        const bar_y = (h_d - track_h) * 0.5;

        // Track.
        roundedRect(cr, bar_x, bar_y, bar_w, track_h, track_r);
        c.cairo_set_source_rgba(cr, PILL_TRACK_FILL.r, PILL_TRACK_FILL.g, PILL_TRACK_FILL.b, 1.0);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, PILL_TRACK_BORDER.r, PILL_TRACK_BORDER.g, PILL_TRACK_BORDER.b, 1.0);
        c.cairo_set_line_width(cr, 1.5);
        c.cairo_stroke(cr);

        // Taken fill (gold, shaded from the left to size_pct%).
        const taken_w = bar_w * (@as(f64, @floatFromInt(self.size_pct)) / 100.0);
        if (taken_w > 0.0) {
            roundedRect(cr, bar_x, bar_y, taken_w, track_h, track_r);
            c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 120.0 / 255.0);
            c.cairo_fill(cr);
        }

        // The ball at the edge of the taken region.
        const ball_cx = bar_x + taken_w;
        c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 1.0);
        c.cairo_arc(cr, ball_cx, bar_y + track_h * 0.5, ball_r, 0.0, std.math.pi * 2.0);
        c.cairo_stroke(cr);

        // The % value, CFC'd above the bar (the one number that matters). While
        // a keyboard exact-% is mid-typed it shows the pending digits instead.
        var pct_buf: [8]u8 = undefined;
        const pct: []const u8 = blk: {
            if (self.pct_len > 0) {
                const s = std.fmt.bufPrint(&pct_buf, "{s}%", .{self.pct_buf[0..self.pct_len]}) catch "0%";
                break :blk s;
            }
            const s = std.fmt.bufPrint(&pct_buf, "{d}%", .{self.size_pct}) catch "0%";
            break :blk s;
        };
        var ext: c.cairo_text_extents_t = undefined;
        c.cairo_set_font_size(cr, font);
        c.cairo_set_source_rgba(cr, PILL_TEXT_ACTIVE.r, PILL_TEXT_ACTIVE.g, PILL_TEXT_ACTIVE.b, 1.0);
        c.cairo_text_extents(cr, pct.ptr, &ext);
        c.cairo_move_to(cr, pad_x + (content_w - ext.width) * 0.5, bar_y - 20.0 * scale_f);
        c.cairo_show_text(cr, pct.ptr);

        // Hint line (settings.md §182): teach the gesture in one line.
        c.cairo_set_source_rgba(cr, PILL_TEXT_DIM.r, PILL_TEXT_DIM.g, PILL_TEXT_DIM.b, 1.0);
        c.cairo_text_extents(cr, "tap for a quarter, hold to fine-tune", &ext);
        c.cairo_move_to(cr, pad_x + (content_w - ext.width) * 0.5, bar_y + track_h + 26.0 * scale_f + ext.height);
        c.cairo_show_text(cr, "tap for a quarter, hold to fine-tune");
    }

    fn renderClaimConsent(self: *SignInBar, cr: *c.cairo_t, w_d: f64, h_d: f64, font: f64, scale_f: f64) void {
        const pad_x: f64 = 22.0 * scale_f;
        const content_w = w_d - 2.0 * pad_x;

        // The nag, in Granny's terms (settings.md: never "mkfs.ext4").
        const is_full = self.size_pct >= 100;
        const line1: []const u8 = if (is_full)
            "ALL of the shared disc goes to this home."
        else
            "Give this home its own private part of the disc.";
        const line2: []const u8 = if (is_full)
            "No one else can ever add theirs."
        else
            "The rest stays a shared pool for the others.";

        const y0 = (h_d - PILL_TRACK_H * scale_f) * 0.5 - 20.0 * scale_f;
        c.cairo_set_font_size(cr, font);
        c.cairo_set_source_rgba(cr, PILL_TEXT_ACTIVE.r, PILL_TEXT_ACTIVE.g, PILL_TEXT_ACTIVE.b, 1.0);
        var ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, line1.ptr, &ext);
        c.cairo_move_to(cr, pad_x + (content_w - ext.width) * 0.5, y0 + ext.height);
        c.cairo_show_text(cr, line1.ptr);
        c.cairo_set_source_rgba(cr, PILL_TEXT_DIM.r, PILL_TEXT_DIM.g, PILL_TEXT_DIM.b, 1.0);
        c.cairo_text_extents(cr, line2.ptr, &ext);
        c.cairo_move_to(cr, pad_x + (content_w - ext.width) * 0.5, y0 + ext.height * 2.0 + 10.0 * scale_f);
        c.cairo_show_text(cr, line2.ptr);

        // The two-choice ball: CANCEL (default) | CONFIRM. ←→ flips, Enter settles.
        const seg_w = PILL_SEG_W * scale_f;
        const track_h = PILL_TRACK_H * scale_f;
        const track_r = track_h * 0.5;
        const inset = PILL_INSET * scale_f;
        const pill_h = track_h - 2.0 * inset;
        const pill_r = pill_h * 0.5;
        const pill_w = seg_w - 2.0 * inset;
        const track_w = seg_w * 2.0;
        const track_x = pad_x + @max(0.0, (content_w - track_w) * 0.5);
        const track_y = (h_d - track_h) * 0.5 + 20.0 * scale_f;

        roundedRect(cr, track_x, track_y, track_w, track_h, track_r);
        c.cairo_set_source_rgba(cr, PILL_TRACK_FILL.r, PILL_TRACK_FILL.g, PILL_TRACK_FILL.b, 1.0);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, PILL_TRACK_BORDER.r, PILL_TRACK_BORDER.g, PILL_TRACK_BORDER.b, 1.0);
        c.cairo_set_line_width(cr, 1.5);
        c.cairo_stroke(cr);

        const active: usize = if (self.consent_cancel) 0 else 1;
        {
            const pill_x = track_x + @as(f64, @floatFromInt(active)) * seg_w + inset;
            roundedRect(cr, pill_x, track_y + inset, pill_w, pill_h, pill_r);
            c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 90.0 / 255.0);
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, 200.0 / 255.0);
            c.cairo_set_line_width(cr, 1.5);
            c.cairo_stroke(cr);
        }
        c.cairo_set_font_size(cr, font);
        const labels = [_][:0]const u8{ "Cancel", "Confirm" };
        for (0..2) |i| {
            const seg_x = track_x + @as(f64, @floatFromInt(i)) * seg_w;
            var ext2: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, labels[i].ptr, &ext2);
            const tcol = if (i == active) PILL_TEXT_ACTIVE else PILL_TEXT_DIM;
            c.cairo_set_source_rgba(cr, tcol.r, tcol.g, tcol.b, 1.0);
            c.cairo_move_to(cr, seg_x + (seg_w - ext2.width) * 0.5, track_y + track_h * 0.5 + font * 0.30);
            c.cairo_show_text(cr, labels[i].ptr);
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
