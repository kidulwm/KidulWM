const std = @import("std");
const Server = @import("server.zig").Server;

pub fn main(init: std.process.Init.Minimal) !void {
    std.log.info("KidulWM boot", .{});

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try Server.init(allocator);
    errdefer server.deinit();

    const runtime_dir = std.process.Environ.getPosix(init.environ, "XDG_RUNTIME_DIR") orelse "/tmp";
    const socket_path = try std.fs.path.join(allocator, &.{ runtime_dir, "kidulwm-control.sock" });
    defer allocator.free(socket_path);

    try server.createIpcSocket(socket_path);
    std.log.info("KidulWM: IPC control socket at {s}", .{socket_path});

    const no_backend = std.process.Environ.getPosix(init.environ, "KIDULWM_NO_BACKEND") != null;
    const maybe_wayland_display = std.process.Environ.getPosix(init.environ, "KIDULWM_WAYLAND_DISPLAY");
    try server.start(no_backend, maybe_wayland_display);

    server.deinit();
}
