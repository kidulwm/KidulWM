const std = @import("std");
const linux = std.os.linux;
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const ipc = @import("ipc.zig");
const Window = @import("window.zig").Window;
const layer_mod = @import("layer.zig");
const LayerSurface = layer_mod.LayerSurface;
const InputManager = @import("input.zig").InputManager;
const PointerManager = @import("input/pointer.zig").PointerManager;
const KeyboardManager = @import("input/keyboard.zig").KeyboardManager;
const style = @import("core/style.zig");
const theme_mod = @import("core/theme.zig");
const Theme = theme_mod.Theme;
const slidedeck = @import("core/slidedeck.zig");
const output_layout_config = @import("core/output_layout_config.zig");
const animation = @import("core/animation.zig");
const render_image = @import("render/image.zig");
const DataBuffer = @import("render/buffer.zig").DataBuffer;

/// Boot reveal effects for the wallpaper (palette-locked, picked at random
/// per boot). All run ~2.2s with a smoothstep ramp; the per-pixel ones
/// blend master vs theme-tinted copies so no foreign colours ever show.
pub const WallpaperEffect = enum { fade };

/// Fullscreen-video present phases (fullscreen.md: fullscreen is a MODE, not
/// a deck position). The card never moves; a black curtain + the kplayd
/// surface fade in/out in a controlled sequence (kidul present law: the
/// video fades in, it never pops in on the first decoded frame).
pub const FullscreenPhase = enum {
    idle, // no transition in flight
    fade_to_black, // curtain 0->1: deck + peeks fade to black
    wait_video, // black; waiting for kplayd's surface to map
    fade_video_in, // kplay surface 0->1 over black
    fade_video_out, // kplay surface 1->0 -> black (exit)
    fade_from_black, // curtain 1->0: deck fades back in
};

/// Pixel handoff from the wallpaper worker thread to the main thread.
pub const WallpaperResult = struct {
    pixels: []u8, // page_allocator-owned ARGB32
    width: i32,
    height: i32,
    stride: i32,
    ok: bool,
};
const chrome_renderer = @import("render/chrome.zig");
const cairo = @import("dm").c;
const overview_card = @import("render/overview_card.zig");
const overview_slide_mod = @import("ui/overview_slide.zig");
const tray_slide_mod = @import("ui/tray_slide.zig");
const media_slide_mod = @import("ui/media_slide.zig");
const kplay_client_mod = @import("ipc/kplay_client.zig");
const media_mod = @import("ui/media.zig");
const peek_mod = @import("ui/peek.zig");
const keybinds = @import("config/keybinds.zig");
const c = @cImport({
    @cInclude("stdio.h");
});
const c_std = @cImport({
    @cInclude("stdlib.h");
});

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

/// One observed pressed key event, recorded for the debug probe.
/// `swallowed_by` names the subsystem that consumed the event without a
/// keybind match ("" = forwarded to client or matched a bind).
pub const KeyRingEntry = struct {
    sym: u32 = 0,
    mod4: bool = false,
    ctrl: bool = false,
    action: [24]u8 = [_]u8{0} ** 24,
    action_len: u8 = 0,

    pub fn setAction(self: *KeyRingEntry, name: []const u8) void {
        const n = @min(name.len, self.action.len);
        @memcpy(self.action[0..n], name[0..n]);
        self.action_len = @intCast(n);
    }
};

/// CARD 2b slice 4: extension sniff for the media_play IPC verb — music
/// paths play headless in kplayd (no video surface); everything else enters
/// fullscreen mode. Granny-simple v1; kplayd makes its own decode call.
fn isMusicPath(path: []const u8) bool {
    const exts = [_][]const u8{ ".mp3", ".flac", ".ogg", ".opus", ".m4a", ".aac", ".wav", ".wma" };
    const ext = std.fs.path.extension(path);
    for (exts) |e| {
        if (std.ascii.eqlIgnoreCase(ext, e)) return true;
    }
    return false;
}

pub const Output = struct {
    server: *Server,
    wlr_output: *wlr.Output,
    scene_output: *wlr.SceneOutput,
    link: wl.list.Link,
    frame: wl.Listener(*wlr.Output),
    destroy: wl.Listener(*wlr.Output),
    /// Phase 2 step 2 (verdict 50+): per-output render counter. handleFrame
    /// bumps THIS (plus the global server.ft_rendered) so FRAMETRACE can
    /// split the idle frame rate per output — the global counter folds a
    /// 144Hz + 60Hz two-output rig into one number and hides who wakes.
    ft_rendered: u64 = 0,
    deck: slidedeck.SlideDeck,
    /// Overview slide for THIS output's deck (per-output by ruling).
    overview: overview_slide_mod.OverviewSlide = .{},
    /// Home slide content painter state (TASKCARD-3): the slide itself is a
    /// real deck.slides entry (kind .home); this holds tree + buffers only.
    home_slide: tray_slide_mod.TraySlide = .{},
    /// Media player slide content painter state (kind .media_player slide).
    media_slide: media_slide_mod.MediaSlide = .{},
    /// CARD 2b slice 2: the exported host toplevel (kplayd parents its video
    /// surface to this via xdg-foreign). One per fullscreen session — lives
    /// on the output that owns the media card, NOT a deck slide.
    video_host_surface: ?*@import("ipc/internal_client.zig").HostSurface = null,
    video_kplay_client: ?@import("ipc/kplay_client.zig").KplayClient = null,
    /// Permanent per-output edge peeks (TASKCARD-3): EXIT dots + counts,
    /// one click router, and the restored peek widget stack (weather /
    /// gauges / drives / KSD logo left; network + clock right). Born on
    /// output birth; the only hide condition is deck fullscreen.
    peek: peek_mod.Peek = undefined,
    /// Per-output wallpaper scene buffer (fill-contain, no crop). The master
    /// pixel buffer lives on server.background.image_buffer; each output gets
    /// its own scene buffer referencing it, sized to that output's logical
    /// box. This kills the "one global wallpaper only spans the first output"
    /// bug and the resulting mirror/top-center artifacts.
    wallpaper_scene_buffer: ?*wlr.SceneBuffer = null,
    /// Transient boot-reveal overlay: fullscreen tinted copy fading out over
    /// the master wallpaper. Self-destroys at the end of the fade; the
    /// permanent wallpaper buffer is never mutated by the animation.
    wallpaper_reveal_buffer: ?*wlr.SceneBuffer = null,

    pub fn init(self: *Output, server: *Server, wlr_output: *wlr.Output, scene_output: *wlr.SceneOutput) void {
        self.* = .{
            .server = server,
            .wlr_output = wlr_output,
            .scene_output = scene_output,
            .link = undefined,
            .frame = wl.Listener(*wlr.Output).init(handleFrame),
            .destroy = wl.Listener(*wlr.Output).init(handleDestroy),
            .deck = slidedeck.SlideDeck.init(server.allocator),
            .overview = .{},
            .home_slide = .{},
            .media_slide = .{},
            .peek = peek_mod.Peek.init(server.overlay_tree, server.theme),
            .wallpaper_scene_buffer = null,
            .wallpaper_reveal_buffer = null,
        };
        server.outputs.append(self);
        wlr_output.events.frame.add(&self.frame);
        wlr_output.events.destroy.add(&self.destroy);
    }

    /// Create or refresh this output's wallpaper scene buffer from the master
    /// image buffer. Fill-contain: scale the image to fit entirely inside the
    /// output's logical box, centered, with the theme background color filling
    /// any letterbox bars. No crop.
    pub fn setupWallpaper(self: *Output, server: *Server) void {
        // Tear down any existing per-output wallpaper node first.
        if (self.wallpaper_scene_buffer) |sb| {
            sb.node.destroy();
            self.wallpaper_scene_buffer = null;
        }

        const master = server.background.image_buffer orelse return;
        var box: wlr.Box = undefined;
        server.output_layout.getBox(self.wlr_output, &box);
        if (box.width <= 0 or box.height <= 0) return;

        const scene_buffer = server.scene.tree.createSceneBuffer(master) catch return;
        // Fill-contain: preserve aspect, fit entirely inside the box.
        const iw: f64 = @floatFromInt(master.width);
        const ih: f64 = @floatFromInt(master.height);
        const bw: f64 = @floatFromInt(box.width);
        const bh: f64 = @floatFromInt(box.height);
        var dest_w: i32 = box.width;
        var dest_h: i32 = box.height;
        var x: i32 = box.x;
        var y: i32 = box.y;
        if (iw / ih > bw / bh) {
            // Image wider than output: letterbox top/bottom.
            dest_w = box.width;
            dest_h = @intFromFloat(@floor(bw * (ih / iw)));
            y = box.y + @divTrunc(box.height - dest_h, 2);
        } else {
            // Image taller than output: pillarbox left/right.
            dest_h = box.height;
            dest_w = @intFromFloat(@floor(bh * (iw / ih)));
            x = box.x + @divTrunc(box.width - dest_w, 2);
        }
        scene_buffer.setDestSize(dest_w, dest_h);
        scene_buffer.node.setPosition(x, y);
        self.wallpaper_scene_buffer = scene_buffer;
        // Wallpaper is the BOTTOM of the stack, never the top. A freshly
        // created scene node lands above every sibling — windows included —
        // which veiled the whole screen in the wallpaper image whenever an
        // output's wallpaper was (re)created after clients mapped (the
        // "mythical mist" bug, 2026-09-05). Lower it explicitly, then
        // re-assert overlay-topmost so the peeks and widgets stay visible.
        scene_buffer.node.lowerToBottom();
        // lowerToBottom puts the wallpaper under the solid bg_rect too —
        // raise it back to sit directly above the background colour.
        if (server.background.node) |bg_node| {
            scene_buffer.node.placeAbove(bg_node);
        }
        server.overlay_tree.node.raiseToTop();
    }

    /// Create or destroy this output's transient boot-reveal overlay: a
    /// fullscreen tinted copy fading out above the permanent wallpaper.
    pub fn setupWallpaperReveal(self: *Output, server: *Server, tinted_buffer: ?*wlr.Buffer) void {
        if (self.wallpaper_reveal_buffer) |sb| {
            sb.node.destroy();
            self.wallpaper_reveal_buffer = null;
        }
        const buf = tinted_buffer orelse return;
        var box: wlr.Box = undefined;
        server.output_layout.getBox(self.wlr_output, &box);
        if (box.width <= 0 or box.height <= 0) return;
        const scene_buffer = server.scene.tree.createSceneBuffer(buf) catch return;
        scene_buffer.setDestSize(box.width, box.height);
        scene_buffer.node.setPosition(box.x, box.y);
        scene_buffer.setOpacity(1.0);
        // Sit directly above the permanent wallpaper, below everything else.
        if (self.wallpaper_scene_buffer) |wp| {
            scene_buffer.node.placeAbove(&wp.node);
        } else {
            scene_buffer.node.lowerToBottom();
        }
        server.overlay_tree.node.raiseToTop();
        self.wallpaper_reveal_buffer = scene_buffer;
    }

    pub fn deinit(self: *Output) void {
        self.frame.link.remove();
        self.destroy.link.remove();
        self.deck.deinit();
        if (self.wallpaper_reveal_buffer) |sb| {
            sb.node.destroy();
            self.wallpaper_reveal_buffer = null;
        }
        if (self.wallpaper_scene_buffer) |sb| {
            sb.node.destroy();
            self.wallpaper_scene_buffer = null;
        }
        // Home/media/video slide surfaces die with the output (their scene
        // trees live in the output's render path). Playback itself lives in
        // kplayd (out of process) — nothing here can dangle decoded frames.
        while (!self.server.scene_mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.server.scene_mutex.unlock();
        if (self.home_slide.tree) |tree| {
            tree.node.destroy();
            self.home_slide.tree = null;
            self.home_slide.card_buffer = null;
            self.home_slide.chrome_buffer = null;
        }
        self.peek.deinit();
    }

    fn handleFrame(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
        const self: *Output = @fieldParentPtr("frame", listener);
        _ = wlr_output;
        // SCENE LOCK: hold for the whole frame — slide buffers and
        // scene_output.commit walk the graph the IPC thread can mutate.
        while (!self.server.scene_mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.server.scene_mutex.unlock();
        const now_us = animation.nowUs();
        self.server.ft_rendered += 1;
        self.ft_rendered += 1;
        if (now_us -| self.server.ft_last_log_us >= 1_000_000) {
            self.server.ft_last_log_us = now_us;
            std.log.info("KidulWM: FRAMETRACE rendered={d} layout={d} peek={d} scale={d} reveal={d} notify={d} commit={d} ghostty={d} kplay={d} other={d}", .{
                self.server.ft_rendered, self.server.ft_layout, self.server.ft_peek,
                self.server.ft_scale, self.server.ft_reveal, self.server.ft_notify,
                self.server.ft_commit,
                self.server.ft_commit_ghostty, self.server.ft_commit_kplay, self.server.ft_commit_other,
            });
            var oit = self.server.outputs.iterator(.forward);
            while (oit.next()) |out| {
                std.log.info("KidulWM: FRAMETRACE-OUT {s} rendered={d}", .{ out.wlr_output.name, out.ft_rendered });
            }
        }
        var it = self.server.windows.iterator(.forward);
        while (it.next()) |window| {
            _ = window.tickAnimation(now_us);
        }
        self.server.tickWallpaperReveal(now_us);
        self.server.tickFullscreen(now_us);

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
    /// Layer-shell strata, bottom to top: background, bottom, top, overlay.
    /// Created before overlay_tree so the compositor chrome/peeks stay above
    /// every layer client (slurp draws beneath our widgets).
    layer_trees: [4]*wlr.SceneTree,
    overlay_tree: *wlr.SceneTree,
    output_layout: *wlr.OutputLayout,
    scene_output_layout: *wlr.SceneOutputLayout,
    output_arrangement: output_layout_config.OutputLayout,
    xdg_shell: *wlr.XdgShell,
    layer_shell: *wlr.LayerShellV1,
    output_manager: *wlr.OutputManagerV1,

    shm: *wlr.Shm,
    subcompositor: *wlr.Subcompositor,
    data_device_manager: *wlr.DataDeviceManager,
    viewporter: *wlr.Viewporter,
    screencopy_manager: *wlr.ScreencopyManagerV1,
    fractional_scale_manager: *wlr.FractionalScaleManagerV1,

    seat: *wlr.Seat,
    cursor: *wlr.Cursor,
    xcursor_manager: *wlr.XcursorManager,
    input_manager: *InputManager,
    pointer: PointerManager,
    keyboard: KeyboardManager,
    cursor_x: f64,
    cursor_y: f64,

    ipc_server: ipc.control.Server,
    /// Guards the wlroots scene graph against cross-thread mutation.
    /// (Phase 0 retires the IPC thread, so this is now uncontended on the
    /// main loop — kept as a no-op guard pending a dedicated removal card.)
    /// Held per-frame; scene touch that could cross threads waits ≤ 1 vsync.
    scene_mutex: std.atomic.Mutex = .unlocked,

    state: State,
    theme: style.Style,
    theme_runtime: Theme,
    deck_split: slidedeck.Split,
    deck_orientation: slidedeck.Orientation,
    windows: wl.list.Head(Window, .link),
    layer_surfaces: wl.list.Head(LayerSurface, .link),

    deck: slidedeck.SlideDeck,
    layout_pipe: [2]c_int,
    layout_source: *wl.EventSource,
    layout_requested: std.atomic.Value(bool),

    focused_window: ?*Window,
    keybinds: keybinds.Keybinds,
    focused_window_id: u32 = 0,
    focused_output: ?*Output = null,
    /// Set while warping the cursor to follow focus, so the resulting motion
    /// event does not retrigger focus-follows-cursor (the two halves of
    /// "follow the leader" must not chase each other).
    suppress_focus_follow: bool = false,
    last_focused_slide_id: u32 = 0,
    current_transition_kind: animation.AnimationKind = .snap,
    next_window_id: u32 = 1,

    /// Phase 2 step 2 (verdict 45): frame-source diagnostic counters. Single-
    /// threaded main loop, so plain u64 (no atomics). ft_rendered counts
    /// handleFrame invocations; each ft_* site counts scheduleFrame arms;
    /// FRAMETRACE logs once per second from handleFrame so the per-source rate
    /// names whoever schedules frames at idle.
    ft_rendered: u64 = 0,
    ft_layout: u64 = 0,
    ft_peek: u64 = 0,
    ft_scale: u64 = 0,
    ft_reveal: u64 = 0,
    ft_notify: u64 = 0,
    ft_commit: u64 = 0,
    ft_commit_ghostty: u64 = 0,
    ft_commit_kplay: u64 = 0,
    ft_commit_other: u64 = 0,
    ft_last_log_us: u64 = 0,

    /// Minimal notification feed (stage 2 demolition): replaces the dead
    /// overlay tray's NotificationWidget. Rendered by the home slide's
    /// NOTIFICATIONS CFC section.
    notifications: tray_slide_mod.NotificationStore = .{},
    /// The media PLAYER's home (Barticus law 2026-09-15): Server owns the
    /// MediaWidget. CARD 2b slice 4: playback itself is out of process in
    /// kplayd; this widget is the card UI + the now-playing MIRROR (cached
    /// metadata set on kplay open, cleared on close).
    media_player: media_mod.MediaWidget,
    // Overview lens: virtual cursor (recency position among unparked minis).
    // The ring node lives per-output (Output.overview_ring) — the lens is
    // per-output by ruling.
    overview_cursor: usize = 0,
    input_device_counts: InputDeviceCounts,
    backend_started: bool = false,
    /// A5 boot ladder latch: the media PLAYER slide is spawned once, on the
    /// first output to land.
    boot_player_spawned: bool = false,
    /// FULLSCREEN-IS-A-MODE (fullscreen.md): true while a video plays
    /// fullscreen over its card. The card stays a normal focused slide; the
    /// deck does NOT move; kplayd's surface is pinned edge-to-edge over this
    /// output; a black curtain fades the deck in/out. One per session.
    video_fullscreen: bool = false,
    /// Output owning the fullscreen video (the card's row). Null while off.
    video_fullscreen_output: ?*Output = null,
    /// Deferred fullscreen-enter. handleRequest runs INSIDE control.zig's
    /// readClient parse loop (a main-loop fd-source callback). Entering
    /// fullscreen -> videoHostSpawn -> InternalClient.create ->
    /// pumpRoundtrip -> event_loop.dispatch(1) RE-ENTERS the loop, re-firing
    /// the control-socket fd source and corrupting readClient's in-flight
    /// buffer. So the enter is deferred to handleLayoutEventFd (the layout
    /// pipe), the one fd-source that is already the proven-safe re-entry point.
    pending_video_spawn: ?*Output = null,
    /// Black fade curtain: a fullscreen 1x1 black scene buffer, opacity-ramped
    /// only (Fade-only law — GPU-free, one float on the node). Created on
    /// fullscreen enter, destroyed at rest. Sits above the deck + peeks, below
    /// kplayd (z: deck < overlay_tree < curtain < kplay_window).
    curtain_buffer: ?*wlr.SceneBuffer = null,
    /// Curtain fade state machine. ~180ms per phase, smoothstepped, driven
    /// per-frame like the wallpaper reveal (tickFullscreen).
    curtain_anim: struct {
        phase: FullscreenPhase = .idle,
        start_us: u64 = 0,
    } = .{},
    /// Peek widget timer (right-peek clock painter + widget polls, on the
    /// minute).
    peek_widget_timer: ?*wl.EventSource = null,
    /// Shared peek widget state (weather/gauge/drives/network + KSD logo
    /// surface). Initialized at server init — never lazily.
    peek_widgets: peek_mod.Widgets = undefined,
    chrome_style_generation: u32,

    /// Last N pressed key events for the bobPI/debug probe. Lock-free enough:
    /// written on the main thread only, read by the IPC thread via memcpy.
    key_ring: [32]KeyRingEntry = [_]KeyRingEntry{.{}} ** 32,
    key_ring_pos: usize = 0,
    key_events_seen: u64 = 0,

    decoration_manager: *wlr.XdgDecorationManagerV1,

    /// xdg-foreign (CARD 2b, kplay attack): the media slide exports its
    /// surface, kplayd imports the handle and parents its video surface.
    /// Registry first, then the v2 globals (exporter + importer).
    xdg_foreign_registry: *wlr.XdgForeignRegistry,
    xdg_foreign_v2: *wlr.XdgForeignV2,

    /// CARD 2b slice 1: the compositor's own Wayland client for slide-host
    /// surfaces (one host xdg_toplevel per fullscreen video session). Created
    /// lazily on first fullscreen enter; null until then.
    internal_client: ?*@import("ipc/internal_client.zig").InternalClient = null,

    /// CARD 2b slice 3: kplayd's video toplevel (app_id "com.kidul.kplay"),
    /// tracked server-side OUTSIDE the deck/windows list — no deck slide,
    /// no chrome, no focus. Its scene tree is pinned edge-to-edge over the
    /// fullscreen output (placeKplayWindow). Null while kplayd has no
    /// video surface up.
    kplay_window: ?*Window = null,

    new_output: wl.Listener(*wlr.Output),
    new_toplevel_decoration: wl.Listener(*wlr.XdgToplevelDecorationV1),
    backend_destroy: wl.Listener(*wlr.Backend),
    new_xdg_toplevel: wl.Listener(*wlr.XdgToplevel),
    new_layer_surface: wl.Listener(*wlr.LayerSurfaceV1),
    output_layout_change: wl.Listener(*wlr.OutputLayout),

    background: struct {
        node: ?*wlr.SceneNode,
        color: [4]f32,
        rect: ?*wlr.SceneRect,
        image_buffer: ?*wlr.Buffer,
        image_scene_buffer: ?*wlr.SceneBuffer,
    },
    /// Async wallpaper pipeline (2026-09-05): the PNG decodes on a worker
    /// thread so boot paints widgets instantly on the theme-colour rect;
    /// the worker signals wallpaper_pipe and the main thread builds the
    /// DataBuffer + per-output nodes in handleWallpaperEventFd, then runs
    /// a ~2.2s palette-locked reveal animation chosen at random per boot.
    wallpaper_pipe: [2]c_int,
    wallpaper_source: ?*wl.EventSource,
    wallpaper_thread: ?std.Thread,
    /// Worker->main handoff. Written ONLY by the worker before the pipe
    /// byte; read ONLY by the main thread after reading the pipe byte.
    wallpaper_result: ?WallpaperResult,
    /// Transient tinted-copy buffer for the boot reveal overlay. Owned by
    /// the server, dropped when the fade completes (or on wallpaper
    /// reload/deinit). The permanent wallpaper buffer holds MASTER pixels
    /// from the start and is never touched by the animation.
    wallpaper_reveal_wlr_buffer: ?*wlr.Buffer = null,
    wallpaper_anim: struct {
        active: bool,
        start_us: u64,
        effect: WallpaperEffect,
        progress: f64,
    },
    outputs: wl.list.Head(Output, .link),
    /// Screens-off state (anti-burn blanking). While true, every output is
    /// committed disabled; any key press or another screen_off press wakes.
    screens_off: bool = false,
    /// smartLock (2026-09-17): idle-blank machinery. last_input_us is
    /// stamped on every key/button/motion/axis; a minute-tick timer fires
    /// screensOffSet(true) when idle >= keybinds.blank.timeout_s and
    /// playbackInhibitsBlank() is false.
    last_input_us: u64 = 0,
    blank_timer: ?*wl.EventSource = null,
    /// gracePeriod (2026-09-19): MONOTONIC-µs deadline while input is
    /// swallowed after a fade-into-existence (wake). Blind input — a
    /// password typed at a black screen, an accidental two-key mash, a
    /// blind click — is discarded, never forwarded to the focused slide.
    /// 0 = not in grace. Checked by keyboard.zig handleKey and every
    /// pointer.zig handler.
    input_grace_until_us: u64 = 0,
    /// Session master volume (2026-09-17): 0.0-1.0. Compositor-owned —
    /// ksound owns per-stream policy/floor, we own the user-facing knob.
    /// Applied via pactl set-sink-input-volume @DEFAULT_SINK@ per press
    /// (same pactl pattern ksound's real_backend uses for unmute/100%).
    master_volume: f32 = 1.0,
    master_muted: bool = false,

    /// Catcher for dropped outputs. Every early-return error path in
    /// handleNewOutput records (name, stage, err) here instead of vanishing
    /// into the log scroll. Surfaced in writeBootCheck so a black screen is
    /// one file-read away from its cause. Fixed-size: drops beyond the cap
    /// still hit the log, just not the record.
    output_drops: [8]OutputDrop = undefined,
    output_drop_count: usize = 0,

    pub const DropStage = enum { init_render, commit_state, layout_add, scene_output, alloc };

    pub const OutputDrop = struct {
        name: [64]u8 = undefined,
        name_len: usize = 0,
        stage: DropStage = .alloc,
        err: ?anyerror = null,
    };

    fn recordOutputDrop(self: *Server, wlr_output: *wlr.Output, stage: DropStage, err: ?anyerror) void {
        if (self.output_drop_count >= self.output_drops.len) return;
        const rec = &self.output_drops[self.output_drop_count];
        const name_span = std.mem.span(wlr_output.name);
        const n = @min(name_span.len, rec.name.len);
        @memcpy(rec.name[0..n], name_span[0..n]);
        rec.name_len = n;
        rec.stage = stage;
        rec.err = err;
        self.output_drop_count += 1;
        std.log.err("KidulWM: OUTPUT DROPPED {s} stage={s} err={?}", .{ name_span, @tagName(stage), err });
    }

    fn getWindowsResponse(self: *Server) ipc.message.Response {
        var list = std.ArrayList(ipc.message.WindowInfo).initCapacity(self.allocator, 16) catch return .{ .ok = true, .windows = &[_]ipc.message.WindowInfo{} };
        defer list.deinit(self.allocator);
        var it = self.windows.iterator(.forward);
        while (it.next()) |window| {
            const info = ipc.message.WindowInfo{
                .window_id = window.id,
                .app_id = if (window.app_id.len > 0) self.allocator.dupe(u8, window.app_id.buf[0..window.app_id.len]) catch null else null,
                .title = if (window.title.len > 0) self.allocator.dupe(u8, window.title.buf[0..window.title.len]) catch null else null,
                .mapped = window.toplevel.base.surface.mapped,
            };
            list.append(self.allocator, info) catch continue;
        }
        return .{ .ok = true, .windows = list.toOwnedSlice(self.allocator) catch &[_]ipc.message.WindowInfo{} };
    }

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
                // Remote/IPC target (A6): same as the keybind — focus the
                // home slide if this row has one, else spawn one at index 0.
                self.homeSlideFocusOrSpawn();
                return .{ .ok = true };
            },
            .arrange_outputs => {
                // Re-read the declared arrangement (outputs.toml) and re-place
                // every output. Fixes a live mirrored session without restart.
                // VALIDATE FIRST: a broken config must never touch live state.
                var v = output_layout_config.validate(self.allocator);
                if (!v.ok()) {
                    const msg = v.problems.items[0];
                    self.notificationAdd("WM reset blocked", msg, "kidulwm", "high", null, null);
                    return .{ .ok = false, .message = msg };
                }
                self.arrangeOutputsLive();
                return .{ .ok = true, .message = "outputs re-arranged" };
            },
            .kadence => |p| {
                return self.setStageKadence(p.output, p.width, p.height, p.refresh_mhz, p.scale);
            },
            .media_card_toggle => {
                // REDIRECT (TASKCARD-3): focus the media player slide if
                // this row has one, else spawn it — a real deck slide.
                self.mediaSlideFocusOrSpawn();
                return .{ .ok = true };
            },
            .media_play => |p| {
                // CARD 2b slice 4: playback = kplay.sock verbs only. The
                // compositor never decodes a frame; kplayd owns the player.
                self.kplayCloseAny(); // one player, one truth
                self.kplayOpen(p.path);
                // FULLSCREEN IS A MODE (fullscreen.md): non-music playback
                // enters fullscreen mode on the media card's output. The card
                // never moves; a curtain fades it out and the video fades in.
                if (!isMusicPath(p.path)) {
                    var oit = self.outputs.iterator(.forward);
                    while (oit.next()) |o| {
                        if (o.deck.findKind(.media_player) != null and o.media_slide.isOpen()) {
                            // DEFER to handleLayoutEventFd (main loop, layout
                            // pipe). Entering fullscreen spawns the host surface
                            // + pumps the event loop, which must not re-enter
                            // readClient's parse loop (buffer corruption). The
                            // deferral is about RE-ENTRANCY, not thread safety.
                            self.pending_video_spawn = o;
                            self.requestLayout();
                            break;
                        }
                    }
                }
                return .{ .ok = true, .message = "media play requested" };
            },
            .media_toggle => {
                self.kplayTogglePause();
                return .{ .ok = true };
            },
            .media_next => {
                return .{ .ok = true };
            },
            .media_prev => {
                return .{ .ok = true };
            },
            .media_seek => |p| {
                self.kplaySeekRel(p.seconds);
                return .{ .ok = true };
            },
            .notification_test => |p| {
                self.notificationAdd(p.title, p.body, p.source_id, p.priority, p.action_id, p.display_mode);
                return .{ .ok = true, .message = "notification added" };
            },
            .notification_clear => {
                self.notifications.clear();
                return .{ .ok = true, .message = "notifications cleared" };
            },
            .kfiles_navigate => |p| {
                // Write navigation target to a file kfiles polls. This avoids
                // adding a server socket inside the standalone client.
                const f = c.fopen("/tmp/kfiles-navigate", "w");
                if (f == null) {
                    return .{ .ok = false, .message = "failed to create navigate file" };
                }
                defer _ = c.fclose(f.?);
                _ = c.fprintf(f.?, "%s\n", p.path.ptr);
                return .{ .ok = true, .message = "navigate queued" };
            },
            .get_windows => return self.getWindowsResponse(),
            .debug_status => return self.getDebugStatusResponse(),
            .scene_dump => return self.getSceneDumpResponse(),
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
            .set_theme, .reload_theme, .arrange_outputs, .kadence, .tray_toggle, .media_card_toggle, .media_play, .media_toggle, .media_next, .media_prev, .media_seek, .notification_test, .notification_clear, .kfiles_navigate, .get_windows, .debug_status, .scene_dump, .quit => {},
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
        // xdg-output: grim/slurp/wlr-randr and every screencopy client read
        // output names/logical boxes from zxdg_output_manager_v1. Without it
        // grim guessed a 0x0 layout and captured nothing (2026-09-16).
        // Auto-tracks the output layout; no per-output wiring needed.
        _ = try wlr.XdgOutputManagerV1.create(wl_server, output_layout);
        const compositor = try wlr.Compositor.create(wl_server, 6, renderer);
        const scene = try wlr.Scene.create();
        // zwlr_gamma_control_v1: night-light / colour-temperature clients
        // (gammastep, wlsunset, noctalia nightlight) submit per-output gamma
        // LUTs; the scene graph owns set_gamma and applies the LUT at commit.
        const gamma_control_manager = try wlr.GammaControlManagerV1.create(wl_server);
        scene.setGammaControlManagerV1(gamma_control_manager);
        const scene_output_layout = try scene.attachOutputLayout(output_layout);
        const xdg_shell = try wlr.XdgShell.create(wl_server, 6);
        // zwlr_layer_shell_v1 (version 5): slurp and any future layer
        // client. Scene-backed; surfaces live in the scene's own strata
        // below the compositor overlay_tree.
        const layer_shell = try wlr.LayerShellV1.create(wl_server, 5);
        const shm = try wlr.Shm.createWithRenderer(wl_server, 1, renderer);
        const subcompositor = try wlr.Subcompositor.create(wl_server);
        const data_device_manager = try wlr.DataDeviceManager.create(wl_server);
        const viewporter = try wlr.Viewporter.create(wl_server);
        const screencopy_manager = try wlr.ScreencopyManagerV1.create(wl_server);
        const fractional_scale_manager = try wlr.FractionalScaleManagerV1.create(wl_server, 1);
        const decoration_manager = try wlr.XdgDecorationManagerV1.create(wl_server);
        // xdg-foreign v2 (CARD 2b): registry shared by both globals.
        const xdg_foreign_registry = try wlr.XdgForeignRegistry.create(wl_server);
        const xdg_foreign_v2 = try wlr.XdgForeignV2.create(wl_server, xdg_foreign_registry);

        const seat = try wlr.Seat.create(wl_server, "seat0");
        seat.setCapabilities(.{ .pointer = true, .keyboard = true });

        const cursor = try wlr.Cursor.create();
        cursor.attachOutputLayout(output_layout);

        const xcursor_manager = try wlr.XcursorManager.create(null, 24);
        try xcursor_manager.load(1);
        cursor.setXcursor(xcursor_manager, "left_ptr");

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
            .output_arrangement = output_layout_config.load(allocator),
            .xdg_shell = xdg_shell,
            .layer_shell = layer_shell,
            .output_manager = output_manager,
            .shm = shm,
            .subcompositor = subcompositor,
            .data_device_manager = data_device_manager,
            .viewporter = viewporter,
            .screencopy_manager = screencopy_manager,
            .fractional_scale_manager = fractional_scale_manager,
            .decoration_manager = decoration_manager,
            .xdg_foreign_registry = xdg_foreign_registry,
            .xdg_foreign_v2 = xdg_foreign_v2,
            .seat = seat,
            .cursor = cursor,
            .xcursor_manager = xcursor_manager,
            .input_manager = undefined,
            .pointer = undefined,
            .keyboard = undefined,
            .cursor_x = 0,
            .cursor_y = 0,
            .input_device_counts = .{},
            .layer_trees = undefined,
            .focused_window = null,
            .ipc_server = undefined,
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
            .layer_surfaces = undefined,
            .layout_requested = std.atomic.Value(bool).init(false),
            .keybinds = keybinds.Keybinds.load(allocator),
            .deck = slidedeck.SlideDeck.init(allocator),
            .layout_pipe = undefined,
            .layout_source = undefined,
            .new_output = undefined,
            .new_toplevel_decoration = undefined,
            .backend_destroy = undefined,
            .new_xdg_toplevel = undefined,
            .new_layer_surface = undefined,
            .output_layout_change = undefined,
            .background = .{
                .node = null,
                .rect = null,
                .color = style.default_style.color_background.toF32(),
                .image_buffer = null,
                .image_scene_buffer = null,
            },
            .wallpaper_pipe = undefined,
            .wallpaper_source = null,
            .wallpaper_thread = null,
            .wallpaper_result = null,
            .wallpaper_anim = .{ .active = false, .start_us = 0, .effect = .fade, .progress = 0 },
            .overlay_tree = undefined,
            .outputs = undefined,
            .chrome_style_generation = 0,
            .media_player = undefined,
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

        var li: usize = 0;
        while (li < 4) : (li += 1) {
            server.layer_trees[li] = try server.scene.tree.createSceneTree();
        }
        // overlay_tree created AFTER the layer strata: sibling creation order
        // is stacking order, so compositor chrome/peeks render above every
        // layer client (slurp's scrim sits under our widgets).
        const overlay_tree = try server.scene.tree.createSceneTree();
        server.overlay_tree = overlay_tree;

        server.media_player = media_mod.MediaWidget.init(server.allocator);

        // Peek widgets: initialized at server init, never lazily — they
        // paint from the first frame on every output birth.
        server.peek_widgets = peek_mod.Widgets.init(server.allocator, &server.theme_runtime);
        server.peek_widgets.update();

        const bg_rect = try server.scene.tree.createSceneRect(1, 1, &server.background.color);
        server.background.rect = bg_rect;
        server.background.node = &bg_rect.node;
        // The background colour is the floor of the stack — pin it there so
        // later nodes (wallpaper, windows) never slip beneath it.
        bg_rect.node.lowerToBottom();

        // Wallpaper decodes on a worker thread (widgets-first boot law,
        // 2026-09-05): the theme-colour rect above paints immediately, the
        // PNG lands when ready and a random palette-locked reveal animation
        // runs. The pipe fd below is armed next to layout_pipe; the worker
        // thread is spawned there too (it needs the pipe write end).
        server.spawnWallpaperWorker(event_loop) catch |err| {
            std.log.warn("KidulWM: wallpaper worker unavailable ({}), keeping theme colour", .{err});
        };

        // Background/wallpaper nodes were created after the overlay tree, so
        // ensure it stays on top of the background for immediate visibility.
        server.overlay_tree.node.raiseToTop();

        server.pointer.init(server);
        server.keyboard.init(server);
        server.windows.init();
        server.layer_surfaces.init();
        server.input_manager = try server.allocator.create(InputManager);
        InputManager.init(server.input_manager, server);

        // Boot-time media library pre-warm: scans all categories and
        // warms dentry caches on a background thread, so the first
        // media slide open hits warm data, not SSHFS cold reads.
        media_mod.spawnPrewarm();

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

        server.new_layer_surface = wl.Listener(*wlr.LayerSurfaceV1).init(handleNewLayerSurface);
        server.new_layer_surface.link.init();
        layer_shell.events.new_surface.add(&server.new_layer_surface);

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

        // Peek widget timer: right-peek clock repaint on the minute, plus
        // the weather/network state polls (the old overlay's update()
        // pattern — weather reads its 10-min cache internally, network
        // scans every 2s internally; the minute tick just pokes both).
        server.peek_widget_timer = try event_loop.addTimer(*Server, handlePeekWidgetTimer, server);
        try server.peek_widget_timer.?.timerUpdate(msToNextMinute());

        // smartLock (2026-09-17): idle-blank poll timer. Fires on a 30 s
        // cadence (or the conf'd timeout, whichever is sooner); blanks when
        // idle >= blankscreen_timeout and playback doesn't inhibit.
        server.blank_timer = try event_loop.addTimer(*Server, Server.handleBlankTimer, server);
        server.noteInputActivity();

        return server;
    }

    fn msToNextMinute() c_int {
        var ts: linux.timespec = undefined;
        _ = linux.clock_gettime(linux.CLOCK.REALTIME, &ts);
        const into_min: i64 = @mod(@as(i64, ts.sec), 60);
        return @intCast((60 - into_min) * 1000);
    }

    fn handlePeekWidgetTimer(self: *Server) c_int {
        self.peek_widgets.update();
        var it = self.outputs.iterator(.forward);
        while (it.next()) |output| {
            output.peek.refreshClock();
            output.peek.refreshWidgets(&self.peek_widgets);
            self.ft_peek += 1;
            output.wlr_output.scheduleFrame();
        }
        self.peek_widget_timer.?.timerUpdate(msToNextMinute()) catch {};
        return 0;
    }

    pub fn createIpcSocket(self: *Server, path: []const u8) !void {
        self.socket_path = path;
        self.ipc_server = try ipc.control.Server.create(self.allocator, .{
            .socket_path = path,
            .event_loop = self.wl_server.getEventLoop(),
            .state = self,
            .handler = struct {
                fn handle(s: *anyopaque, req: ipc.message.Request) ipc.message.Response {
                    return @as(*Server, @ptrCast(@alignCast(s))).handleRequest(req);
                }
            }.handle,
        });
        // Phase 0 (I5): the control socket is a main-loop fd source, not a
        // thread. handleLine/handleRequest run on the main loop.
        try self.ipc_server.start();
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

        // I1 single-authority seed (Card 1.5): publish our socket name as
        // WAYLAND_DISPLAY in our OWN environment, so every spawned tentacle
        // inherits it downstream — never re-typed in a spawn string. setenv
        // copies, so this is safe even when `name` points into the
        // auto-socket stack buffer.
        _ = setenv("WAYLAND_DISPLAY", name.ptr, 1);

        if (!no_backend) {
            try self.backend.start();
            self.backend_started = true;
            std.log.info("KidulWM: backend started", .{});
            self.writeBootCheck();
        } else {
            std.log.info("KidulWM: skipping backend start", .{});
            const event_loop = self.wl_server.getEventLoop();
            const shutdown_source = try event_loop.addTimer(*@This(), handleShutdownTimer, self);
            try shutdown_source.timerUpdate(8000);
        }

        // CARD 2b slice 1 smoke test (KIDULWM_INTERNAL_CLIENT_TEST=1):
        // exercise the internal client + export handshake at boot and log
        // the handle. Opt-in only; normal boots skip it entirely.
        if (std.c.getenv("KIDULWM_INTERNAL_CLIENT_TEST") != null) {
            std.log.info("KidulWM: [2b-smoke] env set, running smoke test", .{});
            self.runInternalClientSmokeTest();
        }

        self.wl_server.run();
    }

    pub fn deinit(self: *Server) void {
        // Internal client teardown before destroyClients — it IS a client.
        if (self.internal_client) |ic| {
            ic.destroy();
            self.internal_client = null;
        }
        // Disconnect all clients before tearing down globals, otherwise
        // wl_display_destroy asserts if clients are still connected.
        self.wl_server.destroyClients();

        self.ipc_server.destroy();

        self.media_player.deinit();
        self.keybinds.deinit();

        self.input_manager.deinit();
        self.allocator.destroy(self.input_manager);
        self.pointer.deinit();
        self.keyboard.deinit();
        self.deck.deinit();

        _ = linux.close(self.layout_pipe[0]);
        _ = linux.close(self.layout_pipe[1]);

        // Tear down outputs BEFORE overlay_tree: each output's peek holds
        // child scene trees of overlay_tree, so destroying the parent first
        // leaves the children's destroy() touching freed wlroots state
        // (nested-smoke teardown segfault at peek.deinit).
        while (self.outputs.first()) |output| {
            output.link.remove();
            output.deinit();
            self.allocator.destroy(output);
        }
        self.overlay_tree.node.destroy();

        self.output_layout_change.link.remove();
        self.new_xdg_toplevel.link.remove();
        self.new_layer_surface.link.remove();
        self.new_output.link.remove();
        self.backend_destroy.link.remove();
        self.new_toplevel_decoration.link.remove();

        self.cursor.destroy();
        self.xcursor_manager.destroy();

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
            self.ft_layout += 1;
            output.wlr_output.scheduleFrame();
        }
    }

    pub fn requestUpdateCapabilities(self: *Server) void {
        self.seat.setCapabilities(.{
            .pointer = self.input_device_counts.pointer > 0,
            .keyboard = self.input_device_counts.keyboard > 0,
        });
    }

    /// Record one pressed key event into the debug ring. Called from the
    /// keyboard handler before any swallow decision; `note` is the keybind
    /// action name or the subsystem that swallowed the event.
    pub fn recordKeyEvent(self: *Server, sym: u32, mod4: bool, ctrl: bool, note: []const u8) void {
        var entry = &self.key_ring[self.key_ring_pos % self.key_ring.len];
        entry.* = .{ .sym = sym, .mod4 = mod4, .ctrl = ctrl };
        entry.setAction(note);
        self.key_ring_pos += 1;
        self.key_events_seen += 1;
    }

    /// Boot checklist: runs after backend start, writes a plain-text verdict
    /// for bobPI / post-mortem reading. Same content goes to the session log.
    pub fn writeBootCheck(self: *Server) void {
        var report = std.ArrayList(u8).empty;
        defer report.deinit(self.allocator);

        report.appendSlice(self.allocator, "kidulwm bootcheck\n") catch return;

        var output_count: usize = 0;
        var out_it = self.outputs.iterator(.forward);
        while (out_it.next()) |output| {
            output_count += 1;
            var box: wlr.Box = undefined;
            self.output_layout.getBox(output.wlr_output, &box);
            const wo = output.wlr_output;
            report.print(self.allocator, "output[{d}]: {s} mode={d}x{d}@{d} scale={d:.2} box={d},{d} {d}x{d} enabled={}\n", .{
                output_count,
                wo.name,
                wo.width,
                wo.height,
                wo.refresh,
                wo.scale,
                box.x,
                box.y,
                box.width,
                box.height,
                wo.enabled,
            }) catch return;
        }
        if (output_count == 0) report.appendSlice(self.allocator, "output: NONE — no displays attached\n") catch return;

        // The catcher: any output that hit an early-return error path in
        // handleNewOutput is named here with the exact stage that killed it.
        if (self.output_drop_count > 0) {
            report.print(self.allocator, "output_drops: {d}\n", .{self.output_drop_count}) catch return;
            for (self.output_drops[0..self.output_drop_count]) |drop| {
                report.print(self.allocator, "  drop: {s} stage={s} err={?}\n", .{
                    drop.name[0..drop.name_len],
                    @tagName(drop.stage),
                    drop.err,
                }) catch return;
            }
        }

        report.print(self.allocator, "keyboards: {d} pointers: {d}\n", .{
            self.input_device_counts.keyboard,
            self.input_device_counts.pointer,
        }) catch return;
        report.print(self.allocator, "keybinds: {d} loaded (source={s})\n", .{
            self.keybinds.binds.items.len,
            if (self.keybinds.fallback) "built-in" else "user config",
        }) catch return;
        report.print(self.allocator, "ipc_socket: {s}\n", .{self.socket_path}) catch return;
        report.appendSlice(self.allocator, "verdict: ") catch return;
        if (output_count == 0) {
            report.appendSlice(self.allocator, "FAIL no outputs\n") catch return;
        } else if (self.output_drop_count > 0) {
            report.print(self.allocator, "FAIL {d} output(s) dropped\n", .{self.output_drop_count}) catch return;
        } else if (self.input_device_counts.keyboard == 0) {
            report.appendSlice(self.allocator, "FAIL no keyboard\n") catch return;
        } else if (self.keybinds.binds.items.len == 0) {
            report.appendSlice(self.allocator, "FAIL no keybinds\n") catch return;
        } else {
            report.appendSlice(self.allocator, "OK\n") catch return;
        }

        std.log.info("bootcheck:\n{s}", .{report.items});
        // Persistent path: /tmp is tmpfs and wiped on reboot — the exact
        // failure mode this report exists for. Session log lives in the
        // same dir via kidulwm-session.
        const dir_z = "/home/dad/.local/state/kidulwm";
        _ = linux.mkdir(dir_z, 0o755);
        const path_z = "/home/dad/.local/state/kidulwm/bootcheck.txt";
        const fd = linux.open(path_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
        if (@as(isize, @bitCast(fd)) >= 0) {
            defer _ = linux.close(@intCast(fd));
            _ = linux.write(@intCast(fd), report.items.ptr, report.items.len);
        }
    }

    /// Scene-graph dump for `kidulwm-control scene_dump` — writes every scene
    /// node (type, enabled, world coords, dest size, opacity, owning window id
    /// for chrome trees tagged via node.data) to
    /// /home/dad/.local/state/kidulwm/scene_dump.txt. Read-only walk; used to
    /// hunt the "mist layer" and leaked chrome nodes across outputs.
    fn getSceneDumpResponse(self: *Server) ipc.message.Response {
        const alloc = self.allocator;
        var buf = std.ArrayList(u8).empty;
        defer buf.deinit(alloc);

        buf.appendSlice(alloc, "kidulwm scene dump\n") catch return .{ .ok = false };

        // Output layout boxes for reference.
        var out_it = self.outputs.iterator(.forward);
        while (out_it.next()) |output| {
            var box: wlr.Box = undefined;
            self.output_layout.getBox(output.wlr_output, &box);
            buf.print(alloc, "output {s} box={d},{d} {d}x{d} scale={d:.2}\n", .{
                output.wlr_output.name, box.x, box.y, box.width, box.height, output.wlr_output.scale,
            }) catch return .{ .ok = false };
        }
        buf.appendSlice(alloc, "-- tree --\n") catch return .{ .ok = false };

        dumpSceneTree(&buf, alloc, &self.scene.tree, 0);

        const path_z = "/home/dad/.local/state/kidulwm/scene_dump.txt";
        const fd = linux.open(path_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
        if (@as(isize, @bitCast(fd)) < 0) {
            std.log.err("scene_dump: open failed", .{});
            return .{ .ok = false, .message = "scene_dump: open failed" };
        }
        defer _ = linux.close(@intCast(fd));
        _ = linux.write(@intCast(fd), buf.items.ptr, buf.items.len);
        return .{ .ok = true, .message = "scene dump written to scene_dump.txt" };
    }

    fn dumpSceneTree(buf: *std.ArrayList(u8), alloc: std.mem.Allocator, tree: *wlr.SceneTree, depth: usize) void {
        var it = tree.children.iterator(.forward);
        while (it.next()) |node| {
            var i: usize = 0;
            while (i < depth) : (i += 1) buf.appendSlice(alloc, "  ") catch return;
            var lx: c_int = 0;
            var ly: c_int = 0;
            const has_coords = node.coords(&lx, &ly);
            const owner: []const u8 = if (node.data) |d| blk: {
                const win: *Window = @ptrCast(@alignCast(d));
                break :blk std.fmt.allocPrint(alloc, " window_id={d}", .{win.id}) catch "";
            } else "";
            switch (node.type) {
                .tree => {
                    buf.print(alloc, "tree enabled={} at={d},{d}{s}\n", .{ node.enabled, lx, ly, owner }) catch return;
                    const sub: *wlr.SceneTree = @fieldParentPtr("node", node);
                    dumpSceneTree(buf, alloc, sub, depth + 1);
                },
                .rect => {
                    const rect: *wlr.SceneRect = @fieldParentPtr("node", node);
                    buf.print(alloc, "rect enabled={} at={d},{d} size={d}x{d}{s}\n", .{ node.enabled, lx, ly, rect.width, rect.height, owner }) catch return;
                },
                .buffer => {
                    const sb: *wlr.SceneBuffer = @fieldParentPtr("node", node);
                    buf.print(alloc, "buffer enabled={} at={d},{d} dest={d}x{d} opacity={d:.2}{s}\n", .{ node.enabled, lx, ly, sb.dst_width, sb.dst_height, sb.opacity, owner }) catch return;
                },
            }
            _ = has_coords;
        }
    }

    /// JSON debug status for `kidulwm-control debug_status` — the bobPI probe.
    /// Called from the IPC thread; only reads main-thread-written state.
    fn getDebugStatusResponse(self: *Server) ipc.message.Response {
        const alloc = self.allocator;
        var buf = std.ArrayList(u8).empty;
        defer buf.deinit(alloc);

        buf.appendSlice(alloc, "{\"outputs\":[") catch return .{ .ok = false };
        var first = true;
        var out_it = self.outputs.iterator(.forward);
        while (out_it.next()) |output| {
            if (!first) buf.appendSlice(alloc, ",") catch return .{ .ok = false };
            first = false;
            var box: wlr.Box = undefined;
            self.output_layout.getBox(output.wlr_output, &box);
            const wo = output.wlr_output;
            buf.print(alloc, "{{\"name\":\"{s}\",\"mode\":[{d},{d}],\"refresh\":{d},\"scale\":{d:.2},\"box\":[{d},{d},{d},{d}],\"enabled\":{},\"overview_open\":{},\"media_open\":{}}}", .{
                wo.name,
                wo.width,
                wo.height,
                wo.refresh,
                wo.scale,
                box.x,
                box.y,
                box.width,
                box.height,
                wo.enabled,
                output.deck.overview_slide_open,
                output.media_slide.isOpen(),
            }) catch return .{ .ok = false };
        }
        buf.print(alloc, "],\"devices\":{{\"keyboards\":{d},\"pointers\":{d}}}", .{
            self.input_device_counts.keyboard,
            self.input_device_counts.pointer,
        }) catch return .{ .ok = false };
        buf.print(alloc, ",\"keybinds\":{{\"count\":{d},\"fallback\":{}}}", .{
            self.keybinds.binds.items.len,
            self.keybinds.fallback,
        }) catch return .{ .ok = false };
        buf.print(alloc, ",\"flags\":{{}}", .{}) catch return .{ .ok = false };
        buf.print(alloc, ",\"key_events_seen\":{d},\"key_ring\":[", .{self.key_events_seen}) catch return .{ .ok = false };
        // Oldest-first replay of the ring.
        const ring_count = @min(self.key_ring_pos, self.key_ring.len);
        var i: usize = 0;
        while (i < ring_count) : (i += 1) {
            const idx = (self.key_ring_pos - ring_count + i) % self.key_ring.len;
            const e = self.key_ring[idx];
            if (i > 0) buf.appendSlice(alloc, ",") catch return .{ .ok = false };
            buf.print(alloc, "{{\"sym\":{d},\"mod4\":{},\"ctrl\":{},\"note\":\"{s}\"}}", .{
                e.sym,
                e.mod4,
                e.ctrl,
                e.action[0..e.action_len],
            }) catch return .{ .ok = false };
        }
        buf.appendSlice(alloc, "]}") catch return .{ .ok = false };

        const owned = buf.toOwnedSlice(alloc) catch return .{ .ok = false };
        return .{ .ok = true, .data = owned };
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
                .slide_count = @intCast(deck.slides.items.len),
            },
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
        if (deck.slides.items[idx].parked) return;
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

    /// Return the output under the pointer, or null. THE CURSOR IS THE FOCUS
    /// YOU CAN SEE (CFC law): a NEW slide (media card, home launcher) opens on
    /// the stage the pointer rests on — never the stage that merely last held
    /// keyboard focus. This is the "each screen is its own slideDeck, the two
    /// never meet" routing authority: spawn goes by the pointer, focus-follow
    /// goes by currentDeck. The single global focused_output is a focus-follow
    /// hint only; it must never decide where a new slide is born.
    fn cursorOutput(self: *Server) ?*Output {
        self.syncCursorMirror();
        var oit = self.outputs.iterator(.forward);
        while (oit.next()) |output| {
            var box: wlr.Box = undefined;
            self.output_layout.getBox(output.wlr_output, &box);
            if (self.cursor_x >= @as(f64, @floatFromInt(box.x)) and
                self.cursor_x < @as(f64, @floatFromInt(box.x + box.width)) and
                self.cursor_y >= @as(f64, @floatFromInt(box.y)) and
                self.cursor_y < @as(f64, @floatFromInt(box.y + box.height)))
            {
                return output;
            }
        }
        return null;
    }

    /// The deck that receives a NEW slide: cursor output first (CFC law),
    /// fall back to currentDeck for headless/smoke runs and boot edges.
    fn spawnDeck(self: *Server) *slidedeck.SlideDeck {
        if (self.cursorOutput()) |output| return &output.deck;
        return self.currentDeck();
    }

    /// Assign a window to the best available output when it maps.
    /// CFC law: everything follows focus, and the CURSOR is the focus you
    /// can see. When the pointer rests on a different stage than the focused
    /// window, the pointer's stage owns new slides — otherwise Granny moves
    /// the mouse to the TV, clicks, and the app opens on the other screen.
    /// Keyboard-driven focus changes warp the cursor along (warpCursorToFocus),
    /// so the two halves can't stay in disagreement for long either way.
    pub fn assignOutput(self: *Server, window: *Window) void {
        if (window.output != null) return;
        // CFC law: the CURSOR's stage owns a new window before any focus
        // hint. Granny moves the mouse to the TV, clicks, and the app opens
        // on the TV — not on the stage that last held keyboard focus.
        if (self.cursorOutput()) |output| {
            window.output = output;
            return;
        }
        if (self.focused_output) |output| {
            window.output = output;
            return;
        }
        if (self.focused_window) |focused| {
            if (focused.output) |output| {
                window.output = output;
                return;
            }
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

    /// Toggle the overview slide on the current deck's output.
    /// The lens machinery is gone; this is the whole mode switch.
    pub fn overviewToggle(self: *Server) void {
        const deck = self.currentDeck();
        if (deck.slides.items.len == 0) return;
        // Find the output that owns this deck.
        var owner: ?*Output = null;
        var it = self.outputs.iterator(.forward);
        while (it.next()) |output| {
            if (&output.deck == deck) owner = output;
        }
        if (deck.overview_slide_open) {
            if (owner) |output| self.overviewSlideClose(output);
            deck.closeOverviewSlide();
            self.focusReturnFromOverview(deck);
        } else {
            // fullscreen.md LAW: navigation exits fullscreen — opening the
            // overview retires the playing video first (same as focusNext).
            if (self.video_fullscreen) self.videoFullscreenExit();
            // Siblings never both: if a home slide holds this row, destroy
            // it before the overview takes over the slot state.
            if (deck.findKind(.home) != null) {
                self.homeSlideClose();
            }
            deck.openOverviewSlide();
            self.overview_cursor = 0;
            if (owner) |output| self.overviewSlideOpen(output);
        }
        self.requestLayout();
    }

    fn focusReturnFromOverview(self: *Server, deck: *slidedeck.SlideDeck) void {
        if (deck.slides.items.len == 0) {
            self.clearFocus();
            return;
        }
        const slide = deck.slides.items[deck.focused_index];
        self.focused_window_id = slide.window_id;
        if (self.windowById(slide.window_id)) |window| {
            if (window.toplevel.base.surface.mapped) self.focusWindow(window);
        }
    }

    /// currentDeck, made public for input handlers.
    pub fn currentDeckPub(self: *Server) *slidedeck.SlideDeck {
        return self.currentDeck();
    }

    /// Move the overview virtual cursor one step (recomputes the card ring
    /// on the next layout). dir: -1 left/prev, +1 right/next, -2 up, +2 down.
    /// Wraps within the unparked set. Only meaningful with the overview open.
    pub fn overviewMoveCursor(self: *Server, dir: i32) void {
        const deck = self.currentDeck();
        if (!deck.overview_slide_open) return;
        const n = deck.unparkedCount();
        if (n == 0) return;
        const cols: usize = slidedeck.SlideDeck.overview_cols;
        const cur: isize = @intCast(self.overview_cursor);
        var next: isize = switch (dir) {
            -1 => cur - 1,
            1 => cur + 1,
            -2 => cur - @as(isize, @intCast(cols)),
            2 => cur + @as(isize, @intCast(cols)),
            else => cur,
        };
        const total: isize = @intCast(n);
        next = @mod(next, total);
        self.overview_cursor = @intCast(next);
        // Redraw the card so the ring moves.
        var it = self.outputs.iterator(.forward);
        while (it.next()) |output| {
            if (&output.deck == deck and output.overview.isOpen()) {
                self.overviewSlideClose(output);
                self.overviewSlideOpen(output);
            }
        }
        self.requestLayout();
    }

    /// Enter with the overview open: accept the slide under the virtual
    /// cursor (unparking if needed), close the overview, focus it.
    pub fn overviewAcceptFocused(self: *Server) void {
        const deck = self.currentDeck();
        if (!deck.overview_slide_open) return;
        if (deck.slides.items.len == 0) {
            self.overviewToggle();
            return;
        }
        const idx = deck.slideIndexAtRecency(self.overview_cursor) orelse blk: {
            break :blk @min(deck.overview_return_index, deck.slides.items.len - 1);
        };
        _ = deck.unparkIndex(idx);
        // Close first (restores reparented trees), then focus.
        var it = self.outputs.iterator(.forward);
        while (it.next()) |output| {
            if (&output.deck == deck) self.overviewSlideClose(output);
        }
        deck.overview_slide_open = false;
        deck.empty_slot = .none;
        deck.focused_index = idx;
        const win_id = deck.slides.items[idx].window_id;
        self.focused_window_id = win_id;
        if (self.windowById(win_id)) |window| {
            if (window.toplevel.base.surface.mapped) self.focusWindow(window);
        }
        self.requestLayout();
    }

    /// Open the overview slide's scene: card background + reparented minis.
    /// Tile rects and the card are both full-output-space, so reparented
    /// slide trees position directly at tile coords — no offset needed.
    fn overviewSlideOpen(self: *Server, output: *Output) void {
        if (output.overview.isOpen()) return;
        const deck = &output.deck;
        const tree = self.scene.tree.createSceneTree() catch return;
        output.overview.tree = tree;
        tree.node.raiseToTop();

        // Tile layout (cursor at recency 0 on open).
        output.overview.tile_count = overview_card.layoutTiles(deck, &output.overview.tiles, self.overview_cursor);

        // Card background sized to the FULL output (the slide fills the
        // focused area via layout; the card is the whole slide).
        var box: wlr.Box = undefined;
        self.output_layout.getBox(output.wlr_output, &box);
        const width = box.width;
        const height = box.height;
        const scale: u32 = @intFromFloat(@max(1.0, output.wlr_output.scale));
        deck.sync(@intCast(width), @intCast(height), self.state.gap, self.deck_split, self.deck_orientation);

        const surface = overview_card.renderCard(self.theme, width, height, scale, output.overview.tiles[0..output.overview.tile_count]) orelse {
            tree.node.destroy();
            output.overview.tree = null;
            return;
        };
        defer cairo.cairo_surface_destroy(surface);
        const pixels = overview_card.surfacePixels(surface);
        const buffer = DataBuffer.create(pixels.pixels, pixels.width, pixels.height, pixels.stride) catch {
            tree.node.destroy();
            output.overview.tree = null;
            return;
        };
        const card = tree.createSceneBuffer(buffer) catch {
            wlr.Buffer.drop(buffer);
            tree.node.destroy();
            output.overview.tree = null;
            return;
        };
        wlr.Buffer.drop(buffer);
        output.overview.card_buffer = card;
        // Same scale law as the media slide: rendered at physical pixels,
        // displayed at logical size.
        card.setDestSize(width, height);

        // Reparent each slide's scene tree into the card at its tile rect.
        for (output.overview.tiles[0..output.overview.tile_count], 0..) |t, i| {
            const slide = deck.slides.items[t.slide_index];
            const window = self.windowById(slide.window_id) orelse continue;
            output.overview.saved_parents[i] = &self.scene.tree;
            output.overview.saved_x[i] = @intFromFloat(@round(window.animation.cur_x));
            output.overview.saved_y[i] = @intFromFloat(@round(window.animation.cur_y));
            output.overview.saved_w[i] = @intFromFloat(@round(window.animation.cur_w));
            output.overview.saved_h[i] = @intFromFloat(@round(window.animation.cur_h));
            output.overview.saved_enabled[i] = window.scene_tree.node.enabled;
            window.scene_tree.node.reparent(tree);
            window.scene_tree.node.setPosition(t.x, t.y);
            window.scene_tree.node.setEnabled(true);
            window.setLayoutTarget(t.x, t.y, t.w, t.h);
            window.setSurfaceDestSize(@intCast(t.w), @intCast(t.h));
            window.applyContainment();
            window.clearChrome();
        }
        std.log.info("KidulWM: overview slide open on output, tiles={d}", .{output.overview.tile_count});
    }

    /// Close the overview slide: restore every reparented slide tree to the scene
    /// root with its saved geometry, then destroy the card tree.
    fn overviewSlideClose(self: *Server, output: *Output) void {
        if (!output.overview.isOpen()) return;
        const deck = &output.deck;
        for (output.overview.tiles[0..output.overview.tile_count], 0..) |t, i| {
            const slide = deck.slides.items[t.slide_index];
            const window = self.windowById(slide.window_id) orelse continue;
            if (output.overview.saved_parents[i]) |parent| {
                window.scene_tree.node.reparent(parent);
            }
            window.scene_tree.node.setEnabled(output.overview.saved_enabled[i]);
            window.setLayoutTarget(
                output.overview.saved_x[i],
                output.overview.saved_y[i],
                @intCast(@max(1, output.overview.saved_w[i])),
                @intCast(@max(1, output.overview.saved_h[i])),
            );
            window.scene_tree.node.setPosition(output.overview.saved_x[i], output.overview.saved_y[i]);
            window.setSurfaceDestSize(0, 0);
        }
        output.overview.tree.?.node.destroy();
        output.overview.tree = null;
        output.overview.card_buffer = null;
        output.overview.tile_count = 0;
        std.log.info("KidulWM: overview slide closed", .{});
    }

    // ── Home slide — REAL deck slide at index 0 (TASKCARD-3 stage 2) ─────

    /// Return the output that owns the given deck (compositor slide render
    /// target).
    fn outputForDeck(self: *Server, deck: *slidedeck.SlideDeck) ?*Output {
        var it = self.outputs.iterator(.forward);
        while (it.next()) |output| {
            if (&output.deck == deck) return output;
        }
        return null;
    }

    /// Focus the output that owns the given deck so follow-up focus changes
    /// keep landing on this row.
    fn focusOutputForDeck(self: *Server, deck: *slidedeck.SlideDeck) void {
        if (self.outputForDeck(deck)) |output| {
            self.focused_output = output;
        }
    }

    /// tray_toggle / weather_card / media_card target (A7): focus the home
    /// slide if this row has one, else spawn one at index 0 and focus it.
    /// At most one per row; never auto-respawned; standard quit destroys it.
    pub fn homeSlideFocusOrSpawn(self: *Server) void {
        const deck = self.spawnDeck();
        // Siblings never both: if the overview slide is open on this row,
        // close its scene tree before the home slide spawns into the row.
        if (deck.overview_slide_open) {
            if (self.outputForDeck(deck)) |output| self.overviewSlideClose(output);
            deck.overview_slide_open = false;
            deck.empty_slot = .none;
        }
        self.focusOutputForDeck(deck);
        if (deck.findKind(.home)) |idx| {
            deck.focusWindowByIndex(idx);
        } else {
            _ = deck.addCompositorSlide(.home, 0, true);
            if (self.outputForDeck(deck)) |output| {
                self.homeSlideOpen(output);
            }
        }
        self.clearFocus();
        self.requestLayout();
    }

    /// Standard quit on the home slide (A7): destroy it like any slide.
    /// Never auto-respawned; tray_toggle re-spawns on demand.
    pub fn homeSlideClose(self: *Server) void {
        const deck = self.currentDeck();
        if (deck.findKind(.home) == null) return;
        if (self.outputForDeck(deck)) |output| {
            self.homeSlideCloseOn(output);
        }
        _ = deck.removeCompositorSlide(.home);
        self.requestLayout();
    }

    /// EPHEMERAL LAW: activating a home-slide launcher item spawn/focuses
    /// the target slide, then the home slide destroys itself. v1: the
    /// launcher is keyboard-only CFC — wire the SELF-EJECT on any
    /// successful launch so the law exists.
    pub fn homeSlideLaunch(self: *Server, cmd: []const u8) void {
        const deck = self.currentDeck();
        const has_home = deck.findKind(.home) != null;
        self.spawnCommand(cmd);
        if (has_home) {
            // The spawn maps a client which takes focus via handleMap; the
            // home slide self-ejects NOW (successful launch = litter
            // otherwise). One flag, not an architecture.
            self.homeSlideClose();
        }
    }

    /// Create the home slide's scene tree on the output (card + stock chrome
    /// border — A1). Deck entry is created by the caller.
    fn homeSlideOpen(self: *Server, output: *Output) void {
        if (output.home_slide.isOpen()) return;
        const tree = self.scene.tree.createSceneTree() catch return;
        output.home_slide.tree = tree;
        tree.node.raiseToTop();
        self.homeSlidePaint(output);
        std.log.info("KidulWM: home slide open on output", .{});
    }

    /// (Re)render the home slide card + stock chrome into the slide's stock
    /// deck rect. Called on open and from applyLayout on every layout event
    /// while the slide exists; the repaint guard skips unchanged geometry so
    /// walking (slide position changes) re-positions, not re-renders.
    pub fn homeSlidePaint(self: *Server, output: *Output) void {
        const tree = output.home_slide.tree orelse return;
        const deck = &output.deck;
        const idx = deck.findKind(.home) orelse {
            // The deck entry died but the scene tree lives — teardown.
            self.homeSlideCloseOn(output);
            return;
        };
        var target = deck.targetForSlide(idx);
        var box: wlr.Box = undefined;
        self.output_layout.getBox(output.wlr_output, &box);
        target.x += box.x;
        target.y += box.y;
        const scale: u32 = @intFromFloat(@max(1.0, output.wlr_output.scale));
        const buf_w: i32 = @intCast(target.width);
        const buf_h: i32 = @intCast(target.height);
        if (buf_w <= 0 or buf_h <= 0) return;
        const geom_same = (buf_w == output.home_slide.card_last_w and
            buf_h == output.home_slide.card_last_h);
        const feed_same = (self.notifications.generation == output.home_slide.card_last_notif_gen);
        if (!geom_same or !feed_same or output.home_slide.card_buffer == null) {
            const buffer = tray_slide_mod.renderToBuffer(self.theme, buf_w, buf_h, scale, &self.notifications) orelse return;
            if (output.home_slide.card_buffer) |old| old.node.destroy();
            const card = tree.createSceneBuffer(buffer) catch {
                wlr.Buffer.drop(buffer);
                return;
            };
            wlr.Buffer.drop(buffer);
            output.home_slide.card_buffer = card;
            // Rendered at physical pixels; pin the display size back to the
            // logical target rect (same scale law as the media slide).
            card.setDestSize(buf_w, buf_h);
            card.node.raiseToTop();
            output.home_slide.card_last_w = buf_w;
            output.home_slide.card_last_h = buf_h;
            output.home_slide.card_last_notif_gen = self.notifications.generation;

            // A1: stock chrome border ring on top of the card.
            const chrome_buf = tray_slide_mod.renderChromeToBuffer(self.theme, buf_w, buf_h, scale);
            if (chrome_buf) |cb| {
                if (output.home_slide.chrome_buffer) |old| old.node.destroy();
                if (tree.createSceneBuffer(cb) catch null) |chrome| {
                    output.home_slide.chrome_buffer = chrome;
                    wlr.Buffer.drop(cb);
                    chrome.setDestSize(buf_w, buf_h);
                    chrome.node.raiseToTop();
                } else {
                    wlr.Buffer.drop(cb);
                }
            }
        }
        tree.node.setPosition(target.x, target.y);
    }

    fn homeSlideCloseOn(self: *Server, output: *Output) void {
        _ = self;
        if (!output.home_slide.isOpen()) return;
        output.home_slide.tree.?.node.destroy();
        output.home_slide.tree = null;
        output.home_slide.card_buffer = null;
        output.home_slide.chrome_buffer = null;
        output.home_slide.card_last_w = 0;
        output.home_slide.card_last_h = 0;
        output.home_slide.card_last_notif_gen = 0;
        std.log.info("KidulWM: home slide closed", .{});
    }

    /// ONE PLAYER PER SESSION (law: media-is-a-slide.md ruling 3). CARD 2b
    /// slice 4: the one player is kplayd, out of process — close whatever it
    /// has open before a new 'open' lands (take-over, granny-simple).
    fn kplayCloseAny(self: *Server) void {
        // Prefer an already-connected client (video slide owns one); else
        // a short-lived connection just for the close verb.
        var oit = self.outputs.iterator(.forward);
        while (oit.next()) |o| {
            if (o.video_kplay_client) |*kc| {
                kc.close() catch {};
                return;
            }
        }
        if (kplay_client_mod.KplayClient.connect(self.allocator)) |kc0| {
            var kc = kc0;
            defer kc.destroy();
            kc.close() catch {};
        } else |_| {}
    }

    /// kplay.sock 'open <path>' — start playback in kplayd (video spawns its
    /// shell; music is headless). Logged for the harness evidence line.
    pub fn kplayOpen(self: *Server, path: []const u8) void {
        if (path.len == 0) return;
        var oit = self.outputs.iterator(.forward);
        while (oit.next()) |o| {
            if (o.video_kplay_client) |*kc| {
                kc.open(path) catch |err| {
                    std.log.warn("[kplay] open failed via slide client: {s}", .{@errorName(err)});
                };
                std.log.info("[kplay] open sent (slide client): {s}", .{path});
                return;
            }
        }
        if (kplay_client_mod.KplayClient.connect(self.allocator)) |kc0| {
            var kc = kc0;
            defer kc.destroy();
            std.log.info("[kplay] open sent: {s}", .{path});
            kc.open(path) catch |err| {
                std.log.warn("[kplay] open reply err: {s}", .{@errorName(err)});
                return;
            };
        } else |err| {
            std.log.warn("[kplay] connect failed (kplayd down?): {s}", .{@errorName(err)});
        }
    }

    /// Toggle pause via kplay.sock. One player one truth = kplay.sock status;
    /// v1 flips the mirrored cached state optimistically (Granny law).
    pub fn kplayTogglePause(self: *Server) void {
        const do_resume = !self.media_player.cached.playing;
        if (kplay_client_mod.KplayClient.connect(self.allocator)) |kc0| {
            var kc = kc0;
            defer kc.destroy();
            if (do_resume) {
                kc.unpause() catch {};
            } else {
                kc.pause() catch {};
            }
        } else |_| {}
        if (self.media_player.cached.available) {
            self.media_player.cached.playing = do_resume;
        }
    }

    /// Relative seek via kplay.sock 'seek_rel <seconds>'.
    pub fn kplaySeekRel(self: *Server, seconds: f64) void {
        if (kplay_client_mod.KplayClient.connect(self.allocator)) |kc0| {
            var kc = kc0;
            defer kc.destroy();
            kc.seekRel(seconds) catch |err| {
                std.log.warn("[kplay] seek_rel failed: {s}", .{@errorName(err)});
            };
        } else |_| {}
    }

    /// Stop via kplay.sock 'close' + clear the now-playing mirror.
    pub fn kplayStop(self: *Server) void {
        self.kplayCloseAny();
        self.media_player.clearNowPlaying();
    }

    /// Toggle the media player slide (TASKCARD-3 stage 3): the player is a
    /// NORMAL compositor-owned app slide in the deck. Open = focus it if
    /// this row has one, else spawn one at index 0 (A5 boot also spawns it).
    /// Close = destroy it through the stock path — NO return-index
    /// bookkeeping; the deck settles back naturally.
    pub fn mediaSlideToggle(self: *Server) void {
        const deck = self.spawnDeck();
        if (deck.findKind(.media_player) != null) {
            // Close in THIS deck (the cursor's stage), not currentDeck — a
            // toggle must be symmetric with where it opened.
            if (self.outputForDeck(deck)) |output| {
                self.mediaSlideCloseOn(output);
            }
            _ = deck.removeCompositorSlide(.media_player);
            self.requestLayout();
            return;
        }
        // Spawn: land right of the focused slide and become focused, pushing
        // the former focus LEFT (same as addWindow). The home slide is the
        // ONLY far-left (index 0) resident — the media player is a normal
        // slide, not a far-left sibling.
        if (deck.overview_slide_open) {
            if (self.outputForDeck(deck)) |output| self.overviewSlideClose(output);
            deck.overview_slide_open = false;
            deck.empty_slot = .none;
        }
        self.focusOutputForDeck(deck);
        const insert_at = @min(deck.focused_index + 1, deck.slides.items.len);
        _ = deck.addCompositorSlide(.media_player, insert_at, false);
        if (self.outputForDeck(deck)) |output| {
            self.mediaSlideOpen(output);
        }
        self.clearFocus();
        self.requestLayout();
    }

    /// Focus the media player slide (spawn if missing) — the
    /// media_card_toggle redirect target.
    pub fn mediaSlideFocusOrSpawn(self: *Server) void {
        const deck = self.spawnDeck();
        if (deck.findKind(.media_player)) |idx| {
            deck.focusWindowByIndex(idx);
            self.clearFocus();
            self.requestLayout();
            return;
        }
        self.mediaSlideToggle();
    }

    /// Destroy the media player slide: stock removeWindow path; focus
    /// settles on the neighbor — NO return-index bookkeeping. If the video is
    /// fullscreen, exit fullscreen first (fade out + teardown, sound dies).
    pub fn mediaSlideClose(self: *Server) void {
        if (self.video_fullscreen) self.videoFullscreenExit();
        const deck = self.currentDeck();
        if (deck.findKind(.media_player) == null) return;
        if (self.outputForDeck(deck)) |output| {
            self.mediaSlideCloseOn(output);
        }
        _ = deck.removeCompositorSlide(.media_player);
        self.requestLayout();
    }

    fn mediaSlideOpen(self: *Server, output: *Output) void {
        // SCENE LOCK: reachable from the IPC thread (media_card_toggle).
        while (!self.scene_mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.scene_mutex.unlock();
        if (output.media_slide.isOpen()) return;
        // Reopen-lands-on-the-card LAW (Barticus, 2026-09-12): the widget IS
        // the card reference (cached title/art/selection), so keep it alive
        // across destroy/respawn while its music lives (out of process in
        // kplayd — the widget only mirrors now-playing state).
        const keep_widget = output.media_slide.widget_ready and
            output.media_slide.widget.is_music;
        if (output.media_slide.widget_ready and !keep_widget) {
            output.media_slide.widget.deinit();
            output.media_slide.widget = media_mod.MediaWidget.init(self.allocator);
        }
        const tree = self.scene.tree.createSceneTree() catch return;
        output.media_slide.tree = tree;
        tree.node.raiseToTop();
        self.overlay_tree.node.raiseToTop();
        self.mediaSlideRefresh(output);
        std.log.info("KidulWM: media player slide open on output", .{});
    }

    /// (Re)render the media widget into the slide's card buffer at the
    /// slide's stock deck rect. Called on open and whenever the widget's
    /// state_generation moves.
    pub fn mediaSlideRefresh(self: *Server, output: *Output) void {
        const tree = output.media_slide.tree orelse return;
        const deck = &output.deck;
        const widget = output.media_slide.ensureWidget(self.allocator);
        const idx = deck.findKind(.media_player) orelse {
            // The deck entry died but the scene tree lives — teardown.
            self.mediaSlideCloseOn(output);
            return;
        };
        const target = deck.targetForSlide(idx);
        var box: wlr.Box = undefined;
        self.output_layout.getBox(output.wlr_output, &box);
        const scale: u32 = @intFromFloat(@max(1.0, output.wlr_output.scale));
        const buf_w: i32 = @intCast(target.width);
        const buf_h: i32 = @intCast(target.height);
        const pos_x: i32 = target.x + box.x;
        const pos_y: i32 = target.y + box.y;
        if (buf_w <= 0 or buf_h <= 0) return;
        // CARD REPAINT GUARD (verdict 17, 2026-09-12): applyLayout fires on
        // every layout event (window commit, focus change, etc.) while the
        // slide is open. renderToBuffer allocates a 33 MB ARGB32 cairo surface
        // each call; rapid re-fires pile up simultaneous GPU-held bufs →
        // 20-35 MB/s RSS growth in the prewarm window (active=false) → OOM.
        // Skip when geometry is unchanged AND no widget mutation has dirtied
        // the content. card_dirty is set on open, on key mutations in
        // mediaSlideKey, and on mediaSlideRefresh callers that know content
        // changed (art load, play stop, etc.).
        const geom_same = (buf_w == output.media_slide.card_last_w and
            buf_h == output.media_slide.card_last_h);
        const gen_same = (widget.state_generation == output.media_slide.card_last_gen);
        if (geom_same and gen_same and !output.media_slide.card_dirty and output.media_slide.card_buffer != null) {
            // Position may have changed even if size is the same (deck walk).
            if (output.media_slide.card_buffer) |card| {
                output.media_slide.tree.?.node.setPosition(pos_x, pos_y);
                card.node.raiseToTop();
            }
            self.overlay_tree.node.raiseToTop();
            return;
        }
        output.media_slide.card_last_w = buf_w;
        output.media_slide.card_last_h = buf_h;
        output.media_slide.card_last_gen = widget.state_generation;
        output.media_slide.card_dirty = false;
        const buffer = media_slide_mod.renderToBuffer(widget, self.theme, buf_w, buf_h, scale) orelse return;
        if (output.media_slide.card_buffer) |old| old.node.destroy();
        const card = tree.createSceneBuffer(buffer) catch {
            wlr.Buffer.drop(buffer);
            return;
        };
        // createSceneBuffer locks the buffer (refcount +1). Release the
        // creator's reference so the scene node holds the ONLY ref and
        // node-destroy actually frees the ~27MB pixel data. Missing this drop
        // is the per-cycle media-slide retention leak (uprobe-pinned 2026-09-29).
        wlr.Buffer.drop(buffer);
        output.media_slide.card_buffer = card;
        // The buffer was rendered at physical pixels (target × scale) for
        // crispness; the scene graph shows buffers 1:1 by default, which
        // blows the card up by the output scale on HiDPI (the "huge media
        // player, top-left corner only" bug). Pin the display size back to
        // the logical target rect.
        card.setDestSize(buf_w, buf_h);
        tree.node.setPosition(pos_x, pos_y);
        card.node.raiseToTop();
        // Not playing: the overlay tree (bands) sits above the slide.
        self.overlay_tree.node.raiseToTop();
    }

    fn mediaSlideCloseOn(self: *Server, output: *Output) void {
        // SCENE LOCK: this can run on the IPC thread; the render thread may
        // be mid-draw on the same nodes (2026-09-06 pixman abort).
        while (!self.scene_mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.scene_mutex.unlock();
        if (!output.media_slide.isOpen()) return;
        // CARD 2b slice 4: closing the media slide never crashes — there is
        // nothing in-process to tear down. Playback (if any) lives in kplayd;
        // a video slide close sends the 'close' verb on its own path.
        // Destroy the card buffer node FIRST (leaking it left a stale frame
        // on screen — the "quit not clearing" bug), then the tree.
        if (output.media_slide.card_buffer) |buf| buf.node.destroy();
        output.media_slide.tree.?.node.destroy();
        output.media_slide.tree = null;
        output.media_slide.card_buffer = null;
        std.log.info("KidulWM: media player slide closed", .{});
    }

    // ── CARD 2b slice 1: internal client smoke test ────────────────────

    /// Lazily create the compositor's own Wayland client (socketpair →
    /// wl_client_create + connect_to_fd → registry roundtrip). One per
    /// server lifetime; slice 2 (slide lifecycle) will call this on first
    /// video-slide spawn.
    pub fn ensureInternalClient(self: *Server) !*@import("ipc/internal_client.zig").InternalClient {
        const ic_mod = @import("ipc/internal_client.zig");
        if (self.internal_client) |ic| return ic;
        const ic = try ic_mod.InternalClient.create(self.allocator, self.wl_server);
        self.internal_client = ic;
        return ic;
    }

    /// Boot smoke test (KIDULWM_INTERNAL_CLIENT_TEST=1): create the
    /// internal client, spawn one host toplevel, export it, and log the
    /// handle. Proves the socketpair handshake + registry + exporter
    /// end-to-end inside the live compositor.
    fn runInternalClientSmokeTest(self: *Server) void {
        const ic_mod = @import("ipc/internal_client.zig");
        const ic = self.ensureInternalClient() catch |err| {
            std.log.err("KidulWM: [2b-smoke] internal client FAILED: {s}", .{@errorName(err)});
            return;
        };
        const host = ic_mod.HostSurface.create(ic, "com.kidul.video-slide-host", "kplay host (smoke)") catch |err| {
            std.log.err("KidulWM: [2b-smoke] host surface export FAILED: {s}", .{@errorName(err)});
            return;
        };
        std.log.info("KidulWM: [2b-smoke] export handle = {s}", .{host.handle.?});
        host.destroy();
        std.log.info("KidulWM: [2b-smoke] PASS (client up, exported, handle received, torn down)", .{});
    }

    // ── Fullscreen video — a MODE the card enters and leaves (fullscreen.md) ──

    /// Enter fullscreen mode (deferred via pending_video_spawn so the host
    /// surface + internal-client pump never re-enter readClient's parse loop).
    /// The card stays a normal focused slide and does NOT move; a black
    /// curtain fades the deck + peeks to black, then kplayd's surface fades in
    /// edge-to-edge over it. Idempotent — a second enter while fullscreen is a
    /// no-op (one player, one fullscreen).
    pub fn videoFullscreenEnter(self: *Server, output: *Output) void {
        if (self.video_fullscreen) return;
        self.video_fullscreen = true;
        self.video_fullscreen_output = output;
        self.videoHostSpawn(output);
        self.curtainEnsure(output);
        self.curtain_anim.phase = .fade_to_black;
        self.curtain_anim.start_us = animation.nowUs();
        output.wlr_output.scheduleFrame();
        std.log.info("KidulWM: fullscreen enter — curtain fading deck to black", .{});
    }

    /// Exit fullscreen mode: fade the video out to black, teardown kplayd +
    /// host, then fade the deck back in. Called on quit AND on navigation
    /// (retire). The card persists throughout — it never moved.
    pub fn videoFullscreenExit(self: *Server) void {
        if (!self.video_fullscreen) return;
        const output = self.video_fullscreen_output orelse {
            self.video_fullscreen = false;
            return;
        };
        switch (self.curtain_anim.phase) {
            .fade_from_black => return, // already exiting
            .fade_to_black, .wait_video => {
                // Video never came up (kplayd still spawning): teardown now,
                // then fade the deck back in from the black we already reached.
                self.videoTeardown(output);
                self.curtain_anim.phase = .fade_from_black;
                self.curtain_anim.start_us = animation.nowUs();
                output.wlr_output.scheduleFrame();
                return;
            },
            .idle, .fade_video_in, .fade_video_out => {},
        }
        self.curtain_anim.phase = .fade_video_out;
        self.curtain_anim.start_us = animation.nowUs();
        output.wlr_output.scheduleFrame();
        std.log.info("KidulWM: fullscreen exit — fading video to black", .{});
    }

    /// Create the black fade curtain: a 1x1 black buffer stretched fullscreen,
    /// raised above the deck + peeks, below kplayd. Opacity starts at 0.
    fn curtainEnsure(self: *Server, output: *Output) void {
        if (self.curtain_buffer != null) return;
        var box: wlr.Box = undefined;
        self.output_layout.getBox(output.wlr_output, &box);
        if (box.width <= 0 or box.height <= 0) return;
        const black = [_]u8{ 0, 0, 0, 255 }; // ARGB32 LE = opaque black
        const buf = DataBuffer.create(&black, 1, 1, 4) catch return;
        const sb = self.scene.tree.createSceneBuffer(buf) catch {
            wlr.Buffer.drop(buf);
            return;
        };
        sb.setDestSize(box.width, box.height);
        sb.node.setPosition(box.x, box.y);
        sb.setOpacity(0.0);
        self.curtain_buffer = sb;
        // deck < overlay_tree(peeks) < curtain < kplay_window
        self.overlay_tree.node.raiseToTop();
        sb.node.raiseToTop();
        if (self.kplay_window) |kw| kw.scene_tree.node.raiseToTop();
    }

    fn curtainDestroy(self: *Server) void {
        if (self.curtain_buffer) |sb| {
            sb.node.destroy();
            self.curtain_buffer = null;
        }
    }

    /// Set opacity on every buffer in kplayd's surface tree. The video fades
    /// its own pixels; the curtain fades its own. GPU-free (Fade-only law).
    fn kplaySetOpacity(self: *Server, opacity: f32) void {
        const window = self.kplay_window orelse return;
        var o = opacity;
        window.surface_tree.node.forEachBuffer(*f32, struct {
            fn iter(buffer: *wlr.SceneBuffer, sx: c_int, sy: c_int, data: *f32) void {
                _ = sx;
                _ = sy;
                buffer.setOpacity(data.*);
            }
        }.iter, &o);
    }

    /// Re-assert fullscreen z-order: deck < overlay_tree(peeks) < curtain <
    /// kplayd. applyLayout raises overlay_tree on every layout event, which
    /// would strand the peeks ABOVE the curtain mid-fade (peeks popping over
    /// the deck as it fades). Called every tick while fullscreen is active so
    /// the curtain always stays between the deck and the video.
    fn fullscreenZOrder(self: *Server) void {
        if (!self.video_fullscreen) return;
        if (self.curtain_buffer) |sb| {
            self.overlay_tree.node.raiseToTop();
            sb.node.raiseToTop();
        }
        if (self.kplay_window) |kw| kw.scene_tree.node.raiseToTop();
    }

    /// Smoothstepped 0..1 over ~180ms, then held. Mirrors the wallpaper reveal
    /// ramp (t*t*(3-2t)) so both transitions share one easing language.
    fn fullscreenProgress(self: *Server, now_us: u64) f64 {
        const duration_us: u64 = 180_000;
        const elapsed = now_us -| self.curtain_anim.start_us;
        var t: f64 = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(duration_us));
        if (t >= 1.0) t = 1.0;
        return t * t * (3.0 - 2.0 * t);
    }

    /// Per-frame fullscreen transition driver. Called from handleFrame while
    /// fullscreen is active. Re-arms scheduleFrame until the phase settles.
    fn tickFullscreen(self: *Server, now_us: u64) void {
        if (!self.video_fullscreen) return;
        const output = self.video_fullscreen_output orelse return;
        self.fullscreenZOrder();
        const p = self.fullscreenProgress(now_us);
        switch (self.curtain_anim.phase) {
            .idle => return,
            .fade_to_black => {
                // Curtain 0->1: deck fades to black.
                if (self.curtain_buffer) |sb| sb.setOpacity(@floatCast(p));
                if (p >= 1.0) {
                    self.curtain_anim.phase = .wait_video;
                    self.curtain_anim.start_us = now_us;
                    // kplayd may already be up — reveal immediately.
                    if (self.kplay_window != null) self.curtainRevealVideo();
                }
                output.wlr_output.scheduleFrame();
            },
            .wait_video => {
                // Black held; placeKplayWindow triggers the reveal on map. No
                // frame re-arm — the map event schedules the next frame itself,
                // so the compositor idles at black (drain no energy) until the
                // surface is ready.
            },
            .fade_video_in => {
                // Video 0->1 over the black curtain (which stays at 1). The
                // video fades its own pixels into existence — controlled
                // present, never a pop-on-receive.
                self.kplaySetOpacity(@floatCast(p));
                if (p >= 1.0) {
                    self.curtain_anim.phase = .idle;
                    // Video is now the sole visible node: disable overlay_tree
                    // so wlroots can scan out directly (Card A).
                    self.syncScanoutOverlay();
                    std.log.info("KidulWM: fullscreen video revealed", .{});
                } else {
                    output.wlr_output.scheduleFrame();
                }
            },
            .fade_video_out => {
                // Video 1->0, revealing the black curtain behind it.
                self.kplaySetOpacity(@floatCast(1.0 - p));
                if (p >= 1.0) {
                    self.videoTeardown(output);
                    self.curtain_anim.phase = .fade_from_black;
                    self.curtain_anim.start_us = now_us;
                    // Re-enable overlay_tree so the peeks fade back in with
                    // the deck as the curtain lifts.
                    self.syncScanoutOverlay();
                }
                output.wlr_output.scheduleFrame();
            },
            .fade_from_black => {
                // Curtain 1->0: deck fades back in from black.
                if (self.curtain_buffer) |sb| sb.setOpacity(@floatCast(1.0 - p));
                if (p >= 1.0) {
                    self.curtainDestroy();
                    self.video_fullscreen = false;
                    self.video_fullscreen_output = null;
                    self.curtain_anim.phase = .idle;
                    self.requestLayout();
                    std.log.info("KidulWM: fullscreen exited", .{});
                } else {
                    output.wlr_output.scheduleFrame();
                }
            },
        }
    }

    /// kplayd's surface is mapped and the curtain is black: fade the video in
    /// from 0 over the black. The surface just mapped at full opacity, so snap
    /// it to 0 first — the fade-in is the controlled present, no pop.
    fn curtainRevealVideo(self: *Server) void {
        if (self.curtain_buffer == null) return;
        self.kplaySetOpacity(0.0);
        self.curtain_anim.phase = .fade_video_in;
        self.curtain_anim.start_us = animation.nowUs();
        if (self.video_fullscreen_output) |o| o.wlr_output.scheduleFrame();
    }

    /// Host surface + export + kplay parent handshake for the fullscreen
    /// video. Order: internal client → host toplevel (committed, exported) →
    /// kplay.sock connect → parent <handle>. kplayd replies 'err parent_failed'
    /// if its shell isn't up yet (no video playing) — logged, and the open
    /// path retries parent after 'open'.
    fn videoHostSpawn(self: *Server, output: *Output) void {
        const ic_mod = @import("ipc/internal_client.zig");
        const kplay_mod = @import("ipc/kplay_client.zig");
        const ic = self.ensureInternalClient() catch |err| {
            std.log.warn("KidulWM: video host: internal client unavailable ({s})", .{@errorName(err)});
            return;
        };
        const host = ic_mod.HostSurface.create(ic, "com.kidul.video-slide-host", "kplay host") catch |err| {
            std.log.warn("KidulWM: video host: surface/export failed ({s})", .{@errorName(err)});
            return;
        };
        output.video_host_surface = host;
        std.log.info("KidulWM: video host surface exported, handle={s}", .{host.handle.?});

        // kplayd may not be running (music-only session). Connect failure
        // is silent-ish: the open path (slice 3) connects again lazily.
        if (kplay_mod.KplayClient.connect(self.allocator)) |client| {
            output.video_kplay_client = client;
            var kc = output.video_kplay_client.?;
            kc.parent(host.handle.?) catch |err| {
                std.log.info("KidulWM: video host: kplay parent deferred ({s})", .{@errorName(err)});
            };
        } else |_| {
            std.log.info("KidulWM: video host: kplayd not reachable yet (parent deferred)", .{});
        }
    }

    /// Pin kplayd's video toplevel edge-to-edge over the fullscreen output.
    /// Fullscreen is a mode, not a slide — there is no rect to chase; the
    /// surface is the whole output, zero chrome. kplayd letterboxes INSIDE its
    /// own surface; we never paint matte. Also the reveal trigger: when the
    /// curtain has faded to black and kplayd maps, start the video fade-in.
    /// Called from: window map (window.zig handleMap) and applyLayout.
    pub fn placeKplayWindow(self: *Server) void {
        const window = self.kplay_window orelse return;
        const output = self.video_fullscreen_output orelse {
            window.scene_tree.node.setEnabled(false);
            return;
        };
        if (!self.video_fullscreen) {
            window.scene_tree.node.setEnabled(false);
            return;
        }
        var box: wlr.Box = undefined;
        self.output_layout.getBox(output.wlr_output, &box);
        if (box.width == 0 or box.height == 0) {
            window.scene_tree.node.setEnabled(false);
            return;
        }
        // Tell kplayd the surface size so it renders to fill (it letterboxes
        // internally); the compositor never scales video itself.
        const w_changed = window.animation.target_w != @as(f64, @floatFromInt(box.width));
        const h_changed = window.animation.target_h != @as(f64, @floatFromInt(box.height));
        if (w_changed or h_changed) {
            _ = window.toplevel.setSize(@intCast(box.width), @intCast(box.height));
        }
        window.setLayoutTarget(box.x, box.y, @intCast(box.width), @intCast(box.height));
        window.scene_tree.node.setEnabled(true);
        // kplayd above the curtain (z: deck < overlay < curtain < kplayd).
        if (self.curtain_buffer) |sb| sb.node.raiseToTop();
        window.scene_tree.node.raiseToTop();
        self.overlay_tree.node.raiseToTop();

        // Controlled present: while the curtain is still fading to black, the
        // video must stay hidden (opacity 0) — a surface that maps early must
        // never pop over the half-faded deck. Reveal only once black is held.
        switch (self.curtain_anim.phase) {
            .fade_to_black => self.kplaySetOpacity(0.0),
            .wait_video => self.curtainRevealVideo(),
            else => {},
        }
    }

    /// Teardown the fullscreen video: unparent + close over kplay.sock, then
    /// destroy the host toplevel (revokes the export handle). The card is not
    /// touched — it never moved. Clear the now-playing mirror (music close
    /// follows the same verb on its own path).
    fn videoTeardown(self: *Server, output: *Output) void {
        if (output.video_kplay_client) |*kc| {
            kc.unparent() catch {};
            kc.close() catch {};
            kc.destroy();
            output.video_kplay_client = null;
            self.media_player.clearNowPlaying();
        }
        if (output.video_host_surface) |host| {
            host.destroy();
            output.video_host_surface = null;
        }
        if (self.kplay_window) |kw| {
            kw.scene_tree.node.setEnabled(false);
        }
        std.log.info("KidulWM: fullscreen video torn down (card persists)", .{});
    }

    /// True while any output's media slide is open (keyboard routing).
    pub fn mediaSlideOpenAnywhere(self: *Server) bool {
        var it = self.outputs.iterator(.forward);
        while (it.next()) |output| {
            if (output.media_slide.isOpen()) return true;
        }
        return false;
    }

    /// INPUT LAW key table for the open media slide. Returns true when the
    /// key was consumed. Widget state changes trigger a re-render.
    fn mediaPrintableChar(sym: @import("xkbcommon").Keysym) ?u8 {
        const xkb = @import("xkbcommon");
        const v = @intFromEnum(sym);
        if (v >= @intFromEnum(xkb.Keysym.a) and v <= @intFromEnum(xkb.Keysym.z))
            return @as(u8, @intCast(v - @intFromEnum(xkb.Keysym.a))) + 'a';
        if (v >= @intFromEnum(xkb.Keysym.@"0") and v <= @intFromEnum(xkb.Keysym.@"9"))
            return @as(u8, @intCast(v - @intFromEnum(xkb.Keysym.@"0"))) + '0';
        if (sym == xkb.Keysym.space) return ' ';
        if (sym == xkb.Keysym.minus) return '-';
        if (sym == xkb.Keysym.period) return '.';
        return null;
    }

    pub fn mediaSlideKey(self: *Server, sym: @import("xkbcommon").Keysym) bool {
        const xkb = @import("xkbcommon");
        // Deck law (playback.md): keys route to the slide on the CURRENT-
        // FOCUS output only. No cross-output scanning — if the slide lives
        // somewhere else, the cursor isn't there, and neither is the typing.
        const deck = self.currentDeck();
        if (deck.findKind(.media_player) == null) return false;
        // FOCUS LAW (media-is-a-slide.md ruling 2, re-locked 2026-09-18):
        // keys reach the media slide ONLY while it is the focused centre
        // slide. A media slide parked elsewhere in the deck must never
        // capture, swallow, or redirect input.
        if (deck.empty_slot != .none) return false;
        if (deck.focused_index >= deck.slides.items.len) return false;
        if (deck.slides.items[deck.focused_index].kind != .media_player) return false;
        var out_opt: ?*Output = null;
        {
            var it = self.outputs.iterator(.forward);
            while (it.next()) |o| {
                if (&o.deck == deck) {
                    out_opt = o;
                    break;
                }
            }
        }
        const out = out_opt orelse return false;
        if (!out.media_slide.isOpen()) return false;
        const widget = &out.media_slide.widget;
        if (!out.media_slide.widget_ready) return false;
        var dirty = false;

        if (widget.search_focused) {
            switch (sym) {
                xkb.Keysym.Escape => {
                    widget.cancelSearch();
                    dirty = true;
                },
                xkb.Keysym.Return, xkb.Keysym.KP_Enter => {
                    const text = widget.acceptSearch();
                    if (text.len == 2) {
                        var lb: [2]u8 = undefined;
                        const code = std.ascii.lowerString(&lb, text);
                        if (std.mem.eql(u8, code, "mo")) widget.setCategory(.movies) else if (std.mem.eql(u8, code, "tv")) widget.setCategory(.tv) else if (std.mem.eql(u8, code, "mu")) widget.setCategory(.music) else widget.jumpToSearchPrefix(text);
                    } else if (text.len > 0) {
                        widget.jumpToSearchPrefix(text);
                    }
                    widget.focusControl(.result);
                    dirty = true;
                },
                xkb.Keysym.Left => {
                    if (widget.search_len > 0 and widget.search_caret > 0) widget.moveSearchCaret(-1) else widget.focusControl(.category);
                    dirty = true;
                },
                xkb.Keysym.Right => {
                    if (widget.search_caret < widget.search_len) widget.moveSearchCaret(1) else widget.focusSlider();
                    dirty = true;
                },
                xkb.Keysym.Up => {
                    widget.focusControl(.category);
                    dirty = true;
                },
                xkb.Keysym.Down => {
                    widget.focusControl(.result);
                    widget.selected_result = widget.grid_cols / 2;
                    widget.adjustScrollToSelection();
                    dirty = true;
                },
                xkb.Keysym.Home => {
                    widget.search_caret = 0;
                    dirty = true;
                },
                xkb.Keysym.End => {
                    widget.search_caret = widget.search_len;
                    dirty = true;
                },
                xkb.Keysym.BackSpace => {
                    widget.backspaceSearch();
                    dirty = true;
                },
                xkb.Keysym.Delete => {
                    widget.deleteSearch();
                    dirty = true;
                },
                xkb.Keysym.Tab => {
                    widget.focusSearch();
                    dirty = true;
                },
                else => {
                    if (mediaPrintableChar(sym)) |ch| {
                        widget.appendSearch(ch);
                        dirty = true;
                    }
                },
            }
            if (dirty) {
                out.media_slide.card_dirty = true;
                self.mediaSlideRefresh(out);
            }
            return true;
        }

        switch (sym) {
            xkb.Keysym.Escape => {
                self.mediaSlideToggle();
                return true;
            },
            xkb.Keysym.Left => {
                switch (widget.focus) {
                    .category => widget.moveCategory(-1),
                    .subcategory => widget.moveSubcategory(-1),
                    .search => widget.moveSearchCaret(-1),
                    .result => widget.moveResultSelection(-1),
                    .slider => widget.focusControl(.result),
                }
                dirty = true;
            },
            xkb.Keysym.Right => {
                switch (widget.focus) {
                    .category => widget.moveCategory(1),
                    .subcategory => widget.moveSubcategory(1),
                    .search => widget.moveSearchCaret(1),
                    .result => {
                        if (widget.isResultLastColumn()) widget.focusSlider() else widget.moveResultSelection(1);
                    },
                    .slider => {},
                }
                dirty = true;
            },
            xkb.Keysym.Up => {
                switch (widget.focus) {
                    .category => {
                        if (widget.up_plus_one) {
                            // Already in UP+1: hard stop, no further up.
                        } else if (widget.hasResults()) {
                            // THE UP: from landing, ↑ puts row0 in center.
                            // Top peek empty, row1 half below. Pills gone.
                            widget.focusControl(.result);
                            widget.selected_result = widget.grid_cols / 2; // center col of row0
                            widget.adjustScrollToSelection();
                        }
                    },
                    .subcategory => widget.closeSubcategory(),
                    .search => widget.focusControl(.category),
                    .result => {
                        // Top row + Up = UP+1 (pills centered, row0 below).
                        if (widget.atResultTopRow()) {
                            widget.up_plus_one = true;
                            widget.focusControl(.category);
                        } else {
                            widget.moveResultVertical(-1);
                        }
                    },
                    .slider => widget.moveSliderVertical(-1),
                }
                dirty = true;
            },
            xkb.Keysym.Down => {
                switch (widget.focus) {
                    // Down from the pills goes to the TILES — search is
                    // letter-summoned only, never a navigation stop.
                    .category => {
                        if (widget.up_plus_one) {
                            // UP+1 + Down = back to THE UP (row0 centered).
                            widget.up_plus_one = false;
                            if (widget.hasResults()) {
                                widget.focusControl(.result);
                                widget.selected_result = widget.grid_cols / 2; // row0 center col
                                widget.adjustScrollToSelection();
                            }
                        } else if (widget.subcategory_open) {
                            widget.focusControl(.subcategory);
                        } else {
                            if (widget.hasResults()) {
                                // THE DOWN: from landing, ↓ puts row1 in center.
                                // Row0 becomes top peek, row2 becomes bottom peek.
                                widget.focusControl(.result);
                                widget.selected_result = widget.grid_cols + widget.grid_cols / 2; // row1 center col
                                widget.adjustScrollToSelection();
                            }
                        }
                    },
                    .subcategory => {
                        if (widget.hasResults()) {
                            widget.focusControl(.result);
                            widget.selected_result = widget.grid_cols / 2;
                            widget.adjustScrollToSelection();
                        }
                    },
                    .search => {
                        if (widget.hasResults()) {
                            widget.focusControl(.result);
                            widget.selected_result = widget.grid_cols / 2;
                            widget.adjustScrollToSelection();
                        } else {
                            widget.focusControl(.slider);
                        }
                    },
                    .result => widget.moveResultVertical(1),
                    .slider => widget.moveSliderVertical(1),
                }
                dirty = true;
            },
            xkb.Keysym.Tab => {
                switch (widget.focus) {
                    // Tab cycles pills <-> tiles; search is letter-summoned.
                    .category, .subcategory => {
                        if (widget.hasResults()) widget.focusControl(.result) else widget.focusControl(.slider);
                    },
                    .search => {
                        if (widget.hasResults()) widget.focusControl(.result) else widget.focusControl(.slider);
                    },
                    .result, .slider => widget.focusControl(.category),
                }
                dirty = true;
            },
            xkb.Keysym.Page_Up => {
                widget.pageList(-1);
                dirty = true;
            },
            xkb.Keysym.Page_Down => {
                widget.pageList(1);
                dirty = true;
            },
            xkb.Keysym.space, xkb.Keysym.Return, xkb.Keysym.KP_Enter => {
                switch (widget.focus) {
                    .category => {
                        if (widget.canOpenSubcategory()) widget.openSubcategory();
                    },
                    .subcategory => widget.closeSubcategory(),
                    .search => {},
                    .result => {
                        if (widget.category == .music) {
                            // MUSIC PATH: kplayd headless open (out of
                            // process), mirror now-playing, dismiss slide.
                            // Grab entry before closing (getLibrary is global).
                            const entry = widget.selectedResultEntry();
                            const path = widget.selectedResultPath();
                            if (path.len > 0 and entry != null) {
                                const e = entry.?;
                                self.kplayCloseAny();
                                self.kplayOpen(path);
                                self.media_player.setMusicNowPlaying(
                                    std.mem.sliceTo(e.title, 0),
                                    std.mem.sliceTo(e.artist, 0),
                                );
                            }
                            // Dismiss the slide — returns focus to the opening slide.
                            self.mediaSlideToggle();
                            return true;
                        }
                        // Movies / TV: kplayd open + FULLSCREEN MODE — the
                        // card stays put and a curtain fade hands the output
                        // to the video (fullscreen.md).
                        const path = widget.selectedResultPath();
                        if (path.len > 0) {
                            self.kplayCloseAny();
                            self.kplayOpen(path);
                            self.videoFullscreenEnter(out);
                        }
                    },
                    .slider => {},
                }
                dirty = true;
            },
            else => {
                if (mediaPrintableChar(sym)) |ch| {
                    if (widget.focus == .search) {
                        widget.appendSearch(ch);
                    } else {
                        widget.focusControl(.result);
                        widget.jumpToLetter(if (ch >= 'a' and ch <= 'z') std.ascii.toUpper(ch) else ch);
                    }
                    dirty = true;
                }
            },
        }
        if (dirty) {
            out.media_slide.card_dirty = true;
            self.mediaSlideRefresh(out);
        }
        return true;
    }

    /// Hit-test a click in output-local coords against the overview's tiles.
    /// Returns the deck slide index to focus, or null (empty card space).
    pub fn overviewSlideHitTest(self: *Server, x: i32, y: i32) ?usize {
        var it = self.outputs.iterator(.forward);
        while (it.next()) |output| {
            if (!output.overview.isOpen()) continue;
            for (output.overview.tiles[0..output.overview.tile_count]) |t| {
                if (x >= t.x and x < t.x + @as(i32, @intCast(t.w)) and
                    y >= t.y and y < t.y + @as(i32, @intCast(t.h)))
                {
                    return t.slide_index;
                }
            }
        }
        return null;
    }

    /// Park (or unpark) the focused slide. Parked slides stay alive in the deck
    /// but are hidden from normal layout and skipped by navigation. Parking the
    /// only slide is refused (ruling 2026-08-19). When the last unparked slide
    /// is parked, the deck drops into the existing empty-slot state.
    pub fn parkToggleFocused(self: *Server) void {
        const deck = self.currentDeck();
        if (deck.slides.items.len == 0) return;
        if (deck.empty_slot != .none) return;
        const idx = deck.focused_index;
        if (deck.slides.items[idx].parked) {
            // Already parked (only reachable via overview in Task 2+) — unpark.
            _ = deck.unparkIndex(idx);
            self.requestLayout();
            return;
        }
        if (!deck.parkFocused()) return;
        if (deck.unparkedCount() == 0) {
            // Everything is parked: force the empty-slot state.
            deck.empty_slot = .after_last;
            self.clearFocus();
            self.requestLayout();
            return;
        }
        const slide = deck.slides.items[deck.focused_index];
        self.focused_window_id = slide.window_id;
        if (self.windowById(slide.window_id)) |window| {
            if (window.toplevel.base.surface.mapped) {
                self.focusWindow(window);
            }
        }
        self.requestLayout();
    }

    /// Focus the next slide, pushing into the virtual empty slot past the end
    /// instead of wrapping around.
    pub fn focusNext(self: *Server) void {
        // fullscreen.md LAW: fullscreen is a MODE, not a deck position. Any
        // deck-navigation input exits it — retire the playing video to its
        // card FIRST (fade out + teardown, card persists), then move. Never
        // navigate with the video still up.
        if (self.video_fullscreen) self.videoFullscreenExit();
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
            self.warpCursorToFocus();
            self.requestLayout();
        }
    }

    /// Focus the previous slide, pushing into the virtual empty slot before the
    /// first slide instead of wrapping around.
    pub fn focusPrev(self: *Server) void {
        // fullscreen.md LAW: navigation exits fullscreen — retire the video
        // to its card first, then move (mirror of focusNext).
        if (self.video_fullscreen) self.videoFullscreenExit();
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
            self.warpCursorToFocus();
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

    /// Mirror wlroots' clamped cursor position into the legacy cursor_x/y
    /// fields. SINGLE CURSOR TRUTH (2026-09-15): those fields are a read-only
    /// mirror for the many hit-test call sites; the wlr.Cursor is the only
    /// writer of record. Every cursor-consuming entry point syncs first so a
    /// missed mirror update can never again drift hit-testing off the screen.
    pub fn syncCursorMirror(self: *Server) void {
        self.cursor_x = self.cursor.x;
        self.cursor_y = self.cursor.y;
    }

    pub fn focusAtCursor(self: *Server) void {
        self.syncCursorMirror();
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

    /// POINTER-ENTER FIX v2 (2026-09-15): never hit-test the GLOBAL scene
    /// tree for pointer-enter. The chrome overlay is a raw DataBuffer raised
    /// above every window at the same coords; a global node.at() returns the
    /// chrome buffer first, and SceneSurface.tryFromBuffer() on it is null —
    /// so pointer enter silently never happened and wlroots dropped every
    /// button/axis event (BTN-NOTIFY serial=0 focused=false flood). Walk the
    /// per-window trees instead (they contain only the client xdg surface;
    /// chrome lives in overlay_tree, outside them), mirroring focusAtCursor.
    /// SURFACE-LOCAL LAW (2026-09-15): returns the surface-local (sx, sy) of
    /// the cursor for the entered surface, or null if no client is under the
    /// pointer. wlr_seat_pointer_notify_motion/notify_enter take LOCAL
    /// coords — passing layout coords (cursor_x/y) shifts hit-testing by the
    /// window's layout position on x (slide at x=25 -> +25px; slide on the
    /// second stage -> +1920px, "spread out over both screens"). Y looked
    /// fine only because slides sit near y=0. All clients were affected;
    /// kbrowser's "click 25px left of the button" was this bug.
    pub fn pointerEnterAtCursor(self: *Server) ?struct { sx: f64, sy: f64 } {
        self.syncCursorMirror();
        // Layer surfaces first: overlay/top strata render above windows, so
        // a mapped layer client under the cursor (slurp's selection scrim)
        // owns the pointer. Walk the list once per stratum that outranks
        // windows — overlay, then top.
        var lit = self.layer_surfaces.iterator(.forward);
        while (lit.next()) |ls| {
            const layer = ls.layer_surface.current.layer;
            if (layer != .overlay and layer != .top) continue;
            if (!ls.layer_surface.surface.mapped) continue;
            const sls = ls.scene_layer_surface orelse continue;
            const lnode = &sls.tree.node;
            if (!lnode.enabled) continue;
            var nx: f64 = undefined;
            var ny: f64 = undefined;
            const node = lnode.at(self.cursor_x, self.cursor_y, &nx, &ny) orelse continue;
            if (node.type != .buffer) continue;
            const scene_buffer: *wlr.SceneBuffer = @fieldParentPtr("node", node);
            const scene_surface = wlr.SceneSurface.tryFromBuffer(scene_buffer) orelse continue;
            const surface = scene_surface.surface;
            if (self.seat.pointer_state.focused_surface != surface) {
                std.log.debug("KidulWM: PTR-ENTER layer ns={s} nx={d:.0} ny={d:.0}", .{ ls.layer_surface.namespace, nx, ny });
                self.seat.pointerNotifyEnter(surface, nx, ny);
            }
            return .{ .sx = nx, .sy = ny };
        }
        var it = self.windows.iterator(.forward);
        while (it.next()) |window| {
            const wnode = &window.scene_tree.node;
            if (!window.toplevel.base.surface.mapped or !wnode.enabled) continue;
            var nx: f64 = undefined;
            var ny: f64 = undefined;
            const node = wnode.at(self.cursor_x, self.cursor_y, &nx, &ny) orelse continue;
            if (node.type != .buffer) continue;
            const scene_buffer: *wlr.SceneBuffer = @fieldParentPtr("node", node);
            const scene_surface = wlr.SceneSurface.tryFromBuffer(scene_buffer) orelse continue;
            const surface = scene_surface.surface;
            if (self.seat.pointer_state.focused_surface != surface) {
                std.log.debug("KidulWM: PTR-ENTER id={d} surface={*} nx={d:.0} ny={d:.0}", .{ window.id, surface, nx, ny });
                self.seat.pointerNotifyEnter(surface, nx, ny);
            }
            return .{ .sx = nx, .sy = ny };
        }
        if (self.seat.pointer_state.focused_surface != null) {
            self.seat.pointerNotifyClearFocus();
            // No client under the pointer — re-assert the default cursor
            // or the last client's image (e.g. a text field's ibeam) sticks.
            self.cursor.setXcursor(self.xcursor_manager, "left_ptr");
        }
        return null;
    }

    /// Focus-follows-cursor half of "follow the leader": on pointer motion,
    /// if the cursor has crossed onto a different output than the one holding
    /// keyboard focus, hand focus to whatever window is under the cursor.
    /// Guarded: only fires when a mapped window is hit (an empty stage keeps
    /// the old focus — no flapping on bare wallpaper).
    pub fn focusFollowsCursor(self: *Server) void {
        if (self.suppress_focus_follow) return;
        self.syncCursorMirror();
        var cursor_output: ?*Output = null;
        var oit = self.outputs.iterator(.forward);
        while (oit.next()) |output| {
            var box: wlr.Box = undefined;
            self.output_layout.getBox(output.wlr_output, &box);
            const cx = self.cursor_x;
            const cy = self.cursor_y;
            if (cx >= @as(f64, @floatFromInt(box.x)) and
                cx < @as(f64, @floatFromInt(box.x + box.width)) and
                cy >= @as(f64, @floatFromInt(box.y)) and
                cy < @as(f64, @floatFromInt(box.y + box.height)))
            {
                cursor_output = output;
                break;
            }
        }
        const co = cursor_output orelse return;
        if (self.focused_output == co) return;
        // Only steal the stage if a window is actually under the cursor.
        var hit_any = false;
        var it = self.windows.iterator(.forward);
        while (it.next()) |window| {
            if (window.output != co) continue;
            const node = &window.scene_tree.node;
            if (!window.toplevel.base.surface.mapped) continue;
            if (!node.enabled) continue;
            var nx: f64 = undefined;
            var ny: f64 = undefined;
            if (node.at(self.cursor_x, self.cursor_y, &nx, &ny)) |_| {
                std.log.info("KidulWM: focusFollowsCursor hit id={d} on {s}, focusing", .{ window.id, co.wlr_output.name });
                self.focusWindow(window);
                return;
            }
            hit_any = true;
        }
        // Empty stage: still adopt it as the focused output so new windows
        // map there and Mod4+O behaves, but keep existing window focus.
        std.log.info("KidulWM: focusFollowsCursor {s} -> {s}: no hit (candidate_windows={}, cursor={d:.0},{d:.0})", .{
            if (self.focused_output) |fo| fo.wlr_output.name else "none",
            co.wlr_output.name,
            hit_any,
            self.cursor_x,
            self.cursor_y,
        });
        self.focused_output = co;
    }

    /// Cursor-follows-focus half of "follow the leader": warp the pointer to
    /// the centre of the focused window's current layout target. Called after
    /// any non-pointer focus change (hotkey, IPC, map, stage jump).
    pub fn warpCursorToFocus(self: *Server) void {
        const window = self.focused_window orelse return;
        const cx = window.animation.target_x + window.animation.target_w / 2.0;
        const cy = window.animation.target_y + window.animation.target_h / 2.0;
        self.suppress_focus_follow = true;
        _ = self.cursor.warp(null, cx, cy);
        self.cursor_x = cx;
        self.cursor_y = cy;
        // Enter the surface before notifying motion — wlroots drops
        // pointerNotifyMotion when no pointer surface is focused. And notify
        // in SURFACE-LOCAL coords (SURFACE-LOCAL LAW), not the layout cx/cy.
        if (self.pointerEnterAtCursor()) |p| {
            self.seat.pointerNotifyMotion(0, p.sx, p.sy);
        }
        self.suppress_focus_follow = false;
    }

    /// Toggle fullscreen on the focused slide (Mod4+f / F11). Fullscreen is
    /// a SIZE, not a mode: the slide fills the whole output until toggled
    /// back. Stock path — the video slide uses it too (A4 plays ball).
    pub fn fullscreenToggleFocused(self: *Server) void {
        const deck = self.currentDeck();
        const state = deck.fullscreenToggleFocused() orelse return;
        std.log.info("KidulWM: fullscreen toggle -> {s} (focused_index={d})", .{
            if (state) @as([]const u8, "FULL") else "windowed",
            deck.focused_index,
        });
        self.requestLayout();
    }

    /// Mod4+O: jump keyboard focus to the other stage, and (leader law) pull
    /// the cursor along with it.
    pub fn focusOutputNext(self: *Server) void {
        var count: usize = 0;
        var it = self.outputs.iterator(.forward);
        while (it.next()) |_| count += 1;
        if (count < 2) return;

        const current = self.focused_output orelse self.outputs.first() orelse return;
        // Outputs form a ring; pick the next one after `current`.
        var next: ?*Output = null;
        var seen_current = false;
        it = self.outputs.iterator(.forward);
        while (it.next()) |output| {
            if (seen_current) {
                next = output;
                break;
            }
            if (output == current) seen_current = true;
        }
        if (next == null) next = self.outputs.first();
        const target = next orelse return;

        // Only move focus when the target stage has a real slide to hand it
        // to. The old shape set focused_output unconditionally, desyncing it
        // from the focused window on an empty stage (focus says eDP, window
        // still on HDMI) — the "everything weird" state.
        const deck = &target.deck;
        if (deck.slides.items.len == 0 or deck.empty_slot != .none) return;
        self.focused_output = target;
        const slide = deck.slides.items[deck.focused_index];
        if (self.windowById(slide.window_id)) |window| {
            self.focusWindow(window);
        }
        self.warpCursorToFocus();
        self.requestLayout();
    }

    /// Toggle DPMS-style output blanking on every output. Off commits
    /// enabled=false (the panel actually powers down — no burn); on commits
    /// the output back enabled with its existing mode. Mode/scale state is
    /// untouched, so wake is a plain re-enable.
    pub fn screensOffSet(self: *Server, off: bool) void {
        if (self.screens_off == off) return;
        self.screens_off = off;
        var it = self.outputs.iterator(.forward);
        while (it.next()) |output| {
            var state = wlr.Output.State.init();
            defer state.finish();
            state.setEnabled(!off);
            if (!output.wlr_output.commitState(&state)) {
                std.log.err("KidulWM: screen_off commit failed for {s}", .{std.mem.span(output.wlr_output.name)});
            }
        }
        std.log.info("KidulWM: screens {s}", .{if (off) "OFF" else "ON"});
    }

    pub fn screensOffToggle(self: *Server) void {
        self.screensOffSet(!self.screens_off);
    }

    /// smartLock: stamp input activity. Called from every input handler
    /// (keyboard key, pointer motion/button/axis). While screens are off a
    /// stamp alone does NOT wake — the wake decision lives in keyboard.zig
    /// (blind-first-press law) — it just resets the idle clock.
    pub fn noteInputActivity(self: *Server) void {
        var ts: linux.timespec = undefined;
        _ = linux.clock_gettime(.MONOTONIC, &ts);
        self.last_input_us = @as(u64, @intCast(ts.sec)) * 1_000_000 + @as(u64, @intCast(@divTrunc(ts.nsec, 1000)));
        // Rearm the poll so a long-idle machine doesn't tick forever.
        self.rearmBlankTimer();
    }

    /// gracePeriod open: swallow all input for 2s after a fade-into-
    /// existence (wake). Mirrors ksound's fade-in grace — nothing forwards
    /// to an app until the screen has visibly settled.
    pub fn beginInputGrace(self: *Server) void {
        var ts: linux.timespec = undefined;
        _ = linux.clock_gettime(.MONOTONIC, &ts);
        self.input_grace_until_us = @as(u64, @intCast(ts.sec)) * 1_000_000
            + @as(u64, @intCast(@divTrunc(ts.nsec, 1000))) + 2_000_000; // 2s gracePeriod
    }

    /// True while inside the post-wake gracePeriod. Cheap in steady state:
    /// one compare when the deadline is already cleared.
    pub fn inInputGrace(self: *Server) bool {
        if (self.input_grace_until_us == 0) return false;
        var ts: linux.timespec = undefined;
        _ = linux.clock_gettime(.MONOTONIC, &ts);
        const now_us = @as(u64, @intCast(ts.sec)) * 1_000_000 + @as(u64, @intCast(@divTrunc(ts.nsec, 1000)));
        if (now_us >= self.input_grace_until_us) {
            self.input_grace_until_us = 0;
            return false;
        }
        return true;
    }

    fn rearmBlankTimer(self: *Server) void {
        const t = self.blank_timer orelse return;
        const timeout_s = self.keybinds.blank.timeout_s;
        if (timeout_s == 0) {
            t.timerUpdate(0) catch {}; // disabled
            return;
        }
        // Poll at the sooner of 30 s or the timeout — keeps the check cheap
        // while staying within seconds of the configured boundary.
        const poll_ms: c_int = @intCast(@min(@as(u64, timeout_s) * 1000, 30_000));
        t.timerUpdate(poll_ms) catch {};
    }

    /// The screen-blanking question is never "is something playing?" — it's
    /// "would blanking break what the user is watching right now?"
    ///   visual playback (video/karaoke/LIVE TV) + playing → inhibit
    ///   audio-only music + playing                        → inhibit iff conf
    ///   paused / stopped / nothing                        → never inhibit
    /// True while music is playing (mirrored from kplay open; the slideless
    /// blank-inhibit question — see playbackInhibitsBlank).
    pub fn playbackInhibitsBlank(self: *Server) bool {
        // FULLSCREEN VIDEO (movies / LIVE TV) is visual playback by
        // definition — the deck sits behind a curtain and kplayd's surface
        // owns the output. The music mirror (cached, set by setMusicNowPlaying)
        // only covers headless audio; the video path never touches it, so
        // without this a movie/TV got blanked every timeout_s (600s) — the
        // "cuts the movie every 10 min" bug. Inhibit iff visual-inhibit is set.
        if (self.video_fullscreen) return self.keybinds.blank.inhibit_visual;
        const mp = &self.media_player;
        if (!mp.cached.available or !mp.cached.playing) return false;
        if (!mp.is_music) return self.keybinds.blank.inhibit_visual;
        return self.keybinds.blank.inhibit_audio;
    }

    /// Step the session master volume by delta (±0.05 per press), clamp
    /// [0,1], unmute on any volume change, and push to the default sink
    /// through pactl (ksound's own verb pattern). Safe to call with the
    /// screen black — this is the blind-first-press volume door.
    pub fn volumeStep(self: *Server, delta: f32) void {
        self.master_volume = std.math.clamp(self.master_volume + delta, 0.0, 1.0);
        self.master_muted = false;
        self.volumeApply();
    }

    pub fn volumeToggleMute(self: *Server) void {
        self.master_muted = !self.master_muted;
        self.volumeApply();
    }

    fn volumeApply(self: *Server) void {
        var pctbuf: [16]u8 = undefined;
        const pct: u32 = @intFromFloat(self.master_volume * 100.0);
        const pct_s = std.fmt.bufPrintZ(&pctbuf, "{d}%", .{pct}) catch return;
        var mutebuf: [8]u8 = undefined;
        const mute_s = std.fmt.bufPrintZ(&mutebuf, "{d}", .{@intFromBool(self.master_muted)}) catch return;
        var cmdbuf: [128]u8 = undefined;
        const cmd = std.fmt.bufPrintZ(&cmdbuf, "pactl set-sink-volume @DEFAULT_SINK@ {s} ; pactl set-sink-mute @DEFAULT_SINK@ {s}", .{ pct_s, mute_s }) catch return;
        _ = c_std.system(cmd.ptr);
        std.log.info("KidulWM: master volume {d}%{s}", .{ pct, if (self.master_muted) " MUTED" else "" });
    }

    fn handleBlankTimer(server: *Server) c_int {
        const timeout_s = server.keybinds.blank.timeout_s;
        if (timeout_s == 0) return 0; // disabled
        if (server.screens_off) return 0; // already blank; wake owns rearm
        var ts: linux.timespec = undefined;
        _ = linux.clock_gettime(.MONOTONIC, &ts);
        const now_us = @as(u64, @intCast(ts.sec)) * 1_000_000 + @as(u64, @intCast(@divTrunc(ts.nsec, 1000)));
        const idle_us = now_us -| server.last_input_us;
        if (idle_us >= @as(u64, timeout_s) * 1_000_000) {
            if (server.playbackInhibitsBlank()) {
                std.log.info("KidulWM: blankscreen idle {d}s >= {d}s but playback inhibits (visual={} music={})", .{ idle_us / 1_000_000, timeout_s, server.keybinds.blank.inhibit_visual, server.keybinds.blank.inhibit_audio });
            } else {
                std.log.info("KidulWM: blankscreen idle {d}s >= {d}s — screens OFF", .{ idle_us / 1_000_000, timeout_s });
                server.screensOffSet(true);
                return 0;
            }
        }
        server.rearmBlankTimer();
        return 0;
    }

    /// Mod4+Ctrl+O: send the focused slide to the other stage's deck.
    pub fn moveFocusedToOutputNext(self: *Server) void {
        const window = self.focused_window orelse return;
        const from_output = window.output orelse return;
        var it = self.outputs.iterator(.forward);
        var count: usize = 0;
        while (it.next()) |_| count += 1;
        if (count < 2) return;

        var next: ?*Output = null;
        var seen_current = false;
        it = self.outputs.iterator(.forward);
        while (it.next()) |output| {
            if (seen_current) {
                next = output;
                break;
            }
            if (output == from_output) seen_current = true;
        }
        if (next == null) next = self.outputs.first();
        const target = next orelse return;
        if (target == from_output) return;

        from_output.deck.removeWindow(window.id);
        target.deck.addWindow(window.id);
        window.output = target;
        // Re-enter surfaces so scale/layer hints follow the new stage.
        var oit = self.outputs.iterator(.forward);
        while (oit.next()) |output| {
            if (output == target) {
                window.toplevel.base.surface.sendEnter(output.wlr_output);
            } else if (output == from_output) {
                window.toplevel.base.surface.sendLeave(output.wlr_output);
            }
        }
        self.focused_output = target;
        self.focusWindow(window);
        self.warpCursorToFocus();
        self.requestLayout();
    }

    /// Card A (god code, render-path law): when the video slide is focused
    /// AND fullscreen, kplayd's buffer is the sole visible node and wlroots
    /// can scan it out directly — but the overlay_tree node (peek + chrome
    /// rings, already visually empty here) still stacks above it and defeats
    /// Scanout overlay toggle (Card A): when fullscreen video is REVEALED
    /// (idle phase — kplayd's buffer is the sole visible node), drop
    /// overlay_tree so wlroots can scan out directly. During the fade phases
    /// the overlay stays enabled so the peeks fade with the deck under the
    /// curtain. Called from applyLayout and the fullscreen tick's phase edges.
    fn syncScanoutOverlay(self: *Server) void {
        const scanout = self.video_fullscreen and self.curtain_anim.phase == .idle;
        if (scanout)
            std.log.info("KidulWM: scanout candidate — disabling overlay_tree (fullscreen video)", .{});
        self.overlay_tree.node.setEnabled(!scanout);
    }

    pub fn applyLayout(self: *Server) void {
        self.layout_requested.store(false, .monotonic);
        std.log.info("KidulWM: applyLayout called", .{});

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
            var box: wlr.Box = undefined;
            self.output_layout.getBox(wlr_output, &box);
            const width = @as(u32, @intCast(box.width));
            const height = @as(u32, @intCast(box.height));
            output.deck.sync(width, height, self.state.gap, self.deck_split, self.deck_orientation);

            // PEEK (TASKCARD-3): permanent per-output edge peeks. Signage
            // follows the deck state. VISIBILITY LAW: the whole peek set
            // (widgets + signage) hides ONLY while the FOCUSED slide is
            // fullscreen — fullscreen apps own the edges. A fullscreen
            // slide walked off-focus is a standard slide, so the peek
            // must stay visible (it is where that slide now lives).
            {
                const bs: u32 = @intFromFloat(@max(1.0, wlr_output.scale));
                const n_slides = output.deck.slides.items.len;
                const focused_fullscreen = output.deck.empty_slot == .none and
                    output.deck.focused_index < n_slides and
                    output.deck.slides.items[output.deck.focused_index].fullscreen;
                output.peek.setHidden(focused_fullscreen);
                const has_left = (output.deck.empty_slot == .none and output.deck.focused_index > 0) or
                    (output.deck.empty_slot == .after_last and n_slides > 0);
                const has_right = (output.deck.empty_slot == .none and output.deck.focused_index + 1 < n_slides) or
                    (output.deck.empty_slot == .before_first and n_slides > 0);
                // LAW: guard the empty deck — at first layout slides.len==0
                // and empty_slot==.none, and the unchecked
                // (len - focused_index - 1) underflows usize (boot crash,
                // 2026-09-15).
                const left_count: u32 = if (n_slides == 0)
                    0
                else if (output.deck.empty_slot == .after_last)
                    @intCast(n_slides)
                else if (output.deck.empty_slot == .before_first)
                    0
                else
                    @intCast(output.deck.focused_index);
                const right_count: u32 = if (n_slides == 0)
                    0
                else if (output.deck.empty_slot == .before_first)
                    @intCast(n_slides)
                else if (output.deck.empty_slot == .after_last)
                    0
                else
                    @intCast(n_slides - output.deck.focused_index - 1);
                output.peek.updateOutput(width, height, bs, box.x, box.y, &self.peek_widgets);
                output.peek.setNeighbors(has_left, has_right, left_count, right_count);
            }

            if (output.deck.slides.items.len == 0) continue;
            any_slides = true;
            // While the overview slide is open on this output, the
            // slides' scene trees are REPARENTED into the card with tile
            // geometry — the row layout below must not touch them.
            if (output.deck.overviewSlideOpen() and output.overview.isOpen()) {
                continue;
            }

            var focused_slide_window: ?*Window = null;
            var active_compositor: ?*Output = null;
            const deck_ptr = &output.deck;
            for (output.deck.slides.items, 0..) |slide, slide_idx| {
                // Compositor-owned slides (home / media player / video) have
                // no client window — they are painted after the loop, at
                // their stock deck rect.
                if (slide.kind != .app) {
                    if (output.deck.empty_slot == .none and slide_idx == output.deck.focused_index and !slide.parked) {
                        active_compositor = output;
                    }
                    continue;
                }
                const window = self.windowById(slide.window_id) orelse continue;
                if (!window.toplevel.base.surface.mapped) continue;

                // Translate output-local deck coords into global scene coords.
                const target = blk: {
                    var t = output.deck.targetForSlide(slide_idx);
                    t.x += box.x;
                    t.y += box.y;
                    break :blk t;
                };
                // When the deck is in an empty-slot state (past the ends of the
                // row), no slide is focused — disable everything.
                const is_focused = output.deck.empty_slot == .none and slide_idx == output.deck.focused_index and !slide.parked;
                const w_changed = window.animation.target_w != @as(f64, @floatFromInt(target.width));
                const h_changed = window.animation.target_h != @as(f64, @floatFromInt(target.height));
                const size_changed = w_changed or h_changed;
                window.setLayoutTarget(target.x, target.y, target.width, target.height);
                if (focus_changed) {
                    window.startTransition(self.current_transition_kind);
                }
                if (is_focused) {
                    // Focused slide: full screen, chrome border, surface scaled to fit.
                    window.scene_tree.node.setEnabled(true);
                    window.clearMiniScale();
                    if (size_changed) {
                        _ = window.toplevel.setSize(@intCast(target.width), @intCast(target.height));
                    }
                    window.setSurfaceOffsetForFocus();
                    window.applyContainment();
                    focused_slide_window = window;
                    if (slide.fullscreen) {
                        window.clearChrome();
                    } else {
                        window.updateChrome(true, .all);
                    }
                    window.scene_tree.node.raiseToTop();
                    self.overlay_tree.node.raiseToTop();
                } else {
                    // Non-focused slides: disabled, no rendering, no chrome.
                    window.scene_tree.node.setEnabled(false);
                    window.clearMiniScale();
                    window.clearChrome();
                }
            }

            // Compositor-owned slides paint at their stock deck rect (the
            // same targetForSlide geometry a client window gets — walks,
            // peeks, A4 fullscreen all through stock machinery), refreshed
            // after window layout and raised above this output's windows.
            if (output.home_slide.isOpen()) {
                self.homeSlidePaint(output);
            }
            if (output.media_slide.isOpen()) {
                self.mediaSlideRefresh(output);
                if (output.media_slide.tree) |tree| {
                    tree.node.raiseToTop();
                }
                self.overlay_tree.node.raiseToTop();
            }

            if (deck_ptr == active_deck) {
                if (deck_ptr.empty_slot == .none) {
                    if (active_compositor != null) {
                        // Focus rests on a compositor-owned slide: no client
                        // surface owns the seat.
                        self.clearFocus();
                    } else if (focused_slide_window) |window| {
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
                    const is_focused = self.deck.empty_slot == .none and slide_idx == self.deck.focused_index and !slide.parked;
                    const w_changed = window.animation.target_w != @as(f64, @floatFromInt(target.width));
                    const h_changed = window.animation.target_h != @as(f64, @floatFromInt(target.height));
                    const size_changed = w_changed or h_changed;
                    window.setLayoutTarget(target.x, target.y, target.width, target.height);
                    if (focus_changed) {
                        window.startTransition(self.current_transition_kind);
                    }
                    if (is_focused) {
                        window.scene_tree.node.setEnabled(true);
                        window.clearMiniScale();
                        if (size_changed) {
                            _ = window.toplevel.setSize(@intCast(target.width), @intCast(target.height));
                        }
                        window.setSurfaceOffsetForFocus();
                        window.applyContainment();
                        if (slide.fullscreen) {
                            window.clearChrome();
                        } else {
                            window.updateChrome(true, .all);
                        }
                        window.scene_tree.node.raiseToTop();
                        self.overlay_tree.node.raiseToTop();
                        if (self.deck.empty_slot == .none) {
                            self.focusWindow(window);
                        }
                    } else {
                        window.scene_tree.node.setEnabled(false);
                        window.clearMiniScale();
                        window.clearChrome();
                    }
                }
            }
        }

        if (!any_slides or (active_deck.empty_slot != .none and !active_deck.overviewSlideOpen())) {
            self.clearFocus();
        }

        self.last_focused_slide_id = current_focused_slide_id;

        // Card A (god code): fullscreen video revealed = kplayd scans out.
        self.syncScanoutOverlay();
    }

    fn handleLayoutEventFd(_fd: c_int, _mask: wl.EventMask, server: *Server) c_int {
        _ = _fd;
        _ = _mask;
        var buf: [16]u8 = undefined;
        _ = linux.read(server.layout_pipe[0], &buf, buf.len);
        server.applyLayout();
        // Deferred video-slide spawn (see pending_video_spawn). Runs here, on
        // the main loop, OUTSIDE the control socket's readClient parse loop —
        // the spawn's event-loop pump is a legal re-entry from this pipe
        // source, but corrupts readClient's buffer if done inline in
        // handleRequest.
        if (server.pending_video_spawn) |vout| {
            server.pending_video_spawn = null;
            server.videoFullscreenEnter(vout);
        }
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

    /// CFC scale law: integer scale only, from pixel density.
    /// TVs lie about physical size in EDID; pixels don't lie. The "retina"
    /// crossover for desktop use is FHD-per-scale-unit: anything at or above
    /// QHD-class (2560px wide) renders at 2x, everything below at 1x.
    /// 24-28" 4K → 2x (right), 27-32" 1440p → 2x (right), 1080p → 1x.
    /// Scale is decided HERE and nowhere else.
    fn pickIntegerScale(wlr_output: *wlr.Output) f32 {
        return pickIntegerScaleForWidth(wlr_output.width, wlr_output.name);
    }

    /// Decide scale from the MODE we are about to commit, never from live
    /// output state: wlr_output.width is 0 until the mode commit lands, and
    /// reading it early silently picks 1x on a 2x panel (Kogan 4K, 2026-09-04:
    /// "HDMI-A-1 0px wide -> scale 1", then mode 3840x2160 committed at
    /// scale 1 — slides quartered, tray stranded bottom-left).
    fn pickIntegerScaleForWidth(width: i32, name: [*c]const u8) f32 {
        const scale: f32 = if (width >= 2560) 2.0 else 1.0;
        std.log.info("KidulWM: output {s} {d}px wide -> scale {d:.0}", .{ name, width, scale });
        return scale;
    }

    /// Scale is decided in handleNewOutput and nowhere else. Every surface on
    /// this output must hear about it, or a client that mapped while the
    /// output was at scale 1 keeps committing scale-1 buffers — rendered 1:1
    /// physical on a 2x panel, they occupy the top-left quarter (the Kogan
    /// 4K bug, 2026-09-04).
    pub fn syncOutputScaleToWindows(self: *Server, wlr_output: *wlr.Output, scale: f32) void {
        var it = self.windows.iterator(.forward);
        while (it.next()) |window| {
            const wo = window.output orelse continue;
            if (wo.wlr_output != wlr_output) continue;
            const surface = window.toplevel.base.surface;
            wlr.FractionalScaleManagerV1.notifyScale(surface, scale);
            surface.sendEnter(wlr_output);
            const target = window.animation;
            const tw: i32 = @intFromFloat(@max(0.0, target.target_w));
            const th: i32 = @intFromFloat(@max(0.0, target.target_h));
            if (tw > 0 and th > 0) {
                _ = window.toplevel.setSize(tw, th);
                _ = window.toplevel.base.scheduleConfigure();
            }
            std.log.info("KidulWM: scale sync id={d} output={s} scale={d:.0} reconfigure={d}x{d}", .{ window.id, wlr_output.name, scale, tw, th });
        }
    }

    fn handleNewOutput(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
        const self: *Server = @fieldParentPtr("new_output", listener);

        if (!wlr_output.initRender(self.renderer_allocator, self.renderer)) {
            self.recordOutputDrop(wlr_output, .init_render, null);
            return;
        }

        var state = wlr.Output.State.init();
        defer state.finish();
        state.setEnabled(true);
        // Single enable+mode commit: the two-commit split (enable first,
        // then mode) left bare-metal connectors dark — some DRM drivers
        // reject enable-without-mode or the follow-up mode commit, and we
        // then dropped the output entirely. Reverted to the shape that
        // found the second screen.
        if (pickOutputMode(wlr_output)) |mode| {
            state.setMode(mode);
        } else {
            state.setCustomMode(1024, 768, 60_000);
        }
        // CFC scale law: integer scale only, auto from pixel density,
        // committed atomically with the mode so layout/clients never see a
        // 1x frame. Scale must be decided from the MODE WE JUST CHOSE —
        // wlr_output.width is still 0 here (mode not yet committed), which
        // is exactly how the Kogan 4K got scale 1 (2026-09-04).
        const committed_width: i32 = if (state.mode) |m| m.width else state.custom_mode.width;
        var scale = pickIntegerScaleForWidth(committed_width, wlr_output.name);
        // User fractional override from outputs.toml [arrange] — e.g.
        // scale = 1.7. Overrides the auto law for this output only; the
        // logical box is physical/scale so fractional gives a larger
        // logical desktop than integer 2x.
        if (self.output_arrangement.find(std.mem.span(wlr_output.name))) |p| {
            if (p.scale) |s| {
                scale = s;
                std.log.info("KidulWM: output {s} scale override {d:.2} (outputs.toml)", .{ wlr_output.name, s });
            }
        }
        state.setScale(scale);
        if (!wlr_output.commitState(&state)) {
            self.recordOutputDrop(wlr_output, .commit_state, null);
            return;
        }

        std.log.info("KidulWM: new output {s} {d}x{d} scale={d:.0} phys={d}x{d}mm drm_fd={d}", .{ wlr_output.name, wlr_output.width, wlr_output.height, scale, wlr_output.phys_width, wlr_output.phys_height, wlr_output.backend.getDrmFd() });
        // Placement is declared physical reality (outputs.toml [arrange]),
        // in logical units. Unknown outputs fall back to addAuto (extend right).
        // Two outputs must never land at the same origin — that is how the
        // mirror incident happened.
        if (self.output_arrangement.find(std.mem.span(wlr_output.name))) |p| {
            _ = self.output_layout.add(wlr_output, p.x, p.y) catch |err| {
                self.recordOutputDrop(wlr_output, .layout_add, err);
                return;
            };
            std.log.info("KidulWM: placed output {s} at {d},{d} (declared)", .{ wlr_output.name, p.x, p.y });
        } else {
            _ = self.output_layout.addAuto(wlr_output) catch |err| {
                self.recordOutputDrop(wlr_output, .layout_add, err);
                return;
            };
            std.log.info("KidulWM: placed output {s} via addAuto (no declared position)", .{wlr_output.name});
        }
        // Prefer the layout-managed scene output (attachOutputLayout creates
        // one per layout output and keeps its position synced to the layout
        // coordinates — this is what stops the mirror). But never drop an
        // output: if the layout-managed one is missing (e.g. the layout
        // remove/re-add cycle in arrangeOutputsLive raced us), fall back to
        // creating our own and pinning it to the declared layout position.
        // An output we refuse to drive is a black screen.
        const scene_output = self.scene.getSceneOutput(wlr_output) orelse blk: {
            std.log.warn("KidulWM: no layout-managed scene output for {s}; creating fallback", .{wlr_output.name});
            const so = self.scene.createSceneOutput(wlr_output) catch |err| {
                self.recordOutputDrop(wlr_output, .scene_output, err);
                return;
            };
            var box: wlr.Box = undefined;
            self.output_layout.getBox(wlr_output, &box);
            so.setPosition(box.x, box.y);
            break :blk so;
        };
        const output = self.allocator.create(Output) catch |err| {
            self.recordOutputDrop(wlr_output, .alloc, err);
            return;
        };
        output.init(self, wlr_output, scene_output);
        std.log.info("KidulWM: output added to layout", .{});
        // Give this output its own wallpaper node, sized to its logical box
        // with fill-contain (no crop). Must happen after placement so the box
        // coordinates are real.
        output.setupWallpaper(self);
        // Boot cursor placement: the hardware cursor starts at 0,0 — the
        // shared corner of the layout, a no-man's-land belonging to no stage
        // (top edge of the laptop when docked). The first output to land
        // claims it: warp to the centre of that output's box and adopt the
        // stage, so the very first click/keypress does something. When
        // docked, the declared main screen (origin 0,0 = Kogan) is driven
        // first and wins; undocked, the laptop is the only candidate.
        if (self.focused_output == null) {
            var box: wlr.Box = undefined;
            self.output_layout.getBox(wlr_output, &box);
            const cx = @as(f64, @floatFromInt(box.x)) + @as(f64, @floatFromInt(box.width)) / 2.0;
            const cy = @as(f64, @floatFromInt(box.y)) + @as(f64, @floatFromInt(box.height)) / 2.0;
            _ = self.cursor.warp(null, cx, cy);
            self.cursor_x = cx;
            self.cursor_y = cy;
            self.focused_output = output;
            std.log.info("KidulWM: boot cursor parked on {s} at {d:.0},{d:.0}", .{ wlr_output.name, cx, cy });
        }
        // Compute layout immediately so window panels appear on the first frame,
        // instead of waiting for the asynchronous layout-event loop tick.
        self.applyLayout();
        // PEEK BIRTH (TASKCARD-3): permanent per-output edge peeks render
        // from the first frame, REGARDLESS of deck state. Born here; the
        // only later hide is deck fullscreen (applyLayout drives it).
        {
            var b: wlr.Box = undefined;
            self.output_layout.getBox(wlr_output, &b);
            const bs: u32 = @intFromFloat(@max(1.0, wlr_output.scale));
            output.peek.updateOutput(@intCast(b.width), @intCast(b.height), bs, b.x, b.y, &self.peek_widgets);
            // EXIT signage for whatever the deck already holds (first frame:
            // empty deck, both signs off — ends are where the sign is
            // loudest, a missing sign means nowhere to walk).
            const n0 = output.deck.slides.items.len;
            output.peek.setNeighbors(false, false, 0, @intCast(n0));
            output.peek.refreshClock();
        }
        // BOOT LADDER (A5): the first output to land spawns the media
        // PLAYER appliance as a normal compositor-owned app slide — first
        // frame, first focus. No home slide exists at keyless boot.
        // HOST GATE (Barticus 2026-09-17): on this host the player is a
        // Mod4+m slide like any other; boot-open is TV-profile behaviour.
        // Gate via env: KIDULWM_BOOT_MEDIA=1 restores the TV boot ladder.
        const boot_media = blk: {
            const val = std.c.getenv("KIDULWM_BOOT_MEDIA") orelse break :blk false;
            break :blk std.mem.eql(u8, std.mem.span(val), "1");
        };
        if (boot_media and !self.boot_player_spawned) {
            self.boot_player_spawned = true;
            _ = output.deck.addCompositorSlide(.media_player, 0, false);
            self.mediaSlideOpen(output);
        }
        // Tell any windows already on this output about the committed scale
        // (they may have mapped while the output was still at scale 1).
        self.syncOutputScaleToWindows(wlr_output, scale);
        self.requestLayout();
        self.ft_scale += 1;
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
        // CARD 2b slice 3: kplayd's video surface (app_id "com.kidul.kplay")
        // is NOT a normal slide — no deck entry, no chrome, no focus. It is
        // tracked server-side and pinned over the video slide's rect every
        // layout (placeKplayWindow). It stays a toplevel child of the video
        // slide's host surface (xdg-foreign), never a wl_subsurface.
        if (toplevel.app_id) |app_id| {
            if (std.mem.eql(u8, std.mem.sliceTo(app_id, 0), "com.kidul.kplay")) {
                window.is_kplay = true;
                self.kplay_window = window;
                std.log.info("KidulWM: kplayd video toplevel tracked id={d} (no deck/chrome/focus)", .{window.id});
                return;
            }
        }
        self.windows.append(window);
    }

    /// kplayd sets its app_id ("com.kidul.kplay") AFTER xdg_toplevel creation
    /// (get_toplevel precedes set_app_id by protocol order), so
    /// handleNewXdgToplevel — which reads toplevel.app_id at creation — always
    /// sees null and appends kplayd's video surface to the normal window list.
    /// Re-classify here, on set_app_id, and pull the window out of the deck
    /// citizens: kplayd's video surface gets no slide, no chrome, no focus —
    /// placeKplayWindow pins it over the video slide rect instead.
    /// Idempotent: a toplevel already born with the app_id set (the early
    /// handleNewXdgToplevel path) is already is_kplay and is skipped.
    pub fn classifyKplay(self: *Server, window: *Window) void {
        if (window.is_kplay) return;
        if (!std.mem.eql(u8, window.app_id.asSlice(), "com.kidul.kplay")) return;
        window.is_kplay = true;
        self.kplay_window = window;
        if (window.link.prev != null) window.link.remove();
        std.log.info("KidulWM: kplayd video toplevel classified id={d} (no deck/chrome/focus)", .{window.id});
    }

    fn handleNewLayerSurface(listener: *wl.Listener(*wlr.LayerSurfaceV1), layer_surface: *wlr.LayerSurfaceV1) void {
        const self: *Server = @fieldParentPtr("new_layer_surface", listener);
        std.log.info("KidulWM: new layer surface ns={s} layer={s}", .{
            layer_surface.namespace,
            @tagName(layer_surface.pending.layer),
        });
        _ = LayerSurface.create(self, layer_surface) catch |err| {
            std.log.err("failed to create layer surface: {}", .{err});
            return;
        };
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

    /// Re-place every output from the declared arrangement (outputs.toml).
    /// Live fix for a mirrored session; assumes config already validated.
    pub fn arrangeOutputsLive(self: *Server) void {
        self.output_arrangement = output_layout_config.load(self.allocator);
        var it = self.outputs.iterator(.forward);
        var placed: usize = 0;
        while (it.next()) |output| {
            const name = std.mem.span(output.wlr_output.name);
            self.output_layout.remove(output.wlr_output);
            if (self.output_arrangement.find(name)) |p| {
                _ = self.output_layout.add(output.wlr_output, p.x, p.y) catch {
                    _ = self.output_layout.addAuto(output.wlr_output) catch continue;
                    continue;
                };
            } else {
                _ = self.output_layout.addAuto(output.wlr_output) catch continue;
            }
            placed += 1;
        }
        std.log.info("KidulWM: arrange_outputs re-placed {d} outputs", .{placed});
    }

    /// C3 select — switch a stage's mode (kadence) at runtime. Content-aware
    /// mode select's conductor primitive: the usher decides, this executes.
    /// Prefers an EXISTING EDID mode matching the request (setMode — the
    /// connector's real, tested timing); only when the panel doesn't advertise
    /// one do we generate a synthetic STANDARD-CVT custom mode (reduced
    /// blanking OFF). setCustomMode on a NATIVE/preferred resolution emits a
    /// standard-CVT timing the Kogan can't sync -> black screen (verdict 76).
    /// Scale re-picked by the CFC law unless overridden, committed atomically,
    /// then every window on that output is re-notified of the new scale. A mode
    /// whose standard-CVT clock exceeds the panel's EDID dotclock cap is
    /// rejected by the connector — the commit fails, we report it, and the
    /// output is untouched (a failed commit never leaves a half-mode).
    pub fn setStageKadence(self: *Server, name: []const u8, width: u32, height: u32, refresh_mhz: u32, scale_override: ?f32) ipc.message.Response {
        var oit = self.outputs.iterator(.forward);
        while (oit.next()) |output| {
            if (!std.mem.eql(u8, std.mem.span(output.wlr_output.name), name)) continue;

            var state = wlr.Output.State.init();
            defer state.finish();
            state.setEnabled(true);
            if (findMode(output.wlr_output, width, height, refresh_mhz)) |m| {
                state.setMode(m);
            } else {
                state.setCustomMode(@intCast(width), @intCast(height), @intCast(refresh_mhz));
            }
            const scale = scale_override orelse pickIntegerScaleForWidth(@intCast(width), output.wlr_output.name);
            state.setScale(scale);
            if (!output.wlr_output.commitState(&state)) {
                std.log.err("KidulWM: kadence {s} -> {d}x{d}@{d}mHz commit FAILED (rejected by connector?)", .{ name, width, height, refresh_mhz });
                return .{ .ok = false, .message = "kadence commit failed — mode rejected by connector (dotclock cap?)" };
            }
            self.syncOutputScaleToWindows(output.wlr_output, scale);
            std.log.info("KidulWM: kadence {s} -> {d}x{d}@{d}mHz scale={d:.2}", .{ name, width, height, refresh_mhz, scale });
            return .{ .ok = true, .message = "kadence applied" };
        }
        return .{ .ok = false, .message = "no such output" };
    }

    /// Find an EDID-advertised mode matching a requested width/height/refresh
    /// (mHz). Refresh is matched within ±1 Hz so a 59.94 panel mode satisfies a
    /// "60" request and 23.976 satisfies "24" — we want the connector's exact
    /// timing, not a synthetic CVT re-derivation of the same nominal mode.
    fn findMode(wlr_output: *wlr.Output, width: u32, height: u32, refresh_mhz: u32) ?*wlr.Output.Mode {
        const w: i32 = @intCast(width);
        const h: i32 = @intCast(height);
        const r: i32 = @intCast(refresh_mhz);
        var it = wlr_output.modes.iterator(.forward);
        while (it.next()) |mode| {
            if (mode.width != w) continue;
            if (mode.height != h) continue;
            const diff: i32 = mode.refresh - r;
            if (diff >= -1000 and diff <= 1000) return mode;
        }
        return null;
    }

    fn updateBackgroundLayout(self: *Server, box: *const wlr.Box) void {
        // The global fallback rect covers the whole layout box. Per-output
        // wallpaper buffers are sized in setupWallpaper; nothing to do here.
        if (self.background.rect) |rect| {
            rect.setSize(box.width, box.height);
        }
        if (self.background.node) |node| {
            node.setPosition(box.x, box.y);
        }
    }

    fn loadWallpaper(self: *Server, path: []const u8) !void {
        _ = path;
        // Runtime reloads route through the worker too; a reload mid-boot
        // just replaces the pending result (last write wins on the pipe).
        // Nothing to do synchronously here.
        _ = self;
    }

    /// Spawn the wallpaper worker thread + arm the event-loop fd that
    /// receives its result. The worker decodes the PNG OFF the boot path;
    /// the main thread builds buffers in handleWallpaperEventFd.
    fn spawnWallpaperWorker(self: *Server, event_loop: *wl.EventLoop) !void {
        const fds = blk: {
            var fds: [2]c_int = undefined;
            const rc = linux.pipe(&fds);
            if (rc != 0) return error.PipeCreateFailed;
            break :blk fds;
        };
        self.wallpaper_pipe = fds;
        self.wallpaper_source = try event_loop.addFd(*Server, fds[0], .{ .readable = true }, handleWallpaperEventFd, self);
        self.wallpaper_thread = try std.Thread.spawn(.{}, wallpaperThreadMain, .{self});
    }

    fn wallpaperThreadMain(server: *Server) void {
        const wp_home = std.c.getenv("HOME") orelse "/home/kidul";
        var path_buf: [4096]u8 = undefined;
        const wp_path = std.fmt.bufPrint(&path_buf, "{s}/Pictures/Wallpapers/theWallpaper.png", .{wp_home}) catch unreachable;

        var result: WallpaperResult = .{ .pixels = &[_]u8{}, .width = 0, .height = 0, .stride = 0, .ok = false };
        if (render_image.Image.loadPng(wp_path)) |image| {
            const len: usize = @intCast(image.stride * image.height);
            const copy = std.heap.page_allocator.alloc(u8, len) catch null;
            if (copy) |buf| {
                @memcpy(buf, image.data[0..len]);
                result = .{ .pixels = buf, .width = image.width, .height = image.height, .stride = image.stride, .ok = true };
                std.log.info("KidulWM: wallpaper decoded on worker ({d}x{d})", .{ image.width, image.height });
            }
            image.deinit();
        } else |err| {
            std.log.warn("KidulWM: wallpaper decode failed: {}", .{err});
        }

        // Publish THEN signal; main thread reads result only after the byte.
        server.wallpaper_result = result;
        _ = linux.write(server.wallpaper_pipe[1], &[_]u8{1}, 1);
    }

    fn handleWallpaperEventFd(fd: c_int, mask: wl.EventMask, server: *Server) c_int {
        _ = fd;
        _ = mask;
        var buf: [8]u8 = undefined;
        _ = linux.read(server.wallpaper_pipe[0], &buf, buf.len);
        const result = server.wallpaper_result orelse return 0;
        server.wallpaper_result = null;
        if (server.wallpaper_thread) |t| {
            t.join();
            server.wallpaper_thread = null;
        }
        if (!result.ok) return 0;

        // Tear down any old per-output nodes + master buffer.
        var it = server.outputs.iterator(.forward);
        while (it.next()) |output| {
            if (output.wallpaper_scene_buffer) |sb| {
                sb.node.destroy();
                output.wallpaper_scene_buffer = null;
            }
            output.setupWallpaperReveal(server, null);
        }
        if (server.wallpaper_reveal_wlr_buffer) |b| wlr.Buffer.drop(b);
        server.wallpaper_reveal_wlr_buffer = null;
        server.wallpaper_anim.active = false;
        if (server.background.image_buffer) |buffer| wlr.Buffer.drop(buffer);
        server.background.image_buffer = null;

        // The permanent wallpaper buffer gets MASTER pixels from frame zero
        // and is never touched by the animation again.
        const buffer = DataBuffer.create(result.pixels, result.width, result.height, result.stride) catch return 0;
        // Keep background.rect/node as the permanent bottom anchor: the
        // rect still fills letterbox bars around the wallpaper, and
        // setupWallpaper places the wallpaper node directly above it.
        server.background.image_buffer = buffer;
        server.background.image_scene_buffer = null;

        var it2 = server.outputs.iterator(.forward);
        while (it2.next()) |output| {
            output.setupWallpaper(server);
        }

        // Boot reveal ("butterfly"): build a palette-tinted copy as a
        // transient fullscreen overlay ABOVE the wallpaper, fading 1->0.
        // Fade-only law (2026-09-07): opacity ramps are GPU-free (one float
        // on the scene node); the per-pixel iris/wipe/whirlpool passes were
        // the CPU storm, so they're gone for good.
        const tinted = std.heap.page_allocator.dupe(u8, result.pixels) catch null;
        var reveal_buffer: ?*wlr.Buffer = null;
        if (tinted) |t| {
            const bg = server.background.color;
            const tr: u32 = @intFromFloat(@min(255, @max(0, bg[0] * 255)));
            const tg: u32 = @intFromFloat(@min(255, @max(0, bg[1] * 255)));
            const tb: u32 = @intFromFloat(@min(255, @max(0, bg[2] * 255)));
            var i: usize = 0;
            while (i + 3 < t.len) : (i += 4) {
                // ARGB32 in memory on LE = B,G,R,A bytes.
                t[i] = @intCast((@as(u32, t[i]) + tb) / 2);
                t[i + 1] = @intCast((@as(u32, t[i + 1]) + tg) / 2);
                t[i + 2] = @intCast((@as(u32, t[i + 2]) + tr) / 2);
            }
            if (DataBuffer.create(t, result.width, result.height, result.stride) catch null) |rb| {
                // create() owns a copy of the pixels now — release our dupe.
                std.heap.page_allocator.free(t);
                reveal_buffer = rb;
            } else {
                std.heap.page_allocator.free(t);
            }
        }
        server.wallpaper_reveal_wlr_buffer = reveal_buffer;

        var it3 = server.outputs.iterator(.forward);
        while (it3.next()) |output| output.setupWallpaperReveal(server, reveal_buffer);

        if (reveal_buffer != null) {
            server.wallpaper_anim = .{ .active = true, .start_us = animation.nowUs(), .effect = .fade, .progress = 0 };
            var it4 = server.outputs.iterator(.forward);
            while (it4.next()) |output| {
                server.ft_reveal += 1;
                output.wlr_output.scheduleFrame();
            }
            std.log.info("KidulWM: wallpaper reveal 'fade' started", .{});
        }
        return 0;
    }

    /// Per-frame reveal tick, called from Output.handleFrame while active.
    /// progress 0..1 smoothstepped over 2.2s; blends tinted->master per the
    /// effect's mask, then commits the final master pixels once at the end.
    fn tickWallpaperReveal(self: *Server, now_us: u64) void {
        if (!self.wallpaper_anim.active) return;
        const duration_us: u64 = 2_200_000;
        const elapsed = now_us -| self.wallpaper_anim.start_us;
        var t: f64 = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(duration_us));
        if (t >= 1.0) t = 1.0;
        const p = t * t * (3.0 - 2.0 * t); // smoothstep
        self.wallpaper_anim.progress = p;

        // Fade-only: one opacity float per output overlay. No pixel passes,
        // no mutation of the permanent wallpaper buffer.
        const opacity: f32 = @floatCast(1.0 - p);
        var it = self.outputs.iterator(.forward);
        while (it.next()) |output| {
            if (output.wallpaper_reveal_buffer) |sb| sb.setOpacity(opacity);
        }

        if (t >= 1.0) {
            // Curtain law: at rest the overlay is GONE, not parked. Destroy
            // the nodes and drop the tinted buffer; the wallpaper below has
            // held master pixels since boot frame zero.
            var it2 = self.outputs.iterator(.forward);
            while (it2.next()) |output| output.setupWallpaperReveal(self, null);
            if (self.wallpaper_reveal_wlr_buffer) |b| wlr.Buffer.drop(b);
            self.wallpaper_reveal_wlr_buffer = null;
            self.wallpaper_anim.active = false;
            std.log.info("KidulWM: wallpaper reveal complete", .{});
        } else {
            // Re-arm so the reveal advances at the output's refresh rate.
            var it3 = self.outputs.iterator(.forward);
            while (it3.next()) |output| {
                self.ft_reveal += 1;
                output.wlr_output.scheduleFrame();
            }
        }
    }

    fn handleShutdownTimer(server: *@This()) c_int {
        server.wl_server.terminate();
        return 0;
    }

    pub fn requestQuit(self: *Server) void {
        const event_loop = self.wl_server.getEventLoop();
        const source = event_loop.addTimer(*@This(), handleShutdownTimer, self) catch |err| {
            std.log.err("failed to schedule quit timer: {}", .{err});
            return;
        };
        source.timerUpdate(1) catch |err| {
            std.log.err("failed to arm quit timer: {}", .{err});
        };
    }

    /// Notification ingress (stage 2): append to the minimal home-slide
    /// feed store and wake outputs so an open home slide re-renders.
    /// Priority/action/display_mode survive in the signature for IPC
    /// compatibility but the store keeps title/body/source only.
    pub fn notificationAdd(self: *Server, title: []const u8, body: []const u8, source_id: []const u8, priority: ?[]const u8, action_id: ?[]const u8, display_mode: ?[]const u8) void {
        _ = priority;
        _ = action_id;
        _ = display_mode;
        self.notifications.add(title, body, source_id);
        var it = self.outputs.iterator(.forward);
        while (it.next()) |output| {
            self.ft_notify += 1;
            output.wlr_output.scheduleFrame();
        }
    }

    pub fn nextAnimationKind(self: *Server) void {
        self.current_transition_kind = switch (self.current_transition_kind) {
            .snap => .wobble,
            .wobble => .ripple,
            .ripple => .snap,
        };
        std.log.info("KidulWM: animation preset -> {s}", .{@tagName(self.current_transition_kind)});
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

        // I1 (Card 1.5): inherit the compositor's own environment — identity
        // (WAYLAND_DISPLAY, XDG_RUNTIME_DIR) and CSD policy (GTK_CSD) flow
        // from one authority. Tentacle-specific needs live in the per-app
        // wrapper (launch-kidul-terminal.sh), not here.
        const envp: [*:null]const ?[*:0]const u8 = @ptrCast(std.c.environ);
        _ = linux.execve(argv[0].?, &argv, envp);
        linux.exit(127);
    }

    pub fn handlePointerMove(self: *Server, _: f64, _: f64) bool {
        // Params ignored: wlroots owns the cursor; hit-test the clamped truth.
        // The peek has NO hover state (furniture, not a widget) — motion is
        // never claimed here.
        self.syncCursorMirror();
        return false;
    }

    pub fn handlePointerClick(self: *Server, _: f64, _: f64) bool {
        // Params ignored: wlroots owns the cursor; hit-test the clamped truth.
        self.syncCursorMirror();
        const x = self.cursor_x;
        const y = self.cursor_y;
        // Overview slide open: click a tile to focus that slide
        // (unpark if needed), or click empty card space to close.
        const deck = self.currentDeck();
        if (deck.overview_slide_open) {
            const xi: i32 = @intFromFloat(x);
            const yi: i32 = @intFromFloat(y);
            if (self.overviewSlideHitTest(xi, yi)) |idx| {
                _ = deck.unparkIndex(idx);
                var it = self.outputs.iterator(.forward);
                while (it.next()) |output| {
                    if (&output.deck == deck) self.overviewSlideClose(output);
                }
                deck.overview_slide_open = false;
                deck.empty_slot = .none;
                deck.focused_index = idx;
                const win_id = deck.slides.items[idx].window_id;
                self.focused_window_id = win_id;
                if (self.windowById(win_id)) |window| {
                    if (window.toplevel.base.surface.mapped) self.focusWindow(window);
                }
            } else {
                self.overviewToggle(); // empty space = close, back to sender
            }
            self.requestLayout();
            return true;
        }
        // PEEK click router (one router): click = walk to the neighbor on
        // that side. Hit-test the output under the cursor's peek.
        var it = self.outputs.iterator(.forward);
        while (it.next()) |output| {
            var box: wlr.Box = undefined;
            self.output_layout.getBox(output.wlr_output, &box);
            const lx = x - @as(f64, @floatFromInt(box.x));
            const ly = y - @as(f64, @floatFromInt(box.y));
            if (lx < 0 or ly < 0 or lx >= @as(f64, @floatFromInt(box.width)) or ly >= @as(f64, @floatFromInt(box.height))) continue;
            if (output.peek.handleClick(lx, ly)) |side| {
                std.log.info("KidulWM: PTR-CLAIM peek-click side={s} x={d:.0} y={d:.0}", .{ @tagName(side), x, y });
                self.focused_output = output;
                switch (side) {
                    .left => self.focusPrev(),
                    .right => self.focusNext(),
                }
                return true;
            }
        }
        return false;
    }

    pub fn handlePointerAxis(self: *Server, _: f64, _: f64, _: f64) bool {
        self.syncCursorMirror();
        return false;
    }

    pub fn logPointerDiagnostic(self: *Server, tag: []const u8, x: f64, y: f64) void {
        _ = self;
        const now = @import("core/animation.zig").nowUs();
        const S = struct {
            var last: u64 = 0;
        };
        if (now - S.last < 1_000_000) return;
        S.last = now;
        std.log.debug("KidulWM: pointer {s} x={d:.1} y={d:.1}", .{ tag, x, y });
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
