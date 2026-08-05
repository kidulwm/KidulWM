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

    // Local config commands (no IPC needed): write ~/.config/kidulwm/gauges.toml.
    if (std.mem.eql(u8, cmd, "set-show-temp")) {
        const value = it.next() orelse {
            std.log.err("set-show-temp requires on|off", .{});
            return error.MissingArgument;
        };
        try setGaugeFlag(allocator, "show_temp", value);
        return;
    }
    if (std.mem.eql(u8, cmd, "set-show-ram")) {
        const value = it.next() orelse {
            std.log.err("set-show-ram requires on|off", .{});
            return error.MissingArgument;
        };
        try setGaugeFlag(allocator, "show_ram", value);
        return;
    }
    if (std.mem.eql(u8, cmd, "set-temp-threshold")) {
        const value = it.next() orelse {
            std.log.err("set-temp-threshold requires a Fahrenheit value", .{});
            return error.MissingArgument;
        };
        try setGaugeFlag(allocator, "temp_threshold_f", value);
        return;
    }

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
        if (std.mem.eql(u8, cmd, "weather_toggle_card")) break :blk .{ .weather_toggle_card = {} };
        if (std.mem.eql(u8, cmd, "media_card_toggle")) break :blk .{ .media_card_toggle = {} };
        if (std.mem.eql(u8, cmd, "media_play")) {
            const path = it.next() orelse {
                std.log.err("media_play requires a path argument", .{});
                return error.MissingArgument;
            };
            break :blk .{ .media_play = .{ .path = path } };
        }
        if (std.mem.eql(u8, cmd, "media_toggle")) break :blk .{ .media_toggle = {} };
        if (std.mem.eql(u8, cmd, "media_next")) break :blk .{ .media_next = {} };
        if (std.mem.eql(u8, cmd, "media_prev")) break :blk .{ .media_prev = {} };
        if (std.mem.eql(u8, cmd, "media_seek")) {
            const seconds_str = it.next() orelse {
                std.log.err("media_seek requires a seconds argument", .{});
                return error.MissingArgument;
            };
            const seconds = std.fmt.parseFloat(f64, seconds_str) catch {
                std.log.err("media_seek requires a numeric seconds argument", .{});
                return error.InvalidArgument;
            };
            break :blk .{ .media_seek = .{ .seconds = seconds } };
        }
        if (std.mem.eql(u8, cmd, "notification_test")) {
            const title = it.next() orelse "Test";
            const body = it.next() orelse "This is a test notification.";
            const source_id = it.next() orelse "test";
            const priority = it.next();
            const action_id = it.next();
            const display_mode = it.next();
            break :blk .{ .notification_test = .{
                .title = title,
                .body = body,
                .source_id = source_id,
                .priority = priority,
                .action_id = action_id,
                .display_mode = display_mode,
            } };
        }
        if (std.mem.eql(u8, cmd, "notification_clear")) break :blk .{ .notification_clear = {} };
        if (std.mem.eql(u8, cmd, "get_windows")) break :blk .{ .get_windows = {} };
        if (std.mem.eql(u8, cmd, "kfiles_navigate")) {
            const path = it.next() orelse {
                std.log.err("kfiles_navigate requires a path argument", .{});
                return error.MissingArgument;
            };
            break :blk .{ .kfiles_navigate = .{ .path = path } };
        }
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

/// Update (or create) a single key in ~/.config/kidulwm/gauges.toml.
/// Boolean flags accept on/off/true/false/1/0; numeric keys are written raw.
fn setGaugeFlag(allocator: std.mem.Allocator, key: []const u8, raw_value: []const u8) !void {
    const home = std.c.getenv("HOME") orelse return error.NoHome;
    const dir_path = try std.fs.path.join(allocator, &.{ std.mem.span(home), ".config", "kidulwm" });
    defer allocator.free(dir_path);
    const file_path = try std.fs.path.join(allocator, &.{ dir_path, "gauges.toml" });
    defer allocator.free(file_path);

    const is_bool_key = std.mem.eql(u8, key, "show_temp") or std.mem.eql(u8, key, "show_ram");
    const value = if (is_bool_key)
        if (std.mem.eql(u8, raw_value, "on") or std.mem.eql(u8, raw_value, "true") or std.mem.eql(u8, raw_value, "1")) "true" else "false"
    else
        raw_value;

    // Read existing content (if any) and rewrite the key.
    var lines = std.ArrayList([]const u8).empty;
    defer {
        for (lines.items) |l| allocator.free(l);
        lines.deinit(allocator);
    }
    var replaced = false;
    if (readFileAlloc(allocator, file_path)) |content| {
        defer allocator.free(content);
        var it2 = std.mem.splitScalar(u8, content, '\n');
        while (it2.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            const is_target = trimmed.len > key.len and
                std.mem.startsWith(u8, trimmed, key) and
                (trimmed[key.len] == ' ' or trimmed[key.len] == '=' or trimmed[key.len] == '\t');
            if (is_target and !replaced) {
                const nl = try std.fmt.allocPrint(allocator, "{s} = {s}", .{ key, value });
                try lines.append(allocator, nl);
                replaced = true;
            } else {
                try lines.append(allocator, try allocator.dupe(u8, line));
            }
        }
    } else |_| {}
    if (!replaced) {
        const nl = try std.fmt.allocPrint(allocator, "{s} = {s}", .{ key, value });
        try lines.append(allocator, nl);
    }

    // Ensure config dir exists.
    const dir_z = try allocator.dupeZ(u8, dir_path);
    defer allocator.free(dir_z);
    _ = linux.mkdir(dir_z, 0o755);

    // Write file back with a [gauges] header if we created it.
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const has_header = blk: {
        for (lines.items) |l| {
            if (std.mem.startsWith(u8, std.mem.trim(u8, l, " \t"), "[gauges]")) break :blk true;
        }
        break :blk false;
    };
    if (!has_header) try out.appendSlice(allocator, "[gauges]\n");
    for (lines.items) |l| {
        if (l.len == 0) continue;
        try out.appendSlice(allocator, l);
        try out.append(allocator, '\n');
    }

    const path_z = try allocator.dupeZ(u8, file_path);
    defer allocator.free(path_z);
    const fd_i: i32 = @intCast(linux.open(path_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644));
    if (fd_i < 0) return error.WriteFailed;
    defer _ = linux.close(fd_i);
    _ = linux.write(fd_i, out.items.ptr, out.items.len);
    std.log.info("gauges.toml: {s} = {s}", .{ key, value });
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const file_fd = linux.open(path_z, .{ .ACCMODE = .RDONLY }, 0);
    if (@as(isize, @bitCast(file_fd)) < 0) return error.FileNotFound;
    const fd: i32 = @intCast(file_fd);
    defer _ = linux.close(fd);
    var content = std.ArrayList(u8).empty;
    errdefer content.deinit(allocator);
    var read_buf: [4096]u8 = undefined;
    while (true) {
        const n = linux.read(fd, &read_buf, read_buf.len);
        if (n < 0) return error.ReadFailed;
        if (n == 0) break;
        try content.appendSlice(allocator, read_buf[0..@as(usize, @intCast(n))]);
    }
    return content.toOwnedSlice(allocator);
}
