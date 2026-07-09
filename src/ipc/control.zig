const std = @import("std");
const linux = std.os.linux;
const message = @import("message.zig");

pub const Server = @This();

allocator: std.mem.Allocator,
socket_path_z: [:0]const u8,
listener_fd: i32,
epoll_fd: i32,
clients: std.ArrayList(Client),
state: *anyopaque,
handler: *const fn (*anyopaque, message.Request) message.Response,
stopped: bool = false,

const Client = struct {
    fd: i32,
    buf: [4096]u8,
    offset: usize,
};

pub const Options = struct {
    socket_path: []const u8,
    state: *anyopaque,
    handler: *const fn (*anyopaque, message.Request) message.Response,
};

fn setNonBlocking(fd: i32) !void {
    const flags = linux.fcntl(fd, linux.F.GETFL, 0);
    if (flags < 0) return error.FcntlFailed;
    var o: linux.O = @bitCast(@as(u32, @intCast(flags)));
    o.NONBLOCK = true;
    const new_flags: u32 = @bitCast(o);
    if (linux.fcntl(fd, linux.F.SETFL, new_flags) < 0) {
        return error.FcntlFailed;
    }
}

fn socketAddr(path: [:0]const u8) !std.posix.sockaddr.un {
    var addr: std.posix.sockaddr.un = std.mem.zeroes(std.posix.sockaddr.un);
    addr.family = linux.AF.UNIX;
    if (path.len >= addr.path.len - 1) return error.NameTooLong;
    @memcpy(addr.path[0..path.len], path);
    addr.path[path.len] = 0;
    return addr;
}

pub fn create(allocator: std.mem.Allocator, options: Options) !Server {
    const socket_path_z = try allocator.dupeZ(u8, options.socket_path);
    errdefer allocator.free(socket_path_z);

    _ = linux.unlink(socket_path_z);

    const listener_fd = @as(i32, @intCast(linux.socket(linux.AF.UNIX, linux.SOCK.STREAM, 0)));
    if (listener_fd < 0) return error.SocketFailed;
    errdefer _ = linux.close(listener_fd);

    try setNonBlocking(listener_fd);

    const addr = try socketAddr(socket_path_z);
    const addr_len: u32 = @intCast(@offsetOf(std.posix.sockaddr.un, "path") + options.socket_path.len + 1);
    if (linux.bind(listener_fd, @ptrCast(&addr), addr_len) < 0) {
        return error.BindFailed;
    }
    if (linux.listen(listener_fd, 16) < 0) {
        return error.ListenFailed;
    }

    const epoll_fd = @as(i32, @intCast(linux.epoll_create1(0)));
    if (epoll_fd < 0) return error.EpollFailed;
    errdefer _ = linux.close(epoll_fd);

    var event: linux.epoll_event = .{
        .events = linux.EPOLL.IN,
        .data = .{ .fd = listener_fd },
    };
    if (linux.epoll_ctl(epoll_fd, linux.EPOLL.CTL_ADD, listener_fd, &event) < 0) {
        return error.EpollCtlFailed;
    }

    return Server{
        .allocator = allocator,
        .socket_path_z = socket_path_z,
        .listener_fd = listener_fd,
        .epoll_fd = epoll_fd,
        .clients = std.ArrayList(Client).empty,
        .state = options.state,
        .handler = options.handler,
    };
}

pub fn destroy(self: *Server) void {
    self.stopped = true;
    for (self.clients.items) |client| {
        _ = linux.close(client.fd);
    }
    self.clients.deinit(self.allocator);
    _ = linux.close(self.epoll_fd);
    _ = linux.close(self.listener_fd);
    self.allocator.free(self.socket_path_z);
}

pub fn tick(self: *Server) !void {
    var events: [16]linux.epoll_event = undefined;
    const n = linux.epoll_wait(self.epoll_fd, &events, 16, 0);

    for (events[0..@intCast(n)]) |ev| {
        const fd = ev.data.fd;

        if (fd == self.listener_fd) {
            try self.acceptClient();
            continue;
        }

        if (ev.events & linux.EPOLL.IN != 0) {
            const done = try self.readClient(fd);
            if (done) self.removeClient(fd);
            continue;
        }

        if (ev.events & (linux.EPOLL.ERR | linux.EPOLL.HUP) != 0) {
            self.removeClient(fd);
        }
    }
}

fn acceptClient(self: *Server) !void {
    const client_fd = @as(i32, @intCast(linux.accept4(self.listener_fd, null, null, linux.SOCK.NONBLOCK)));
    if (client_fd < 0) return error.AcceptFailed;
    errdefer _ = linux.close(client_fd);

    var event: linux.epoll_event = .{
        .events = linux.EPOLL.IN,
        .data = .{ .fd = client_fd },
    };
    if (linux.epoll_ctl(self.epoll_fd, linux.EPOLL.CTL_ADD, client_fd, &event) < 0) {
        return error.EpollCtlFailed;
    }

    const client: Client = .{ .fd = client_fd, .buf = undefined, .offset = 0 };
    try self.clients.append(self.allocator, client);
}

fn readClient(self: *Server, fd: i32) !bool {
    const client = self.findClient(fd) orelse return true;
    if (client.offset >= client.buf.len) return true;

    const read_slice = client.buf[client.offset..client.buf.len];
    const rc = linux.read(fd, read_slice.ptr, read_slice.len);
    const n = switch (linux.errno(rc)) {
        .SUCCESS => rc,
        .AGAIN, .INTR => return false,
        else => |err| {
            std.log.err("ipc read error: {}", .{err});
            return true;
        },
    };

    if (n == 0) return true;
    const base = client.offset;
    client.offset += @intCast(n);
    if (client.offset > client.buf.len) {
        std.log.warn("KidulWM: IPC read overflow, closing client", .{});
        return true;
    }

    var start = base;
    const end = client.offset;
    while (start < end) {
        const slice = client.buf[start..end];
        if (std.mem.indexOf(u8, slice, "\n")) |newline| {
            const line = std.mem.trim(u8, slice[0..newline], " \t\r");
            if (line.len > 0) {
                self.handleLine(fd, line) catch |err| {
                    std.log.err("ipc handle error: {}", .{err});
                };
            }
            start += newline + 1;
        } else break;
    }

    if (start > 0) {
        const unconsumed = client.offset - start;
        if (unconsumed > 0) {
            std.mem.copyForwards(u8, client.buf[0..unconsumed], client.buf[start..client.offset]);
        }
        client.offset = unconsumed;
    }

    return false;
}

fn handleLine(self: *Server, fd: i32, line: []const u8) !void {
    const req = message.decodeRequest(self.allocator, line) catch |err| {
        try self.sendError(fd, "invalid request");
        std.log.err("ipc decode error: {}", .{err});
        return;
    };

    const resp = self.handler(self.state, req);
    const payload = try resp.toJson(self.allocator);
    defer self.allocator.free(payload);

    _ = linux.write(fd, payload.ptr, payload.len);
    _ = linux.write(fd, "\n", 1);
}

fn sendError(self: *Server, fd: i32, msg: []const u8) !void {
    const resp = message.Response{ .ok = false, .message = msg };
    const payload = try resp.toJson(self.allocator);
    defer self.allocator.free(payload);
    _ = linux.write(fd, payload.ptr, payload.len);
    _ = linux.write(fd, "\n", 1);
}

fn findClient(self: *Server, fd: i32) ?*Client {
    for (self.clients.items) |*client| {
        if (client.fd == fd) return client;
    }
    return null;
}

fn removeClient(self: *Server, fd: i32) void {
    var i: usize = 0;
    while (i < self.clients.items.len) {
        if (self.clients.items[i].fd == fd) {
            const removed = self.clients.swapRemove(i);
            _ = linux.close(removed.fd);
            var event: linux.epoll_event = undefined;
            _ = linux.epoll_ctl(self.epoll_fd, linux.EPOLL.CTL_DEL, fd, &event);
            return;
        }
        i += 1;
    }
}
