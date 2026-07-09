const std = @import("std");
const linux = std.os.linux;
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const ipc = @import("ipc.zig");
const Window = @import("window.zig").Window;
const InputManager = @import("input.zig").InputManager;
const PointerManager = @import("input/pointer.zig").PointerManager;
const KeyboardManager = @import("input/keyboard.zig").KeyboardManager;
const style = @import("core/style.zig");
const slidedeck = @import("core/slidedeck.zig");
const animation = @import("core/animation.zig");

const InputDeviceCounts = packed struct { pointer: u32 = 0, keyboard: u32 = 0 };

pub const Output = struct {
    server: *Server,
    wlr_output: *wlr.Output,
    scene_output: *wlr.SceneOutput,
    link: wl.list.Link,
    frame: wl.Listener(*wlr.Output),
    destroy: wl.Listener(*wlr.Output),
    deck: slidedeck.SlideDeck,

    pub fn init(self: *Output, server: *Server, wlr_output: *wlr.Output, scene_output: *wlr.SceneOutput) void {
        self.* = .{
            .server = server,
            .wlr_output = wlr_output,
            .scene_output = scene_output,
            .link = undefined,
            .frame = wl.Listener(*wlr.Output).init(handleFrame),
            .destroy = wl.Listener(*wlr.Output).init(handleDestroy),
            .deck = slidedeck.SlideDeck.init(server.allocator),
        };
        server.outputs.append(self);
        wlr_output.events.frame.add(&self.frame);
        wlr_output.events.destroy.add(&self.destroy);
    }

    pub fn deinit(self: *Output) void {
        self.frame.link.remove();
        self.destroy.link.remove();
        self.deck.deinit();
    }

    fn handleFrame(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
        const self: *Output = @fieldParentPtr("frame", listener);
        _ = wlr_output;
        const now_us = animation.nowUs();
        var it = self.server.windows.iterator(.forward);
        while (it.next()) |window| {
            _ = window.tickAnimation(now_us);
        }
        var ts: linux.timespec = undefined;
        _ = linux.clock_gettime(linux.CLOCK.MONOTONIC, &ts);
        const ok = self.scene_output.commit(null);
        if (!ok) {
            std.log.warn("KidulWM: scene output commit failed, skipping frame done", .{});
            return;
        }
        self.scene_output.sendFrameDone(@ptrCast(&ts));
    }

    fn handleDestroy(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
        const self: *Output = @fieldParentPtr("destroy", listener);
        self.link.remove();
        self.deinit();
        self.server.allocator.destroy(self);
        _ = wlr_output;
    }
};

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
    cursor: *wlr.Cursor,
    input_manager: *InputManager,
    pointer: PointerManager,
    keyboard: KeyboardManager,
    cursor_x: f64,
    cursor_y: f64,

    ipc_server: ipc.control.Server,
    ipc_thread: ?std.Thread,
    ipc_running: std.atomic.Value(bool),

    state: State,
    theme: style.Style,
    deck_split: slidedeck.Split,
    deck_orientation: slidedeck.Orientation,
    windows: wl.list.Head(Window, .link),

    deck: slidedeck.SlideDeck,
    layout_pipe: [2]c_int,
    layout_source: *wl.EventSource,
    layout_requested: std.atomic.Value(bool),

    focused_window: ?*Window,
    focused_window_id: u32 = 0,
    focused_output: ?*Output = null,
    next_window_id: u32 = 1,
    input_device_counts: InputDeviceCounts,
    backend_started: bool = false,

    new_output: wl.Listener(*wlr.Output),
    backend_destroy: wl.Listener(*wlr.Backend),
    new_xdg_toplevel: wl.Listener(*wlr.XdgToplevel),
    output_layout_change: wl.Listener(*wlr.OutputLayout),

    background: struct {
        rect: ?*wlr.SceneRect,
        color: [4]f32,
    },
    outputs: wl.list.Head(Output, .link),

    fn handleRequest(self: *Server, req: ipc.message.Request) ipc.message.Response {
        switch (req) {
            .quit => self.requestQuit(),
            .get_layout => return self.getLayoutResponse(),
            .set_focus => |p| {
                self.focusWindowByIndex(p.window_id);
                return .{ .ok = true };
            },
            .focus_next => {
                self.focusNext();
                return .{ .ok = true };
            },
            .focus_prev => {
                self.focusPrev();
                return .{ .ok = true };
            },
            .set_theme => |p| {
                std.log.info("theme update: {s} = {s}", .{ p.key, p.value });
                self.applyTheme(p.key, p.value);
                return .{ .ok = true, .message = "theme updated" };
            },
            else => return self.handleStateRequest(req),
        }
        return self.handleStateRequest(req);
    }

    pub const State = struct {
        gap: u32 = style.layout.gap,
    };

    /// Convert IPC split ratios + orientation into a Deck Split.  The deck owns
    /// the authoritative split state so all placement math stays in one place.
    fn splitFromRequest(self: *const Server, left_peek: f32, focus: f32, right_peek: f32) slidedeck.Split {
        _ = self;
        return .{ .left_peek = left_peek, .focus = focus, .right_peek = right_peek };
    }

    fn handleStateRequest(self: *Server, req: ipc.message.Request) ipc.message.Response {
        switch (req) {
            .ping => return .{ .ok = true, .message = "pong" },
            .get_layout => return self.getLayoutResponse(),
            .set_gap => |p| {
                self.state.gap = p.gap;
            },
            .set_split => |p| {
                self.deck_split = self.splitFromRequest(p.left_peek, p.focus, p.right_peek);
            },
            .split_left => self.deck_split = self.splitFromRequest(
                style.layout.horizontal_split.left_peek,
                style.layout.horizontal_split.focus,
                style.layout.horizontal_split.right_peek,
            ),
            .split_right => self.deck_split = self.splitFromRequest(
                style.layout.horizontal_split.right_peek,
                style.layout.horizontal_split.focus,
                style.layout.horizontal_split.left_peek,
            ),
            .split_top => {
                self.deck_split = self.splitFromRequest(
                    style.layout.vertical_top_split.left_peek,
                    style.layout.vertical_top_split.focus,
                    style.layout.vertical_top_split.right_peek,
                );
                self.deck_orientation = .vertical;
            },
            .split_bottom => {
                self.deck_split = self.splitFromRequest(
                    style.layout.vertical_bottom_split.left_peek,
                    style.layout.vertical_bottom_split.focus,
                    style.layout.vertical_bottom_split.right_peek,
                );
                self.deck_orientation = .vertical;
            },
            .set_focus => {}, // handled at handleRequest level
            .focus_next => self.currentDeck().focusNext(),
            .focus_prev => self.currentDeck().focusPrev(),
            .subscribe => return .{ .ok = true, .message = "subscription registered" },
            .set_theme, .quit => {},
        }
        self.requestLayout();
        return .{ .ok = true };
    }

    pub fn init(allocator: std.mem.Allocator, force_pixman: bool) !*Server {
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

        const renderer = if (force_pixman)
            try wlr.Renderer.createPixman()
        else
            try wlr.Renderer.autocreate(backend);
        try renderer.initServer(wl_server);
        std.log.info("KidulWM: renderer pixman={} gles2={}", .{ renderer.isPixman(), renderer.isGles2() });

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

        const cursor = try wlr.Cursor.create();
        cursor.attachOutputLayout(output_layout);

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
            .cursor = cursor,
            .input_manager = undefined,
            .pointer = undefined,
            .keyboard = undefined,
            .cursor_x = 0,
            .cursor_y = 0,
            .input_device_counts = .{},
            .focused_window = null,
            .ipc_server = undefined,
            .ipc_thread = null,
            .ipc_running = std.atomic.Value(bool).init(false),
            .state = .{},
            .theme = style.default(),
            .deck_split = .{
                .left_peek = style.layout.horizontal_split.left_peek,
                .focus = style.layout.horizontal_split.focus,
                .right_peek = style.layout.horizontal_split.right_peek,
            },
            .deck_orientation = .horizontal,
            .windows = undefined,
            .layout_requested = std.atomic.Value(bool).init(false),
            .deck = slidedeck.SlideDeck.init(allocator),
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
            .outputs = undefined,
        };

        server.outputs.init();

        server.background.rect = try server.scene.tree.createSceneRect(1, 1, &server.background.color);

        server.pointer.init(server);
        server.keyboard.init(server);
        server.windows.init();
        server.input_manager = try server.allocator.create(InputManager);
        InputManager.init(server.input_manager, server);

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
            self.backend_started = true;
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
        // Disconnect all clients before tearing down globals, otherwise
        // wl_display_destroy asserts if clients are still connected.
        self.wl_server.destroyClients();

        if (self.ipc_thread) |thread| {
            self.ipc_running.store(false, .monotonic);
            thread.join();
            self.ipc_thread = null;
        }
        self.ipc_server.destroy();

        self.input_manager.deinit();
        self.allocator.destroy(self.input_manager);
        self.pointer.deinit();
        self.keyboard.deinit();
        self.deck.deinit();

        _ = linux.close(self.layout_pipe[0]);
        _ = linux.close(self.layout_pipe[1]);

        // Tear down outputs before the scene and layout that back them.
        while (self.outputs.first()) |output| {
            output.link.remove();
            output.deinit();
            self.allocator.destroy(output);
        }

        self.output_layout_change.link.remove();
        self.new_xdg_toplevel.link.remove();
        self.new_output.link.remove();
        self.backend_destroy.link.remove();

        self.cursor.destroy();

        // scene/scene_output_layout and most globals do not expose destroy()
        // wrappers in this zig-wlroots version; the display teardown frees them.
        // Destroy only the singletons that have explicit wrappers.
        self.seat.destroy();
        // output_manager has no explicit destroy wrapper in this version.
        self.output_layout.destroy();

        if (self.backend_started) {
            self.backend.destroy();
        } else {
            std.log.info("KidulWM: backend was not started, skipping destroy", .{});
        }

        self.renderer_allocator.destroy();
        self.renderer.destroy();
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
        const deck = self.currentDeck();
        return .{
            .ok = true,
            .layout = ipc.message.LayoutResponse{
                .orientation = if (self.deck_orientation == .horizontal) "horizontal" else "vertical",
                .gap = self.state.gap,
                .left_peek = self.deck_split.left_peek,
                .focus = self.deck_split.focus,
                .right_peek = self.deck_split.right_peek,
                .focused_window = @intCast(deck.focused_index),
                .window_count = window_count,
                .slide_count = @intCast(deck.slides.items.len),            },
        };
    }

    fn syncDeckFocus(self: *Server) void {
        const focused = self.focused_window orelse return;
        const deck = self.deckForWindow(focused);
        for (deck.slides.items, 0..) |slide, i| {
            if (slide.window_id == self.focused_window_id) {
                deck.focused_index = i;
                return;
            }
        }
    }

    pub fn focusWindowByIndex(self: *Server, idx: usize) void {
        const deck = self.currentDeck();
        if (idx >= deck.slides.items.len) return;
        deck.focused_index = idx;
        self.focused_window_id = deck.slides.items[idx].window_id;
        const window = self.windowById(self.focused_window_id) orelse return;
        if (window.toplevel.base.surface.mapped) {
            self.focusWindow(window);
            self.requestLayout();
        }
    }



    /// Return the deck that owns a window.  Windows created before any output
    /// exist fall back to the server-level deck so headless/smoke tests still run.
    pub fn deckForWindow(self: *Server, window: *Window) *slidedeck.SlideDeck {
        if (window.output) |output| return &output.deck;
        return &self.deck;
    }

    /// Return the deck currently receiving focus commands.
    fn currentDeck(self: *Server) *slidedeck.SlideDeck {
        if (self.focused_window) |window| {
            if (window.output) |output| return &output.deck;
        }
        if (self.focused_output) |output| return &output.deck;
        if (self.outputs.first()) |output| return &output.deck;
        return &self.deck;
    }

    /// Assign a window to the best available output when it maps.
    pub fn assignOutput(self: *Server, window: *Window) void {
        if (window.output != null) return;
        if (self.focused_output) |output| {
            window.output = output;
            return;
        }
        if (self.outputs.first()) |output| {
            window.output = output;
            return;
        }
    }
    /// Find a window by its stable deck id.
    pub fn windowById(self: *Server, id: u32) ?*Window {
        var it = self.windows.iterator(.forward);
        while (it.next()) |window| {
            if (window.id == id) return window;
        }
        return null;
    }

    /// Focus the next mapped window in the list, wrapping around.
    pub fn focusNext(self: *Server) void {
        const deck = self.currentDeck();
        if (deck.slides.items.len == 0) return;
        deck.focusNext();
        const slide = deck.slides.items[deck.focused_index];
        self.focused_window_id = slide.window_id;
        const window = self.windowById(slide.window_id) orelse return;
        if (window.toplevel.base.surface.mapped) {
            self.focusWindow(window);
            self.requestLayout();
        }
    }
    pub fn focusPrev(self: *Server) void {
        const deck = self.currentDeck();
        if (deck.slides.items.len == 0) return;
        deck.focusPrev();
        const slide = deck.slides.items[deck.focused_index];
        self.focused_window_id = slide.window_id;
        const window = self.windowById(slide.window_id) orelse return;
        if (window.toplevel.base.surface.mapped) {
            self.focusWindow(window);
            self.requestLayout();
        }
    }
    fn focusFirstMapped(self: *Server) void {
        var it = self.windows.iterator(.forward);
        while (it.next()) |window| {
            if (window.toplevel.base.surface.mapped) {
                self.focusWindow(window);
                self.requestLayout();
                return;
            }
        }
        self.clearFocus();
    }

    fn focusLastMapped(self: *Server) void {
        var it = self.windows.iterator(.reverse);
        while (it.next()) |window| {
            if (window.toplevel.base.surface.mapped) {
                self.focusWindow(window);
                self.requestLayout();
                return;
            }
        }
        self.clearFocus();
    }

    pub fn clearFocus(self: *Server) void {
        self.focused_window = null;
        self.focused_window_id = 0;
        self.seat.keyboardNotifyClearFocus();
    }

    pub fn focusWindow(self: *Server, window: *Window) void {
        if (self.focused_window == window) {
            // Ensure the seat focus is on this surface even if it already appears selected.
            window.focus(self.seat);
            self.focused_window_id = window.id;
            if (window.output) |output| self.focused_output = output;
            self.syncDeckFocus();
            return;
        }
        if (!window.toplevel.base.surface.mapped) {
            std.log.debug("KidulWM: refusing focus on unmapped surface", .{});
            return;
        }
        self.focused_window = window;
        self.focused_window_id = window.id;
        if (window.output) |output| self.focused_output = output;
        window.focus(self.seat);
        self.syncDeckFocus();
    }

    pub fn focusAtCursor(self: *Server) void {
        var it = self.windows.iterator(.forward);
        while (it.next()) |window| {
            const node = &window.scene_tree.node;
            if (!window.toplevel.base.surface.mapped) continue;
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

        const active_deck = self.currentDeck();
        var any_slides = false;

        var output_it = self.outputs.iterator(.forward);
        while (output_it.next()) |output| {
            const wlr_output = output.wlr_output;
            const width = @as(u32, @intCast(wlr_output.width));
            const height = @as(u32, @intCast(wlr_output.height));
            output.deck.sync(width, height, self.state.gap, self.deck_split, self.deck_orientation);

            if (output.deck.slides.items.len == 0) continue;
            any_slides = true;

            var focused_slide_window: ?*Window = null;
            const deck_ptr = &output.deck;
            for (output.deck.slides.items, 0..) |slide, slide_idx| {
                const window = self.windowById(slide.window_id) orelse continue;
                if (!window.toplevel.base.surface.mapped) continue;

                const target = output.deck.targetForSlide(slide_idx);
                const size_changed = window.animation.target_w != @as(f64, @floatFromInt(target.width)) or
                    window.animation.target_h != @as(f64, @floatFromInt(target.height));
                window.setLayoutTarget(target.x, target.y, target.width, target.height);
                if (size_changed) {
                    _ = window.toplevel.setSize(@intCast(target.width), @intCast(target.height));
                }

                if (slide_idx == output.deck.focused_index) {
                    focused_slide_window = window;
                    window.updateDim(true);
                } else {
                    window.updateDim(false);
                }
            }

            if (deck_ptr == active_deck) {
                if (focused_slide_window) |window| {
                    self.focusWindow(window);
                }
            }
        }

        // Fallback headless mode: no outputs yet.
        if (self.outputs.length() == 0) {
            self.deck.sync(1024, 768, self.state.gap, self.deck_split, self.deck_orientation);
            if (self.deck.slides.items.len > 0) {
                any_slides = true;
                for (self.deck.slides.items, 0..) |slide, slide_idx| {
                    const window = self.windowById(slide.window_id) orelse continue;
                    if (!window.toplevel.base.surface.mapped) continue;
                    const target = self.deck.targetForSlide(slide_idx);
                    const size_changed = window.animation.target_w != @as(f64, @floatFromInt(target.width)) or
                        window.animation.target_h != @as(f64, @floatFromInt(target.height));
                    window.setLayoutTarget(target.x, target.y, target.width, target.height);
                    if (size_changed) {
                        _ = window.toplevel.setSize(@intCast(target.width), @intCast(target.height));
                    }
                    if (slide_idx == self.deck.focused_index) {
                        window.updateDim(true);
                        self.focusWindow(window);
                    } else {
                        window.updateDim(false);
                    }
                }
            }
        }

        if (!any_slides) {
            self.clearFocus();
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

        if (!wlr_output.initRender(self.renderer_allocator, self.renderer)) {
            std.log.err("KidulWM: failed to initialize output render, dropping output", .{});
            return;
        }

        var state = wlr.Output.State.init();
        defer state.finish();
        state.setEnabled(true);
        if (wlr_output.preferredMode()) |mode| {
            state.setMode(mode);
        } else {
            state.setCustomMode(1024, 768, 60_000);
        }
        if (!wlr_output.commitState(&state)) {
            std.log.err("KidulWM: failed to commit output state, dropping output", .{});
            return;
        }

        std.log.info("KidulWM: new output {s} {d}x{d}", .{ wlr_output.name, wlr_output.width, wlr_output.height });

        _ = self.output_layout.addAuto(wlr_output) catch |err| {
            std.log.err("failed to add output to layout: {}", .{err});
            return;
        };
        const scene_output = self.scene.createSceneOutput(wlr_output) catch |err| {
            std.log.err("scene output create failed: {}", .{err});
            return;
        };
        const output = self.allocator.create(Output) catch |err| {
            std.log.err("failed to allocate output state: {}", .{err});
            return;
        };
        output.init(self, wlr_output, scene_output);
        std.log.info("KidulWM: output added to layout", .{});
        self.requestLayout();
        wlr_output.scheduleFrame();
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

    fn applyTheme(self: *Server, key: []const u8, value: []const u8) void {
        if (std.mem.eql(u8, key, "border_focused")) {
            self.theme.color_border_focused = style.Style.Color.fromString(value) catch |err| {
                std.log.warn("invalid border_focused color '{s}': {}", .{ value, err });
                return;
            };
        } else if (std.mem.eql(u8, key, "border")) {
            self.theme.color_border = style.Style.Color.fromString(value) catch |err| {
                std.log.warn("invalid border color '{s}': {}", .{ value, err });
                return;
            };
        } else if (std.mem.eql(u8, key, "background")) {
            self.theme.color_background = style.Style.Color.fromString(value) catch |err| {
                std.log.warn("invalid background color '{s}': {}", .{ value, err });
                return;
            };
        } else if (std.mem.eql(u8, key, "gap")) {
            const gap = std.fmt.parseInt(u32, value, 10) catch |err| {
                std.log.warn("invalid gap '{s}': {}", .{ value, err });
                return;
            };
            self.theme.gap = gap;
            self.state.gap = gap;
        } else {
            std.log.info("unknown theme key '{s}', ignoring", .{key});
            return;
        }


        self.background.color = self.theme.color_background.toF32();
        self.requestLayout();
    }
};
