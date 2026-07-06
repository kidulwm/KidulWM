const std = @import("std");
const linux = std.os.linux;
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const ipc = @import("ipc.zig");
const Window = @import("window.zig").Window;

pub const Server = struct {
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    wl_server: *wl.Server,
    backend: *wlr.Backend,
    compositor: *wlr.Compositor,
    scene: *wlr.Scene,
    output_layout: *wlr.OutputLayout,
    scene_output_layout: *wlr.SceneOutputLayout,
    xdg_shell: *wlr.XdgShell,
    output_manager: *wlr.OutputManagerV1,

    ipc_server: ipc.control.Server,
    ipc_thread: ?std.Thread,
    ipc_running: std.atomic.Value(bool),

    state: State,
    windows: wl.list.Head(Window, .link),

    layout_requested: std.atomic.Value(bool),

    new_output: wl.Listener(*wlr.Output),
    backend_destroy: wl.Listener(*wlr.Backend),
    new_xdg_toplevel: wl.Listener(*wlr.XdgToplevel),
    output_layout_change: wl.Listener(*wlr.OutputLayout),

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
        const compositor = try wlr.Compositor.create(wl_server, 6, null);
        const scene = try wlr.Scene.create();
        const scene_output_layout = try scene.attachOutputLayout(output_layout);
        const xdg_shell = try wlr.XdgShell.create(wl_server, 6);

        var self = Server{
            .allocator = allocator,
            .socket_path = &.{},
            .wl_server = wl_server,
            .backend = backend,
            .compositor = compositor,
            .scene = scene,
            .output_layout = output_layout,
            .scene_output_layout = scene_output_layout,
            .xdg_shell = xdg_shell,
            .output_manager = output_manager,
            .ipc_server = undefined,
            .ipc_thread = null,
            .ipc_running = std.atomic.Value(bool).init(false),
            .state = .{},
            .windows = undefined,
            .layout_requested = std.atomic.Value(bool).init(false),
            .new_output = undefined,
            .backend_destroy = undefined,
            .new_xdg_toplevel = undefined,
            .output_layout_change = undefined,
        };
        self.windows.init();

        self.new_output = wl.Listener(*wlr.Output).init(handleNewOutput);
        backend.events.new_output.add(&self.new_output);

        self.backend_destroy = wl.Listener(*wlr.Backend).init(handleBackendDestroy);
        backend.events.destroy.add(&self.backend_destroy);

        self.new_xdg_toplevel = wl.Listener(*wlr.XdgToplevel).init(handleNewXdgToplevel);
        xdg_shell.events.new_toplevel.add(&self.new_xdg_toplevel);

        self.output_layout_change = wl.Listener(*wlr.OutputLayout).init(handleOutputLayoutChange);
        output_layout.events.change.add(&self.output_layout_change);

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

    pub fn requestLayout(self: *Server) void {
        self.layout_requested.store(true, .monotonic);
    }

    fn applyLayout(self: *Server) void {
        self.layout_requested.store(false, .monotonic);
        if (self.output_layout.outputs.length() == 0) return;

        const layout_output = self.output_layout.outputs.first() orelse return;
        const wlr_output = layout_output.output;
        const width = wlr_output.width;
        const height = wlr_output.height;

        const allocator = self.allocator;
        var model = @import("core/layout.zig").LayoutModel.createFromOutput(allocator, @intCast(width), @intCast(height), self.state.gap) catch |err| {
            std.log.err("layout model failed: {}", .{err});
            return;
        };
        defer model.deinit();

        const split = @import("core/layout.zig").Split{
            .left_peek = self.state.left_peek,
            .focus = self.state.focus,
            .right_peek = self.state.right_peek,
        };

        var it = self.windows.iterator(.forward);
        var col_idx: usize = 0;
        while (it.next()) |window| : (col_idx += 1) {
            if (col_idx >= 3) break;
            const target = @import("core/layout.zig").LayoutModel.columnTarget(&model.outputs.items[0], @intCast(col_idx), split.left_peek, split.focus, split.right_peek);
            window.scene_tree.node.setPosition(@intCast(target.x), @intCast(target.y));
            _ = window.toplevel.setSize(@intCast(target.width), @intCast(target.height));
        }
    }

    fn ipcThreadLoop(self: *Server) void {
        std.log.info("KidulWM: IPC thread started", .{});
        while (self.ipc_running.load(.monotonic)) {
            self.ipc_server.tick() catch |err| {
                std.log.err("ipc tick error: {}", .{err});
            };
            if (self.layout_requested.load(.monotonic)) {
                self.applyLayout();
            }
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
        _ = self.scene.createSceneOutput(wlr_output) catch |err| {
            std.log.err("scene output create failed: {}", .{err});
            return;
        };
        std.log.info("KidulWM: output added to layout", .{});
        self.requestLayout();
    }

    fn handleBackendDestroy(listener: *wl.Listener(*wlr.Backend), backend: *wlr.Backend) void {
        const self: *Server = @fieldParentPtr("backend_destroy", listener);
        _ = self;
        _ = backend;
        std.log.info("KidulWM: backend destroyed", .{});
    }

    fn handleNewXdgToplevel(listener: *wl.Listener(*wlr.XdgToplevel), toplevel: *wlr.XdgToplevel) void {
        const self: *Server = @fieldParentPtr("new_xdg_toplevel", listener);
        std.log.info("KidulWM: new toplevel", .{});
        const window = Window.create(self, toplevel) catch |err| {
            std.log.err("failed to create window for toplevel: {}", .{err});
            return;
        };
        self.windows.append(window);
    }

    fn handleOutputLayoutChange(listener: *wl.Listener(*wlr.OutputLayout), output_layout: *wlr.OutputLayout) void {
        const self: *Server = @fieldParentPtr("output_layout_change", listener);
        _ = output_layout;
        self.requestLayout();
    }

    fn handleShutdownTimer(server: *@This()) c_int {
        server.wl_server.terminate();
        return 0;
    }
};
