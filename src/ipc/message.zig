const std = @import("std");
const posix = std.posix;

pub const RequestTag = enum {
    ping,
    get_layout,
    set_focus,
    focus_next,
    focus_prev,
    set_gap,
    set_split,
    split_left,
    split_right,
    split_top,
    split_bottom,
    set_theme,
    subscribe,
    quit,
};

pub const Request = union(RequestTag) {
    ping: void,
    get_layout: void,
    set_focus: struct {
        window_id: u32,
    },
    focus_next,
    focus_prev,
    set_gap: struct {
        gap: u32,
    },
    set_split: struct {
        left_peek: f32,
        focus: f32,
        right_peek: f32,
    },
    split_left: void,
    split_right: void,
    split_top: void,
    split_bottom: void,
    set_theme: struct {
        key: []const u8,
        value: []const u8,
    },
    subscribe: struct {
        events: []const u8,
    },
    quit: void,
};

pub const LayoutResponse = struct {
    orientation: []const u8,
    gap: u32,
    left_peek: f32,
    focus: f32,
    right_peek: f32,
    focused_window: u32,
    window_count: usize,
};

pub const Response = struct {
    ok: bool,
    message: ?[]const u8 = null,
    data: ?[]const u8 = null,
    layout: ?LayoutResponse = null,

    pub fn toJson(self: Response, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(self, .{})});
    }

    pub fn decodeJson(json: []const u8) !Response {
        return try std.json.parseFromSlice(Response, std.heap.page_allocator, json, .{});
    }
};

pub fn decodeRequest(allocator: std.mem.Allocator, line: []const u8) !Request {
    const parsed = try std.json.parseFromSlice(Request, allocator, line, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return parsed.value;
}

pub fn encodeRequest(allocator: std.mem.Allocator, req: Request) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(req, .{})});
}
