const std = @import("std");
const linux = std.os.linux;
const message = @import("message.zig");
const wl = @import("wayland").server.wl;

/// kidulwm-control IPC socket server, driven by the MAIN wl_event_loop.
///
/// Phase 0 (I5): the control socket used to run on a dedicated thread
/// (ipcThreadLoop) that polled its own epoll and called handleRequest from
/// that thread. handleRequest mutates the scene graph and — via the
/// internal-client handshake — re-enters the main wl_event_loop, which is
/// the SIGSEGV crash class (two threads dispatching one wl_display).
///
/// Now the listener and every client fd are wl_event_loop fd sources. All
/// line parsing and handleRequest run on the main loop. There is no thread,
/// no epoll, and no cross-thread dispatch here.
pub const Server = @This();

allocator: std.mem.Allocator,
socket_path_z: [:0]const u8,
listener_fd: i32,
event_loop: *wl.EventLoop,
listener_source: ?*wl.EventSource = null,
clients: std.ArrayList(Client),
state: *anyopaque,
handler: *const fn (*anyopaque, message.Request) message.Response,
stopped: bool = false,
/// Re-entrancy guard. handleLine -> handleRequest can trigger an event-loop
/// pump (internal-client handshake -> wl_event_loop dispatch). That nested
/// dispatch re-fires this server's fd source while readClient is mid-parse
/// of a client buffer, corrupting client.offset. wl_event_loop is
/// level-triggered, so a skipped re-entrant call re-fires cleanly once the
/// outer read returns. Single flag is enough: everything here is on the
/// main loop (Phase 0 / I5).
reading: bool = false,

const Client = struct {
    fd: i32,
    source: ?*wl.EventSource = null,
    buf: [4096]u8,
    offset: usize,
};

pub const Options = struct {
    socket_path: []const u8,
    event_loop: *wl.EventLoop,
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

    return Server{
        .allocator = allocator,
        .socket_path_z = socket_path_z,
        .listener_fd = listener_fd,
        .event_loop = options.event_loop,
        .clients = std.ArrayList(Client).empty,
        .state = options.state,
        .handler = options.handler,
    };
}

/// Register the listener fd on the main event loop. Called once, after the
/// compositor's wl_display (and its event loop) exist.
pub fn start(self: *Server) !void {
    self.listener_source = try self.event_loop.addFd(*Server, self.listener_fd, .{ .readable = true }, handleAccept, self);
}

pub fn destroy(self: *Server) void {
    self.stopped = true;
    if (self.listener_source) |source| {
        source.remove();
        self.listener_source = null;
    }
    for (self.clients.items) |client| {
        if (client.source) |source| source.remove();
        _ = linux.close(client.fd);
    }
    self.clients.deinit(self.allocator);
    _ = linux.close(self.listener_fd);
    self.allocator.free(self.socket_path_z);
}

fn handleAccept(_fd: c_int, _mask: wl.EventMask, server: *Server) c_int {
    _ = _fd;
    _ = _mask;
    // Drain every pending connection (level-triggered: accept until EAGAIN).
    // accept4 returns usize with the error encoded, so route through errno()
    // instead of @intCast — EAGAIN (no more pending) is huge-positive and
    // would panic a checked cast.
    while (true) {
        const rc = linux.accept4(server.listener_fd, null, null, linux.SOCK.NONBLOCK);
        const client_fd = switch (linux.errno(rc)) {
            .SUCCESS => @as(i32, @intCast(rc)),
            else => break,
        };
        const source = server.event_loop.addFd(*Server, client_fd, .{ .readable = true }, handleClientReadable, server) catch {
            _ = linux.close(client_fd);
            break;
        };
        server.clients.append(server.allocator, .{ .fd = client_fd, .source = source, .buf = undefined, .offset = 0 }) catch {
            source.remove();
            _ = linux.close(client_fd);
            break;
        };
    }
    return 0;
}

fn handleClientReadable(fd: c_int, _mask: wl.EventMask, server: *Server) c_int {
    _ = _mask;
    // Re-entrant dispatch: skip and let level-trigger re-fire after the outer
    // read completes (see Server.reading). Corruption guard, not a throttle.
    if (server.reading) return 0;
    server.reading = true;
    defer server.reading = false;
    const done = server.readClient(fd);
    if (done) server.removeClient(fd);
    return 0;
}

fn readClient(self: *Server, fd: i32) bool {
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

    if (n == 0) return true; // EOF: client closed
    // Defensive: never trust the kernel to return fewer bytes than requested.
    const safe_n = if (n > read_slice.len) read_slice.len else n;
    client.offset += safe_n;
    if (client.offset > client.buf.len) {
        std.log.warn("KidulWM: IPC read overflow, closing client", .{});
        return true;
    }

    // Parse from the FRONT of the buffer. A request line whose JSON landed in
    // one read() and whose '\n' landed in a later read() leaves the JSON at
    // buf[0..] with the newline appended after it. Starting the scan at the
    // pre-read offset (the old `base`) skips those buffered bytes and silently
    // drops the request (the 3s client-timeout stall). Front-of-buffer scan
    // sees the whole line regardless of how reads split it.
    var parse_pos: usize = 0;
    const end = client.offset;
    while (parse_pos < end) {
        const slice = client.buf[parse_pos..end];
        if (std.mem.indexOfScalar(u8, slice, '\n')) |newline| {
            const line = std.mem.trim(u8, slice[0..newline], " \t\r");
            if (line.len > 0) {
                self.handleLine(fd, line) catch |err| {
                    std.log.err("ipc handle error: {s}", .{@errorName(err)});
                };
            }
            parse_pos += newline + 1;
        } else break;
    }

    if (parse_pos > 0) {
        const unconsumed = end - parse_pos;
        if (unconsumed > 0) {
            std.mem.copyForwards(u8, client.buf[0..unconsumed], client.buf[parse_pos..end]);
        }
        client.offset = unconsumed;
    }

    return false;
}

fn handleLine(self: *Server, fd: i32, line: []const u8) !void {
    const req = message.decodeRequest(self.allocator, line) catch |err| {
        try self.sendError(fd, "invalid request");
        std.log.err("ipc decode error: {s}", .{@errorName(err)});
        return;
    };

    // Runs on the MAIN loop now (Phase 0 / I5). handleRequest may mutate the
    // scene graph freely; nothing here runs off-thread.
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
            if (removed.source) |source| source.remove();
            _ = linux.close(removed.fd);
            return;
        }
        i += 1;
    }
}
