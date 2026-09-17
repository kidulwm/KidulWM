//! kvis.sock client (CARD 2b slice 2): the media slide's line to kvisd.
//! Same socket client does open + parent (HANDOFF session 23): spawn
//! connects, opens the path, then parents kvisd's video surface onto the
//! slide's exported host toplevel. Close sends 'unparent' + 'close'.
//!
//! Transport: SOCK_SEQPACKET (record-oriented, one line per packet —
//! matches kvisd_main.zig). Blocking connect + blocking verbs with a
//! short reply wait: the compositor main thread is the only caller and
//! kvisd replies synchronously inside its 20ms poll quantum, so a
//! bounded synchronous exchange is correct here — no async state
//! machine, no event-loop integration for v1.

const std = @import("std");
const linux = std.os.linux;

pub const Error = error{
    NoRuntimeDir,
    SocketFailed,
    ConnectFailed,
    WriteFailed,
    ReplyTimeout,
    DaemonError,
    OutOfMemory,
};

pub const KvisClient = struct {
    fd: linux.fd_t,
    allocator: std.mem.Allocator,

    /// Connect to $XDG_RUNTIME_DIR/kvis.sock (fallback /run/user/<uid>).
    pub fn connect(allocator: std.mem.Allocator) Error!KvisClient {
        var pbuf: [256]u8 = undefined;
        const path = blk: {
            if (std.c.getenv("XDG_RUNTIME_DIR")) |d|
                break :blk std.fmt.bufPrint(&pbuf, "{s}/kvis.sock", .{std.mem.span(d)}) catch return error.NoRuntimeDir;
            break :blk std.fmt.bufPrint(&pbuf, "/run/user/{d}/kvis.sock", .{linux.getuid()}) catch return error.NoRuntimeDir;
        };

        const fd: linux.fd_t = @intCast(linux.socket(linux.AF.UNIX, linux.SOCK.SEQPACKET | linux.SOCK.CLOEXEC, 0));
        if (fd < 0) return error.SocketFailed;
        errdefer _ = linux.close(fd);

        var addr: linux.sockaddr.un = .{ .family = linux.AF.UNIX, .path = [_]u8{0} ** 108 };
        if (path.len >= addr.path.len) return error.NoRuntimeDir;
        @memcpy(addr.path[0..path.len], path);
        if (linux.connect(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.un)) != 0)
            return error.ConnectFailed;

        return .{ .fd = fd, .allocator = allocator };
    }

    pub fn destroy(self: *KvisClient) void {
        _ = linux.close(self.fd);
    }

    fn send(self: *KvisClient, line: []const u8) Error!void {
        const n = linux.write(self.fd, line.ptr, line.len);
        const sn: isize = @bitCast(n);
        if (sn <= 0) return error.WriteFailed;
    }

    /// Wait for one reply line (bounded: ~2s worst case via poll).
    /// kvisd broadcasts 'event ...' lines to every client — skip those;
    /// we want the ok/err reply to OUR verb.
    fn recvReply(self: *KvisClient, buf: []u8) Error![]const u8 {
        var waited_ms: u32 = 0;
        while (waited_ms < 2000) : (waited_ms += 20) {
            var pfd = [_]linux.pollfd{.{ .fd = self.fd, .events = linux.POLL.IN, .revents = 0 }};
            const ready = linux.poll(&pfd, 1, 20);
            if (@as(isize, @bitCast(ready)) <= 0) continue;
            const n = linux.read(self.fd, buf.ptr, buf.len);
            const sn: isize = @bitCast(n);
            if (sn <= 0) return error.WriteFailed; // daemon dropped us
            const line = std.mem.trim(u8, buf[0..@intCast(sn)], " \r\n\t");
            if (std.mem.startsWith(u8, line, "event ")) continue; // broadcast, not our reply
            return line;
        }
        return error.ReplyTimeout;
    }

    fn verb(self: *KvisClient, line: []const u8) Error!void {
        var rbuf: [1024]u8 = undefined;
        try self.send(line);
        const r = try self.recvReply(&rbuf);
        if (std.mem.eql(u8, r, "ok")) return;
        if (std.mem.startsWith(u8, r, "err")) return error.DaemonError;
        // Unknown reply shape — treat as failure so callers notice.
        return error.DaemonError;
    }

    /// open <path> — start playback (video spawns the kvisd shell).
    pub fn open(self: *KvisClient, path: []const u8) Error!void {
        var buf: [4096]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "open {s}\n", .{path}) catch return error.OutOfMemory;
        try self.verb(line);
    }

    /// parent <handle> — import the slide's exported toplevel handle and
    /// parent kvisd's video surface to it (xdg-foreign v2).
    pub fn parent(self: *KvisClient, handle: []const u8) Error!void {
        var buf: [1024]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "parent {s}\n", .{handle}) catch return error.OutOfMemory;
        try self.verb(line);
    }

    /// unparent — sever the xdg-foreign parent link (idempotent daemon-side).
    pub fn unparent(self: *KvisClient) Error!void {
        try self.verb("unparent\n");
    }

    /// close — stop playback and drop the shell (daemon stays alive).
    pub fn close(self: *KvisClient) Error!void {
        try self.verb("close\n");
    }

    /// pause / resume — idempotent daemon-side.
    pub fn pause(self: *KvisClient) Error!void {
        try self.verb("pause\n");
    }

    pub fn unpause(self: *KvisClient) Error!void {
        try self.verb("resume\n");
    }
};
