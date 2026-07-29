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
const theme_mod = @import("core/theme.zig");
const Theme = theme_mod.Theme;
const slidedeck = @import("core/slidedeck.zig");
const animation = @import("core/animation.zig");
const chrome_renderer = @import("render/chrome.zig");
const curtain_renderer = @import("render/curtain.zig");
const render_image = @import("render/image.zig");
const DataBuffer = @import("render/buffer.zig").DataBuffer;
const ui = @import("./ui/tray.zig");
const keybinds = @import("config/keybinds.zig");

extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern fn unsetenv(name: [*:0]const u8) c_int;

fn applyTitleBarEnvironment(show_title_bars: bool) void {
    if (show_title_bars) {
        std.log.info("KidulWM: enabling client title bars", .{});
        _ = unsetenv("GTK_CSD");
        _ = unsetenv("GDK_DEBUG");
        _ = unsetenv("QT_WAYLAND_DISABLE_WINDOWDECORATION");
    } else {
        std.log.info("KidulWM: disabling client title bars", .{});
        _ = setenv("GTK_CSD", "0", 1);
        _ = setenv("GDK_DEBUG", "no-csd", 1);
        _ = setenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1", 1);
    }
}

const InputDeviceCounts = packed struct { pointer: u32 = 0, keyboard: u32 = 0 };

pub const Output = struct {
    server: *Server,
    wlr_output: *wlr.Output,
    scene_output: *wlr.SceneOutput,
    link: wl.list.Link,
    frame: wl.Listener(*wlr.Output),
    destroy: wl.Listener(*wlr.Output),
    deck: slidedeck.SlideDeck,
    curtains: ?*curtain_renderer.OutputCurtains,

    pub fn init(self: *Output, server: *Server, wlr_output: *wlr.Output, scene_output: *wlr.SceneOutput) void {
        self.* = .{
            .server = server,
            .wlr_output = wlr_output,
            .scene_output = scene_output,
            .link = undefined,
            .frame = wl.Listener(*wlr.Output).init(handleFrame),
            .destroy = wl.Listener(*wlr.Output).init(handleDestroy),
            .deck = slidedeck.SlideDeck.init(server.allocator),
            .curtains = null,
        };
        server.outputs.append(self);
        wlr_output.events.frame.add(&self.frame);
        wlr_output.events.destroy.add(&self.destroy);
    }

    pub fn deinit(self: *Output) void {
        self.server.tray.removeOutput(self);
        self.frame.link.remove();
        self.destroy.link.remove();
        if (self.curtains) |curtains| {
            curtains.destroy();
            self.curtains = null;
        }
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
        self.server.tray.update();
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
    overlay_tree: *wlr.SceneTree,
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
    theme_runtime: Theme,
    deck_split: slidedeck.Split,
    deck_orientation: slidedeck.Orientation,
    windows: wl.list.Head(Window, .link),

    deck: slidedeck.SlideDeck,
    layout_pipe: [2]c_int,
    layout_source: *wl.EventSource,
    layout_requested: std.atomic.Value(bool),

    focused_window: ?*Window,
    keybinds: keybinds.Keybinds,
    focused_window_id: u32 = 0,
    focused_output: ?*Output = null,
    last_focused_slide_id: u32 = 0,
    current_transition_kind: animation.AnimationKind = .snap,
    next_window_id: u32 = 1,

    tray: ui.Tray,
    input_device_counts: InputDeviceCounts,
    backend_started: bool = false,
    chrome_style_generation: u32,

    decoration_manager: *wlr.XdgDecorationManagerV1,

    new_output: wl.Listener(*wlr.Output),
    new_toplevel_decoration: wl.Listener(*wlr.XdgToplevelDecorationV1),
    backend_destroy: wl.Listener(*wlr.Backend),
    new_xdg_toplevel: wl.Listener(*wlr.XdgToplevel),
    output_layout_change: wl.Listener(*wlr.OutputLayout),

    background: struct {
        node: ?*wlr.SceneNode,
        color: [4]f32,
        rect: ?*wlr.SceneRect,
        image_buffer: ?*wlr.Buffer,
        image_scene_buffer: ?*wlr.SceneBuffer,
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
                // Mirror per-key changes into the runtime theme container so
                // TrayCard and other future widgets see them too.
                self.theme_runtime.style = self.theme;
                self.theme_runtime.bumpGeneration();
                return .{ .ok = true, .message = "theme updated" };
            },
            .reload_theme => {
                self.theme_runtime.reload(self.allocator) catch |err| {
                    std.log.err("theme reload failed: {}", .{err});
                    return .{ .ok = false, .message = "reload failed" };
                };
                self.theme = self.theme_runtime.style;
                applyTitleBarEnvironment(self.theme.show_title_bars);
                self.background.color = self.theme.color_background.toF32();
                if (self.background.image_scene_buffer == null) {
                    if (self.background.rect) |rect| {
                        rect.setColor(&self.background.color);
                    }
                }
                self.chrome_style_generation +%= 1;
                self.requestLayout();
                return .{ .ok = true, .message = "theme reloaded" };
            },
            .tray_toggle => {
                self.tray.toggle();
                return .{ .ok = true };
            },
            .tray_select_next => {
                self.tray.selectNext();
                return .{ .ok = true };
            },
            .tray_select_prev => {
                self.tray.selectPrev();
                return .{ .ok = true };
            },
            .tray_activate => {
                self.tray.activateSelected();
                return .{ .ok = true };
            },
            .tray_toggle_card => {
                self.tray.toggleCard();
                return .{ .ok = true };
            },
            .weather_toggle_card => {
                self.tray.toggleWeatherCard();
                return .{ .ok = true };
            },
            .media_card_toggle => {
                self.tray.toggleMediaCard();
                return .{ .ok = true };
            },
            .media_play => |p| {
                self.tray.media.play(p.path);
                return .{ .ok = true, .message = "media play requested" };
            },
            .media_toggle => {
                self.tray.media.playPause();
                return .{ .ok = true };
            },
            .media_next => {
                self.tray.media.next();
                return .{ .ok = true };
            },
            .media_prev => {
                self.tray.media.prev();
                return .{ .ok = true };
            },
            .media_seek => |p| {
                self.tray.media.seek(p.seconds);
                return .{ .ok = true };
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
            .set_theme, .reload_theme, .tray_toggle, .tray_select_next, .tray_select_prev, .tray_activate, .tray_toggle_card, .weather_toggle_card, .media_card_toggle, .media_play, .media_toggle, .media_next, .media_prev, .media_seek, .quit => {},
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
        const decoration_manager = try wlr.XdgDecorationManagerV1.create(wl_server);

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
            .decoration_manager = decoration_manager,
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
            .theme_runtime = Theme.initDefaults(),
            .deck_split = .{
                .left_peek = style.layout.horizontal_split.left_peek,
                .focus = style.layout.horizontal_split.focus,
                .right_peek = style.layout.horizontal_split.right_peek,
            },
            .deck_orientation = .horizontal,
            .windows = undefined,
            .layout_requested = std.atomic.Value(bool).init(false),
            .keybinds = keybinds.Keybinds.load(allocator),
        .deck = slidedeck.SlideDeck.init(allocator),
            .layout_pipe = undefined,
            .layout_source = undefined,
            .new_output = undefined,
            .new_toplevel_decoration = undefined,
            .backend_destroy = undefined,
            .new_xdg_toplevel = undefined,
            .output_layout_change = undefined,
            .background = .{
                .node = null,
                .rect = null,
                .color = style.default_style.color_background.toF32(),
                .image_buffer = null,
                .image_scene_buffer = null,
            },
            .overlay_tree = undefined,
            .outputs = undefined,
            .chrome_style_generation = 0,
            .tray = undefined,
        };

        server.outputs.init();

        // Load the runtime theme once at startup.  If no theme file exists we
        // keep the built-in defaults; if one exists but is malformed we warn
        // and continue with defaults.
        server.theme_runtime.reload(allocator) catch |err| {
            std.log.warn("KidulWM: failed to load theme at startup ({}), using defaults", .{err});
        };
        server.theme = server.theme_runtime.style;
        applyTitleBarEnvironment(server.theme.show_title_bars);
        server.background.color = server.theme.color_background.toF32();

        const overlay_tree = try server.scene.tree.createSceneTree();
        server.overlay_tree = overlay_tree;

        server.tray = try ui.Tray.init(server.allocator, Server.makeTrayHost(server), overlay_tree);

        const bg_rect = try server.scene.tree.createSceneRect(1, 1, &server.background.color);
        server.background.rect = bg_rect;
        server.background.node = &bg_rect.node;

        server.loadWallpaper("/home/kidul/Pictures/Wallpapers/theWallpaper.png") catch |err| {
            std.log.warn("KidulWM: failed to load wallpaper, using fallback color: {}", .{err});
        };

        // Background/wallpaper nodes were created after the tray, so ensure the
        // overlay tree stays on top of the background for immediate visibility.
        server.overlay_tree.node.raiseToTop();

        server.pointer.init(server);
        server.keyboard.init(server);
        server.windows.init();
        server.input_manager = try server.allocator.create(InputManager);
        InputManager.init(server.input_manager, server);

        server.new_output = wl.Listener(*wlr.Output).init(handleNewOutput);
        server.new_output.link.init();
        backend.events.new_output.add(&server.new_output);

        server.new_toplevel_decoration = wl.Listener(*wlr.XdgToplevelDecorationV1).init(handleNewToplevelDecoration);
        server.new_toplevel_decoration.link.init();
        decoration_manager.events.new_toplevel_decoration.add(&server.new_toplevel_decoration);

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

        self.tray.deinit();
        self.keybinds.deinit();
        self.overlay_tree.node.destroy();

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
        var output_it = self.outputs.iterator(.forward);
        while (output_it.next()) |output| {
            output.wlr_output.scheduleFrame();
        }
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
                deck.empty_slot = .none;
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

    /// Focus the next slide, pushing into the virtual empty slot past the end
    /// instead of wrapping around.
    pub fn focusNext(self: *Server) void {
        const deck = self.currentDeck();
        if (deck.slides.items.len == 0) return;
        deck.focusNext();
        if (deck.empty_slot != .none) {
            self.clearFocus();
            self.requestLayout();
            return;
        }
        const slide = deck.slides.items[deck.focused_index];
        self.focused_window_id = slide.window_id;
        const window = self.windowById(slide.window_id) orelse return;
        if (window.toplevel.base.surface.mapped) {
            self.focusWindow(window);
            self.requestLayout();
        }
    }

    /// Focus the previous slide, pushing into the virtual empty slot before the
    /// first slide instead of wrapping around.
    pub fn focusPrev(self: *Server) void {
        const deck = self.currentDeck();
        if (deck.slides.items.len == 0) return;
        deck.focusPrev();
        if (deck.empty_slot != .none) {
            self.clearFocus();
            self.requestLayout();
            return;
        }
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
        const deck = self.currentDeck();
        if (deck.empty_slot != .none) return;
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
        const current_focused_slide_id: u32 = if (active_deck.empty_slot == .none and active_deck.slides.items.len > 0)
            active_deck.slides.items[active_deck.focused_index].window_id
        else
            0;
        const focus_changed = self.last_focused_slide_id != current_focused_slide_id;

        var any_slides = false;

        var output_it = self.outputs.iterator(.forward);
        while (output_it.next()) |output| {
            const wlr_output = output.wlr_output;
            const width = @as(u32, @intCast(wlr_output.width));
            const height = @as(u32, @intCast(wlr_output.height));
            output.deck.sync(width, height, self.state.gap, self.deck_split, self.deck_orientation);

            if (output.curtains) |curtains| {
                var box: wlr.Box = undefined;
                self.output_layout.getBox(wlr_output, &box);
                const scale: u32 = @intFromFloat(@max(1.0, wlr_output.scale));
                const has_left_peek = output.deck.focused_index > 0;
                const has_right_peek = output.deck.focused_index + 1 < output.deck.slides.items.len;
                curtains.update(self.theme, self.theme_runtime.generation, scale, box, self.deck_split.left_peek, self.deck_split.right_peek, has_left_peek, has_right_peek);
            }

            if (output.deck.slides.items.len == 0) continue;
            any_slides = true;

            var focused_slide_window: ?*Window = null;
            const deck_ptr = &output.deck;
            for (output.deck.slides.items, 0..) |slide, slide_idx| {
                const window = self.windowById(slide.window_id) orelse continue;
                if (!window.toplevel.base.surface.mapped) continue;

                const target = output.deck.targetForSlide(slide_idx);
                const is_focused = slide_idx == output.deck.focused_index;
                const peek_edges = if (slide_idx < output.deck.focused_index) chrome_renderer.EdgeMode.left_peek else chrome_renderer.EdgeMode.right_peek;
                const w_changed = window.animation.target_w != @as(f64, @floatFromInt(target.width));
                const h_changed = window.animation.target_h != @as(f64, @floatFromInt(target.height));
                const size_changed = w_changed or h_changed;
                window.setLayoutTarget(target.x, target.y, target.width, target.height);
                if (focus_changed) {
                    window.startTransition(self.current_transition_kind);
                }
                // Only reconfigure and scale the actual client surface for the focused
                // slide. Side peeks keep their full-window scene tree (so the chrome
                // overlay masks the entire bounds), but the surface buffer itself is
                // left at its natural size and only offset within that tree.
                if (is_focused and size_changed) {
                    _ = window.toplevel.setSize(@intCast(target.width), @intCast(target.height));
                }
                if (is_focused) {
                    window.setSurfaceDestSize(@intCast(target.width), @intCast(target.height));
                    window.setSurfaceOffset(0, 0);
                } else {
                    window.setSurfaceOffsetForPeek(peek_edges);
                }

                if (is_focused) {
                    focused_slide_window = window;
                    window.updateDim(true);
                    window.updateChrome(true, .all);
                    window.scene_tree.node.raiseToTop();
                    self.overlay_tree.node.raiseToTop();
                } else {
                    window.updateDim(false);
                    window.updateChrome(false, peek_edges);
                }
            }

            if (deck_ptr == active_deck) {
                if (deck_ptr.empty_slot == .none) {
                    if (focused_slide_window) |window| {
                        self.focusWindow(window);
                    }
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
                    const is_focused = slide_idx == self.deck.focused_index;
                    const w_changed = window.animation.target_w != @as(f64, @floatFromInt(target.width));
                    const h_changed = window.animation.target_h != @as(f64, @floatFromInt(target.height));
                    const size_changed = w_changed or h_changed;
                window.setLayoutTarget(target.x, target.y, target.width, target.height);
                if (focus_changed) {
                    window.startTransition(self.current_transition_kind);
                }
                    if (is_focused and size_changed) {
                        _ = window.toplevel.setSize(@intCast(target.width), @intCast(target.height));
                    }
                    if (is_focused) {
                        window.setSurfaceDestSize(@intCast(target.width), @intCast(target.height));
                        window.setSurfaceOffset(0, 0);
                    } else {
                        const edges = if (slide_idx < self.deck.focused_index) chrome_renderer.EdgeMode.left_peek else chrome_renderer.EdgeMode.right_peek;
                        window.setSurfaceOffsetForPeek(edges);
                    }
                    if (is_focused) {
                        window.updateDim(true);
                        window.updateChrome(true, .all);
                        window.scene_tree.node.raiseToTop();
                        self.overlay_tree.node.raiseToTop();
                        if (self.deck.empty_slot == .none) {
                            self.focusWindow(window);
                        }
                    } else {
                        const edges = if (slide_idx < self.deck.focused_index) chrome_renderer.EdgeMode.left_peek else chrome_renderer.EdgeMode.right_peek;
                        window.updateDim(false);
                        window.updateChrome(false, edges);
                    }
                }
            }
        }

        if (!any_slides) {
            self.clearFocus();
        }

        self.last_focused_slide_id = current_focused_slide_id;
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

    fn pickOutputMode(wlr_output: *wlr.Output) ?*wlr.Output.Mode {
        // Virtual/QEMU outputs advertise a tiny preferred mode (e.g. 1280x800) while
        // offering huge 4K/5K modes. For software-raster GLES2 (kms_swrast) 4K is too
        // heavy, so pick the largest advertised mode up to 1920x1080. This keeps text
        // sharp while leaving enough CPU/GPU headroom for motion.
        const is_virtual = std.mem.startsWith(u8, std.mem.span(wlr_output.name), "Virtual");
        const preferred = wlr_output.preferredMode();
        if (!is_virtual) return preferred;

        var best: ?*wlr.Output.Mode = null;
        var best_pixels: i32 = 0;
        const max_pixels: i32 = 1920 * 1080;
        var it = wlr_output.modes.iterator(.forward);
        while (it.next()) |mode| {
            const pixels = mode.width * mode.height;
            if (pixels > best_pixels and pixels <= max_pixels) {
                best = mode;
                best_pixels = pixels;
            }
        }
        if (best) |b| return b;
        return preferred;
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
        if (pickOutputMode(wlr_output)) |mode| {
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
        output.curtains = curtain_renderer.OutputCurtains.create(self.allocator, self.overlay_tree) catch |err| blk: {
            std.log.err("failed to create curtains: {}", .{err});
            break :blk null;
        };
        self.tray.addOutput(output);
        // Compute layout immediately so window panels appear on the first frame,
        // instead of waiting for the asynchronous layout-event loop tick.
        self.applyLayout();
        self.requestLayout();
        wlr_output.scheduleFrame();
    }

    fn handleBackendDestroy(listener: *wl.Listener(*wlr.Backend), backend: *wlr.Backend) void {
        const self: *Server = @fieldParentPtr("backend_destroy", listener);
        _ = self;
        _ = backend;
        std.log.info("KidulWM: backend destroyed", .{});
    }

    fn handleNewToplevelDecoration(listener: *wl.Listener(*wlr.XdgToplevelDecorationV1), decoration: *wlr.XdgToplevelDecorationV1) void {
        const self: *Server = @fieldParentPtr("new_toplevel_decoration", listener);
        // Some clients create the decoration object before the xdg surface is
        // initialized.  wlroots asserts when scheduling a configure on an
        // uninitialized surface, so skip the explicit mode set in that case;
        // the client/server default will apply once the surface is ready.
        const toplevel = decoration.toplevel;
        if (!toplevel.base.initialized) {
            return;
        }
        // Default to server-side decorations (no client title bars). Honour the
        // user's explicit override when they want title bars, but signature look
        // means SSD by default.
        const mode: wlr.XdgToplevelDecorationV1.Mode = if (self.theme.show_title_bars) .client_side else .server_side;
        _ = decoration.setMode(mode);
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
        self.updateBackgroundLayout(&box);

        self.applyLayout();
        self.requestLayout();
    }

    fn updateBackgroundLayout(self: *Server, box: *const wlr.Box) void {
        if (self.background.node) |node| {
            node.setPosition(box.x, box.y);
        }
        if (self.background.image_scene_buffer) |scene_buffer| {
            scene_buffer.setDestSize(box.width, box.height);
        } else if (self.background.rect) |rect| {
            rect.setSize(box.width, box.height);
        }
    }

    fn loadWallpaper(self: *Server, path: []const u8) !void {
        // Tear down any existing background node and image buffer first.
        if (self.background.node) |node| {
            node.destroy();
            self.background.node = null;
        }
        if (self.background.image_buffer) |buffer| {
            wlr.Buffer.drop(buffer);
            self.background.image_buffer = null;
            self.background.image_scene_buffer = null;
        }

        const image = render_image.Image.loadPng(path) catch |err| {
            std.log.warn("KidulWM: failed to load wallpaper '{s}': {}", .{ path, err });
            // Fall back to a solid-colour background rect.
            const rect = try self.scene.tree.createSceneRect(1, 1, &self.background.color);
            self.background.rect = rect;
            self.background.image_scene_buffer = null;
            self.background.node = &rect.node;
            return;
        };
        defer image.deinit();

        const buffer = try DataBuffer.create(image.data, image.width, image.height, image.stride);
        errdefer wlr.Buffer.drop(buffer);

        // Attach the image buffer directly to the root scene tree so there is
        // no intermediate transform to get wrong. The buffer remains referenced
        // by image_buffer and by the scene buffer (which locks it), so both must
        // be released before replacement.
        const scene_buffer = try self.scene.tree.createSceneBuffer(buffer);
        scene_buffer.setDestSize(image.width, image.height);

        self.background.rect = null;
        self.background.image_buffer = buffer;
        self.background.image_scene_buffer = scene_buffer;
        self.background.node = &scene_buffer.node;

        std.log.info("KidulWM: loaded wallpaper '{s}' ({d}x{d})", .{ path, image.width, image.height });
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

    /// Provide the tray with per-output geometry and state access without
    /// creating a circular module dependency on server.zig.
    fn makeTrayHost(self: *Server) ui.TrayHost {
        return .{
            .ctx = self,
            .output_count = struct {
                fn f(ctx: *anyopaque) usize {
                    const s = @as(*Server, @ptrCast(@alignCast(ctx)));
                    return s.outputs.length();
                }
            }.f,
            .output_info = struct {
                fn f(ctx: *anyopaque, index: usize) ui.OutputInfo {
                    const s = @as(*Server, @ptrCast(@alignCast(ctx)));
                    var it = s.outputs.iterator(.forward);
                    var i: usize = 0;
                    while (it.next()) |output| : (i += 1) {
                        if (i == index) {
                            var box: wlr.Box = undefined;
                            s.output_layout.getBox(output.wlr_output, &box);
                            const left_w: i32 = @intFromFloat(@as(f32, @floatFromInt(box.width)) * output.deck.split.left_peek);
                            return .{
                                .x = box.x,
                                .y = box.y,
                                .width = box.width,
                                .height = box.height,
                                .scale = output.wlr_output.scale,
                                .focus_left = box.x + left_w,
                            };
                        }
                    }
                    return .{ .x = 0, .y = 0, .width = 0, .height = 0, .scale = 1.0, .focus_left = 0 };
                }
            }.f,
            .right_peek_box = struct {
                fn f(ctx: *anyopaque, output_index: usize) ?wlr.Box {
                    const s = @as(*Server, @ptrCast(@alignCast(ctx)));
                    var it = s.outputs.iterator(.forward);
                    var i: usize = 0;
                    while (it.next()) |output| : (i += 1) {
                        if (i != output_index) continue;
                        var layout_box: wlr.Box = undefined;
                        s.output_layout.getBox(output.wlr_output, &layout_box);
                        const split = output.deck.split;
                        const w: f32 = @floatFromInt(layout_box.width);
                        const h: f32 = @floatFromInt(layout_box.height);
                        return switch (output.deck.orientation) {
                            .horizontal => .{
                                .x = layout_box.x + @as(i32, @intFromFloat(w * (split.left_peek + split.focus))),
                                .y = layout_box.y,
                                .width = @intFromFloat(w * split.right_peek),
                                .height = layout_box.height,
                            },
                            .vertical => .{
                                .x = layout_box.x,
                                .y = layout_box.y + @as(i32, @intFromFloat(h * (split.left_peek + split.focus))),
                                .width = layout_box.width,
                                .height = @intFromFloat(h * split.right_peek),
                            },
                        };
                    }
                    return null;
                }
            }.f,

            .left_peek_box = struct {
                fn f(ctx: *anyopaque, output_index: usize) ?wlr.Box {
                    const s = @as(*Server, @ptrCast(@alignCast(ctx)));
                    var it = s.outputs.iterator(.forward);
                    var i: usize = 0;
                    while (it.next()) |output| : (i += 1) {
                        if (i != output_index) continue;
                        var layout_box: wlr.Box = undefined;
                        s.output_layout.getBox(output.wlr_output, &layout_box);
                        const split = output.deck.split;
                        const w: f32 = @floatFromInt(layout_box.width);
                        const h: f32 = @floatFromInt(layout_box.height);
                        return switch (output.deck.orientation) {
                            .horizontal => .{
                                .x = layout_box.x,
                                .y = layout_box.y,
                                .width = @intFromFloat(w * split.left_peek),
                                .height = layout_box.height,
                            },
                            .vertical => .{
                                .x = layout_box.x,
                                .y = layout_box.y,
                                .width = layout_box.width,
                                .height = @intFromFloat(h * split.left_peek),
                            },
                        };
                    }
                    return null;
                }
            }.f,
            .get_animation_kind = struct {
                fn f(ctx: *anyopaque) animation.AnimationKind {
                    const s = @as(*Server, @ptrCast(@alignCast(ctx)));
                    return s.current_transition_kind;
                }
            }.f,
            .cycle_animation = struct {
                fn f(ctx: *anyopaque) void {
                    const s = @as(*Server, @ptrCast(@alignCast(ctx)));
                    s.nextAnimationKind();
                }
            }.f,
            .request_frame = struct {
                fn f(ctx: *anyopaque) void {
                    const s = @as(*Server, @ptrCast(@alignCast(ctx)));
                    var it = s.outputs.iterator(.forward);
                    while (it.next()) |output| {
                        output.wlr_output.scheduleFrame();
                    }
                }
            }.f,
            .is_transition_active = struct {
                fn f(ctx: *anyopaque) bool {
                    const s = @as(*Server, @ptrCast(@alignCast(ctx)));
                    var it = s.windows.iterator(.forward);
                    while (it.next()) |window| {
                        if (window.animation.last_us != 0) return true;
                    }
                    return false;
                }
            }.f,
            .focused_window_box = struct {
                fn f(ctx: *anyopaque) ?wlr.Box {
                    const s: *Server = @ptrCast(@alignCast(ctx));
                    const w = s.focused_window orelse return null;
                    return .{
                        .x = @intFromFloat(@round(w.animation.cur_x)),
                        .y = @intFromFloat(@round(w.animation.cur_y)),
                        .width = @intFromFloat(@round(w.animation.cur_w)),
                        .height = @intFromFloat(@round(w.animation.cur_h)),
                    };
                }
            }.f,
            .theme = &self.theme_runtime,
        };
    }

    pub fn nextAnimationKind(self: *Server) void {
        self.current_transition_kind = switch (self.current_transition_kind) {
            .snap => .wobble,
            .wobble => .ripple,
            .ripple => .snap,
        };
        std.log.info("KidulWM: animation preset -> {s}", .{@tagName(self.current_transition_kind)});
        self.tray.requestUpdate();
    }

    pub fn spawnCommand(self: *Server, cmd: []const u8) void {
        _ = self;
        const pid = linux.fork();
        if (@as(isize, @bitCast(pid)) < 0) {
            std.log.warn("KidulWM: fork failed for spawn", .{});
            return;
        }
        if (pid != 0) return;

        // redirect stdio so the compositor keeps its pipe fds
        const devnull = linux.open("/dev/null", .{ .ACCMODE = .RDONLY }, 0);
        if (@as(isize, @bitCast(devnull)) >= 0) {
            const fd: i32 = @intCast(devnull);
            _ = linux.dup2(fd, linux.STDIN_FILENO);
            _ = linux.dup2(fd, linux.STDOUT_FILENO);
            _ = linux.dup2(fd, linux.STDERR_FILENO);
            _ = linux.close(fd);
        }

        const child_allocator = std.heap.page_allocator;
        var it = std.mem.tokenizeScalar(u8, cmd, ' ');
        var argv: [33:null]?[*:0]const u8 = undefined;
        var argc: usize = 0;
        while (it.next()) |arg| {
            if (argc >= argv.len - 1) break;
            const z = child_allocator.dupeZ(u8, arg) catch break;
            argv[argc] = z.ptr;
            argc += 1;
        }
        if (argc == 0) {
            std.log.warn("KidulWM: empty spawn command", .{});
            linux.exit(127);
        }
        argv[argc] = null;

        const envp = [_:null]?[*:0]const u8{
            "WAYLAND_DISPLAY=wayland-1",
            "XDG_RUNTIME_DIR=/run/user/1000",
            "GHOSTTY_RESOURCES_DIR=/usr/share/ghostty",
            null,
        };
        _ = linux.execve(argv[0].?, &argv, &envp);
        linux.exit(127);
    }

    pub fn handlePointerMove(self: *Server, x: f64, y: f64) bool {
        return self.tray.handlePointerMove(x, y);
    }

    pub fn handlePointerClick(self: *Server, x: f64, y: f64) bool {
        return self.tray.handlePointerClick(x, y);
    }

    pub fn logPointerDiagnostic(self: *Server, tag: []const u8, x: f64, y: f64) void {
        _ = self;
        const now = @import("core/animation.zig").nowUs();
        const S = struct {
            var last: u64 = 0;
        };
        if (now - S.last < 1_000_000) return;
        S.last = now;
        std.log.info("KidulWM: pointer {s} x={d:.1} y={d:.1}", .{ tag, x, y });
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
            self.theme.peek_glass_border_color = self.theme.color_border;
        } else if (std.mem.eql(u8, key, "background")) {
            self.theme.color_background = style.Style.Color.fromString(value) catch |err| {
                std.log.warn("invalid background color '{s}': {}", .{ value, err });
                return;
            };

        } else if (std.mem.eql(u8, key, "border_width")) {
            const border_width = std.fmt.parseFloat(f32, value) catch |err| {
                std.log.warn("invalid border_width '{s}': {}", .{ value, err });
                return;
            };
            self.theme.border_width = border_width;
            self.chrome_style_generation +%= 1;
            self.requestLayout();
            return;
        } else if (std.mem.eql(u8, key, "gap")) {
            const gap = std.fmt.parseInt(u32, value, 10) catch |err| {
                std.log.warn("invalid gap '{s}': {}", .{ value, err });
                return;
            };
            self.theme.gap = gap;
            self.state.gap = gap;
        } else if (std.mem.eql(u8, key, "corner_style")) {
            if (std.mem.eql(u8, value, "round")) {
                self.theme.corner_style = .round;
            } else if (std.mem.eql(u8, value, "chamfer")) {
                self.theme.corner_style = .chamfer;
            } else if (std.mem.eql(u8, value, "square")) {
                self.theme.corner_style = .square;
            } else {
                std.log.warn("unknown corner_style '{s}', expected round/chamfer/square", .{value});
                return;
            }
            self.chrome_style_generation +%= 1;
            self.requestLayout();
            return;
        } else if (std.mem.eql(u8, key, "show_title_bars")) {
            if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1")) {
                self.theme.show_title_bars = true;
            } else if (std.mem.eql(u8, value, "false") or std.mem.eql(u8, value, "0")) {
                self.theme.show_title_bars = false;
            } else {
                std.log.warn("unknown show_title_bars '{s}', expected true/false", .{value});
                return;
            }
            self.requestLayout();
            return;
        } else {
            std.log.info("unknown theme key '{s}', ignoring", .{key});
            return;
        }

        self.background.color = self.theme.color_background.toF32();
        if (self.background.image_scene_buffer == null) {
            if (self.background.rect) |rect| {
                rect.setColor(&self.background.color);
            }
        }
        self.requestLayout();
    }
};
