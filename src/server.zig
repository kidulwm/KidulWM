const std = @import("std");
const linux = std.os.linux;
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const ipc = @import("ipc.zig");

pub const Server = struct {
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    wl_server: *wl.Server,
    backend: *wlr.Backend,
    output_layout: *wlr.OutputLayout,
    ipc_server: ipc.control.Server,
    ipc_thread: ?std.Thread,
    ipc_running: std.atomic.Value(bool),
    output_manager: *wlr.OutputManagerV1,
    state: State,

    layout_requested: std.atomic.Value(bool),

    new_output: wl.Listener(*wlr.Output),
    backend_destroy: wl.Listener(*wlr.Backend),

    pub const State = struct {
        gap: u32 = 8,
        left_peek: f32 = 0.08,
        focus: f32 = 0.94,
        right_peek: f32 = 0.08,
        focused_window: u32 = 0,

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

    pub fn init(allocator: std.mem.Allocator) !Server {
        const wl_server = try wl.Server.create();
        errdefer wl_server.destroy();

        const event_loop = wl_server.getEventLoop();

        const backend = wlr.Backend.autocreate(event_loop, null) catch |err| {
            std.log.warn("wlroots backend autocreate failed ({}); falling back to headless skeleton", .{err});
            return error.BackendCreateFailed;
        };
        errdefer backend.destroy();

        const output_layout = try wlr.OutputLayout.create(wl_server);
        errdefer output_layout.destroy();

        const output_manager = try wlr.OutputManagerV1.create(wl_server);

        var self = Server{
            .allocator = allocator,
            .socket_path = &.{},
            .wl_server = wl_server,
            .backend = backend,
            .output_layout = output_layout,
            .ipc_server = undefined,
            .ipc_thread = null,
            .ipc_running = std.atomic.Value(bool).init(false),
            .output_manager = output_manager,
            .state = .{},
            .layout_requested = std.atomic.Value(bool).init(false),
            .new_output = undefined,
            .backend_destroy = undefined,
        };

        self.new_output = wl.Listener(*wlr.Output).init(handleNewOutput);
        backend.events.new_output.add(&self.new_output);

        self.backend_destroy = wl.Listener(*wlr.Backend).init(handleBackendDestroy);
        backend.events.destroy.add(&self.backend_destroy);

        return self;
    }

    pub fn createIpcSocket(self: *Server, path: []const u8) !void {
        self.socket_path = path;
        self.ipc_server = try ipc.control.Server.create(self.allocator, .{
            .socket_path = path,
            .state = &self.state,
            .handler = struct {
                fn handle(s: *anyopaque, req: ipc.message.Request) ipc.message.Response {
                    return @as(*Server, @ptrCast(@alignCast(s))).state.handleRequest(req);
                }
            }.handle,
        });

        self.ipc_running.store(true, .monotonic);
        self.ipc_thread = try std.Thread.spawn(.{}, ipcThreadLoop, .{self});
    }

    pub fn start(self: *Server, no_backend: bool) !void {
        if (!no_backend) {
            try self.backend.start();
            std.log.info("KidulWM: backend started", .{});
        } else {
            std.log.info("KidulWM: skipping backend start", .{});
            _ = try self.wl_server.getEventLoop().addTimer(
                *@This(),
                handleShutdownTimer,
                self,
            );
        }

        var socket_name: [11]u8 = undefined;
        const name = try self.wl_server.addSocketAuto(&socket_name);
        std.log.info("KidulWM: Wayland socket {s}", .{name});

        self.wl_server.run();
    }

    pub fn deinit(self: *Server) void {
        if (self.ipc_thread) |thread| {
            self.ipc_running.store(false, .monotonic);
            thread.join();
            self.ipc_thread = null;
        }
        self.ipc_server.destroy();
        self.output_layout.destroy();
        self.backend.destroy();
        self.wl_server.destroy();
    }

    fn ipcThreadLoop(self: *Server) void {
        std.log.info("KidulWM: IPC thread started", .{});
        while (self.ipc_running.load(.monotonic)) {
            self.ipc_server.tick() catch |err| {
                std.log.err("ipc tick error: {}", .{err});
            };
            var ts = std.posix.timespec{ .sec = 0, .nsec = 10 * std.time.ns_per_ms };
            _ = linux.nanosleep(&ts, null);
        }
        std.log.info("KidulWM: IPC thread stopping", .{});
    }

    fn handleNewOutput(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
        const self: *Server = @fieldParentPtr("new_output", listener);
        std.log.info("KidulWM: new output {s} {d}x{d}", .{ wlr_output.name, wlr_output.width, wlr_output.height });
        _ = self.output_layout.addAuto(wlr_output) catch |err| {
            std.log.err("failed to add output to layout: {}", .{err});
            return;
        };
        std.log.info("KidulWM: output added to layout", .{});
    }

    fn handleBackendDestroy(listener: *wl.Listener(*wlr.Backend), backend: *wlr.Backend) void {
        const self: *Server = @fieldParentPtr("backend_destroy", listener);
        _ = self;
        _ = backend;
        std.log.info("KidulWM: backend destroyed", .{});
    }

    fn handleShutdownTimer(server: *@This()) c_int {
        server.wl_server.terminate();
        return 0;
    }
};
