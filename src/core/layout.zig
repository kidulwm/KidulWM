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

pub const Column = struct {
    id: u32,
    windows: std.ArrayList(Window),
    target: Rect,
    is_focused: bool = false,
};

pub const Window = struct {
    id: u32,
    surface_id: u32,
    bbox: Rect,
};

pub const Split = struct {
    left_peek: f32,
    focus: f32,
    right_peek: f32,

    pub fn default() Split {
        return .{
            .left_peek = style.layout.default_split.left_peek,
            .focus = style.layout.default_split.focus,
            .right_peek = style.layout.default_split.right_peek,
        };
    }

    pub fn verify(self: *Split) void {
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

pub const Orientation = enum { horizontal, vertical };

pub const Output = struct {
    id: u32,
    name: []const u8,
    width: u32,
    height: u32,
    columns: std.ArrayList(Column),
    focused_column: i32 = 1,
    gap: u32,
    split: Split,
    orientation: Orientation = .horizontal,
    style: style.Style,

    pub fn deinit(self: *Output, allocator: std.mem.Allocator) void {
        for (self.columns.items) |*col| {
            col.windows.deinit(allocator);
        }
        self.columns.deinit(allocator);
    }

    pub fn borderWidth(self: *const Output) f32 {
        return self.style.border_width;
    }

    pub fn borderColor(self: *const Output) [4]f32 {
        const focused = (self.focused_column >= 0 and self.focused_column < self.columns.items.len and
            self.columns.items[@intCast(self.focused_column)].is_focused);
        const c = if (focused) self.style.color_border_focused else self.style.color_border;
        return c.toF32();
    }
};

pub const LayoutModel = struct {
    allocator: std.mem.Allocator,
    outputs: std.ArrayList(Output),
    style: style.Style,

    pub fn create(allocator: std.mem.Allocator) LayoutModel {
        return .{
            .allocator = allocator,
            .outputs = std.ArrayList(Output).empty,
            .style = style.default(),
        };
    }

    /// Create a reusable, single-output layout model with the three canonical
    /// columns pre-allocated.  All geometry updates after this are in-place.
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, gap: u32) !LayoutModel {
        var self = create(allocator);
        errdefer self.deinit();

        try self.outputs.ensureTotalCapacity(allocator, 1);

        var output = Output{
            .id = 1,
            .name = "primary",
            .width = width,
            .height = height,
            .columns = std.ArrayList(Column).empty,
            .gap = gap,
            .split = Split.default(),
            .orientation = .horizontal,
            .style = style.default(),
        };
        output.split.verify();

        // Pre-size the three columns so layout ticks never hit the allocator.
        try output.columns.ensureTotalCapacity(allocator, 3);
        for (0..3) |i| {
            output.columns.appendAssumeCapacity(.{
                .id = @intCast(i),
                .windows = std.ArrayList(Window).empty,
                .target = undefined,
                .is_focused = (i == 1),
            });
        }

        self.style = style.default();
        output.style = self.style;
        recalcOutput(&output);
        self.outputs.appendAssumeCapacity(output);
        return self;
    }

    /// Legacy convenience kept for tests and one-shot consumers.
    pub fn createFromOutput(allocator: std.mem.Allocator, width: u32, height: u32, gap: u32) !LayoutModel {
        return init(allocator, width, height, gap);
    }

    pub fn deinit(self: *LayoutModel) void {
        for (self.outputs.items) |*output| {
            output.deinit(self.allocator);
        }
        self.outputs.deinit(self.allocator);
    }

    pub fn getOutput(self: *LayoutModel) ?*Output {
        if (self.outputs.items.len == 0) return null;
        return &self.outputs.items[0];
    }

    /// Fast, allocation-free state synchronisation.  Returns true when targets
    /// were recomputed (i.e. something changed).
    pub fn sync(
        output: *Output,
        width: u32,
        height: u32,
        gap: u32,
        left_peek: f32,
        focus: f32,
        right_peek: f32,
        focused_column: i32,
        orientation: Orientation,
    ) bool {
        const fc: i32 = if (focused_column < 0) 0 else if (focused_column > 2) 2 else focused_column;

        var split = Split{ .left_peek = left_peek, .focus = focus, .right_peek = right_peek };
        split.verify();

        const unchanged =
            output.width == width and
            output.height == height and
            output.gap == gap and
            output.focused_column == fc and
            output.orientation == orientation and
            std.math.approxEqAbs(f32, output.split.left_peek, split.left_peek, 1e-5) and
            std.math.approxEqAbs(f32, output.split.focus, split.focus, 1e-5) and
            std.math.approxEqAbs(f32, output.split.right_peek, split.right_peek, 1e-5);

        if (unchanged) return false;

        output.width = width;
        output.height = height;
        output.gap = gap;
        output.focused_column = fc;
        output.orientation = orientation;
        output.split = split;
        recalcOutput(output);
        return true;
    }

    /// Return the cached target rectangle for a column.  All computation was
    /// done once in recalcOutput / sync.
    pub fn columnTarget(output: *Output, col_idx: usize) Rect {
        if (col_idx >= output.columns.items.len) {
            return .{ .x = 0, .y = 0, .width = output.width, .height = output.height };
        }
        return output.columns.items[col_idx].target;
    }

    fn horizontalColumnTarget(output: *Output, col_idx: usize) Rect {
        const w = @as(f32, @floatFromInt(output.width));
        const left_w: u32 = @intFromFloat(w * output.split.left_peek);
        const focus_w: u32 = @intFromFloat(w * output.split.focus);

        const target: Rect = switch (col_idx) {
            0 => .{
                .x = 0,
                .y = 0,
                .width = if (output.focused_column == 0) output.width - left_w else left_w,
                .height = output.height,
            },
            1 => .{
                .x = if (output.focused_column == 0) 0 else @as(i32, @intCast(left_w)),
                .y = 0,
                .width = focus_w,
                .height = output.height,
            },
            2 => .{
                .x = @as(i32, @intCast(left_w + focus_w)),
                .y = 0,
                .width = output.width - left_w - focus_w,
                .height = output.height,
            },
            else => .{ .x = 0, .y = 0, .width = output.width, .height = output.height },
        };
        return target.inset(output.gap);
    }

    fn verticalColumnTarget(output: *Output, col_idx: usize) Rect {
        const h = @as(f32, @floatFromInt(output.height));
        // For vertical splits the "left_peek" becomes top band, "focus" becomes
        // bottom band, and "right_peek" is unused.
        const top_h: u32 = @intFromFloat(h * output.split.left_peek);
        const focus_h: u32 = @intFromFloat(h * output.split.focus);

        const target: Rect = switch (col_idx) {
            0 => .{
                .x = 0,
                .y = 0,
                .width = output.width,
                .height = if (output.focused_column == 0) output.height - top_h else top_h,
            },
            1 => .{
                .x = 0,
                .y = if (output.focused_column == 0) 0 else @as(i32, @intCast(top_h)),
                .width = output.width,
                .height = focus_h,
            },
            2 => .{
                .x = 0,
                .y = @as(i32, @intCast(top_h + focus_h)),
                .width = output.width,
                .height = output.height - top_h - focus_h,
            },
            else => .{ .x = 0, .y = 0, .width = output.width, .height = output.height },
        };
        return target.inset(output.gap);
    }

    pub const SplitKind = enum { peek_left, focus, peek_right };

    pub fn setHorizontalSplit(output: *Output, focus_col: SplitKind) void {
        output.split = .{
            .left_peek = style.layout.horizontal_split.left_peek,
            .focus = style.layout.horizontal_split.focus,
            .right_peek = style.layout.horizontal_split.right_peek,
        };
        output.focused_column = switch (focus_col) {
            .peek_left => 0,
            .focus => 1,
            .peek_right => 2,
        };
        output.orientation = .horizontal;
        recalcOutput(output);
    }

    pub fn setVerticalSplit(output: *Output, top: bool, ratio: f32) void {
        const primary = @max(0.2, @min(0.8, ratio));
        const secondary = 1.0 - primary;
        if (top) {
            output.split = .{ .left_peek = 0.0, .focus = primary, .right_peek = secondary };
            output.focused_column = 1;
        } else {
            output.split = .{ .left_peek = secondary, .focus = primary, .right_peek = 0.0 };
            output.focused_column = 1;
        }
        output.orientation = .vertical;
        recalcOutput(output);
    }

    pub fn orientationFromSplit(left_peek: f32, right_peek: f32) Orientation {
        if (left_peek == 0.0 and right_peek == 0.0) return .vertical;
        return .horizontal;
    }

    pub fn recalcOutput(output: *Output) void {
        const num_cols = output.columns.items.len;
        if (num_cols == 0) return;
        output.split.verify();

        for (output.columns.items, 0..) |*col, idx| {
            col.target = switch (output.orientation) {
                .horizontal => horizontalColumnTarget(output, idx),
                .vertical => verticalColumnTarget(output, idx),
            };
            col.is_focused = (output.focused_column < 0 and idx == 1) or (output.focused_column == @as(i32, @intCast(idx)));
        }
    }
};

test "default horizontal three-column layout" {
    const allocator = std.testing.allocator;
    var model = try LayoutModel.createFromOutput(allocator, 1000, 600, 8);
    defer model.deinit();

    const output = &model.outputs.items[0];
    try std.testing.expectEqual(output.columns.items.len, 3);

    const left = output.columns.items[0].target;
    const focus = output.columns.items[1].target;
    const right = output.columns.items[2].target;

    const total = style.layout.default_split.left_peek + style.layout.default_split.focus + style.layout.default_split.right_peek;
    const focus_base: u32 = @intFromFloat(1000.0 * style.layout.default_split.focus / total);
    const left_base: u32 = @intFromFloat(1000.0 * style.layout.default_split.left_peek / total);
    const expected_focus_width = if (focus_base > 2 * 8) focus_base - 2 * 8 else 0;
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(focus.width)), @as(f32, @floatFromInt(expected_focus_width)), 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(focus.height)), @as(f32, @floatFromInt(output.height - 16)), 1.0);
    try std.testing.expectEqual(focus.x, @as(i32, @intCast(left_base + 8)));

    _ = left;
    _ = right;
}

test "vertical split produces top/bottom bands" {
    const allocator = std.testing.allocator;
    var model = try LayoutModel.createFromOutput(allocator, 1000, 800, 0);
    defer model.deinit();

    const output = &model.outputs.items[0];
    LayoutModel.setVerticalSplit(output, true, 0.5);

    const top = output.columns.items[1].target;
    const bottom = output.columns.items[2].target;

    try std.testing.expectEqual(top.y, 0);
    try std.testing.expectEqual(top.x, 0);
    try std.testing.expectEqual(top.width, 1000);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(top.height)), 400.0, 1.0);
    try std.testing.expectEqual(bottom.y, 400);
    try std.testing.expectEqual(bottom.height, 400);
}

fn expectApproxEq(a: f32, b: f32) !void {
    return std.testing.expectApproxEqAbs(a, b, 1.0);
}
