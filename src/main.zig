const std = @import("std");
const linux = std.os.linux;
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const ipc = @import("ipc.zig");

const State = struct {
    gap: u32 = 8,
    left_peek: f32 = 0.08,
    focus: f32 = 0.94,
    right_peek: f32 = 0.08,
    focused_window: u32 = 0,
    allocator: std.mem.Allocator = std.heap.page_allocator,

    pub fn handleRequest(state: *State, req: ipc.message.Request) ipc.message.Response {
        switch (req) {
            .ping => return .{ .ok = true, .message = "pong" },
            .get_layout => return .{ .ok = true, .message = "layout data pending" },
            .set_gap => |p| state.gap = p.gap,
            .set_split => |p| {
                state.left_peek = p.left_peek;
                state.focus = p.focus;
                state.right_peek = p.right_peek;
            },
            .set_focus => |p| state.focused_window = p.window_id,
            .set_theme => |p| {
                std.log.info("theme update: {s} = {s}", .{ p.key, p.value });
                return .{ .ok = true, .message = "theme updated" };
            },
            .subscribe => return .{ .ok = true, .message = "subscription registered" },
        }
        return .{ .ok = true };
    }
};

pub fn main(init: std.process.Init.Minimal) !void {
    std.log.info("KidulWM boot", .{});

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const tick_limit: usize = 600;
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

    var state = State{ .allocator = allocator };

    const runtime_dir = std.process.Environ.getPosix(init.environ, "XDG_RUNTIME_DIR") orelse "/tmp";
    const full_path = try std.fs.path.join(allocator, &.{ runtime_dir, "kidulwm-control.sock" });
    defer allocator.free(full_path);
    std.log.info("KidulWM: IPC socket at {s}", .{full_path});

    var ipc_server = try ipc.control.Server.create(allocator, .{
        .socket_path = full_path,
        .state = &state,
        .handler = struct {
            fn handle(s: *anyopaque, req: ipc.message.Request) ipc.message.Response {
                return @as(*State, @ptrCast(@alignCast(s))).handleRequest(req);
            }
        }.handle,
    });
    defer ipc_server.destroy();

    std.log.info("KidulWM: IPC server ready", .{});

    var tick_count: usize = 0;
    while (tick_count < tick_limit) : (tick_count += 1) {
        try ipc_server.tick();
        var ts = std.posix.timespec{
            .sec = 0,
            .nsec = 100 * std.time.ns_per_ms,
        };
        _ = linux.nanosleep(&ts, null);
    }

    std.log.info("KidulWM: shutdown", .{});
}
