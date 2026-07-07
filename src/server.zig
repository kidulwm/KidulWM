const std = @import("std");
const linux = std.os.linux;
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const ipc = @import("ipc.zig");
const Window = @import("window.zig").Window;
const InputManager = @import("input.zig").InputManager;
const PointerManager = @import("input/pointer.zig").PointerManager;
const KeyboardManager = @import("input/keyboard.zig").KeyboardManager;
const TrayManager = @import("tray.zig").TrayManager;
const style = @import("core/style.zig");
const layout = @import("core/layout.zig");

const InputDeviceCounts = packed struct { pointer: u32 = 0, keyboard: u32 = 0 };

pub const Server = struct {
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    wl_server: *wl.Server,
    backend: *wlr.Backend,
    renderer: *wlr.Renderer,
    renderer_allocator: *wlr.Allocator,
    compositor: *wlr.Compositor,
    scene: *wlr.Scene,
    output_layout: *wlr.OutputLayout,
    scene_output_layout: *wlr.SceneOutputLayout,
    xdg_shell: *wlr.XdgShell,
    output_manager: *wlr.OutputManagerV1,

    shm: *wlr.Shm,
    subcompositor: *wlr.Subcompositor,
    data_device_manager: *wlr.DataDeviceManager,
    viewporter: *wlr.Viewporter,
    fractional_scale_manager: *wlr.FractionalScaleManagerV1,

    seat: *wlr.Seat,
    input_manager: InputManager,
    pointer: PointerManager,
    keyboard: KeyboardManager,
    cursor_x: f64,
    cursor_y: f64,

    ipc_server: ipc.control.Server,
    ipc_thread: ?std.Thread,
    ipc_running: std.atomic.Value(bool),

    state: State,
    windows: wl.list.Head(Window, .link),

    layout: layout.LayoutModel,
    layout_pipe: [2]c_int,
    layout_source: *wl.EventSource,
    layout_requested: std.atomic.Value(bool),

    focused_window: ?*Window,
    input_device_counts: InputDeviceCounts,

    tray: *TrayManager,

    new_output: wl.Listener(*wlr.Output),
    backend_destroy: wl.Listener(*wlr.Backend),
    new_xdg_toplevel: wl.Listener(*wlr.XdgToplevel),
    output_layout_change: wl.Listener(*wlr.OutputLayout),

    background: struct {
        rect: ?*wlr.SceneRect,
        color: [4]f32,
    },

    fn handleRequest(self: *Server, req: ipc.message.Request) ipc.message.Response {
        switch (req) {
            .quit => self.requestQuit(),
            .get_layout => return self.getLayoutResponse(),
            else => return self.state.handleRequest(req),
        }
        return self.state.handleRequest(req);
    }

    pub const State = struct {
        gap: u32 = style.layout.gap,
        left_peek: f32 = style.layout.default_split.left_peek,
        focus: f32 = style.layout.default_split.focus,
        right_peek: f32 = style.layout.default_split.right_peek,
        focused_window: u32 = 0,
        orientation: layout.Orientation = .horizontal,

        pub fn applyPreset(
            state: *State,
            preset: style.layout.SplitPreset,
            orientation: layout.Orientation,
            focused_window: u32,
        ) void {
            state.orientation = orientation;
            state.left_peek = preset.left_peek;
            state.focus = preset.focus;
            state.right_peek = preset.right_peek;
            state.focused_window = focused_window;
        }

        pub fn handleRequest(state: *State, req: ipc.message.Request) ipc.message.Response {
            switch (req) {
                .ping => return .{ .ok = true, .message = "pong" },
                .get_layout => return .{ .ok = true, .message = "layout data pending" },
                .set_gap => |p| state.gap = p.gap,
                .set_split => |p| {
                    state.left_peek = p.left_peek;
                    state.focus = p.focus;
                    state.right_peek = p.right_peek;
                    state.orientation = layout.LayoutModel.orientationFromSplit(
                        state.left_peek,
                        state.right_peek,
                    );
                },
                .split_left => {
                    state.applyPreset(style.layout.horizontal_split, .horizontal, 1);
                },
                .split_right => {
                    state.applyPreset(style.layout.horizontal_split, .horizontal, 2);
                },
                .split_top => {
                    state.applyPreset(style.layout.vertical_top_split, .vertical, 1);
                },
                .split_bottom => {
                    state.applyPreset(style.layout.vertical_bottom_split, .vertical, 1);
                },
                .set_focus => |p| state.focused_window = p.window_id,
                .set_theme => |p| {
                    std.log.info("theme update: {s} = {s}", .{ p.key, p.value });
                    return .{ .ok = true, .message = "theme updated" };
                },
                .subscribe => return .{ .ok = true, .message = "subscription registered" },
                .quit => {},
            }
            return .{ .ok = true };
        }
    };

    pub fn init(allocator: std.mem.Allocator) !*Server {
        const server = try allocator.create(Server);
        errdefer allocator.destroy(server);

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

        const renderer = try wlr.Renderer.autocreate(backend);
        try renderer.initServer(wl_server);

        const renderer_allocator = try wlr.Allocator.autocreate(backend, renderer);

        const output_manager = try wlr.OutputManagerV1.create(wl_server);
        const compositor = try wlr.Compositor.create(wl_server, 6, renderer);
        const scene = try wlr.Scene.create();
        const scene_output_layout = try scene.attachOutputLayout(output_layout);
        const xdg_shell = try wlr.XdgShell.create(wl_server, 6);
        const shm = try wlr.Shm.createWithRenderer(wl_server, 1, renderer);
        const subcompositor = try wlr.Subcompositor.create(wl_server);
        const data_device_manager = try wlr.DataDeviceManager.create(wl_server);
        const viewporter = try wlr.Viewporter.create(wl_server);
        const fractional_scale_manager = try wlr.FractionalScaleManagerV1.create(wl_server, 1);

        const seat = try wlr.Seat.create(wl_server, "seat0");
        seat.setCapabilities(.{ .pointer = true, .keyboard = true });

        server.* = Server{
            .allocator = allocator,
            .socket_path = &.{},
            .wl_server = wl_server,
            .backend = backend,
            .renderer = renderer,
            .renderer_allocator = renderer_allocator,
            .compositor = compositor,
            .scene = scene,
            .output_layout = output_layout,
            .scene_output_layout = scene_output_layout,
            .xdg_shell = xdg_shell,
            .output_manager = output_manager,
            .shm = shm,
            .subcompositor = subcompositor,
            .data_device_manager = data_device_manager,
            .viewporter = viewporter,
            .fractional_scale_manager = fractional_scale_manager,
            .seat = seat,
            .input_manager = undefined,
            .pointer = undefined,
            .keyboard = undefined,
            .cursor_x = 0,
            .cursor_y = 0,
            .input_device_counts = .{},
            .focused_window = null,
            .tray = undefined,
            .ipc_server = undefined,
            .ipc_thread = null,
            .ipc_running = std.atomic.Value(bool).init(false),
            .state = .{},
            .windows = undefined,
            .layout_requested = std.atomic.Value(bool).init(false),
            .layout = layout.LayoutModel.create(allocator),
            .layout_pipe = undefined,
            .layout_source = undefined,
            .new_output = undefined,
            .backend_destroy = undefined,
            .new_xdg_toplevel = undefined,
            .output_layout_change = undefined,
            .background = .{
                .rect = null,
                .color = style.default_style.color_background.toF32(),
            },
        };

        server.background.rect = try server.scene.tree.createSceneRect(1, 1, &server.background.color);

        server.pointer = PointerManager.init(server);
        server.keyboard = KeyboardManager.init(server);
        server.windows.init();
        server.input_manager = InputManager.init(server);

        server.new_output = wl.Listener(*wlr.Output).init(handleNewOutput);
        server.new_output.link.init();
        backend.events.new_output.add(&server.new_output);

        server.backend_destroy = wl.Listener(*wlr.Backend).init(handleBackendDestroy);
        server.backend_destroy.link.init();
        backend.events.destroy.add(&server.backend_destroy);

        server.new_xdg_toplevel = wl.Listener(*wlr.XdgToplevel).init(handleNewXdgToplevel);
        server.new_xdg_toplevel.link.init();
        xdg_shell.events.new_toplevel.add(&server.new_xdg_toplevel);

        server.output_layout_change = wl.Listener(*wlr.OutputLayout).init(handleOutputLayoutChange);
        server.output_layout_change.link.init();
        output_layout.events.change.add(&server.output_layout_change);

        server.layout_pipe = blk: {
            var fds: [2]c_int = undefined;
            const rc = linux.pipe(&fds);
            if (rc != 0) return error.PipeCreateFailed;
            break :blk fds;
        };
        server.layout_source = try event_loop.addFd(*Server, server.layout_pipe[0], .{ .readable = true }, handleLayoutEventFd, server);

        server.tray = try server.allocator.create(TrayManager);
        try TrayManager.init(server, server.tray);

        return server;
    }

    pub fn createIpcSocket(self: *Server, path: []const u8) !void {
        self.socket_path = path;
        self.ipc_server = try ipc.control.Server.create(self.allocator, .{
            .socket_path = path,
            .state = self,
            .handler = struct {
                fn handle(s: *anyopaque, req: ipc.message.Request) ipc.message.Response {
                    return @as(*Server, @ptrCast(@alignCast(s))).handleRequest(req);
                }
            }.handle,
        });

        self.ipc_running.store(true, .monotonic);
        self.ipc_thread = try std.Thread.spawn(.{}, ipcThreadLoop, .{self});
    }

    pub fn start(self: *Server, no_backend: bool, maybe_socket_name: ?[:0]const u8) !void {
        const name = if (maybe_socket_name) |socket_name| blk: {
            try self.wl_server.addSocket(socket_name);
            break :blk socket_name;
        } else blk: {
            var socket_name: [11]u8 = undefined;
            const n = try self.wl_server.addSocketAuto(&socket_name);
            break :blk n;
        };
        std.log.info("KidulWM: Wayland socket {s}", .{name});

        if (!no_backend) {
            try self.backend.start();
            std.log.info("KidulWM: backend started", .{});
        } else {
            std.log.info("KidulWM: skipping backend start", .{});
            const event_loop = self.wl_server.getEventLoop();
            const shutdown_source = try event_loop.addTimer(*@This(), handleShutdownTimer, self);
            try shutdown_source.timerUpdate(8000);
        }

        self.wl_server.run();
    }

    pub fn deinit(self: *Server) void {
        if (self.ipc_thread) |thread| {
            self.ipc_running.store(false, .monotonic);
            thread.join();
            self.ipc_thread = null;
        }
        self.ipc_server.destroy();

        self.input_manager.deinit();
        self.layout.deinit();

        _ = linux.close(self.layout_pipe[0]);
        _ = linux.close(self.layout_pipe[1]);

        self.output_layout_change.link.remove();
        self.output_layout.destroy();

        self.new_output.link.remove();
        self.backend.destroy();

        self.tray.deinit();
        self.allocator.destroy(self.tray);
        self.wl_server.destroy();
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    pub fn requestLayout(self: *Server) void {
        const was_requested = self.layout_requested.swap(true, .acquire);
        if (was_requested) return;
        _ = linux.write(self.layout_pipe[1], &[_]u8{1}, 1);
    }

    pub fn requestUpdateCapabilities(self: *Server) void {
        self.seat.setCapabilities(.{
            .pointer = self.input_device_counts.pointer > 0,
            .keyboard = self.input_device_counts.keyboard > 0,
        });
    }

    fn getLayoutResponse(self: *Server) ipc.message.Response {
        const window_count = self.windows.length();
        return .{
            .ok = true,
            .layout = ipc.message.LayoutResponse{
                .orientation = if (self.state.orientation == .horizontal) "horizontal" else "vertical",
                .gap = self.state.gap,
                .left_peek = self.state.left_peek,
                .focus = self.state.focus,
                .right_peek = self.state.right_peek,
                .focused_window = self.state.focused_window,
                .window_count = window_count,
            },
        };
    }

    pub fn focusWindow(self: *Server, window: *Window) void {
        if (self.focused_window == window) return;
        self.focused_window = window;
        window.focus(self.seat);
    }

    pub fn focusAtCursor(self: *Server) void {
        var it = self.windows.iterator(.forward);
        while (it.next()) |window| {
            const node = &window.scene_tree.node;
            if (!node.enabled) continue;
            var nx: f64 = undefined;
            var ny: f64 = undefined;
            if (node.at(self.cursor_x, self.cursor_y, &nx, &ny)) |_| {
                self.focusWindow(window);
                return;
            }
        }
    }

    fn applyLayout(self: *Server) void {
        self.layout_requested.store(false, .monotonic);
        if (self.output_layout.outputs.length() == 0) return;

        const layout_output = self.output_layout.outputs.first() orelse return;
        const wlr_output = layout_output.output;
        const width = @as(u32, @intCast(wlr_output.width));
        const height = @as(u32, @intCast(wlr_output.height));

        if (self.layout.outputs.items.len == 0) {
            self.layout = layout.LayoutModel.init(self.allocator, width, height, self.state.gap) catch |err| {
                std.log.err("layout model init failed: {}", .{err});
                return;
            };
        }
        const output = &self.layout.outputs.items[0];

        const window_count = self.windows.length();
        if (window_count == 0 or self.state.focused_window >= window_count) {
            self.focused_window = null;
            return;
        }

        _ = layout.LayoutModel.sync(
            output,
            width,
            height,
            self.state.gap,
            self.state.left_peek,
            self.state.focus,
            self.state.right_peek,
            @as(i32, @intCast(self.state.focused_window)),
            self.state.orientation,
        );

        var it = self.windows.iterator(.forward);
        var col_idx: usize = 0;
        var window_to_focus: ?*Window = null;
        while (it.next()) |window| : (col_idx += 1) {
            if (col_idx >= output.columns.items.len) break;
            const target = layout.LayoutModel.columnTarget(output, col_idx);
            window.scene_tree.node.setPosition(@intCast(target.x), @intCast(target.y));
            _ = window.toplevel.setSize(@intCast(target.width), @intCast(target.height));
            if (col_idx == self.state.focused_window) {
                window_to_focus = window;
            }
        }

        if (window_to_focus) |window| {
            self.focusWindow(window);
        }
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

    fn handleLayoutEventFd(_fd: c_int, _mask: wl.EventMask, server: *Server) c_int {
        _ = _fd;
        _ = _mask;
        var buf: [16]u8 = undefined;
        _ = linux.read(server.layout_pipe[0], &buf, buf.len);
        server.applyLayout();
        return 0;
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
        self.tray.arrange();
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

    fn handleOutputLayoutChange(listener: *wl.Listener(*wlr.OutputLayout), output_layout_arg: *wlr.OutputLayout) void {
        const self: *Server = @fieldParentPtr("output_layout_change", listener);
        _ = output_layout_arg;

        var box: wlr.Box = undefined;
        self.output_layout.getBox(null, &box);
        if (self.background.rect) |rect| {
            rect.node.setPosition(box.x, box.y);
            rect.setSize(box.width, box.height);
        }

        self.requestLayout();
        self.tray.arrange();
    }

    fn handleShutdownTimer(server: *@This()) c_int {
        server.wl_server.terminate();
        return 0;
    }

    fn requestQuit(self: *Server) void {
        const event_loop = self.wl_server.getEventLoop();
        const source = event_loop.addTimer(*@This(), handleShutdownTimer, self) catch |err| {
            std.log.err("failed to schedule quit timer: {}", .{err});
            return;
        };
        source.timerUpdate(1) catch |err| {
            std.log.err("failed to arm quit timer: {}", .{err});
        };
    }
};
