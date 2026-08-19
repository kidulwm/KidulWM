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

pub const Slide = struct {
    window_id: u32,
    /// Parked slides stay in the deck (the client is alive) but are hidden
    /// from normal layout and navigation. Overview mode (Task 2) shows them.
    parked: bool = false,
};

pub const EmptySlot = enum { none, before_first, after_last };

/// View mode: normal row layout vs. the overview lens. Overview is a lens,
/// not a focus change — focused_index is preserved across the toggle.
pub const ViewMode = enum { normal, overview };

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
    view_mode: ViewMode,

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
            .view_mode = .normal,
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

    /// Enter the overview lens. Focus is preserved; layout switches to grid.
    pub fn enterOverview(self: *SlideDeck) void {
        if (self.slides.items.len == 0) return;
        if (self.view_mode == .overview) return;
        self.view_mode = .overview;
        std.log.info("SlideDeck: overview entered (focused_index={d}, slides={d})", .{ self.focused_index, self.slides.items.len });
    }

    /// Recency position of a slide among unparked slides (0 = top-left =
    /// the focused slide). The deck's center-out insert leaves it ordered
    /// [oldest .. newest] left-to-right with focus on the newest, so recency
    /// walks focus -> tail (newest first), then focus-1 down to 0 (the older
    /// tail), keeping the grid newest-first left-to-right, top row first.
    pub fn recencyPos(self: *const SlideDeck, slide_index: usize) ?usize {
        if (slide_index >= self.slides.items.len) return null;
        if (self.slides.items[slide_index].parked) return null;
        var pos: usize = 0;
        // Walk focus .. tail (newest first).
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

    /// Exit the overview lens back to normal row layout. Focus unchanged.
    pub fn exitOverview(self: *SlideDeck) void {
        if (self.view_mode == .normal) return;
        self.view_mode = .normal;
        std.log.info("SlideDeck: overview exited (focused_index={d})", .{self.focused_index});
    }

    pub fn toggleOverview(self: *SlideDeck) void {
        switch (self.view_mode) {
            .normal => self.enterOverview(),
            .overview => self.exitOverview(),
        }
    }

    /// Grid geometry for the overview lens: minis live INSIDE the focused
    /// slide area (the split.focus band — peeks stay clear, per Barticus
    /// 2026-08-19). 2 columns (lounge view trial), 16px padding, parked
    /// slides in a bottom row. Rows continue past the screen bottom for
    /// now; scrolling/clamping arrives with Task 3 interaction.
    pub const overview_cols = 2;
    pub const overview_pad = 16;

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
        // Grid area = the focused slide band of the normal layout (inset by
        // the deck gap, matching where the focused slide actually sits).
        const area = switch (self.orientation) {
            .horizontal => self.horizontalTarget(0).inset(self.gap),
            .vertical => self.verticalTarget(0).inset(self.gap),
        };
        const pad: i32 = @intCast(overview_pad);
        const cell_w: u32 = area.width / overview_cols;
        const cell_w_i: i32 = @intCast(cell_w);
        // Preserve the output aspect ratio for the mini height.
        const mini_w: u32 = cell_w -| 2 * overview_pad;
        const mini_h: u32 = @intFromFloat(@as(f32, @floatFromInt(mini_w)) * @as(f32, @floatFromInt(self.height)) / @as(f32, @floatFromInt(self.width)));
        // Row pitch: mini + pad top AND bottom, so vertical gap matches the
        // horizontal gap between minis.
        const row_pitch: i32 = @intCast(mini_h + 2 * overview_pad);

        // Build the unparked order (most-recently-focused FIRST — the grid
        // fills from the top-left like a page, newest claims the first cell,
        // per Barticus 2026-08-19) and the parked order separately; parked
        // minis live on the last row.
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
            const col: i32 = @intCast(pos % overview_cols);
            const row: i32 = @intCast(pos / overview_cols);
            return .{
                .x = area.x + col * cell_w_i + pad - grow_x,
                .y = area.y + row * row_pitch + pad - grow_y,
                .width = this_w,
                .height = this_h,
            };
        } else {
            // Position among parked slides, in deck order.
            var pos: usize = 0;
            for (self.slides.items[0..slide_index]) |s| {
                if (s.parked) pos += 1;
            }
            const unparked_rows: i32 = blk: {
                const n = self.unparkedCount();
                break :blk @intCast((n + overview_cols - 1) / overview_cols);
            };
            const col: i32 = @intCast(pos % overview_cols);
            const row: i32 = unparked_rows + @divTrunc(@as(i32, @intCast(pos)), overview_cols);
            return .{
                .x = area.x + col * cell_w_i + pad - grow_x,
                .y = area.y + row * row_pitch + pad - grow_y,
                .width = this_w,
                .height = this_h,
            };
        }
    }

    /// Hit-test: which mini (deck index) contains output-local point (x, y)?
    /// Uses the same grid math as overviewTargetForSlide, so hit == visual.
    pub fn miniAtPoint(self: *SlideDeck, x: i32, y: i32) ?usize {
        if (self.view_mode != .overview) return null;
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

    deck.sync(1000, 600, 8, .{ .left_peek = 0.15, .focus = 0.7, .right_peek = 0.15 }, .horizontal);
    deck.addWindow(1);
    deck.addWindow(2);
    deck.addWindow(3);

    // With three slides and focus in the middle, the focused slide should use
    // the central 70% of the width minus the gap insets.
    const focused = deck.targetForSlide(1);
    try std.testing.expectEqual(@as(u32, 684), focused.width);
    try std.testing.expectEqual(@as(i32, 158), focused.x);

    const left = deck.targetForSlide(0);
    try std.testing.expectEqual(@as(i32, 8), left.x);
    try std.testing.expectEqual(@as(u32, 134), left.width);
}

test "insert at focused slide" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(800, 600, 0, .{ .left_peek = 0.15, .focus = 0.7, .right_peek = 0.15 }, .horizontal);
    deck.addWindow(10); // first slide at 0, focused
    deck.addWindow(20); // insert to right of focus, focused
    deck.addWindow(30); // insert to right of focus (index 1), focused

    // Expect order: 10, 30, 20 with focus on 30
    try std.testing.expectEqual(deck.slides.items[0].window_id, 10);
    try std.testing.expectEqual(deck.slides.items[1].window_id, 30);
    try std.testing.expectEqual(deck.slides.items[2].window_id, 20);
    try std.testing.expectEqual(@as(usize, 1), deck.focused_index);
}

test "park focused moves focus to next unparked" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(1000, 600, 0, .{ .left_peek = 0.15, .focus = 0.7, .right_peek = 0.15 }, .horizontal);
    deck.addWindow(1);
    deck.addWindow(2);
    deck.addWindow(3);
    // Deck order after center-out inserts: 1, 3, 2 — focused index 1 (window 3).
    try std.testing.expectEqual(@as(usize, 1), deck.focused_index);

    // Park the focused slide (window 3 at index 1).
    try std.testing.expect(deck.parkFocused());
    try std.testing.expect(deck.slides.items[1].parked);
    // Focus moves to the next unparked slide (index 2, window 2).
    try std.testing.expectEqual(@as(usize, 2), deck.focused_index);
    try std.testing.expectEqual(@as(usize, 2), deck.unparkedCount());

    // focusPrev from index 2 must skip parked index 1 and land on index 0.
    deck.focusPrev();
    try std.testing.expectEqual(@as(usize, 0), deck.focused_index);
    try std.testing.expectEqual(EmptySlot.none, deck.empty_slot);

    // focusNext from index 0 must skip parked index 1 and land on index 2.
    deck.focusNext();
    try std.testing.expectEqual(@as(usize, 2), deck.focused_index);
    try std.testing.expectEqual(EmptySlot.none, deck.empty_slot);

    // focusNext past the last unparked slide lands in the after_last slot.
    deck.focusNext();
    try std.testing.expectEqual(EmptySlot.after_last, deck.empty_slot);

    // Unpark restores the slide at its old index.
    try std.testing.expect(deck.unparkIndex(1));
    try std.testing.expect(!deck.slides.items[1].parked);
    try std.testing.expectEqual(@as(usize, 3), deck.unparkedCount());
}

test "park refuses on single-slide deck" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(800, 600, 0, .{ .left_peek = 0.15, .focus = 0.7, .right_peek = 0.15 }, .horizontal);
    deck.addWindow(42);
    try std.testing.expect(!deck.parkFocused());
    try std.testing.expect(!deck.slides.items[0].parked);
    try std.testing.expectEqual(@as(usize, 0), deck.focused_index);
}

test "parked slide target is zero-width and hidden" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(1000, 600, 0, .{ .left_peek = 0.15, .focus = 0.7, .right_peek = 0.15 }, .horizontal);
    deck.addWindow(1);
    deck.addWindow(2);
    deck.addWindow(3);
    // Park the middle slide (index 1, currently focused).
    _ = deck.parkFocused();

    const parked = deck.targetForSlide(1);
    try std.testing.expectEqual(@as(u32, 0), parked.width);
    try std.testing.expect(parked.x < 0);

    // Unparked slides keep normal targets: index 2 is now focused.
    const focused = deck.targetForSlide(2);
    try std.testing.expect(focused.width > 0);
    try std.testing.expectEqual(@as(i32, 150), focused.x); // left_w = 1000*0.15, gap 0
}

test "focusWindowByIndex refuses parked slide" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(800, 600, 0, .{ .left_peek = 0.15, .focus = 0.7, .right_peek = 0.15 }, .horizontal);
    deck.addWindow(1);
    deck.addWindow(2);
    deck.addWindow(3);
    _ = deck.parkFocused(); // parks index 1
    deck.focusWindowByIndex(0);
    try std.testing.expectEqual(@as(usize, 0), deck.focused_index);
    deck.focusWindowByIndex(1); // parked — must not take focus
    try std.testing.expectEqual(@as(usize, 0), deck.focused_index);
}

test "overview grid: unparked top row, parked bottom row, focus preserved" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(1000, 500, 8, .{ .left_peek = 0.15, .focus = 0.7, .right_peek = 0.15 }, .horizontal);
    deck.addWindow(1);
    deck.addWindow(2);
    deck.addWindow(3);
    deck.addWindow(4);
    // Deck order: 1, 4, 3, 2 — focused index 1 (window 4).
    const saved_focus = deck.focused_index;
    // Park the slide at index 2 (window 3).
    deck.slides.items[2].parked = true;

    deck.enterOverview();
    try std.testing.expectEqual(ViewMode.overview, deck.view_mode);
    // Lens never moves focus.
    try std.testing.expectEqual(saved_focus, deck.focused_index);

    // 1000x500, gap 8, split .15/.7/.15: focus band x=158, y=8, w=684, h=484.
    // 2 cols -> cell 342, mini_w=342-32=310, mini_h=310*500/1000=155.
    // Deck [1,4,3,2], focused idx1 (win4). Recency (focus..tail, then down):
    // idx1 (pos0, top-left), idx3? no — idx2 is PARKED so skipped: idx1, idx3, idx0.
    const m1 = deck.overviewTargetForSlide(1);
    try std.testing.expectEqual(@as(i32, 158 + 16), m1.x);
    try std.testing.expectEqual(@as(i32, 8 + 16), m1.y);
    try std.testing.expectEqual(@as(u32, 310), m1.width);
    try std.testing.expectEqual(@as(u32, 155), m1.height);

    // pos1 = idx3 (win2, tail).
    const m3 = deck.overviewTargetForSlide(3);
    try std.testing.expectEqual(@as(i32, 158 + 342 + 16), m3.x);
    try std.testing.expectEqual(@as(i32, 24), m3.y);

    // pos2 = idx0 (win1, older side) wraps to row 1: pitch 187, y = 8+187+16 = 211.
    const m0 = deck.overviewTargetForSlide(0);
    try std.testing.expectEqual(@as(i32, 158 + 16), m0.x);
    try std.testing.expectEqual(@as(i32, 211), m0.y);

    // Parked slide (idx2): unparked=3 -> 2 rows at 2 cols, parked row = 2,
    // y = 8 + 2*187 + 16 = 398.
    const m2 = deck.overviewTargetForSlide(2);
    try std.testing.expectEqual(@as(i32, 158 + 16), m2.x);
    try std.testing.expectEqual(@as(i32, 398), m2.y);

    // Exit restores normal mode, focus still unchanged.
    deck.exitOverview();
    try std.testing.expectEqual(ViewMode.normal, deck.view_mode);
    try std.testing.expectEqual(saved_focus, deck.focused_index);
}

test "toggleOverview round-trips" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(800, 600, 0, .{ .left_peek = 0.15, .focus = 0.7, .right_peek = 0.15 }, .horizontal);
    deck.addWindow(1);
    deck.toggleOverview();
    try std.testing.expectEqual(ViewMode.overview, deck.view_mode);
    deck.toggleOverview();
    try std.testing.expectEqual(ViewMode.normal, deck.view_mode);
    // Empty deck: enter is a no-op (guard).
    var empty = SlideDeck.init(allocator);
    defer empty.deinit();
    empty.enterOverview();
    try std.testing.expectEqual(ViewMode.normal, empty.view_mode);
}

test "miniAtPoint hit-tests the grid" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(1000, 500, 8, .{ .left_peek = 0.15, .focus = 0.7, .right_peek = 0.15 }, .horizontal);
    deck.addWindow(1);
    deck.addWindow(2);
    deck.addWindow(3);

    // Not in overview: no hits.
    try std.testing.expectEqual(@as(?usize, null), deck.miniAtPoint(200, 50));

    deck.enterOverview();
    // Grid: band x=158,y=8,w=684,h=484; 2 cols; mini 310x155.
    // Slide order: 1, 3, 2, focused idx1. Recency: idx1=(174,24), idx2=(516,24), idx0=(174,211).
    try std.testing.expectEqual(@as(?usize, 1), deck.miniAtPoint(200, 50));
    try std.testing.expectEqual(@as(?usize, 2), deck.miniAtPoint(550, 50));
    try std.testing.expectEqual(@as(?usize, 0), deck.miniAtPoint(200, 250));
    // Gap between minis: no hit.
    try std.testing.expectEqual(@as(?usize, null), deck.miniAtPoint(490, 50));
    // Outside band: no hit.
    try std.testing.expectEqual(@as(?usize, null), deck.miniAtPoint(50, 50));
    // Below the grid: no hit.
    try std.testing.expectEqual(@as(?usize, null), deck.miniAtPoint(200, 499));
}

fn expectApproxEq(a: f32, b: f32) !void {
    return std.testing.expectApproxEqAbs(a, b, 1.0);
}
