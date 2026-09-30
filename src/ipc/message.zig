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
    reload_theme,
    tray_toggle,
    media_card_toggle,
    media_play,
    media_toggle,
    media_next,
    media_prev,
    media_seek,
    notification_test,
    notification_clear,
    arrange_outputs,
    kadence,
    kfiles_navigate,
    get_windows,
    debug_status,
    scene_dump,
    quit,
};

pub const Request = union(RequestTag) {
    ping: void,
    get_layout: void,
    set_focus: struct {
        window_id: u32,
    },
    focus_next: void,
    focus_prev: void,
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
    reload_theme: void,
    tray_toggle: void,
    media_card_toggle: void,
    media_play: struct {
        path: []const u8,
    },
    media_toggle: void,
    media_next: void,
    media_prev: void,
    media_seek: struct {
        seconds: f64,
    },
    notification_test: struct {
        title: []const u8,
        body: []const u8,
        source_id: []const u8,
        priority: ?[]const u8 = null,
        action_id: ?[]const u8 = null,
        display_mode: ?[]const u8 = null,
    },
    notification_clear: void,
    arrange_outputs: void,
    kadence: struct {
        output: []const u8,
        width: u32,
        height: u32,
        refresh_mhz: u32,
        scale: ?f32 = null,
    },
    kfiles_navigate: struct {
        path: []const u8,
    },
    get_windows: void,
    debug_status: void,
    scene_dump: void,
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
    slide_count: usize = 0,
};

pub const WindowInfo = struct {
    window_id: u32,
    app_id: ?[]const u8 = null,
    title: ?[]const u8 = null,
    mapped: bool = false,
};

pub const Response = struct {
    ok: bool,
    message: ?[]const u8 = null,
    data: ?[]const u8 = null,
    layout: ?LayoutResponse = null,
    windows: ?[]const WindowInfo = null,

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
