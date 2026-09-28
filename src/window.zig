const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const Server = @import("server.zig").Server;
const Output = @import("server.zig").Output;
const animation = @import("core/animation.zig");
const chrome_renderer = @import("render/chrome.zig");

/// CHROME LAW (docs/law/chrome.md, amended 2026-09-28): the compositor draws
/// only a thin scene-rect border — no full-window cairo/DataBuffer (that was
/// the 27.14MB-per-layout-event leak, pin 2026-09-28). Flip to false to
/// disable compositor-side framing entirely (KSD apps self-frame).
const chrome_enabled = true;
const Style = @import("core/style.zig").Style;

const Label = struct {
    buf: [64]u8 = undefined,
    len: u8 = 0,

    pub fn asSlice(self: *const Label) []const u8 {
        return self.buf[0..self.len];
    }

    fn set(self: *Label, s: []const u8) bool {
        const clipped = @min(s.len, self.buf.len);
        if (clipped == self.len and std.mem.eql(u8, self.buf[0..clipped], s[0..clipped])) return false;
        @memcpy(self.buf[0..clipped], s[0..clipped]);
        self.len = @intCast(clipped);
        return true;
    }
};

pub const Window = struct {
    server: *Server,
    toplevel: *wlr.XdgToplevel,
    /// Layout/wrapper tree moved around the output.
    scene_tree: *wlr.SceneTree,
    /// Child tree containing the XDG surface; can be offset for peeks.
    surface_tree: *wlr.SceneTree,
    /// Last offset applied via setSurfaceOffset — lets the no-op guard skip
    /// redundant setPosition writes (which damage the scene every time).
    /// First call must always apply, hence the impossible initial value.
    last_surface_offset_x: i32 = std.math.minInt(i32),
    last_surface_offset_y: i32 = std.math.minInt(i32),

    /// Last clip applied via applyContainment — lets the no-op guard skip
    /// subsurfaceTreeSetClip on steady-state commits. minInt = never applied.
    last_clip_x: i32 = std.math.minInt(i32),
    last_clip_y: i32 = std.math.minInt(i32),
    last_clip_w: i32 = std.math.minInt(i32),
    last_clip_h: i32 = std.math.minInt(i32),

    output: ?*Output,
    id: u32,
    link: wl.list.Link,

    /// CARD 2b slice 3: kplayd's video toplevel (app_id "com.kidul.kplay").
    /// Lives outside the deck/windows list: no slide, no chrome, no focus.
    /// The compositor pins its scene tree over the video slide's rect every
    /// layout (Server.placeKplayWindow).
    is_kplay: bool = false,

    animation: animation.WindowAnimation,

    chrome_tree: ?*wlr.SceneTree,
    chrome_scale: u32,
    chrome_style_generation: u32,
    chrome_focused: bool,
    chrome_edges: chrome_renderer.EdgeMode,
    chrome_width: i32,
    chrome_height: i32,
    chrome_label: Label,

    title: Label,
    app_id: Label,

    map: wl.Listener(void),
    unmap: wl.Listener(void),
    destroy: wl.Listener(void),
    toplevel_destroy: wl.Listener(void),
    commit: wl.Listener(*wlr.Surface),
    set_title: wl.Listener(void),
    set_app_id: wl.Listener(void),

    pub fn create(server: *Server, toplevel: *wlr.XdgToplevel) !*Window {
        const window = try server.allocator.create(Window);
        errdefer server.allocator.destroy(window);

        const scene_tree = try server.scene.tree.createSceneTree();
        const surface_tree = try scene_tree.createSceneXdgSurface(toplevel.base);

        const id = server.next_window_id;
        server.next_window_id += 1;

        window.* = .{
            .server = server,
            .toplevel = toplevel,
            .scene_tree = scene_tree,
            .surface_tree = surface_tree,
            .output = null,
            .id = id,
            .link = undefined,
            .animation = .{},
            .chrome_tree = null,
            .chrome_scale = 1,
            .chrome_style_generation = 0,
            .chrome_focused = false,
            .chrome_edges = chrome_renderer.EdgeMode.all,
            .chrome_width = 0,
            .chrome_height = 0,
            .chrome_label = .{},
            .title = .{},
            .app_id = .{},
            .map = wl.Listener(void).init(handleMap),
            .unmap = wl.Listener(void).init(handleUnmap),
            .destroy = wl.Listener(void).init(handleDestroy),
            .toplevel_destroy = wl.Listener(void).init(handleToplevelDestroy),
            .commit = wl.Listener(*wlr.Surface).init(handleCommit),
            .set_title = wl.Listener(void).init(handleSetTitle),
            .set_app_id = wl.Listener(void).init(handleSetAppId),
        };

        window.map.link.init();
        window.unmap.link.init();
        window.destroy.link.init();
        window.toplevel_destroy.link.init();
        window.commit.link.init();
        window.set_title.link.init();
        window.set_app_id.link.init();
        window.link.init();

        toplevel.base.surface.events.map.add(&window.map);
        toplevel.base.surface.events.unmap.add(&window.unmap);
        toplevel.base.events.destroy.add(&window.destroy);
        std.log.info("KidulWM: TRACE create id={d} adding toplevel_destroy listener={*}", .{ window.id, &window.toplevel_destroy });
        // wlroots asserts every toplevel signal's listener_list is empty at the
        // END of the TOPLEVEL destroy emission (destroy_xdg_toplevel), which
        // runs BEFORE the base xdg_surface destroy signal. The detach must be
        // complete by the time toplevel.events.destroy finishes — so listen on
        // the toplevel destroy itself and do the teardown there.
        toplevel.events.destroy.add(&window.toplevel_destroy);
        std.log.info("KidulWM: TRACE create id={d} added; link.prev={*}", .{ window.id, window.toplevel_destroy.link.prev });
        toplevel.base.surface.events.commit.add(&window.commit);
        toplevel.events.set_title.add(&window.set_title);
        toplevel.events.set_app_id.add(&window.set_app_id);

        // Capture initial title/app_id if already provided.
        window.captureTitle();
        window.captureAppId();
        window.refreshPeekLabel();

        return window;
    }

    fn captureTitle(window: *Window) void {
        if (window.toplevel.title) |ptr| {
            const s = std.mem.sliceTo(ptr, 0);
            _ = window.title.set(s);
        }
    }

    fn captureAppId(window: *Window) void {
        if (window.toplevel.app_id) |ptr| {
            const s = std.mem.sliceTo(ptr, 0);
            _ = window.app_id.set(s);
        }
    }

    fn handleSetTitle(listener: *wl.Listener(void)) void {
        const window: *Window = @fieldParentPtr("set_title", listener);
        window.captureTitle();
        window.refreshPeekLabel();
    }

    fn handleSetAppId(listener: *wl.Listener(void)) void {
        const window: *Window = @fieldParentPtr("set_app_id", listener);
        window.captureAppId();
        window.refreshPeekLabel();
        // kplayd sets app_id after toplevel creation — re-classify here so
        // its video surface never becomes a deck slide (focus/chrome/peek).
        window.server.classifyKplay(window);
    }

    fn refreshPeekLabel(window: *Window) void {
        const label = window.computePeekLabel();
        if (window.chrome_label.set(label)) {
            // Force chrome regen on next layout.
            window.chrome_width = 0;
            window.chrome_height = 0;
        }
    }

    fn computePeekLabel(window: *Window) []const u8 {
        const app_slice = window.app_id.asSlice();
        const title_slice = window.title.asSlice();

        // Known app_id nicknames.
        if (appSliceContains(app_slice, "ghostty")) return "Ghostty";
        if (appSliceContains(app_slice, "nano")) return "Nano";
        if (appSliceContains(app_slice, "helium") or
            appSliceContains(app_slice, "brave") or
            appSliceContains(app_slice, "chrome") or
            appSliceContains(app_slice, "firefox")) return "Helium";
        if (appSliceContains(app_slice, "hermes") or appSliceContains(app_slice, "bob")) return "Bob";

        if (app_slice.len > 0) {
            const cleaned = cleanAppId(app_slice);
            if (cleaned.len > 0) return cleaned;
        }

        if (title_slice.len > 0) {
            if (std.mem.indexOfScalar(u8, title_slice, ' ')) |sp| {
                return title_slice[0..sp];
            }
            return title_slice;
        }

        return "App";
    }

    fn appSliceContains(haystack: []const u8, needle: []const u8) bool {
        var lower_buf: [256]u8 = undefined;
        if (haystack.len > lower_buf.len) return false;
        const lowered = std.ascii.lowerString(lower_buf[0..haystack.len], haystack);
        return std.mem.indexOf(u8, lowered, needle) != null;
    }

    fn cleanAppId(app_id_str: []const u8) []const u8 {
        var start: usize = 0;
        // Strip common reverse-DNS prefixes.
        while (std.mem.indexOf(u8, app_id_str[start..], ".")) |dot| {
            start += dot + 1;
        }
        const s = app_id_str[start..];
        if (s.len > 0) return s;
        return app_id_str;
    }

    pub fn focus(self: *Window, seat: *wlr.Seat) void {
        const surface = self.toplevel.base.surface;
        if (!surface.mapped) {
            std.log.debug("KidulWM: refusing focus on unmapped surface", .{});
            return;
        }
        if (seat.getKeyboard()) |keyboard| {
            const keycodes: []const u32 = keyboard.keycodes[0..keyboard.num_keycodes];
            seat.keyboardNotifyEnter(surface, keycodes, &keyboard.modifiers);
        } else {
            seat.keyboardNotifyEnter(surface, &.{}, null);
        }
        std.log.info("KidulWM: focused window", .{});
    }

    /// Layout target is recorded. By default windows snap instantly to their
    /// correct SlideDeck position. Call `startTransition()` to animate this
    /// particular layout change over 120 ms.
    pub fn setLayoutTarget(self: *Window, x: i32, y: i32, w: u32, h: u32) void {
        const tx = @as(f64, @floatFromInt(x));
        const ty = @as(f64, @floatFromInt(y));
        const tw = @as(f64, @floatFromInt(w));
        const th = @as(f64, @floatFromInt(h));

        self.animation.target_x = tx;
        self.animation.target_y = ty;
        self.animation.target_w = tw;
        self.animation.target_h = th;

        // Size and opacity snap immediately; position is only animated while a
        // transition is active.
        self.animation.cur_w = tw;
        self.animation.cur_h = th;
        self.animation.cur_opacity = self.animation.target_opacity;

        if (self.animation.last_us == 0) {
            self.animation.cur_x = tx;
            self.animation.cur_y = ty;
            self.animation.start_x = tx;
            self.animation.start_y = ty;
        }

        self.scene_tree.node.setPosition(
            @intFromFloat(@round(self.animation.cur_x)),
            @intFromFloat(@round(self.animation.cur_y)),
        );
        if (self.chrome_tree) |chrome| {
            chrome.node.setPosition(
                @intFromFloat(@round(self.animation.cur_x)),
                @intFromFloat(@round(self.animation.cur_y)),
            );
        }
    }

    /// Start a 120 ms position transition from the window's current position to
    /// the layout target that was just set by `setLayoutTarget`.
    pub fn startTransition(self: *Window, kind: animation.AnimationKind) void {
        self.animation.start_x = self.animation.cur_x;
        self.animation.start_y = self.animation.cur_y;
        self.animation.kind = kind;
        self.animation.start_us = animation.nowUs();
        self.animation.last_us = self.animation.start_us;
        self.animation.vx = 0;
        self.animation.vy = 0;
    }

    /// Advance any active transition and update the scene.
    pub fn tickAnimation(self: *Window, now_us: animation.TimeUs) bool {
        if (!self.toplevel.base.surface.mapped) return false;
        if (self.animation.last_us == 0) return false;
        const moved = self.animation.tick(now_us);
        if (moved) {
            self.scene_tree.node.setPosition(
                @intFromFloat(@round(self.animation.cur_x)),
                @intFromFloat(@round(self.animation.cur_y)),
            );
            // Chrome lives in overlay_tree — track position explicitly.
            if (self.chrome_tree) |chrome| {
                chrome.node.setPosition(
                    @intFromFloat(@round(self.animation.cur_x)),
                    @intFromFloat(@round(self.animation.cur_y)),
                );
            }
            // Only regenerate chrome if this window already HAS chrome
            // (i.e. it's the focused slide). Non-focused slides have their
            // chrome cleared by applyLayout and should stay chromeless.
            if (self.chrome_tree != null) {
                self.updateChrome(self.chrome_focused, self.chrome_edges);
            }
        } else {
            // Transition finished; reset so future layouts snap.
            self.animation.last_us = 0;
            self.animation.start_us = 0;
        }
        return moved;
    }

    /// Set the destination size of the client surface buffer. This ensures
    /// wlroots considers the surface visible (so it receives frame callbacks)
    /// even when the committed buffer has not yet caught up to the configured
    /// size.
    pub fn setSurfaceDestSize(self: *Window, w: i32, h: i32) void {
        const Size = struct { w: c_int, h: c_int };
        var size = Size{ .w = w, .h = h };
        self.surface_tree.node.forEachBuffer(*Size, struct {
            fn iter(buffer: *wlr.SceneBuffer, sx: c_int, sy: c_int, data: *Size) void {
                _ = sx;
                _ = sy;
                if (wlr.SceneSurface.tryFromBuffer(buffer) == null) return;
                buffer.setDestSize(data.w, data.h);
            }
        }.iter, &size);
    }

    /// Offset the XDG surface within its wrapper tree, used to keep the visible
    /// sliver on the correct side of a peek window. For left peeks the surface
    /// is pulled right so its right edge aligns with the visible sliver; for
    /// right peeks it stays left-aligned; focused windows are top-left aligned.
    pub fn setSurfaceOffset(self: *Window, x: i32, y: i32) void {
        // No-op guard: setPosition damages the scene even when unchanged,
        // and handleCommit calls us on EVERY client commit — an unconditional
        // write here turns any redrawing client (cursor blink, clock) into a
        // full-tilt commit->damage->frame-done->redraw feedback loop that
        // pins the CPU (the 90/s ghostty commit storm, 2026-09-05).
        if (self.last_surface_offset_x == x and self.last_surface_offset_y == y) return;
        self.last_surface_offset_x = x;
        self.last_surface_offset_y = y;
        self.surface_tree.node.setPosition(x, y);
    }

    /// MANDATORY containment rule: clip the client surface to the content
    /// geometry so CSD padding is cropped away.  Called on every window
    /// in applyLayout and on every surface commit.
    pub fn applyContainment(self: *Window) void {
        const surface = self.toplevel.base.surface;
        if (!surface.mapped) return;
        const geom = self.toplevel.base.geometry;
        if (geom.width <= 0 or geom.height <= 0) return;
        // No-op guard: subsurfaceTreeSetClip damages the output even when the
        // box is unchanged, and handleCommit calls us on EVERY client commit —
        // an unconditional write here turns any redrawing client into a
        // commit->damage->frame-done->redraw feedback loop that pins the CPU
        // (the fans-on storm of 2026-09-07: 78-150 fps on both outputs with
        // every animation flag false, clip box never changing).
        if (self.last_clip_x == geom.x and self.last_clip_y == geom.y and
            self.last_clip_w == geom.width and self.last_clip_h == geom.height) return;
        self.last_clip_x = geom.x;
        self.last_clip_y = geom.y;
        self.last_clip_w = geom.width;
        self.last_clip_h = geom.height;
        self.surface_tree.node.subsurfaceTreeSetClip(&wlr.Box{
            .x = geom.x,
            .y = geom.y,
            .width = geom.width,
            .height = geom.height,
        });
    }

    /// Focused window: scale and offset the surface so its content geometry
    /// exactly fills the wrapper. CSD shadows/padding are pushed under the
    /// chrome border ring, eliminating the inner gap.
    pub fn setSurfaceOffsetForFocus(self: *Window) void {
        const surface = self.toplevel.base.surface;
        if (!surface.mapped) {
            std.log.debug("KidulWM: setSurfaceOffsetForFocus id={d} skipped (not mapped)", .{self.id});
            return;
        }

        const geom = self.toplevel.base.geometry;
        const target_w: f64 = self.animation.target_w;
        const target_h: f64 = self.animation.target_h;

        std.log.debug("KidulWM: setSurfaceOffsetForFocus id={d} target={d}x{d} geom={d}x{d}@{d},{d} buffer={d}x{d}", .{ self.id, @as(i32, @intFromFloat(target_w)), @as(i32, @intFromFloat(target_h)), geom.width, geom.height, geom.x, geom.y, surface.current.width, surface.current.height });

        // Avoid division by zero: if geometry or committed buffer is not yet
        // known, fall back to no-op. handleCommit will re-run this once the
        // first buffer arrives.
        if (geom.width <= 0 or geom.height <= 0) {
            std.log.debug("KidulWM: setSurfaceOffsetForFocus id={d} skipped (bad geometry)", .{self.id});
            return;
        }
        if (surface.current.width <= 0 or surface.current.height <= 0) {
            std.log.debug("KidulWM: setSurfaceOffsetForFocus id={d} skipped (no buffer)", .{self.id});
            return;
        }

        // No offset — wlroots handles XDG geometry internally.
        // The clip at (geom.x, geom.y, geom.width, geom.height) crops CSD.
        const off_x: i32 = 0;
        const off_y: i32 = 0;

        self.setSurfaceOffset(off_x, off_y);
    }

    /// Overview mini: scale the whole surface tree down into the mini cell.
    /// Unlike focus (which renders the buffer at native size and only clips
    /// CSD), the mini must shrink the content to the target rect. Uses the
    /// existing per-buffer setDestSize walk (proven path), then clips CSD.
    pub fn setSurfaceForMini(self: *Window) void {
        const surface = self.toplevel.base.surface;
        if (!surface.mapped) return;
        const geom = self.toplevel.base.geometry;
        if (geom.width <= 0 or geom.height <= 0) return;

        const target_w: i32 = @intFromFloat(@max(1.0, self.animation.target_w));
        const target_h: i32 = @intFromFloat(@max(1.0, self.animation.target_h));

        self.surface_tree.node.setPosition(0, 0);
        self.setSurfaceDestSize(target_w, target_h);
        self.applyContainment();
    }

    /// Reset any mini scaling when returning to normal layout. Destination
    /// size of 0x0 means "render at native buffer size" in wlroots.
    pub fn clearMiniScale(self: *Window) void {
        self.setSurfaceDestSize(0, 0);
    }

    /// Regenerate the compositor-drawn chrome overlay for this window.
    /// The overlay follows the layout target size and focus state, ensuring
    /// KidulWM owns the signature corner look regardless of client CSD.
    /// Destroy the compositor-drawn chrome overlay for this window.
    /// Called when the slide becomes non-focused so no border ring lingers.
    pub fn clearChrome(self: *Window) void {
        if (self.chrome_tree) |tree| {
            std.log.info("KidulWM: clearChrome id={d}", .{self.id});
            tree.node.destroy();
            self.chrome_tree = null;
        }
        // Reset cached state so tickAnimation doesn't recreate the chrome
        // with stale focused/edges values.
        self.chrome_focused = false;
        self.chrome_edges = .all;
        self.chrome_width = 0;
        self.chrome_height = 0;
    }

    pub fn updateChrome(self: *Window, focused: bool, edges: chrome_renderer.EdgeMode) void {
        // CHROME LAW (docs/law/chrome.md, amended 2026-09-28): thin border as
        // scene rects only — no full-window cairo/DataBuffer (the leak).
        if (chrome_enabled) {
            // Cache key is the animation TARGET, not the live cur_w/cur_h: the
            // spring eases cur_* toward target over many frames and sub-pixel
            // jitter makes a cur-based key never hit (the 2026-09-07 regen
            // storm). Target changes exactly when geometry does.
            const w: i32 = @intFromFloat(@round(self.animation.target_w));
            const h: i32 = @intFromFloat(@round(self.animation.target_h));
            if (w <= 0 or h <= 0) return;

            var scale: u32 = 1;
            if (self.output) |output| {
                scale = @intFromFloat(@max(1.0, output.wlr_output.scale));
            }

            const style_gen = self.server.chrome_style_generation;
            const same = self.chrome_tree != null and
                self.chrome_width == w and
                self.chrome_height == h and
                self.chrome_focused == focused and
                self.chrome_edges.eql(edges) and
                self.chrome_scale == scale and
                self.chrome_style_generation == style_gen;
            if (same) return;

            if (self.chrome_tree) |tree| {
                tree.node.destroy();
                self.chrome_tree = null;
            }

            // Chrome must live in overlay_tree so it renders ABOVE the client
            // surface (docs/KIDULWM_CHROME_LAYERS.md).
            const tree = self.server.overlay_tree.createSceneTree() catch return;
            tree.node.setPosition(
                @intFromFloat(@round(self.animation.cur_x)),
                @intFromFloat(@round(self.animation.cur_y)),
            );
            tree.node.raiseToTop();
            tree.node.data = self;
            self.chrome_tree = tree;

            self.chrome_width = w;
            self.chrome_height = h;
            self.chrome_focused = focused;
            self.chrome_edges = edges;
            self.chrome_scale = scale;
            self.chrome_style_generation = style_gen;

            // Thin border: four solid scene rects, O(perimeter), no raster. The
            // colour is a theme token (color_border_focused), so a theme reload
            // bumps style_gen above and forces a regen — borders change in sync
            // with every widget.
            const style = self.server.theme;
            const bw: i32 = @max(1, @as(i32, @intFromFloat(@round(style.border_width * @as(f32, @floatFromInt(scale))))));
            const border = style.color_border_focused.toF32();

            if (edges.top) {
                const r = tree.createSceneRect(w, bw, &border) catch null;
                if (r) |rect| rect.node.setPosition(0, 0);
            }
            if (edges.bottom) {
                const r = tree.createSceneRect(w, bw, &border) catch null;
                if (r) |rect| rect.node.setPosition(0, h - bw);
            }
            if (edges.left) {
                const r = tree.createSceneRect(bw, h, &border) catch null;
                if (r) |rect| rect.node.setPosition(0, 0);
            }
            if (edges.right) {
                const r = tree.createSceneRect(bw, h, &border) catch null;
                if (r) |rect| rect.node.setPosition(w - bw, 0);
            }
        }
    }

    fn handleMap(listener: *wl.Listener(void)) void {
        const window: *Window = @fieldParentPtr("map", listener);
        const app_id_slice = window.app_id.asSlice();
        std.log.info("KidulWM: window mapped id={d} app_id='{s}'", .{ window.id, app_id_slice });
        window.server.assignOutput(window);
        // Tell the client its output's scale immediately — before it commits
        // its first buffer — so it renders at buffer_scale = output scale.
        if (window.output) |output| {
            const scale: f64 = output.wlr_output.scale;
            wlr.FractionalScaleManagerV1.notifyScale(window.toplevel.base.surface, scale);
            window.toplevel.base.surface.sendEnter(output.wlr_output);
        }
        // CARD 2b slice 3: kplayd's video toplevel bypasses the deck entirely
        // (no slide, no focus) — it is pinned over the video slide's rect.
        if (window.is_kplay) {
            window.server.placeKplayWindow();
            window.server.requestLayout();
            return;
        }
        const deck = window.server.deckForWindow(window);
        deck.addWindow(window.id);
        std.log.info("KidulWM: added window id={d} to deck slides={d} focused_index={d}", .{ window.id, deck.slides.items.len, deck.focused_index });
        window.server.focusWindow(window);
        if (window.output) |output| window.server.focused_output = output;
        // Run layout synchronously so the slide target is set before the client
        // commits its first buffer. Otherwise handleCommit sees target_w == 0 and
        // cannot scale the surface.
        window.server.applyLayout();
        window.server.requestLayout();
    }

    /// Detach every listener attached to the toplevel/surface. Safe to call
    /// more than once: the wayland-zig Link.remove() nulls prev/next, so a
    /// second call would null-deref — guard on prev != null.
    /// Must run before wlroots teardown (wl_client_destroy -> destroy_xdg_toplevel)
    /// asserts the signal lists are empty; the assert fires at the END of the
    /// toplevel destroy emission, so the detach must happen inside a listener
    /// on toplevel.events.destroy — not base.events.destroy, which runs later.
    fn detachListeners(window: *Window) void {
        const st = window.set_title.link.prev != null;
        const sa = window.set_app_id.link.prev != null;
        if (window.set_title.link.prev != null) window.set_title.link.remove();
        if (window.set_app_id.link.prev != null) window.set_app_id.link.remove();
        if (window.map.link.prev != null) window.map.link.remove();
        if (window.unmap.link.prev != null) window.unmap.link.remove();
        if (window.commit.link.prev != null) window.commit.link.remove();
        if (window.destroy.link.prev != null) window.destroy.link.remove();
        if (window.toplevel_destroy.link.prev != null) window.toplevel_destroy.link.remove();
        std.log.info("KidulWM: detachListeners id={d} set_title_attached={} app_id_attached={}", .{ window.id, st, sa });
    }

    /// wlroots 0.20 teardown order on client disconnect:
    ///   destroy_xdg_toplevel:
    ///     1. wlr_surface_unmap (may early-return if !mapped)
    ///     2. emit toplevel->events.destroy        <- we detach HERE
    ///     3. assert all toplevel listener lists empty
    ///   ... then destroy_xdg_surface:
    ///     4. emit surface->events.destroy          <- base destroy, too late
    /// We free the Window here because the toplevel pointer is about to be
    /// freed by wlroots; the base surface destroy that follows is a no-op for
    /// us once the Window is gone (we've already removed from the deck).
    fn handleToplevelDestroy(listener: *wl.Listener(void)) void {
        const window: *Window = @fieldParentPtr("toplevel_destroy", listener);
        std.log.info("KidulWM: toplevel destroy fired id={d}", .{window.id});
        if (window.server.kplay_window == window) {
            window.server.kplay_window = null;
        }
        if (window.server.focused_window == window) {
            window.server.clearFocus();
        }
        if (window.chrome_tree) |tree| {
            tree.node.destroy();
            window.chrome_tree = null;
        }
        // Destroy the scene tree so a crashed client doesn't leave an orphaned
        // node rendering its last buffer (the "ghost" seen on unpark).
        window.scene_tree.node.destroy();
        window.detachListeners();
        window.server.deckForWindow(window).removeWindow(window.id);
        // Guarded: classifyKplay already unlinked a kplay window from the
        // windows list; a second remove() would null-deref.
        if (window.link.prev != null) window.link.remove();
        window.server.allocator.destroy(window);
    }

    fn handleUnmap(listener: *wl.Listener(void)) void {
        const window: *Window = @fieldParentPtr("unmap", listener);
        std.log.info("KidulWM: window unmapped", .{});
        // Destroy the compositor-drawn chrome so the slide frame does not linger
        // on screen after the client surface disappears.
        if (window.chrome_tree) |tree| {
            tree.node.destroy();
            window.chrome_tree = null;
        }

        if (window.server.focused_window == window) {
            window.server.clearFocus();
        }
        // Listener detach + Window free happen in handleToplevelDestroy, which
        // fires before wlroots' teardown asserts. Do NOT detach here — unmap
        // can fire for transient reasons (minimize-style flows) and re-map later.
        window.server.requestLayout();
    }

    fn handleDestroy(listener: *wl.Listener(void)) void {
        // Base xdg_surface destroy — fires AFTER destroy_xdg_toplevel, by which
        // point the Window is already freed by handleToplevelDestroy. This
        // listener was detached in detachListeners before the free, so this
        // function should never actually be called; if it is, do nothing.
        _ = listener;
    }

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), surface: *wlr.Surface) void {
        const window: *Window = @fieldParentPtr("commit", listener);
        window.server.ft_commit += 1;
        // Per-client attribution: name the committer at idle (the "thick
        // tentacle" hunt). ft_commit alone is a global count and can't say
        // WHO keeps the render loop awake — this split does.
        const app = window.app_id.asSlice();
        if (appSliceContains(app, "ghostty")) {
            window.server.ft_commit_ghostty += 1;
        } else if (appSliceContains(app, "kplay")) {
            window.server.ft_commit_kplay += 1;
        } else {
            window.server.ft_commit_other += 1;
        }
        if (window.toplevel.base.initial_commit) {
            // Send the initial configure now that the XDG surface role is initialized.
            _ = window.toplevel.setSize(0, 0);
        }

        // If this window is focused, re-apply the slide scaling now that a buffer
        // has been committed. The first layout pass often runs before the client
        // has committed, so the scene buffer did not exist when applyLayout ran.
        if (window.server.focused_window == window) {
            const target = window.animation;
            std.log.debug("KidulWM: handleCommit focused id={d} target={d:.0}x{d:.0} buffer={d}x{d} geom={d}x{d}", .{ window.id, target.target_w, target.target_h, surface.current.width, surface.current.height, window.toplevel.base.geometry.width, window.toplevel.base.geometry.height });
            window.setSurfaceOffsetForFocus();
        }

        // Do not request a full layout pass here: map/unmap already trigger layout,
        // and running a full layout pass on every surface commit causes a
        // configure storm once multiple XDG toplevels are mapped.
        window.applyContainment();
    }
};
