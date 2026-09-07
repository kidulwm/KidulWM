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
const output_layout_config = @import("core/output_layout_config.zig");
const animation = @import("core/animation.zig");
const render_image = @import("render/image.zig");
const DataBuffer = @import("render/buffer.zig").DataBuffer;

/// Boot reveal effects for the wallpaper (palette-locked, picked at random
/// per boot). All run ~2.2s with a smoothstep ramp; the per-pixel ones
/// blend master vs theme-tinted copies so no foreign colours ever show.
pub const WallpaperEffect = enum { fade, whirlpool, wipe, iris };

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
const media_slide_mod = @import("ui/media_slide.zig");
const media_mod = @import("ui/media.zig");
const ui = @import("./ui/tray.zig");
const spyglass_mod = @import("./ui/spyglass.zig");
const keybinds = @import("config/keybinds.zig");
const c = @cImport({
    @cInclude("stdio.h");
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

pub const Output = struct {
    server: *Server,
    wlr_output: *wlr.Output,
    scene_output: *wlr.SceneOutput,
    link: wl.list.Link,
    frame: wl.Listener(*wlr.Output),
    destroy: wl.Listener(*wlr.Output),
    deck: slidedeck.SlideDeck,
    /// Sentinel overview slide for THIS output's deck (per-output by ruling).
    overview: overview_slide_mod.OverviewSlide = .{},
    /// Media player slide (left-end sentinel sibling).
    media_slide: media_slide_mod.MediaSlide = .{},
    /// Per-output wallpaper scene buffer (fill-contain, no crop). The master
    /// pixel buffer lives on server.background.image_buffer; each output gets
    /// its own scene buffer referencing it, sized to that output's logical
    /// box. This kills the "one global wallpaper only spans the first output"
    /// bug and the resulting mirror/top-center artifacts.
    wallpaper_scene_buffer: ?*wlr.SceneBuffer = null,

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
            .media_slide = .{},
            .wallpaper_scene_buffer = null,
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
        // re-assert overlay-topmost so widgets/tray/spyglass stay visible.
        scene_buffer.node.lowerToBottom();
        // lowerToBottom puts the wallpaper under the solid bg_rect too —
        // raise it back to sit directly above the background colour.
        if (server.background.node) |bg_node| {
            scene_buffer.node.placeAbove(bg_node);
        }
        server.overlay_tree.node.raiseToTop();
    }

    pub fn deinit(self: *Output) void {
        self.server.tray.removeOutput(self);
        self.frame.link.remove();
        self.destroy.link.remove();
        self.deck.deinit();
        if (self.wallpaper_scene_buffer) |sb| {
            sb.node.destroy();
            self.wallpaper_scene_buffer = null;
        }
        // Video path must die with the output — freeing the pixels while a
        // scene node still references them is a use-after-free, and leaking
        // them is a ghost frame on the remaining outputs.
        while (!self.server.scene_mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.server.scene_mutex.unlock();
        self.server.mediaVideoTeardown(self);
    }

    fn handleFrame(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
        const self: *Output = @fieldParentPtr("frame", listener);
        // TEMP DIAG: frame-rate counter — prints once per second.
        {
            const S = struct {
                var count: u64 = 0;
                var last_log_ms: i64 = 0;
            };
            S.count += 1;
            const now_ms: i64 = @intCast(@divTrunc(animation.nowUs(), 1000));
            if (now_ms - S.last_log_ms >= 1000) {
                std.log.info("KidulWM: FRAMES output={s} count={d}/s media_open={} ready={} active={} wallpaper_anim={}", .{
                    self.wlr_output.name,
                    S.count,
                    self.media_slide.isOpen(),
                    self.media_slide.widget_ready,
                    self.media_slide.widget.player_active,
                    self.server.wallpaper_anim.active,
                });
                S.count = 0;
                S.last_log_ms = now_ms;
            }
        }
        _ = wlr_output;
        // SCENE LOCK: hold for the whole frame — tray.update (drawMediaWidget
        // allocates/destroys scene buffers), mediaVideoRefresh/Teardown, and
        // scene_output.commit all walk the graph the IPC thread can mutate.
        while (!self.server.scene_mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.server.scene_mutex.unlock();
        const now_us = animation.nowUs();
        var it = self.server.windows.iterator(.forward);
        while (it.next()) |window| {
            _ = window.tickAnimation(now_us);
        }
        self.server.tray.update();
        self.server.tickWallpaperReveal(now_us);

        // ── Play-timer arm (reactive) ────────────────────────────────────────
        // The compositor-level play_timer (Server.handlePlayTimer) owns
        // tick() and mediaVideoRefresh() — this output just presents whatever
        // frame is already due (see below). Arm the timer here the first time
        // we see player activity, so playback that starts while no timer is
        // running still gets clocked. The timer self-re-arms; a spurious extra
        // arm from a second output is harmless (timerUpdate resets the delay).
        //
        // Stage 2 — audio-clocked playloop (2026-09-07): advance is now driven
        // by a single compositor-level wl_event_loop timer, not by a specific
        // output's frame callback. Outputs only PRESENT the due frame on their
        // own vsync. See Server.handlePlayTimer, Server.armPlayTimer.
        const any_playing = (self.media_slide.isOpen() and
            self.media_slide.widget_ready and
            self.media_slide.widget.player_active) or
            (!self.media_slide.isOpen() and self.server.tray.media.player_active);
        if (any_playing and self.server.play_timer == null) {
            self.server.armPlayTimer();
        }

        // ── isDone / no-stills teardown (render-thread guards) ───────────────
        // The play_timer checks isDone too, but the render thread must also
        // guard here: if the timer fires and calls disarmPlayTimer between
        // vsync edges we still need to catch a done state and clean up scene
        // nodes (which must happen on the render thread while holding the lock).
        if (self.media_slide.isOpen() and self.media_slide.widget_ready and self.media_slide.widget.player_active) {
            if (self.media_slide.widget.player.isDone()) {
                self.media_slide.widget.ensureStopped();
                self.server.mediaVideoTeardown(self);
                self.server.disarmPlayTimer();
            }
        } else if (self.media_slide.video_buffer != null) {
            // Reconcile: player stopped on a path the server didn't drive
            // (widget.update(), play() switching tracks, widget deinit) —
            // the ghost frame must not outlive playback. LAW: no stills.
            self.server.mediaVideoTeardown(self);
        }

        // ── Slideless isDone guard ───────────────────────────────────────────
        // Mirror of the above for the tray music path (slide closed).
        if (!self.media_slide.isOpen() and self.server.tray.media.player_active) {
            if (self.server.tray.media.player.isDone()) {
                self.server.tray.media.ensureStopped();
                self.server.disarmPlayTimer();
            }
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
    overlay_tree: *wlr.SceneTree,
    output_layout: *wlr.OutputLayout,
    scene_output_layout: *wlr.SceneOutputLayout,
    output_arrangement: output_layout_config.OutputLayout,
    xdg_shell: *wlr.XdgShell,
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
    ipc_thread: ?std.Thread,
    ipc_running: std.atomic.Value(bool),
    /// Guards the wlroots scene graph against cross-thread mutation.
    /// The IPC thread (mediaSlideToggle/Close via kidulwm-control)
    /// destroys scene nodes while the render thread (Output.handleFrame:
    /// tray.update drawMediaWidget, mediaVideoRefresh, scene commit)
    /// walks the same graph — pixman abort on live regions, 2026-09-06
    /// session-killer. Take this on BOTH sides of any scene touch that
    /// can cross threads. Held per-frame; IPC close waits ≤ 1 vsync.
    scene_mutex: std.atomic.Mutex = .unlocked,

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
    /// Set while warping the cursor to follow focus, so the resulting motion
    /// event does not retrigger focus-follows-cursor (the two halves of
    /// "follow the leader" must not chase each other).
    suppress_focus_follow: bool = false,
    last_focused_slide_id: u32 = 0,
    current_transition_kind: animation.AnimationKind = .snap,
    next_window_id: u32 = 1,

    tray: ui.Tray,
    spyglass: ?*spyglass_mod.Spyglass = null,
    // Overview lens: virtual cursor (recency position among unparked minis).
    // The ring node lives per-output (Output.overview_ring) — the lens is
    // per-output by ruling.
    overview_cursor: usize = 0,
    input_device_counts: InputDeviceCounts,
    backend_started: bool = false,
    chrome_style_generation: u32,

    /// Last N pressed key events for the bobPI/debug probe. Lock-free enough:
    /// written on the main thread only, read by the IPC thread via memcpy.
    key_ring: [32]KeyRingEntry = [_]KeyRingEntry{.{}} ** 32,
    key_ring_pos: usize = 0,
    key_events_seen: u64 = 0,

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
    /// Async wallpaper pipeline (2026-09-05): the PNG decodes on a worker
    /// thread so boot paints widgets instantly on the theme-colour rect;
    /// the worker signals wallpaper_pipe and the main thread builds the
    /// DataBuffer + per-output nodes in handleWallpaperEventFd, then runs
    /// a ~2.2s palette-locked reveal animation chosen at random per boot.
    wallpaper_pipe: [2]c_int,
    wallpaper_source: ?*wl.EventSource,
    /// Compositor-level play-timer: advances the mpv frame queue (tick) on the
    /// audio clock, independent of any single output's vsync. Outputs only
    /// present/blit the already-due frame on their own frame callback.
    /// Null while no playback is active; armed by armPlayTimer(); self-re-arms
    /// every PLAY_TIMER_MS until disarmPlayTimer() is called.
    play_timer: ?*wl.EventSource,
    wallpaper_thread: ?std.Thread,
    /// Worker->main handoff. Written ONLY by the worker before the pipe
    /// byte; read ONLY by the main thread after reading the pipe byte.
    wallpaper_result: ?WallpaperResult,
    /// Master + palette-tinted pixel copies kept for the reveal blend.
    /// Both are page_allocator-owned; freed on wallpaper reload/deinit.
    wallpaper_master_px: ?[]u8,
    wallpaper_tinted_px: ?[]u8,
    wallpaper_anim: struct {
        active: bool,
        start_us: u64,
        effect: WallpaperEffect,
        progress: f64,
    },
    outputs: wl.list.Head(Output, .link),

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
                self.tray.toggle();
                return .{ .ok = true };
            },
            .arrange_outputs => {
                // Re-read the declared arrangement (outputs.toml) and re-place
                // every output. Fixes a live mirrored session without restart.
                // VALIDATE FIRST: a broken config must never touch live state.
                var v = output_layout_config.validate(self.allocator);
                if (!v.ok()) {
                    const msg = v.problems.items[0];
                    self.tray.notificationAdd("WM reset blocked", msg, "kidulwm", "high", null, null);
                    return .{ .ok = false, .message = msg };
                }
                self.arrangeOutputsLive();
                return .{ .ok = true, .message = "outputs re-arranged" };
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
                // Media player is a deck SLIDE now, not a tray card.
                self.mediaSlideToggle();
                return .{ .ok = true };
            },
            .media_play => |p| {
                // Route through the open media slide's widget (phase-2 path);
                // fall back to the tray widget if no slide is open.
                var routed = false;
                var oit = self.outputs.iterator(.forward);
                while (oit.next()) |o| {
                    if (o.media_slide.isOpen() and o.media_slide.widget_ready) {
                        o.media_slide.widget.play(p.path);
                        self.mediaSlideRefresh(o);
                        routed = true;
                        break;
                    }
                }
                if (!routed) self.tray.media.play(p.path);
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
            .notification_test => |p| {
                self.tray.notificationAdd(p.title, p.body, p.source_id, p.priority, p.action_id, p.display_mode);
                return .{ .ok = true, .message = "notification added" };
            },
            .notification_clear => {
                self.tray.notifications.clear();
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
            .set_theme, .reload_theme, .arrange_outputs, .tray_toggle, .tray_select_next, .tray_select_prev, .tray_activate, .tray_toggle_card, .weather_toggle_card, .media_card_toggle, .media_play, .media_toggle, .media_next, .media_prev, .media_seek, .notification_test, .notification_clear, .kfiles_navigate, .get_windows, .debug_status, .scene_dump, .quit => {},
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
        const screencopy_manager = try wlr.ScreencopyManagerV1.create(wl_server);
        const fractional_scale_manager = try wlr.FractionalScaleManagerV1.create(wl_server, 1);
        const decoration_manager = try wlr.XdgDecorationManagerV1.create(wl_server);

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
            .output_manager = output_manager,
            .shm = shm,
            .subcompositor = subcompositor,
            .data_device_manager = data_device_manager,
            .viewporter = viewporter,
            .screencopy_manager = screencopy_manager,
            .fractional_scale_manager = fractional_scale_manager,
            .decoration_manager = decoration_manager,
            .seat = seat,
            .cursor = cursor,
            .xcursor_manager = xcursor_manager,
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
            .wallpaper_pipe = undefined,
            .wallpaper_source = null,
            .play_timer = null,
            .wallpaper_thread = null,
            .wallpaper_result = null,
            .wallpaper_master_px = null,
            .wallpaper_tinted_px = null,
            .wallpaper_anim = .{ .active = false, .start_us = 0, .effect = .fade, .progress = 0 },
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
        server.spyglass = spyglass_mod.Spyglass.create(server.allocator, overlay_tree, server.theme) catch |err| blk: {
            std.log.err("failed to create spyglass: {}", .{err});
            break :blk null;
        };

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

        // Background/wallpaper nodes were created after the tray, so ensure the
        // overlay tree stays on top of the background for immediate visibility.
        server.overlay_tree.node.raiseToTop();

        server.pointer.init(server);
        server.keyboard.init(server);
        server.windows.init();
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
            self.writeBootCheck();
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
        if (self.spyglass) |sg| {
            sg.destroy();
            self.spyglass = null;
        }
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
        buf.print(alloc, ",\"flags\":{{\"tray_open\":{},\"calendar_card\":{},\"weather_card\":{},\"media_card\":{},\"network_card\":{},\"files_card\":{},\"signals_card\":{}}}", .{
            self.tray.open,
            self.tray.calendar_card_open,
            self.tray.weather_card_open,
            self.tray.media_card_open,
            self.tray.network_card_open,
            self.tray.files_card_open,
            self.tray.signals_card_open,
        }) catch return .{ .ok = false };
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

    /// Assign a window to the best available output when it maps.
    /// CFC law: everything follows focus, and the CURSOR is the focus you
    /// can see. When the pointer rests on a different stage than the focused
    /// window, the pointer's stage owns new slides — otherwise Granny moves
    /// the mouse to the TV, clicks, and the app opens on the other screen.
    /// Keyboard-driven focus changes warp the cursor along (warpCursorToFocus),
    /// so the two halves can't stay in disagreement for long either way.
    pub fn assignOutput(self: *Server, window: *Window) void {
        if (window.output != null) return;
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

    /// Toggle the sentinel overview slide on the current deck's output.
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
    /// Wraps within the unparked set. Only meaningful with the sentinel open.
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

    /// Enter with the sentinel open: accept the slide under the virtual
    /// cursor (unparking if needed), close the sentinel, focus it.
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

    /// Open the sentinel slide's scene: card background + reparented minis.
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
            tree.node.destroy();
            output.overview.tree = null;
            return;
        };
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

    /// Close the sentinel: restore every reparented slide tree to the scene
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

    /// Toggle the media player slide.
    ///
    /// LAW (docs/law/playback.md, 2026-09-07): the mediaPlayer is a normal
    /// deck slide. It opens on the CURRENT-FOCUS output's deck and lives
    /// nowhere else — no cross-output scanning, no special authority.
    /// The deck flag is the single source of truth for open/closed.
    pub fn mediaSlideToggle(self: *Server) void {
        // Find the output that owns the current focus deck. Deck law: the
        // slide follows the cursor, like every other slide.
        const deck = self.currentDeck();
        var focus_output: ?*Output = null;
        {
            var it = self.outputs.iterator(.forward);
            while (it.next()) |output| {
                if (&output.deck == deck) {
                    focus_output = output;
                    break;
                }
            }
        }
        const output = focus_output orelse return;

        if (deck.media_slide_open) {
            // CLOSE: view-only per audio-authority LAW — playback (if any)
            // survives the card leaving; the peek carries the label.
            self.mediaSlideClose(output);
            deck.closeMediaSlide();
        } else {
            // OPEN: one slide per SESSION, not per deck — the slide follows
            // the cursor. If another output's deck holds the open slide,
            // close that VIEW first (playback survives per audio authority);
            // the slide reopens here, on the cursor's deck.
            {
                var it = self.outputs.iterator(.forward);
                while (it.next()) |other| {
                    if (other != output and other.deck.media_slide_open) {
                        self.mediaSlideClose(other);
                        other.deck.closeMediaSlide();
                    }
                }
            }
            // OPEN: deck state FIRST (openMediaSlide sets empty_slot), then
            // the scene tree on the same output. Overview and media are
            // sibling sentinels — never both.
            deck.openMediaSlide();
            if (output.overview.isOpen()) self.overviewSlideClose(output);
            self.mediaSlideOpen(output);
        }
        self.requestLayout();
    }

    fn mediaSlideOpen(self: *Server, output: *Output) void {
        // SCENE LOCK: reachable from the IPC thread (media_card_toggle).
        while (!self.scene_mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.scene_mutex.unlock();
        if (output.media_slide.isOpen()) return;
        // Every open is FRESH: rebuild the widget so quit-clears is
        // structural, not a flag-reset that can miss a field.
        if (output.media_slide.widget_ready) {
            output.media_slide.widget.deinit();
            output.media_slide.widget = media_mod.MediaWidget.init(self.allocator);
        }
        const tree = self.scene.tree.createSceneTree() catch return;
        output.media_slide.tree = tree;
        tree.node.raiseToTop();
        self.overlay_tree.node.raiseToTop();
        self.mediaSlideRefresh(output);
        std.log.info("KidulWM: media slide open on output", .{});
    }

    /// (Re)render the media widget into the slide's card buffer. Called on
    /// open and whenever the widget's state_generation moves.
    pub fn mediaSlideRefresh(self: *Server, output: *Output) void {
        const tree = output.media_slide.tree orelse return;
        const deck = &output.deck;
        const widget = output.media_slide.ensureWidget(self.allocator);
        // Fullscreen is a SIZE (playback.md): a playing player renders into
        // the full output rect; the card renders into the deck's focused
        // slot (gap-inset, same as a focused client window).
        const target = deck.mediaSlideTarget(widget.player_active);
        const scale: u32 = @intFromFloat(@max(1.0, output.wlr_output.scale));
        const buffer = media_slide_mod.renderToBuffer(widget, self.theme, @intCast(target.width), @intCast(target.height), scale) orelse return;
        if (output.media_slide.card_buffer) |old| old.node.destroy();
        const card = tree.createSceneBuffer(buffer) catch {
            wlr.Buffer.drop(buffer);
            return;
        };
        output.media_slide.card_buffer = card;
        // The buffer was rendered at physical pixels (target × scale) for
        // crispness; the scene graph shows buffers 1:1 by default, which
        // blows the card up by the output scale on HiDPI (the "huge media
        // player, top-left corner only" bug). Pin the display size back to
        // the logical target rect.
        card.setDestSize(@intCast(target.width), @intCast(target.height));
        tree.node.setPosition(target.x, target.y);
        card.node.raiseToTop();
    }

    /// Update the dedicated video scene buffer from the player's current
    /// frame. Called on each frame_serial bump while player_active. Only the
    /// video pixels are copied (native size); the scene graph scales to the
    /// letterboxed rect. No full-slide repaint, no 8MB DataBuffer dupe.
    pub fn mediaVideoRefresh(self: *Server, output: *Output) void {
        const tree = output.media_slide.tree orelse return;
        const widget = &output.media_slide.widget;
        if (!widget.player_active) return;
        const frame = widget.player.currentFrame() orelse return;
        const deck = &output.deck;
        // Video plays fullscreen (playback.md): the letterbox target is the
        // full output rect while the player is active.
        const target = deck.mediaSlideTarget(true);

        // (Re)allocate the persistent pixel buffer if size changed.
        const need: usize = @intCast(frame.stride * frame.h);
        if (output.media_slide.video_pixels.len != need) {
            if (output.media_slide.video_buffer) |sb| {
                sb.node.destroy();
                output.media_slide.video_buffer = null;
            }
            if (output.media_slide.video_wlr_buf) |old| {
                wlr.Buffer.drop(old);
                output.media_slide.video_wlr_buf = null;
            }
            self.allocator.free(output.media_slide.video_pixels);
            output.media_slide.video_pixels = self.allocator.alloc(u8, need) catch return;
        }

        // Copy the frame rows (respect stride).
        const row_bytes: usize = @intCast(frame.w * 4);
        var row: usize = 0;
        while (row < @as(usize, @intCast(frame.h))) : (row += 1) {
            const src_off = row * @as(usize, @intCast(frame.stride));
            @memcpy(output.media_slide.video_pixels[src_off .. src_off + row_bytes], frame.data[src_off .. src_off + row_bytes]);
        }

        // (Re)create the wlroots buffer wrapper if needed. Zero-copy ref:
        // the scene graph reads our video_pixels memory directly; we rewrite
        // it in place each frame. No 8MB dupe.
        if (output.media_slide.video_wlr_buf == null) {
            const buf = DataBuffer.createRef(
                output.media_slide.video_pixels,
                frame.w,
                frame.h,
                frame.stride,
            ) catch return;
            output.media_slide.video_wlr_buf = buf;
        }

        // (Re)create the scene buffer node if needed.
        if (output.media_slide.video_buffer == null) {
            const sb = tree.createSceneBuffer(output.media_slide.video_wlr_buf) catch return;
            output.media_slide.video_buffer = sb;
        } else {
            output.media_slide.video_buffer.?.setBuffer(output.media_slide.video_wlr_buf);
        }

        const sb = output.media_slide.video_buffer.?;
        // Letterbox: scale video into target rect preserving aspect.
        const tw: f64 = @floatFromInt(target.width);
        const th: f64 = @floatFromInt(target.height);
        const vw: f64 = @floatFromInt(frame.w);
        const vh: f64 = @floatFromInt(frame.h);
        const scale = @min(tw / vw, th / vh);
        const dw: i32 = @intFromFloat(vw * scale);
        const dh: i32 = @intFromFloat(vh * scale);
        const tw_i: i32 = @intCast(target.width);
        const th_i: i32 = @intCast(target.height);
        // The video node is a CHILD of the slide tree, which is already
        // positioned at target.x/target.y (see mediaSlideOpen). Use LOCAL
        // coords here — adding target.x/y again double-offsets the video
        // (the "shifted right, strip off-screen" bug).
        const dx: i32 = @divTrunc(tw_i - dw, 2);
        const dy: i32 = @divTrunc(th_i - dh, 2);
        sb.setDestSize(dw, dh);
        sb.node.setPosition(dx, dy);
        // Z-ORDER: the video buffer sits BELOW the card buffer. The card's
        // Player.render (embedder_owns_video) paints the black matte + chrome
        // but leaves the video rect transparent, so the video shows through
        // the hole while the progress bar / buttons stay visible on top.
        if (output.media_slide.card_buffer) |card| card.node.raiseToTop();
    }

    /// Kill the live video scene path: scene node, wlr buffer ref, and the
    /// persistent pixel copy. Called whenever playback stops (ensureStopped)
    /// so the last frame does NOT linger as a ghost behind the wall and
    /// other windows. Safe to call when already torn down.
    pub fn mediaVideoTeardown(self: *Server, output: *Output) void {
        // SCENE LOCK LAW: callers must hold scene_mutex (mediaSlideClose
        // on the IPC thread; handleFrame on the render thread; Output.deinit
        // on the main thread at teardown). Never lock here — nested.
        if (output.media_slide.video_buffer) |sb| sb.node.destroy();
        output.media_slide.video_buffer = null;
        if (output.media_slide.video_wlr_buf) |buf| wlr.Buffer.drop(buf);
        output.media_slide.video_wlr_buf = null;
        if (output.media_slide.video_pixels.len > 0) {
            self.allocator.free(output.media_slide.video_pixels);
            output.media_slide.video_pixels = &.{};
        }
        output.media_slide.last_display_serial = 0;
    }

    fn mediaSlideClose(self: *Server, output: *Output) void {
        // SCENE LOCK: this runs on the IPC thread; the render thread may be
        // mid-draw on the same nodes (2026-09-06 pixman abort).
        while (!self.scene_mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.scene_mutex.unlock();
        if (!output.media_slide.isOpen()) return;
        // AUDIO AUTHORITY LAW (docs/law/playback.md): closing the card is a
        // VIEW change only. Playback never stops here — audio stops only on
        // explicit Stop (or isDone at end of track). The widget and player
        // keep running so the peek label stays live and reopening the card
        // lands mid-track.
        //
        // The dedicated video scene path, however, IS a view: video pixels
        // only exist while the card can show them. Audio-only playback has
        // no video path up. If a video is playing, tearing down its scene
        // buffers stops the GPU-side present without touching the player —
        // reopening re-arms the buffers from currentFrame().
        if (output.media_slide.widget_ready and output.media_slide.widget.player_active) {
            self.mediaVideoTeardown(output);
        }
        // Destroy the card buffer node FIRST (leaking it left a stale frame
        // on screen — the "quit not clearing" bug), then the tree.
        if (output.media_slide.card_buffer) |buf| buf.node.destroy();
        output.media_slide.tree.?.node.destroy();
        output.media_slide.tree = null;
        output.media_slide.card_buffer = null;
        std.log.info("KidulWM: media slide closed (playback continues if active)", .{});
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
        if (!deck.media_slide_open) return false;
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

        // Player mode: route key to Player state machine (Space=pause, Esc=exit, etc.)
        // INPUT LAW (card 2026-09-06 phase 2): unhandled keys FALL THROUGH —
        // the slide never swallows; player Escape exits player, a second
        // Escape closes the slide below.
        if (widget.player_active) {
            const sym_u32 = @intFromEnum(sym);
            if (widget.player.handleKey(sym_u32)) {
                if (widget.player.isDone()) {
                    widget.ensureStopped();
                    self.mediaVideoTeardown(out);
                }
                self.mediaSlideRefresh(out);
                return true;
            }
            return false;
        }

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
            if (dirty) self.mediaSlideRefresh(out);
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
                            // MUSIC PATH: play in tray, dismiss slide.
                            // Grab entry before closing (getLibrary is global).
                            const entry = widget.selectedResultEntry();
                            const path = widget.selectedResultPath();
                            if (path.len > 0 and entry != null) {
                                const e = entry.?;
                                self.tray.media.playMusic(
                                    path,
                                    std.mem.sliceTo(e.title, 0),
                                    std.mem.sliceTo(e.artist, 0),
                                );
                            }
                            // Dismiss the slide — returns focus to the opening slide.
                            self.mediaSlideToggle();
                            return true;
                        }
                        // Movies / TV: existing play-in-slide path.
                        const path = widget.selectedResultPath();
                        if (path.len > 0) widget.play(path);
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
        if (dirty) self.mediaSlideRefresh(out);
        return true;
    }

    /// Hit-test a click in output-local coords against the sentinel's tiles.
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

    /// Focus-follows-cursor half of "follow the leader": on pointer motion,
    /// if the cursor has crossed onto a different output than the one holding
    /// keyboard focus, hand focus to whatever window is under the cursor.
    /// Guarded: only fires when a mapped window is hit (an empty stage keeps
    /// the old focus — no flapping on bare wallpaper).
    pub fn focusFollowsCursor(self: *Server) void {
        if (self.suppress_focus_follow) return;
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
        self.seat.pointerNotifyMotion(0, cx, cy);
        self.suppress_focus_follow = false;
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

        self.focused_output = target;
        // Focus that deck's current slide if it has one.
        const deck = &target.deck;
        if (deck.slides.items.len > 0 and deck.empty_slot == .none) {
            const slide = deck.slides.items[deck.focused_index];
            if (self.windowById(slide.window_id)) |window| {
                self.focusWindow(window);
            }
        }
        self.warpCursorToFocus();
        self.requestLayout();
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

            // Update spyglass icon positions and neighbor availability.
            if (self.spyglass) |sg| {
                const scale: u32 = @intFromFloat(@max(1.0, wlr_output.scale));
                // In empty-slot state, the nearest real slide is on the
                // side it sits: after_last -> neighbor is to the left,
                // before_first -> neighbor is to the right.
                const has_left = (output.deck.empty_slot == .none and output.deck.focused_index > 0) or
                    (output.deck.empty_slot == .after_last and output.deck.slides.items.len > 0);
                const has_right = (output.deck.empty_slot == .none and output.deck.focused_index + 1 < output.deck.slides.items.len) or
                    (output.deck.empty_slot == .before_first and output.deck.slides.items.len > 0);
                sg.updateOutput(width, height, scale);
                sg.setNeighbors(has_left, has_right);
            }

            if (output.deck.slides.items.len == 0) continue;
            any_slides = true;
            // While the sentinel overview slide is open on this output, the
            // slides' scene trees are REPARENTED into the card with tile
            // geometry — the row layout below must not touch them.
            if (output.deck.overviewSlideOpen() and output.overview.isOpen()) {
                if (self.spyglass) |sg| sg.setNeighbors(false, false);
                continue;
            }

            var focused_slide_window: ?*Window = null;
            const deck_ptr = &output.deck;
            for (output.deck.slides.items, 0..) |slide, slide_idx| {
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
                    window.updateChrome(true, .all);
                    window.scene_tree.node.raiseToTop();
                    self.overlay_tree.node.raiseToTop();
                } else {
                    // Non-focused slides: disabled, no rendering, no chrome.
                    window.scene_tree.node.setEnabled(false);
                    window.clearMiniScale();
                    window.clearChrome();
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
                        window.updateChrome(true, .all);
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
        self.tray.addOutput(output);
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
        // Tell any windows already on this output about the committed scale
        // (they may have mapped while the output was still at scale 1).
        self.syncOutputScaleToWindows(wlr_output, scale);
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
        }
        if (server.background.image_buffer) |buffer| wlr.Buffer.drop(buffer);
        server.background.image_buffer = null;

        // Palette-tinted copy: pull each pixel halfway toward the theme
        // background colour. The reveal effects blend between these two
        // copies, so every animation frame stays inside the palette.
        const tinted = std.heap.page_allocator.dupe(u8, result.pixels) catch null;
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
        }
        server.wallpaper_master_px = result.pixels;
        server.wallpaper_tinted_px = tinted;

        // DIAG KILL SWITCH (2026-09-06): wallpaper reveal animations disabled
        // to isolate the persistent "mist" veil + CPU-pinning frame storm.
        // Buffer starts on MASTER pixels and the animation is never armed.
        const start_px = result.pixels;
        const buffer = DataBuffer.create(start_px, result.width, result.height, result.stride) catch return 0;
        // Keep background.rect/node as the permanent bottom anchor: the
        // rect still fills letterbox bars around the wallpaper, and
        // setupWallpaper places the wallpaper node directly above it.
        server.background.image_buffer = buffer;
        server.background.image_scene_buffer = null;

        var it2 = server.outputs.iterator(.forward);
        while (it2.next()) |output| {
            output.setupWallpaper(server);
        }

        // DIAG: animation arming disabled — reveal stays off, master pixels
        // shown from the start. tickWallpaperReveal() early-returns on
        // active==false, so nothing else needs to change.
        std.log.info("KidulWM: wallpaper reveal DISABLED (diag kill switch)", .{});
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

        const master = self.wallpaper_master_px orelse return;
        const tinted = self.wallpaper_tinted_px orelse master;
        const buffer = self.background.image_buffer orelse return;
        const db: *DataBuffer = @fieldParentPtr("base", buffer);
        const out = db.pixels;
        const w: usize = @intCast(buffer.width);
        const h: usize = @intCast(buffer.height);
        const stride: usize = @intCast(db.stride);
        const effect = self.wallpaper_anim.effect;

        switch (effect) {
            .fade => {
                // Cheap: per-buffer opacity ramp instead of a pixel pass.
                var it = self.outputs.iterator(.forward);
                while (it.next()) |output| {
                    if (output.wallpaper_scene_buffer) |sb| {
                        sb.setOpacity(@floatCast(p));
                        output.wlr_output.scheduleFrame();
                    }
                }
            },
            .whirlpool, .wipe, .iris => {
                const cx: f64 = @as(f64, @floatFromInt(w)) / 2;
                const cy: f64 = @as(f64, @floatFromInt(h)) / 2;
                const max_r = @sqrt(cx * cx + cy * cy);
                var y: usize = 0;
                while (y < h) : (y += 1) {
                    const row = y * stride;
                    var x: usize = 0;
                    while (x < w) : (x += 1) {
                        const dx = @as(f64, @floatFromInt(x)) - cx;
                        const dy = @as(f64, @floatFromInt(y)) - cy;
                        const reveal = switch (effect) {
                            .iris => @sqrt(dx * dx + dy * dy) / max_r <= p,
                            .wipe => (dx / (2 * cx) + dy / (2 * cy) + 1.0) / 2.0 <= p,
                            .whirlpool => blk: {
                                const angle = std.math.atan2(dy, dx) + std.math.pi; // 0..2π
                                break :blk angle / (2 * std.math.pi) <= p;
                            },
                            else => true,
                        };
                        const src = if (reveal) master else tinted;
                        const o = row + x * 4;
                        out[o] = src[o];
                        out[o + 1] = src[o + 1];
                        out[o + 2] = src[o + 2];
                        out[o + 3] = src[o + 3];
                    }
                }
            },
        }

        if (t >= 1.0) {
            // Final state: master pixels, full opacity, animation off.
            // The memcpy must run for EVERY effect — fade ramps opacity only
            // and never writes pixels, so skipping it left the TINTED copy
            // on screen forever: the grey "mist" veil of 2026-09-05.
            @memcpy(out, master[0..@min(out.len, master.len)]);
            var it = self.outputs.iterator(.forward);
            while (it.next()) |output| {
                if (output.wallpaper_scene_buffer) |sb| sb.setOpacity(1.0);
            }
            self.wallpaper_anim.active = false;
            std.log.info("KidulWM: wallpaper reveal complete", .{});
        } else {
            // Re-arm so the reveal advances at the output's refresh rate.
            var it = self.outputs.iterator(.forward);
            while (it.next()) |output| output.wlr_output.scheduleFrame();
        }
    }

    fn handleShutdownTimer(server: *@This()) c_int {
        server.wl_server.terminate();
        return 0;
    }

    // ── Compositor-level play-timer ───────────────────────────────────────────
    // Stage 2 (2026-09-07): advance is driven here, NOT in Output.handleFrame.
    //
    // The timer fires every PLAY_TIMER_MS (≈16 ms → ~60 Hz) on the Wayland
    // event-loop main thread — same thread as handleFrame, so no mutex needed
    // between this and scene operations.  For mediaVideoRefresh the IPC-thread
    // rule still applies (scene_mutex held there); the calls below are on the
    // main thread, so they are safe to call without a lock.
    //
    // VSYNC SELF-PERPETUATION preserved: scheduleFrame() is called here for
    // every output that has new video pixels, so the render loop keeps firing
    // at the output's native refresh even when no other event triggers it.
    const PLAY_TIMER_MS: c_int = 16; // ~60 Hz audio-clock advance

    pub fn armPlayTimer(self: *Server) void {
        const event_loop = self.wl_server.getEventLoop();
        if (self.play_timer == null) {
            self.play_timer = event_loop.addTimer(*Server, handlePlayTimer, self) catch |err| {
                std.log.err("KidulWM: play_timer create failed: {}", .{err});
                return;
            };
        }
        self.play_timer.?.timerUpdate(PLAY_TIMER_MS) catch |err| {
            std.log.err("KidulWM: play_timer arm failed: {}", .{err});
        };
    }

    pub fn disarmPlayTimer(self: *Server) void {
        if (self.play_timer) |t| {
            t.timerUpdate(0) catch {}; // 0 ms = disarm without destroy
        }
        // We leave play_timer allocated; it is re-armed by armPlayTimer next
        // time playback starts.  Destroying and re-creating costs an fd each
        // cycle; the event-source pool is small, so reuse is preferred.
    }

    fn handlePlayTimer(self: *Server) c_int {
        // Check whether anything is still playing before doing any work.
        var slide_playing = false;
        var slideless_playing = false;
        var out_it = self.outputs.iterator(.forward);
        while (out_it.next()) |output| {
            if (output.media_slide.isOpen() and
                output.media_slide.widget_ready and
                output.media_slide.widget.player_active)
            {
                slide_playing = true;
                break;
            }
        }
        if (!slide_playing and self.tray.media.player_active) {
            slideless_playing = true;
        }

        if (!slide_playing and !slideless_playing) {
            // Nothing to advance — let the timer lapse (do not re-arm).
            return 0;
        }

        // ── Slide player advance ──────────────────────────────────────────────
        // SCENE LOCK: mediaVideoRefresh creates/updates scene buffers.
        // The IPC thread (mediaSlideClose) destroys nodes concurrently — hold
        // scene_mutex for the same reason handleFrame does.
        if (slide_playing) {
            while (!self.scene_mutex.tryLock()) std.atomic.spinLoopHint();
            defer self.scene_mutex.unlock();

            out_it = self.outputs.iterator(.forward);
            while (out_it.next()) |output| {
                if (!output.media_slide.isOpen() or
                    !output.media_slide.widget_ready or
                    !output.media_slide.widget.player_active) continue;

                if (output.media_slide.widget.player.isDone()) {
                    // isDone teardown: render thread (handleFrame) cleans up
                    // scene nodes safely under the lock it holds per-frame.
                    // Disarm so handleFrame's isDone guard fires next vsync.
                    self.disarmPlayTimer();
                    return 0;
                }

                output.media_slide.widget.player.tick();
                const serial = output.media_slide.widget.player.display_serial;
                if (serial != output.media_slide.last_display_serial) {
                    output.media_slide.last_display_serial = serial;
                    self.mediaVideoRefresh(output);
                    // VSYNC SELF-PERPETUATION: schedule a frame so the output
                    // presents the updated pixels on its own vsync.
                    output.wlr_output.scheduleFrame();
                }
            }
        }

        // ── Slideless music advance ───────────────────────────────────────────
        // Slide closed, music still playing in the tray MediaWidget.
        if (slideless_playing) {
            if (self.tray.media.player.isDone()) {
                self.tray.media.ensureStopped();
                self.disarmPlayTimer();
                return 0;
            }
            self.tray.media.player.tick();
            // No video pixels for audio-only; no scheduleFrame needed here.
            // Arm scheduleFrame on the first output so the tray repaints its
            // now-playing metadata once per timer tick.
            if (self.outputs.first()) |first_out| {
                first_out.wlr_output.scheduleFrame();
            }
        }

        // Re-arm for the next tick.
        self.play_timer.?.timerUpdate(PLAY_TIMER_MS) catch |err| {
            std.log.err("KidulWM: play_timer re-arm failed: {}", .{err});
        };
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
            .is_kfiles_open = struct {
                fn f(ctx: *anyopaque) bool {
                    const s: *Server = @ptrCast(@alignCast(ctx));
                    var it = s.windows.iterator(.forward);
                    while (it.next()) |window| {
                        if (window.app_id.len > 0 and std.mem.eql(u8, window.app_id.buf[0..window.app_id.len], "com.kidulwm.kfiles")) {
                            return window.toplevel.base.surface.mapped;
                        }
                    }
                    return false;
                }
            }.f,
            .media_slide_toggle = struct {
                fn f(ctx: *anyopaque) void {
                    const s: *Server = @ptrCast(@alignCast(ctx));
                    s.mediaSlideToggle();
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
            "GTK_CSD=0",
            "GHOSTTY_RESOURCES_DIR=/usr/share/ghostty",
            null,
        };
        _ = linux.execve(argv[0].?, &argv, &envp);
        linux.exit(127);
    }

    pub fn handlePointerMove(self: *Server, x: f64, y: f64) bool {
        if (self.spyglass) |sg| {
            if (sg.handlePointerMove(x, y)) return true;
        }
        return self.tray.handlePointerMove(x, y);
    }

    pub fn handlePointerClick(self: *Server, x: f64, y: f64) bool {
        // Sentinel overview slide open: click a tile to focus that slide
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
        if (self.spyglass) |sg| {
            if (sg.handlePointerClick(x, y)) |side| {
                self.activateSpyglass(side);
                return true;
            }
        }
        return self.tray.handlePointerClick(x, y);
    }

    /// Spyglass click — navigate to the adjacent slide in the given direction.
    fn activateSpyglass(self: *Server, side: spyglass_mod.Side) void {
        std.log.info("KidulWM: spyglass click {s}", .{if (side == .left) "left" else "right"});
        switch (side) {
            .left => self.focusPrev(),
            .right => self.focusNext(),
        }
    }

    pub fn handlePointerAxis(self: *Server, x: f64, y: f64, delta: f64) bool {
        return self.tray.handleAxis(x, y, delta);
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
