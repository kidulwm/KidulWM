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
            .left_peek = 0.08,
            .focus = 0.94,
            .right_peek = 0.08,
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

pub const Output = struct {
    id: u32,
    name: []const u8,
    width: u32,
    height: u32,
    columns: std.ArrayList(Column),
    focused_column: i32 = 1,
    gap: u32,
    split: Split,

    pub fn deinit(self: *Output, allocator: std.mem.Allocator) void {
        for (self.columns.items) |*col| {
            col.windows.deinit(allocator);
        }
        self.columns.deinit(allocator);
    }
};

pub const LayoutModel = struct {
    allocator: std.mem.Allocator,
    outputs: std.ArrayList(Output),

    pub fn create(allocator: std.mem.Allocator) LayoutModel {
        return .{
            .allocator = allocator,
            .outputs = std.ArrayList(Output).empty,
        };
    }

    pub fn createFromOutput(allocator: std.mem.Allocator, width: u32, height: u32, gap: u32) !LayoutModel {
        var self = create(allocator);
        var output = Output{
            .id = 1,
            .name = "primary",
            .width = width,
            .height = height,
            .columns = std.ArrayList(Column).empty,
            .gap = gap,
            .split = Split.default(),
        };
        output.split.verify();
        // Populate 3 columns so layout mimics 8%-94%-8% peek/focus/peek arrangement.
        for (0..3) |i| {
            try output.columns.append(allocator, .{
                .id = @intCast(i),
                .windows = std.ArrayList(Window).empty,
                .target = undefined,
                .is_focused = (i == 1),
            });
        }
        try self.outputs.append(allocator, output);
        recalcOutput(&self.outputs.items[0]);
        return self;
    }

    pub fn deinit(self: *LayoutModel) void {
        for (self.outputs.items) |*output| {
            output.deinit(self.allocator);
        }
        self.outputs.deinit(self.allocator);
    }

    pub fn columnTarget(output: *Output, col_idx: usize, left_peek: f32, focus: f32, right_peek: f32) Rect {
        var split = Split{ .left_peek = left_peek, .focus = focus, .right_peek = right_peek };
        split.verify();
        output.split = split;

        // adjust / rebuild column targets on demand
        const w = @as(f32, @floatFromInt(output.width));
        const working_area = Rect{ .x = 0, .y = 0, .width = output.width, .height = output.height };
        const focused = output.focused_column;

        const left_w: u32 = @intFromFloat(w * split.left_peek);
        const focus_w: u32 = @intFromFloat(w * split.focus);

        const base_target: Rect = switch (col_idx) {
            0 => .{
                .x = 0,
                .y = 0,
                .width = if (focused == 0) output.width - left_w else left_w,
                .height = output.height,
            },
            1 => .{
                .x = if (focused == 0) 0 else left_w,
                .y = 0,
                .width = focus_w,
                .height = output.height,
            },
            2 => .{
                .x = left_w + focus_w,
                .y = 0,
                .width = output.width - left_w - focus_w,
                .height = output.height,
            },
            else => working_area,
        };
        return base_target.inset(output.gap);
    }

    pub fn recalcOutput(output: *Output) void {
        const w = @as(f32, @floatFromInt(output.width));
        const num_cols = output.columns.items.len;
        if (num_cols == 0) return;
        output.split.verify();

        const left_w: u32 = @intFromFloat(w * output.split.left_peek);
        const focus_w: u32 = @intFromFloat(w * output.split.focus);

        for (output.columns.items, 0..) |*col, idx| {
            const target: Rect = switch (idx) {
                0 => .{
                    .x = 0,
                    .y = 0,
                    .width = left_w,
                    .height = output.height,
                },
                1 => .{
                    .x = @as(i32, @intCast(left_w)),
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
                else => .{
                    .x = 0,
                    .y = 0,
                    .width = output.width,
                    .height = output.height,
                },
            };
            col.target = target.inset(output.gap);
            col.is_focused = (output.focused_column < 0 and idx == 1) or (output.focused_column == @as(i32, @intCast(idx)));
        }
    }
};
