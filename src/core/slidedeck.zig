const std = @import("std");
const style = @import("style.zig");

pub const Rect = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,

    pub fn inset(self: Rect, gap: u32) Rect {
        const g = @as(i32, @intCast(gap));
        return .{
            .x = self.x + g,
            .y = self.y + g,
            .width = if (self.width > 2 * gap) self.width - 2 * gap else 0,
            .height = if (self.height > 2 * gap) self.height - 2 * gap else 0,
        };
    }
};

pub const Orientation = enum { horizontal, vertical };

pub const Split = struct {
    left_peek: f32,
    focus: f32,
    right_peek: f32,

    pub fn normalize(self: *Split) void {
        const sum = self.left_peek + self.focus + self.right_peek;
        if (sum > 0.001 and @abs(sum - 1.0) > 0.001) {
            const scale = 1.0 / sum;
            self.left_peek *= scale;
            self.focus *= scale;
            self.right_peek *= scale;
        }
        self.left_peek = @max(0, self.left_peek);
        self.focus = @max(0, self.focus);
        self.right_peek = @max(0, self.right_peek);
    }
};

/// Compositor-owned slide kinds (TASKCARD-3): home and media player are REAL
/// deck.slides entries — no special flags, no empty-slot tricks. Fullscreen
/// video is NOT a slide kind: it is a MODE the media card enters and leaves
/// (fullscreen.md). `window_id` holds a compositor-generated id that never
/// collides with a client window id (see SlideDeck.compositor_id_base).
pub const SlideKind = enum { app, home, media_player };

pub const Slide = struct {
    window_id: u32,
    /// Parked slides stay in the deck (the client is alive) but are hidden
    /// from normal layout and navigation. Overview mode (Task 2) shows them.
    parked: bool = false,
    /// Fullscreen toggle (Barticus 2026-09-16): any slide may fill the whole
    /// output on a hotkey, in and out. Same law as playback.md — fullscreen
    /// is a SIZE, not a mode. Media auto-fullscreens; other apps use this.
    fullscreen: bool = false,
    /// Slide species. `.app` = backed by a real client window; the rest are
    /// compositor-owned surfaces rendered by a ui/ module.
    kind: SlideKind = .app,
    /// EPHEMERAL LAW (session-and-deck-spec): activating a home-slide
    /// launcher item spawn/focuses the target, then the home slide destroys
    /// itself. The only self-closing slide; one flag, not an architecture.
    ephemeral: bool = false,
};

pub const EmptySlot = enum { none, before_first, after_last };

/// SlideDeck: a per-output stack of full-screen Slides.
/// Only the focused Slide and its immediate neighbours are visible;
/// deeper slides sit off-screen and animate into view when focused.
///
/// Focus may also rest on a virtual empty slot before the first or after the
/// last real slide.  From those slots the nearest real slide becomes the peek
/// on the side it sits, and new windows open into the empty slot.
pub const SlideDeck = struct {
    allocator: std.mem.Allocator,
    slides: std.ArrayList(Slide),
    width: u32,
    height: u32,
    gap: u32,
    focused_index: usize,
    empty_slot: EmptySlot,
    split: Split,
    orientation: Orientation,
    /// Overview slide (PIVOT ruling 2026-08-19): when true, the
    /// after_last empty slot is OCCUPIED by the compositor-owned place-card
    /// grid instead of emptiness. Not a Slide in slides.items — window-count
    /// invariants (slide_count == real client count) stay intact.
    overview_slide_open: bool = false,
    /// The slide index to return to when the overview slide closes.
    overview_return_index: usize = 0,
    next_compositor_id: u32 = compositor_id_base,

    /// Compositor-owned slide ids live in a disjoint range from client
    /// window ids (clients count up from 1). Generated per spawn.
    pub const compositor_id_base: u32 = 0xC000_0000;

    pub fn init(allocator: std.mem.Allocator) SlideDeck {
        return .{
            .allocator = allocator,
            .slides = std.ArrayList(Slide).empty,
            .width = 0,
            .height = 0,
            .gap = style.layout.gap,
            .focused_index = 0,
            .empty_slot = .none,
            .split = .{
                .left_peek = style.layout.default_split.left_peek,
                .focus = style.layout.default_split.focus,
                .right_peek = style.layout.default_split.right_peek,
            },
            .orientation = .horizontal,
        };
    }

    pub fn deinit(self: *SlideDeck) void {
        self.slides.deinit(self.allocator);
    }

    pub fn slideCount(self: *const SlideDeck) usize {
        return self.slides.items.len;
    }

    /// Update output size and split ratios, then re-normalise them.
    pub fn sync(self: *SlideDeck, width: u32, height: u32, gap: u32, split: Split, orientation: Orientation) void {
        self.width = width;
        self.height = height;
        self.gap = gap;
        self.split = split;
        self.split.normalize();
        self.orientation = orientation;
        self.clampFocus();
    }

    pub fn setSplit(self: *SlideDeck, split: Split) void {
        self.split = split;
        self.split.normalize();
    }

    fn clampFocus(self: *SlideDeck) void {
        if (self.slides.items.len == 0) {
            self.focused_index = 0;
            self.empty_slot = .none;
            return;
        }
        if (self.focused_index >= self.slides.items.len) {
            self.focused_index = self.slides.items.len - 1;
        }
        // Ensure the empty slot still references a real slide edge.
        switch (self.empty_slot) {
            .none => {},
            .before_first => self.focused_index = 0,
            .after_last => self.focused_index = self.slides.items.len - 1,
        }
    }

    /// Visual focus position: an integer where real slides sit at 0..n-1 and
    /// the two virtual end slots are -1 and n.  This keeps the nearest real
    /// slide in the adjacent peek slot when focus rests past the ends.
    fn virtualFocus(self: *const SlideDeck) isize {
        const n: isize = @intCast(self.slides.items.len);
        const idx: isize = @intCast(self.focused_index);
        return switch (self.empty_slot) {
            .none => idx,
            .before_first => -1,
            .after_last => n,
        };
    }

    /// Add a new Slide. New windows open near the centre unless focus is on a
    /// virtual end slot, in which case they open at that end and the closest
    /// existing slide becomes the peek from that side.
    pub fn addWindow(self: *SlideDeck, window_id: u32) void {
        switch (self.empty_slot) {
            .before_first => {
                self.slides.insert(self.allocator, 0, .{ .window_id = window_id }) catch {
                    std.log.err("SlideDeck: failed to insert new slide", .{});
                    return;
                };
                self.focused_index = 0;
                self.empty_slot = .none;
                return;
            },
            .after_last => {
                self.slides.append(self.allocator, .{ .window_id = window_id }) catch {
                    std.log.err("SlideDeck: failed to append new slide", .{});
                    return;
                };
                self.focused_index = self.slides.items.len - 1;
                self.empty_slot = .none;
                return;
            },
            .none => {},
        }
        // Insert the new slide immediately to the right of the currently
        // focused slide. This keeps the deck in chronological/left-to-right
        // order: the previously focused window becomes the left peek.
        const insert_at = @min(self.focused_index + 1, self.slides.items.len);
        self.slides.insert(self.allocator, insert_at, .{ .window_id = window_id }) catch {
            std.log.err("SlideDeck: failed to insert new slide", .{});
            return;
        };
        self.focused_index = insert_at;
    }

    pub fn removeWindow(self: *SlideDeck, window_id: u32) void {
        for (self.slides.items, 0..) |slide, i| {
            if (slide.window_id == window_id) {
                _ = self.slides.orderedRemove(i);
                if (i < self.focused_index) {
                    self.focused_index -|= 1;
                } else if (i == self.focused_index) {
                    self.clampFocus();
                }
                return;
            }
        }
    }

    /// Park the focused slide: it stays in the deck but is skipped by normal
    /// navigation and laid out as fully hidden (zero-width, off-screen).
    /// Ruling (2026-08-19): refusing when it is the only slide in the deck.
    pub fn parkFocused(self: *SlideDeck) bool {
        if (self.slides.items.len <= 1) {
            std.log.info("SlideDeck: refusing to park the only slide", .{});
            return false;
        }
        if (self.empty_slot != .none) {
            std.log.info("SlideDeck: nothing focused to park (empty slot)", .{});
            return false;
        }
        const idx = self.focused_index;
        if (self.slides.items[idx].parked) return false;
        self.slides.items[idx].parked = true;
        std.log.info("SlideDeck: parked slide {d} (window {d})", .{ idx, self.slides.items[idx].window_id });
        // Move focus to the nearest unparked slide. Try right first, then left.
        if (self.nextUnparked(idx + 1)) |next| {
            self.focused_index = next;
        } else if (self.prevUnparked(idx)) |prev| {
            self.focused_index = prev;
        } else {
            // No unparked slides left (all others parked) — keep index; the
            // empty-slot state will be forced by the caller.
            std.log.info("SlideDeck: all slides now parked", .{});
        }
        return true;
    }

    /// Unpark a slide by index. It re-appears at its existing position
    /// ("where I left it" — the index never moved while parked).
    pub fn unparkIndex(self: *SlideDeck, index: usize) bool {
        if (index >= self.slides.items.len) return false;
        if (!self.slides.items[index].parked) return false;
        self.slides.items[index].parked = false;
        std.log.info("SlideDeck: unparked slide {d} (window {d})", .{ index, self.slides.items[index].window_id });
        return true;
    }

    /// First unparked slide index at or after `from`, or null.
    pub fn nextUnparked(self: *const SlideDeck, from: usize) ?usize {
        var i = from;
        while (i < self.slides.items.len) : (i += 1) {
            if (!self.slides.items[i].parked) return i;
        }
        return null;
    }

    /// Last unparked slide index strictly before `from`, or null.
    pub fn prevUnparked(self: *const SlideDeck, from: usize) ?usize {
        var i = from;
        while (i > 0) {
            i -= 1;
            if (!self.slides.items[i].parked) return i;
        }
        return null;
    }

    pub fn unparkedCount(self: *const SlideDeck) usize {
        var n: usize = 0;
        for (self.slides.items) |slide| {
            if (!slide.parked) n += 1;
        }
        return n;
    }

    pub fn focusNext(self: *SlideDeck) void {
        if (self.slides.items.len == 0) return;
        switch (self.empty_slot) {
            .before_first => {
                self.empty_slot = .none;
                self.focused_index = self.nextUnparked(0) orelse 0;
            },
            .none => {
                if (self.nextUnparked(self.focused_index + 1)) |next| {
                    self.focused_index = next;
                } else {
                    self.empty_slot = .after_last;
                }
            },
            .after_last => {},
        }
    }

    pub fn focusPrev(self: *SlideDeck) void {
        if (self.slides.items.len == 0) return;
        switch (self.empty_slot) {
            .after_last => {
                self.empty_slot = .none;
                self.focused_index = self.prevUnparked(self.slides.items.len) orelse self.slides.items.len - 1;
            },
            .none => {
                if (self.prevUnparked(self.focused_index)) |prev| {
                    self.focused_index = prev;
                } else {
                    self.empty_slot = .before_first;
                }
            },
            .before_first => {},
        }
    }

    pub fn focusWindowByIndex(self: *SlideDeck, index: usize) void {
        if (index < self.slides.items.len and !self.slides.items[index].parked) {
            self.focused_index = index;
            self.empty_slot = .none;
        }
    }

    /// Spawn a compositor-owned slide (home / media player / video) at
    /// `index`, and focus it. Returns the generated compositor id.
    /// TASKCARD-3: these are REAL deck.slides entries — they walk, peek,
    /// park and quit through the stock paths.
    pub fn addCompositorSlide(self: *SlideDeck, kind: SlideKind, index: usize, ephemeral: bool) u32 {
        const id = self.next_compositor_id;
        self.next_compositor_id +%= 1;
        const at = @min(index, self.slides.items.len);
        self.slides.insert(self.allocator, at, .{ .window_id = id, .kind = kind, .ephemeral = ephemeral }) catch {
            std.log.err("SlideDeck: failed to insert compositor slide", .{});
            return 0;
        };
        self.focused_index = at;
        self.empty_slot = .none;
        return id;
    }

    /// Index of the first slide of the given kind, or null.
    pub fn findKind(self: *const SlideDeck, kind: SlideKind) ?usize {
        for (self.slides.items, 0..) |slide, i| {
            if (slide.kind == kind) return i;
        }
        return null;
    }

    /// Destroy a compositor-owned slide by kind. Focus settles through the
    /// stock removeWindow path — NO return-index bookkeeping.
    pub fn removeCompositorSlide(self: *SlideDeck, kind: SlideKind) bool {
        const idx = self.findKind(kind) orelse return false;
        _ = self.slides.orderedRemove(idx);
        if (idx < self.focused_index) {
            self.focused_index -|= 1;
        } else {
            self.clampFocus();
        }
        return true;
    }

    /// Open the overview slide at the end of the row. The focused
    /// slide index is remembered for the return trip; focus moves onto the
    /// virtual after_last slot, which now displays the card grid.
    pub fn openOverviewSlide(self: *SlideDeck) void {
        if (self.slides.items.len == 0) return;
        if (self.overview_slide_open) return;
        self.overview_return_index = self.focused_index;
        self.overview_slide_open = true;
        self.empty_slot = .after_last;
        std.log.info("SlideDeck: overview slide opened (return_index={d}, slides={d})", .{ self.overview_return_index, self.slides.items.len });
    }

    /// Close the overview slide and return focus to the slide that opened it
    /// (clamped — the deck may have changed while the grid was open).
    pub fn closeOverviewSlide(self: *SlideDeck) void {
        if (!self.overview_slide_open) return;
        self.overview_slide_open = false;
        self.empty_slot = .none;
        if (self.slides.items.len > 0) {
            self.focused_index = @min(self.overview_return_index, self.slides.items.len - 1);
            // Never land back on a parked slide.
            if (self.slides.items[self.focused_index].parked) {
                if (self.nextUnparked(self.focused_index + 1)) |n| {
                    self.focused_index = n;
                } else if (self.prevUnparked(self.focused_index)) |p| {
                    self.focused_index = p;
                }
            }
        }
        std.log.info("SlideDeck: overview slide closed (focused_index={d})", .{self.focused_index});
    }

    pub fn toggleOverviewSlide(self: *SlideDeck) void {
        if (self.overview_slide_open) self.closeOverviewSlide() else self.openOverviewSlide();
    }

    /// True while the overview slide occupies the end slot.
    pub fn overviewSlideOpen(self: *const SlideDeck) bool {
        return self.overview_slide_open and self.empty_slot == .after_last;
    }

    /// Toggle the fullscreen flag on the focused slide (hotkey path).
    /// Returns the new state, or null when no slide is focused.
    pub fn fullscreenToggleFocused(self: *SlideDeck) ?bool {
        if (self.empty_slot != .none) return null;
        if (self.focused_index >= self.slides.items.len) return null;
        const slide = &self.slides.items[self.focused_index];
        if (slide.parked) return null;
        slide.fullscreen = !slide.fullscreen;
        return slide.fullscreen;
    }

    /// Recency position of a slide among unparked slides (0 = top-left).
    /// The walk starts at the focused slide if unparked, else the nearest
    /// unparked slide to its right, then left — the raw focused_index may
    /// point at a parked slide, and a null cursor position breaks the whole
    /// lens (no inflate, no ring).
    pub fn recencyPos(self: *const SlideDeck, slide_index: usize) ?usize {
        if (slide_index >= self.slides.items.len) return null;
        if (self.slides.items[slide_index].parked) return null;
        var pos: usize = 0;
        // Walk focus .. tail (newest first), skipping parked.
        var i: usize = self.focused_index;
        while (i < self.slides.items.len) : (i += 1) {
            if (self.slides.items[i].parked) continue;
            if (i == slide_index) return pos;
            pos += 1;
        }
        // Then focus-1 down to 0 (older side, newest-of-the-old first).
        var j: isize = @as(isize, @intCast(self.focused_index)) - 1;
        while (j >= 0) : (j -= 1) {
            const idx: usize = @intCast(j);
            if (self.slides.items[idx].parked) continue;
            if (idx == slide_index) return pos;
            pos += 1;
        }
        return null;
    }

    /// Inverse of recencyPos: slide index at recency position pos, or null.
    pub fn slideIndexAtRecency(self: *const SlideDeck, pos: usize) ?usize {
        var p: usize = 0;
        var i: usize = self.focused_index;
        while (i < self.slides.items.len) : (i += 1) {
            if (self.slides.items[i].parked) continue;
            if (p == pos) return i;
            p += 1;
        }
        var j: isize = @as(isize, @intCast(self.focused_index)) - 1;
        while (j >= 0) : (j -= 1) {
            const idx: usize = @intCast(j);
            if (self.slides.items[idx].parked) continue;
            if (p == pos) return idx;
            p += 1;
        }
        return null;
    }

    /// Grid geometry for the overview slide's card: minis live INSIDE the
    /// focused slide area (the split.focus strip — peeks stay clear, per
    /// Barticus 2026-08-19). Grid cols from style.layout.overview_cols,
    /// even gaps all round (style.layout.overview_gap), parked slides in a
    /// bottom row. Mini size computed to fit the strip, not from aspect ratio.
    pub const overview_cols = style.layout.overview_cols;
    pub const overview_gap = style.layout.overview_gap;

    /// Return the mini grid rect for slide `slide_index` in overview mode.
    /// Unparked slides fill the top rows left-to-right (recency order);
    /// parked slides sit in a separate row at the bottom of the grid area.
    /// The slide under the virtual cursor is inflated slightly (1.06x) so
    /// keyboard focus is visible without any border chrome.
    pub fn overviewTargetForSlide(self: *SlideDeck, slide_index: usize) Rect {
        return self.overviewTargetForSlideInflated(slide_index, null);
    }

    pub fn overviewTargetForSlideInflated(self: *SlideDeck, slide_index: usize, cursor_index: ?usize) Rect {
        if (slide_index >= self.slides.items.len or self.width == 0) {
            return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        }
        // Grid area = the focused slide strip of the normal layout (inset by
        // the deck gap, matching where the focused slide actually sits).
        const area = switch (self.orientation) {
            .horizontal => self.horizontalTarget(0).inset(self.gap),
            .vertical => self.verticalTarget(0).inset(self.gap),
        };
        const cols = overview_cols;
        const gap: i32 = @intCast(overview_gap);

        // Fixed mini size: computed from the strip dimensions, NEVER changes
        // regardless of slide count. 2 cols always; rows scroll if they
        // exceed the visible strip. The mini is sized so that 3 rows (the
        // max we show: 2 unparked + 1 parked) fit exactly with even gaps.
        const max_visible_rows = 3; // 2 unparked + 1 parked peek

        const mini_w: u32 = @intCast(@max(1, @divTrunc(@as(i32, @intCast(area.width)) - (@as(i32, @intCast(cols)) + 1) * gap, @as(i32, @intCast(cols)))));
        const mini_h: u32 = @intCast(@max(1, @divTrunc(@as(i32, @intCast(area.height)) - (@as(i32, @intCast(max_visible_rows)) + 1) * gap, @as(i32, @intCast(max_visible_rows)))));

        // Grid origin: centered horizontally, top-aligned vertically (rows
        // flow down from the top; if there are fewer than max_visible_rows,
        // the grid is smaller and centered vertically in the strip).
        const unparked = self.unparkedCount();
        const unparked_rows = (unparked + cols - 1) / cols;
        var parked_count: usize = 0;
        for (self.slides.items) |s| {
            if (s.parked) parked_count += 1;
        }
        const parked_rows = if (parked_count > 0) (parked_count + cols - 1) / cols else 0;
        const total_rows = unparked_rows + parked_rows;
        if (total_rows == 0) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };

        const grid_w = @as(i32, @intCast(cols)) * @as(i32, @intCast(mini_w)) + (@as(i32, @intCast(cols)) + 1) * gap;
        const grid_h = @as(i32, @intCast(total_rows)) * @as(i32, @intCast(mini_h)) + (@as(i32, @intCast(total_rows)) + 1) * gap;
        const grid_x = area.x + @divTrunc(@as(i32, @intCast(area.width)) - grid_w, 2);
        const grid_y = area.y + @divTrunc(@as(i32, @intCast(area.height)) - grid_h, 2);

        // Build the unparked order (most-recently-focused FIRST — the grid
        // fills from the top-left like a page, newest claims the first cell,
        // per Barticus 2026-08-19) and the parked order separately; parked
        // minis live on the last row(s).
        const inflate = cursor_index != null and cursor_index.? == slide_index;
        const scale_up: f32 = if (inflate) 1.06 else 1.0;
        const this_w: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(mini_w)) * scale_up));
        const this_h: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(mini_h)) * scale_up));
        const grow_x: i32 = @intCast((this_w - mini_w) / 2);
        const grow_y: i32 = @intCast((this_h - mini_h) / 2);
        const slide = self.slides.items[slide_index];
        if (!slide.parked) {
            // Recency order — identical walk to recencyPos(): focus .. tail
            // first (newest), then focus-1 .. 0 (older side).
            const pos: usize = self.recencyPos(slide_index) orelse 0;
            const col: i32 = @intCast(pos % cols);
            const row: i32 = @intCast(pos / cols);
            return .{
                .x = grid_x + gap + col * (@as(i32, @intCast(mini_w)) + gap) - grow_x,
                .y = grid_y + gap + row * (@as(i32, @intCast(mini_h)) + gap) - grow_y,
                .width = this_w,
                .height = this_h,
            };
        } else {
            // Position among parked slides, in deck order.
            var pos: usize = 0;
            for (self.slides.items[0..slide_index]) |s| {
                if (s.parked) pos += 1;
            }
            const col: i32 = @intCast(pos % cols);
            const row: i32 = @intCast(unparked_rows + pos / cols);
            return .{
                .x = grid_x + gap + col * (@as(i32, @intCast(mini_w)) + gap) - grow_x,
                .y = grid_y + gap + row * (@as(i32, @intCast(mini_h)) + gap) - grow_y,
                .width = this_w,
                .height = this_h,
            };
        }
    }

    /// Hit-test: which mini (deck index) contains output-local point (x, y)?
    /// Uses the same grid math as overviewTargetForSlide, so hit == visual.
    /// Only meaningful while the overview slide is open.
    pub fn miniAtPoint(self: *SlideDeck, x: i32, y: i32) ?usize {
        if (!self.overview_slide_open) return null;
        for (self.slides.items, 0..) |_, i| {
            const r = self.overviewTargetForSlide(i);
            if (r.width == 0) continue;
            if (x >= r.x and x < r.x + @as(i32, @intCast(r.width)) and
                y >= r.y and y < r.y + @as(i32, @intCast(r.height)))
            {
                return i;
            }
        }
        return null;
    }

    /// Return the rectangle for the slide at `slide_index` relative to the
    /// currently focused slide.  Deeper slides are pushed one full screen-width
    /// (or height) off the edge so they can slide in cleanly.
    /// Parked slides are fully hidden: zero-width rect parked off-screen, and
    /// they never displace the positions of unparked slides.
    pub fn targetForSlide(self: *SlideDeck, slide_index: usize) Rect {
        if (slide_index >= self.slides.items.len) {
            return .{ .x = 0, .y = 0, .width = self.width, .height = self.height };
        }
        if (self.slides.items[slide_index].parked) {
            return .{ .x = -@as(i32, @intCast(self.width)), .y = 0, .width = 0, .height = self.height };
        }
        const delta: isize = @as(isize, @intCast(slide_index)) - self.virtualFocus();
        // FULLSCREEN LAW (2026-09-16): a fullscreen flagged slide fills the
        // whole output — no gap inset, no peeks. Only meaningful at delta 0
        // (focused); unfocus a fullscreen slide keeps the flag for return.
        if (delta == 0 and self.slides.items[slide_index].fullscreen) {
            return .{ .x = 0, .y = 0, .width = self.width, .height = self.height };
        }
        const result = switch (self.orientation) {
            .horizontal => self.horizontalTarget(delta),
            .vertical => self.verticalTarget(delta),
        };
        return result.inset(self.gap);
    }

    fn horizontalTarget(self: *SlideDeck, delta: isize) Rect {
        const w: f32 = @floatFromInt(self.width);
        const focus_w: i32 = @intFromFloat(w * self.split.focus);
        const left_w: i32 = @intFromFloat(w * self.split.left_peek);
        const h = self.height;

        const x: i32 = switch (delta) {
            -1 => -@as(i32, @intCast(self.width)) + left_w,
            0 => left_w,
            1 => left_w + focus_w,
            // Deeper slides sit just off the nearest edge so focus changes only
            // animate the focused slide and its immediate neighbours.
            else => if (delta < 0) -@as(i32, @intCast(self.width)) else left_w + focus_w,
        };
        const width: u32 = switch (delta) {
            0 => @intCast(focus_w),
            else => self.width,
        };
        return .{ .x = x, .y = 0, .width = width, .height = h };
    }

    fn verticalTarget(self: *SlideDeck, delta: isize) Rect {
        const h: f32 = @floatFromInt(self.height);
        const focus_h: i32 = @intFromFloat(h * self.split.focus);
        const top_h: i32 = @intFromFloat(h * self.split.left_peek);
        const w = self.width;

        const y: i32 = switch (delta) {
            -1 => -@as(i32, @intCast(self.height)) + top_h,
            0 => top_h,
            1 => top_h + focus_h,
            else => if (delta < 0) -@as(i32, @intCast(self.height)) else top_h + focus_h,
        };
        const height: u32 = switch (delta) {
            0 => @intCast(focus_h),
            else => self.height,
        };
        return .{ .x = 0, .y = y, .width = w, .height = height };
    }
};

test "horizontal slide targets fill the output" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(1000, 600, 8, .{ .left_peek = 0.06, .focus = 0.88, .right_peek = 0.06 }, .horizontal);
    deck.addWindow(1);
    deck.addWindow(2);
    deck.addWindow(3);

    // With three slides and focus on the newest (index 2), the focused slide
    // should use the central 88% of the width minus the gap insets.
    const focused = deck.targetForSlide(2);
    try std.testing.expectEqual(@as(u32, 864), focused.width); // 1000*0.88 - 2*8
    try std.testing.expectEqual(@as(i32, 68), focused.x); // 1000*0.06 + 8

    // Index 1 is the left peek (delta=-1 from focus at 2).
    const left = deck.targetForSlide(1);
    try std.testing.expectEqual(@as(i32, -932), left.x); // -1000 + 60 + 8
    try std.testing.expectEqual(@as(u32, 984), left.width); // 1000 - 2*8
}

test "insert at focused slide" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(800, 600, 0, .{ .left_peek = 0.06, .focus = 0.88, .right_peek = 0.06 }, .horizontal);
    deck.addWindow(10); // first slide at 0, focused
    deck.addWindow(20); // insert to right of focus (index 1), focused
    deck.addWindow(30); // insert to right of focus (index 2), focused

    // Expect order: 10, 20, 30 with focus on 30 (index 2)
    try std.testing.expectEqual(deck.slides.items[0].window_id, 10);
    try std.testing.expectEqual(deck.slides.items[1].window_id, 20);
    try std.testing.expectEqual(deck.slides.items[2].window_id, 30);
    try std.testing.expectEqual(@as(usize, 2), deck.focused_index);
}

test "park focused moves focus to next unparked" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(1000, 600, 0, .{ .left_peek = 0.06, .focus = 0.88, .right_peek = 0.06 }, .horizontal);
    deck.addWindow(1);
    deck.addWindow(2);
    deck.addWindow(3);
    // Deck order after sequential right-of-focus inserts: 1, 2, 3 — focused index 2 (window 3).
    try std.testing.expectEqual(@as(usize, 2), deck.focused_index);

    // Park the focused slide (window 3 at index 2).
    try std.testing.expect(deck.parkFocused());
    try std.testing.expect(deck.slides.items[2].parked);
    // Focus moves to the previous unparked slide (index 1, window 2).
    try std.testing.expectEqual(@as(usize, 1), deck.focused_index);
    try std.testing.expectEqual(@as(usize, 2), deck.unparkedCount());

    // focusPrev from index 1 lands on index 0.
    deck.focusPrev();
    try std.testing.expectEqual(@as(usize, 0), deck.focused_index);
    try std.testing.expectEqual(EmptySlot.none, deck.empty_slot);

    // focusNext from index 0 must skip parked index 2 and land on index 1.
    deck.focusNext();
    try std.testing.expectEqual(@as(usize, 1), deck.focused_index);
    try std.testing.expectEqual(EmptySlot.none, deck.empty_slot);

    // focusNext past the last unparked slide lands in the after_last slot.
    deck.focusNext();
    try std.testing.expectEqual(EmptySlot.after_last, deck.empty_slot);

    // Unpark restores the slide at its old index.
    try std.testing.expect(deck.unparkIndex(2));
    try std.testing.expect(!deck.slides.items[2].parked);
    try std.testing.expectEqual(@as(usize, 3), deck.unparkedCount());
}

test "park refuses on single-slide deck" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(800, 600, 0, .{ .left_peek = 0.06, .focus = 0.88, .right_peek = 0.06 }, .horizontal);
    deck.addWindow(42);
    try std.testing.expect(!deck.parkFocused());
    try std.testing.expect(!deck.slides.items[0].parked);
    try std.testing.expectEqual(@as(usize, 0), deck.focused_index);
}

test "parked slide target is zero-width and hidden" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(1000, 600, 0, .{ .left_peek = 0.06, .focus = 0.88, .right_peek = 0.06 }, .horizontal);
    deck.addWindow(1);
    deck.addWindow(2);
    deck.addWindow(3);
    // Park the focused slide (index 2, window 3).
    _ = deck.parkFocused();

    const parked = deck.targetForSlide(2);
    try std.testing.expectEqual(@as(u32, 0), parked.width);
    try std.testing.expect(parked.x < 0);

    // Unparked slides keep normal targets: index 1 is now focused.
    const focused = deck.targetForSlide(1);
    try std.testing.expect(focused.width > 0);
    try std.testing.expectEqual(@as(i32, 60), focused.x); // left_w = 1000*0.06, gap 0
}

test "focusWindowByIndex refuses parked slide" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(800, 600, 0, .{ .left_peek = 0.06, .focus = 0.88, .right_peek = 0.06 }, .horizontal);
    deck.addWindow(1);
    deck.addWindow(2);
    deck.addWindow(3);
    _ = deck.parkFocused(); // parks index 2 (window 3)
    deck.focusWindowByIndex(0);
    try std.testing.expectEqual(@as(usize, 0), deck.focused_index);
    deck.focusWindowByIndex(2); // parked — must not take focus
    try std.testing.expectEqual(@as(usize, 0), deck.focused_index);
}

test "overview grid: unparked top row, parked bottom row, focus preserved" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(1000, 500, 8, .{ .left_peek = 0.06, .focus = 0.88, .right_peek = 0.06 }, .horizontal);
    deck.addWindow(1);
    deck.addWindow(2);
    deck.addWindow(3);
    deck.addWindow(4);
    // Deck order: 1, 2, 3, 4 — focused index 3 (window 4).
    const saved_focus = deck.focused_index;
    // Park the slide at index 1 (window 2).
    deck.slides.items[1].parked = true;

    // Overview slide opened; focus moved onto the after_last slot. Grid math is
    // lens-independent (pure functions), so targets compute the same.
    deck.openOverviewSlide();
    try std.testing.expect(deck.overviewSlideOpen());

    // 1000x500, gap 8, split .06/.88/.06: focus strip x=68, y=8, w=864, h=484.
    // 2 cols, gap=28 -> mini_w=(864-3*28)/2=390, mini_h=(484-4*28)/3=124.
    // Grid 864x484 centered in strip (no offset). Tiles at x=96/486, y=36/188/340.
    // Deck [1,2,3,4], focused idx3 (win4). Recency (focus..tail, then down):
    // idx3 (pos0, top-left), idx2 (pos1), idx0 (pos2, older side).
    // idx1 is PARKED so skipped in recency.
    const m3 = deck.overviewTargetForSlide(3);
    try std.testing.expectEqual(@as(i32, 96), m3.x);
    try std.testing.expectEqual(@as(i32, 36), m3.y);
    try std.testing.expectEqual(@as(u32, 390), m3.width);
    try std.testing.expectEqual(@as(u32, 124), m3.height);

    // pos1 = idx2 (win3).
    const m2 = deck.overviewTargetForSlide(2);
    try std.testing.expectEqual(@as(i32, 96 + 390 + 28), m2.x);
    try std.testing.expectEqual(@as(i32, 36), m2.y);

    // pos2 = idx0 (win1, older side) wraps to row 1: y = 36 + 124 + 28 = 188.
    const m0 = deck.overviewTargetForSlide(0);
    try std.testing.expectEqual(@as(i32, 96), m0.x);
    try std.testing.expectEqual(@as(i32, 188), m0.y);

    // Parked slide (idx1): unparked=3 -> 2 rows, parked row = 2,
    // y = 8 + 28 + 2*(124+28) = 340.
    const m1 = deck.overviewTargetForSlide(1);
    try std.testing.expectEqual(@as(i32, 96), m1.x);
    try std.testing.expectEqual(@as(i32, 340), m1.y);

    // Close restores the slide that opened it.
    deck.closeOverviewSlide();
    try std.testing.expect(!deck.overviewSlideOpen());
    try std.testing.expectEqual(saved_focus, deck.focused_index);
}

test "compositor slide: real deck entry at index 0, focus walks stock paths" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(800, 600, 0, .{ .left_peek = 0.06, .focus = 0.88, .right_peek = 0.06 }, .horizontal);
    _ = deck.addCompositorSlide(.home, 0, true);
    try std.testing.expectEqual(@as(usize, 1), deck.slides.items.len);
    try std.testing.expectEqual(SlideKind.home, deck.slides.items[0].kind);
    try std.testing.expect(deck.slides.items[0].ephemeral);
    try std.testing.expectEqual(@as(usize, 0), deck.focused_index);
    try std.testing.expectEqual(EmptySlot.none, deck.empty_slot);
    try std.testing.expect(deck.slides.items[0].window_id >= SlideDeck.compositor_id_base);

    // A client window spawns right of home — home slips into the peek.
    deck.addWindow(1);
    try std.testing.expectEqual(@as(usize, 2), deck.slides.items.len);
    try std.testing.expectEqual(@as(usize, 1), deck.focused_index);
    try std.testing.expectEqual(SlideKind.app, deck.slides.items[1].kind);

    // Stock walk back onto home.
    deck.focusPrev();
    try std.testing.expectEqual(@as(usize, 0), deck.focused_index);

    // Ephemeral destroy: focus settles through the stock path, no
    // return-index bookkeeping.
    try std.testing.expect(deck.removeCompositorSlide(.home));
    try std.testing.expectEqual(@as(usize, 1), deck.slides.items.len);
    try std.testing.expectEqual(@as(usize, 0), deck.focused_index);
    try std.testing.expect(!deck.removeCompositorSlide(.home));
}

test "overview slide toggle round-trips" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(800, 600, 0, .{ .left_peek = 0.06, .focus = 0.88, .right_peek = 0.06 }, .horizontal);
    deck.addWindow(1);
    deck.toggleOverviewSlide();
    try std.testing.expect(deck.overview_slide_open);
    try std.testing.expectEqual(EmptySlot.after_last, deck.empty_slot);
    deck.toggleOverviewSlide();
    try std.testing.expect(!deck.overview_slide_open);
    try std.testing.expectEqual(EmptySlot.none, deck.empty_slot);
    // Empty deck: open is a no-op (guard).
    var empty = SlideDeck.init(allocator);
    defer empty.deinit();
    empty.openOverviewSlide();
    try std.testing.expect(!empty.overview_slide_open);
}

test "miniAtPoint hit-tests the grid" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(1000, 500, 8, .{ .left_peek = 0.06, .focus = 0.88, .right_peek = 0.06 }, .horizontal);
    deck.addWindow(1);
    deck.addWindow(2);
    deck.addWindow(3);

    // Not in overview: no hits.
    try std.testing.expectEqual(@as(?usize, null), deck.miniAtPoint(200, 50));

    deck.openOverviewSlide();
    // Grid: strip x=68,y=8,w=864,h=484; 2 cols; mini 390x124 (fixed for 3 rows).
    // Grid 864x332 centered in strip: x=68, y=84. Tiles at y=112/264.
    // Slide order: 1, 2, 3, focused idx2. Recency: idx2=(96,112), idx1=(514,112), idx0=(96,264).
    try std.testing.expectEqual(@as(?usize, 2), deck.miniAtPoint(200, 150));
    try std.testing.expectEqual(@as(?usize, 1), deck.miniAtPoint(550, 150));
    try std.testing.expectEqual(@as(?usize, 0), deck.miniAtPoint(200, 300));
    // Gap between minis: no hit.
    try std.testing.expectEqual(@as(?usize, null), deck.miniAtPoint(490, 150));
    // Outside strip: no hit.
    try std.testing.expectEqual(@as(?usize, null), deck.miniAtPoint(50, 150));
    // Below the grid: no hit.
    try std.testing.expectEqual(@as(?usize, null), deck.miniAtPoint(200, 499));
}

fn expectApproxEq(a: f32, b: f32) !void {
    return std.testing.expectApproxEqAbs(a, b, 1.0);
}
