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
};

/// SlideDeck: a per-output stack of full-screen Slides.
/// Only the focused Slide and its immediate neighbours are visible;
/// deeper slides sit off-screen and animate into view when focused.
pub const SlideDeck = struct {
    allocator: std.mem.Allocator,
    slides: std.ArrayList(Slide),
    width: u32,
    height: u32,
    gap: u32,
    focused_index: usize,
    split: Split,
    orientation: Orientation,

    pub fn init(allocator: std.mem.Allocator) SlideDeck {
        return .{
            .allocator = allocator,
            .slides = std.ArrayList(Slide).empty,
            .width = 0,
            .height = 0,
            .gap = style.layout.gap,
            .focused_index = 0,
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
            return;
        }
        if (self.focused_index >= self.slides.items.len) {
            self.focused_index = self.slides.items.len - 1;
        }
    }

    /// Add a new Slide. New windows open near the centre of the deck so the
    /// matrix grows outward from the middle.
    pub fn addWindow(self: *SlideDeck, window_id: u32) void {
        const insert_at = self.slides.items.len / 2;
        self.slides.insert(self.allocator, insert_at, .{ .window_id = window_id }) catch {
            std.log.err("SlideDeck: failed to insert new slide", .{});
            return;
        };
        // The new slide becomes the focused one; it is placed centre-out.
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

    pub fn focusNext(self: *SlideDeck) void {
        if (self.slides.items.len == 0) return;
        self.focused_index = (self.focused_index + 1) % self.slides.items.len;
    }

    pub fn focusPrev(self: *SlideDeck) void {
        if (self.slides.items.len == 0) return;
        if (self.focused_index == 0) {
            self.focused_index = self.slides.items.len - 1;
        } else {
            self.focused_index -= 1;
        }
    }

    pub fn focusWindowByIndex(self: *SlideDeck, index: usize) void {
        if (index < self.slides.items.len) {
            self.focused_index = index;
        }
    }

    /// Return the rectangle for the slide at `slide_index` relative to the
    /// currently focused slide.  Deeper slides are pushed one full screen-width
    /// (or height) off the edge so they can slide in cleanly.
    pub fn targetForSlide(self: *SlideDeck, slide_index: usize) Rect {
        if (slide_index >= self.slides.items.len) {
            return .{ .x = 0, .y = 0, .width = self.width, .height = self.height };
        }
        const delta: isize = @as(isize, @intCast(slide_index)) - @as(isize, @intCast(self.focused_index));
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
        // Right peek is a full-width window pushed off the right edge, just like
        // the left peek is a full-width window pushed off the left edge. The
        // visible sliver is determined by where the output edge cuts it.
        const h = self.height;

        const x: i32 = switch (delta) {
            // Left neighbour: position so only its rightmost `left_w` pixels
            // are visible at the left edge of the screen, with its right edge
            // butting up against the focused window.
            -1 => -@as(i32, @intCast(self.width)) + left_w,
            0 => left_w,
            1 => left_w + focus_w,
            else => @as(i32, @intCast(delta)) * @as(i32, @intCast(self.width)),
        };
        const width: u32 = switch (delta) {
            -1 => self.width,
            0 => @intCast(focus_w),
            1 => self.width,
            else => self.width,
        };
        return .{ .x = x, .y = 0, .width = width, .height = h };
    }

    fn verticalTarget(self: *SlideDeck, delta: isize) Rect {
        const h: f32 = @floatFromInt(self.height);
        const focus_h: i32 = @intFromFloat(h * self.split.focus);
        const top_h: i32 = @intFromFloat(h * self.split.left_peek);
        const bottom_h: i32 = @intFromFloat(h * self.split.right_peek);
        const w = self.width;

        const y: i32 = switch (delta) {
            -1 => 0,
            0 => top_h,
            1 => top_h + focus_h,
            else => @as(i32, @intCast(delta)) * @as(i32, @intCast(self.height)),
        };
        const height: u32 = switch (delta) {
            -1 => @intCast(top_h),
            0 => @intCast(focus_h),
            1 => @intCast(bottom_h),
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

test "centre-out insertion" {
    const allocator = std.testing.allocator;
    var deck = SlideDeck.init(allocator);
    defer deck.deinit();

    deck.sync(800, 600, 0, .{ .left_peek = 0.15, .focus = 0.7, .right_peek = 0.15 }, .horizontal);
    deck.addWindow(10); // inserted at 0
    deck.addWindow(20); // len=1, centre=0, insert at 0; focus index bumps to 1
    deck.addWindow(30); // len=2, centre=1, insert at 1

    // Expect order: 20, 30, 10 with focus on 30
    try std.testing.expectEqual(deck.slides.items[0].window_id, 20);
    try std.testing.expectEqual(deck.slides.items[1].window_id, 30);
    try std.testing.expectEqual(deck.slides.items[2].window_id, 10);
    try std.testing.expectEqual(@as(usize, 1), deck.focused_index);
}

fn expectApproxEq(a: f32, b: f32) !void {
    return std.testing.expectApproxEqAbs(a, b, 1.0);
}
