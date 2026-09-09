const std = @import("std");
const Server = @import("server.zig").Server;
const kmedia = @import("core/kmedia.zig");
const build_stamp = @import("build_stamp");

pub fn main(init: std.process.Init.Minimal) !void {
    std.log.info("KidulWM boot (kidulwm={s} kmedia={s})", .{ build_stamp.kidulwm_rev, build_stamp.kmedia_rev });

    // Ignore SIGCHLD so children spawned by keybindings are auto-reaped.
    var sa = std.os.linux.Sigaction{
        .handler = .{ .handler = @as(std.os.linux.Sigaction.handler_fn, @ptrFromInt(1)) },
        .mask = std.os.linux.sigemptyset(),
        .flags = 0,
    };
    _ = std.os.linux.sigaction(.CHLD, &sa, null);

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const force_pixman = blk: {
        const val = std.process.Environ.getPosix(init.environ, "WLR_RENDERER") orelse break :blk false;
        break :blk std.mem.eql(u8, val, "pixman");
    };

    var server = try Server.init(allocator, force_pixman);
    errdefer server.deinit();

    const runtime_dir = std.process.Environ.getPosix(init.environ, "XDG_RUNTIME_DIR") orelse "/tmp";
    const socket_path = try std.fs.path.join(allocator, &.{ runtime_dir, "kidulwm-control.sock" });
    defer allocator.free(socket_path);

    try server.createIpcSocket(socket_path);
    std.log.info("KidulWM: IPC control socket at {s}", .{socket_path});

    // Start the kmedia audio capture thread (PipeWire monitor of the default
    // sink → FFT bands for widgets). Silently no-ops if PipeWire is absent.
    kmedia.start();

    const no_backend = std.process.Environ.getPosix(init.environ, "KIDULWM_NO_BACKEND") != null;
    const maybe_wayland_display = std.process.Environ.getPosix(init.environ, "KIDULWM_WAYLAND_DISPLAY");
    try server.start(no_backend, maybe_wayland_display);

    server.deinit();
}
