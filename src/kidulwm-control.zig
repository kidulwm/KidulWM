const std = @import("std");
const linux = std.os.linux;
const ipc = @import("ipc.zig");

fn connectUnixSocket(path: []const u8) !i32 {
    const fd_i: i32 = @intCast(linux.socket(linux.AF.UNIX, linux.SOCK.STREAM, 0));
    if (fd_i < 0) return error.SocketFailed;
    errdefer _ = linux.close(fd_i);

    var addr: std.posix.sockaddr.un = std.mem.zeroes(std.posix.sockaddr.un);
    addr.family = linux.AF.UNIX;
    const path_len = @min(path.len, addr.path.len - 1);
    @memcpy(addr.path[0..path_len], path[0..path_len]);
    addr.path[path_len] = 0;
    const addr_len: u32 = @intCast(@offsetOf(std.posix.sockaddr.un, "path") + path_len + 1);
    const rc = linux.connect(fd_i, @ptrCast(&addr), addr_len);
    if (rc != 0) return error.ConnectFailed;
    return fd_i;
}

pub fn main(init: std.process.Init.Minimal) !void {
    const allocator = std.heap.page_allocator;

    var it = std.process.Args.Iterator.init(init.args);
    _ = it.next(); // skip program name
    const cmd = if (it.next()) |arg| arg else "get_layout";

    const runtime = std.process.Environ.getPosix(init.environ, "XDG_RUNTIME_DIR") orelse "/run/user/1000";
    const socket_path = try std.fs.path.join(allocator, &.{ runtime, "kidulwm-control.sock" });
    defer allocator.free(socket_path);

    const fd = try connectUnixSocket(socket_path);
    defer _ = linux.close(fd);

    const req: ipc.message.Request = blk: {
        if (std.mem.eql(u8, cmd, "ping")) break :blk .{ .ping = {} };
        if (std.mem.eql(u8, cmd, "get_layout")) break :blk .{ .get_layout = {} };
        if (std.mem.eql(u8, cmd, "quit")) break :blk .{ .quit = {} };
        if (std.mem.eql(u8, cmd, "focus_next")) break :blk .{ .focus_next = {} };
        if (std.mem.eql(u8, cmd, "focus_prev")) break :blk .{ .focus_prev = {} };
        if (std.mem.eql(u8, cmd, "split_left")) break :blk .{ .split_left = {} };
        if (std.mem.eql(u8, cmd, "split_right")) break :blk .{ .split_right = {} };
        if (std.mem.eql(u8, cmd, "split_top")) break :blk .{ .split_top = {} };
        if (std.mem.eql(u8, cmd, "split_bottom")) break :blk .{ .split_bottom = {} };
        if (std.mem.eql(u8, cmd, "reload_theme")) break :blk .{ .reload_theme = {} };
        if (std.mem.eql(u8, cmd, "tray_toggle")) break :blk .{ .tray_toggle = {} };
        if (std.mem.eql(u8, cmd, "tray_select_next")) break :blk .{ .tray_select_next = {} };
        if (std.mem.eql(u8, cmd, "tray_select_prev")) break :blk .{ .tray_select_prev = {} };
        if (std.mem.eql(u8, cmd, "tray_activate")) break :blk .{ .tray_activate = {} };
        if (std.mem.eql(u8, cmd, "tray_toggle_card")) break :blk .{ .tray_toggle_card = {} };
        if (std.mem.eql(u8, cmd, "set_theme")) {
            const key = it.next() orelse {
                std.log.err("set_theme requires a key argument", .{});
                return error.MissingArgument;
            };
            const value = it.next() orelse {
                std.log.err("set_theme requires a value argument", .{});
                return error.MissingArgument;
            };
            break :blk .{ .set_theme = .{ .key = key, .value = value } };
        }
        std.log.err("unknown command: {s}", .{cmd});
        return error.UnknownCommand;
    };

    const payload = try ipc.message.encodeRequest(allocator, req);
    defer allocator.free(payload);

    _ = linux.write(fd, payload.ptr, payload.len);
    _ = linux.write(fd, "\n", 1);

    var buf: [4096]u8 = undefined;
    const rc = linux.read(fd, &buf, buf.len);
    if (linux.errno(rc) == .SUCCESS and rc > 0) {
        _ = linux.write(linux.STDOUT_FILENO, &buf, @intCast(rc));
    }
}
