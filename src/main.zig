const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

pub fn main() !void {
    std.log.info("KidulWM boot", .{});

    const server = try wl.Server.create();
    defer server.destroy();

    const event_loop = server.getEventLoop();
    std.log.info("KidulWM: created Wayland display event loop", .{});

    std.log.info("KidulWM: initializing wlroots backend", .{});
    const backend = wlr.Backend.autocreate(event_loop, null) catch |err| {
        std.log.warn("wlroots backend autocreate failed ({}); skeleton exiting gracefully", .{err});
        return;
    };
    defer backend.destroy();

    std.log.info("KidulWM: wlroots backend initialized", .{});
}
