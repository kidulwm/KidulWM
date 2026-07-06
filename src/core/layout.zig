const std = @import("std");

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

pub const Split = struct {
    left_peek: f32,
    focus: f32,
    right_peek: f32,

    pub fn default() Split {
        return .{
            .left_peek = 0.08,
            .focus = 0.94,
            .right_peek = 0.08,
        };
    }

    pub fn normalize(self: *Split) void {
        const sum = self.left_peek + self.focus + self.right_peek;
        if (sum > 0.0) {
            self.left_peek /= sum;
            self.focus /= sum;
            self.right_peek /= sum;
        }
    }

    pub fn verify(self: *Split) void {
        self.normalize();
        // Clamp individual values to sane ranges.
        self.left_peek = std.math.clamp(self.left_peek, 0.0, 1.0);
        self.right_peek = std.math.clamp(self.right_peek, 0.0, 1.0);
        self.focus = 1.0 - self.left_peek - self.right_peek;
        if (self.focus < 0.0) {
            self.focus = 0.0;
            self.normalize();
        }
    }
};

pub const Window = struct {
    id: u32,
    /// Geometry in output logical coordinates, including gap.
    geometry: Rect,
    focused: bool = false,
    surface: ?*anyopaque = null, // placeholder for wlr_surface*
};

pub const Column = struct {
    id: u32,
    windows: std.ArrayList(Window),
    target: Rect,
    weight: f32 = 1.0,
    is_focused: bool = false,

    pub fn deinit(self: *Column) void {
        self.windows.deinit();
    }
};

pub const Output = struct {
    id: u32,
    name: []const u8,
    width: u32,
    height: u32,
    scale: f32 = 1.0,
    split: Split = Split.default(),
    gap: u32 = 8,
    columns: std.ArrayList(Column),
    focused_column: i32 = -1,

    pub fn deinit(self: *Output) void {
        for (self.columns.items) |*col| {
            col.deinit();
        }
        self.columns.deinit();
    }
};

pub const LayoutModel = struct {
    allocator: std.mem.Allocator,
    outputs: std.ArrayList(Output),

    pub fn create(allocator: std.mem.Allocator) LayoutModel {
        return .{
            .allocator = allocator,
            .outputs = std.ArrayList(Output).init(allocator),
        };
    }

    pub fn deinit(self: *LayoutModel) void {
        for (self.outputs.items) |*output| {
            output.deinit();
        }
        self.outputs.deinit();
    }

    pub fn recalcOutput(output: *Output) void {
        const w = @as(f32, @floatFromInt(output.width));
        const working_area = Rect{
            .x = 0,
            .y = 0,
            .width = output.width,
            .height = output.height,
        };

        const num_cols = output.columns.items.len;
        if (num_cols == 0) return;

        output.split.verify();

        // For now, 8%-94%-8% maps to: left peek column, focused column, right peek column.
        // If more than 3 columns, focused gets focus share; others divide peek amounts.
        if (num_cols == 1) {
            output.columns.items[0].target = working_area.inset(output.gap);
            output.columns.items[0].is_focused = true;
        } else if (num_cols == 2) {
            output.split.verify();
            const left_w: u32 = @intFromFloat(w * output.split.left_peek);
            const focus_w: u32 = @intFromFloat(w * output.split.focus);

            output.columns.items[0].target = .{
                .x = 0,
                .y = 0,
                .width = left_w,
                .height = output.height,
            }.inset(output.gap);
            output.columns.items[1].target = .{
                .x = @as(i32, @intCast(left_w)),
                .y = 0,
                .width = focus_w,
                .height = output.height,
            }.inset(output.gap);

            const fc = output.focused_column;
            output.columns.items[0].is_focused = (fc == 0);
            output.columns.items[1].is_focused = (fc != 0);
        } else {
            // 3+ columns: focused in middle; side peek columns split remaining space.
            output.split.verify();
            const left_w: u32 = @intFromFloat(w * output.split.left_peek);
            const focus_w: u32 = @intFromFloat(w * output.split.focus);
            const right_w: u32 = @intFromFloat(w * output.split.right_peek);

            output.columns.items[0].target = .{
                .x = 0,
                .y = 0,
                .width = left_w,
                .height = output.height,
            }.inset(output.gap);

            output.columns.items[1].target = .{
                .x = @as(i32, @intCast(left_w)),
                .y = 0,
                .width = focus_w,
                .height = output.height,
            }.inset(output.gap);

            output.columns.items[2].target = .{
                .x = @as(i32, @intCast(left_w + focus_w)),
                .y = 0,
                .width = right_w,
                .height = output.height,
            }.inset(output.gap);

            const fc = output.focused_column;
            output.columns.items[0].is_focused = (fc == 0);
            output.columns.items[1].is_focused = (fc == 1 or fc < 0);
            output.columns.items[2].is_focused = (fc == 2);
        }
    }
};

const testing = std.testing;

test "default split sums to 1" {
    var split = Split.default();
    split.verify();
    try testing.expectApproxEqAbs(split.left_peek + split.focus + split.right_peek, 1.0, 0.001);
}

test "single column fills output" {
    const allocator = testing.allocator;
    var model = LayoutModel.create(allocator);
    defer model.deinit();

    var output = Output{
        .id = 1,
        .name = "HDMI-1",
        .width = 1920,
        .height = 1080,
        .columns = std.ArrayList(Column).init(allocator),
    };
    try output.columns.append(.{ .id = 10, .windows = std.ArrayList(Window).init(allocator), .target = undefined });
    output.focused_column = 0;

    LayoutModel.recalcOutput(&output);

    try testing.expectEqual(@as(i32, 8), output.columns.items[0].target.x);
    try testing.expectEqual(@as(u32, 1920 - 16), output.columns.items[0].target.width);
}

test "three column split" {
    const allocator = testing.allocator;
    var model = LayoutModel.create(allocator);
    defer model.deinit();

    var output = Output{
        .id = 2,
        .name = "DP-1",
        .width = 3840,
        .height = 2160,
        .columns = std.ArrayList(Column).init(allocator),
        .gap = 16,
    };
    try output.columns.append(.{ .id = 10, .windows = std.ArrayList(Window).init(allocator), .target = undefined });
    try output.columns.append(.{ .id = 11, .windows = std.ArrayList(Window).init(allocator), .target = undefined });
    try output.columns.append(.{ .id = 12, .windows = std.ArrayList(Window).init(allocator), .target = undefined });
    output.focused_column = 1;

    LayoutModel.recalcOutput(&output);

    // Middle column should be roughly 94% focus - 32px gap.
    const col = output.columns.items[1];
    try testing.expect(col.target.width >= 3500 and col.target.width <= 3700);

    output.deinit();
}
