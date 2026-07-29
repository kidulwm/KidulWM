const std = @import("std");

pub const RequestTag = enum {
    notification_test,
};

pub const Request = union(RequestTag) {
    notification_test: struct {
        title: []const u8,
        body: []const u8,
        source_id: []const u8,
    },
};

pub fn encodeRequest(allocator: std.mem.Allocator, req: Request) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(req, .{})});
}
