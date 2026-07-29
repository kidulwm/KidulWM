const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const Server = @import("server.zig").Server;
const Output = @import("server.zig").Output;
const animation = @import("core/animation.zig");
const c = @import("dm").c;
const chrome_renderer = @import("render/chrome.zig");
const DataBuffer = @import("render/buffer.zig").DataBuffer;
const Style = @import("core/style.zig").Style;

const Label = struct {
    buf: [64]u8 = undefined,
    len: u8 = 0,

    fn asSlice(self: *const Label) []const u8 {
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

    output: ?*Output,
    id: u32,
    link: wl.list.Link,

    animation: animation.WindowAnimation,

    dim_rect: ?*wlr.SceneRect,
    dim_color: [4]f32,

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
            .dim_rect = null,
            .dim_color = .{ 0.0, 0.0, 0.0, 0.0 },
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
            .commit = wl.Listener(*wlr.Surface).init(handleCommit),
            .set_title = wl.Listener(void).init(handleSetTitle),
            .set_app_id = wl.Listener(void).init(handleSetAppId),
        };

        window.map.link.init();
        window.unmap.link.init();
        window.destroy.link.init();
        window.commit.link.init();
        window.set_title.link.init();
        window.set_app_id.link.init();
        window.link.init();

        toplevel.base.surface.events.map.add(&window.map);
        toplevel.base.surface.events.unmap.add(&window.unmap);
        toplevel.base.events.destroy.add(&window.destroy);
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
            // Chrome follows scene_tree automatically.
            self.updateChrome(self.chrome_focused, self.chrome_edges);
        } else {
            // Transition finished; reset so future layouts snap.
            self.animation.last_us = 0;
            self.animation.start_us = 0;
        }
        return moved;
    }

    /// Dim or undim the window overlay depending on focus. The overlay size
    /// follows the surface buffer so rounded corners and client-side shading
    /// stay intact.
    pub fn updateDim(self: *Window, focused: bool) void {
        const surface = self.toplevel.base.surface;
        if (!surface.mapped) return;
        const w: i32 = @intCast(surface.current.width);
        const h: i32 = @intCast(surface.current.height);
        if (w <= 0 or h <= 0) return;

        if (focused) {
            if (self.dim_rect) |rect| {
                rect.setSize(0, 0);
            }
            return;
        }

        if (self.dim_rect == null) {
            self.dim_rect = self.scene_tree.createSceneRect(w, h, &self.dim_color) catch return;
        } else if (self.dim_rect) |rect| {
            rect.setSize(w, h);
            rect.setColor(&self.dim_color);
        }
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
        self.surface_tree.node.setPosition(x, y);
    }

    /// Set the internal surface offset for a peek window so the visible sliver
    /// shows the correct edge of the surface content. The XDG scene tree already
    /// accounts for geometry.x/y internally, so we only need to align the
    /// content area (geom.width x geom.height) to the wrapper.
    pub fn setSurfaceOffsetForPeek(self: *Window, edges: chrome_renderer.EdgeMode) void {
        const surface = self.toplevel.base.surface;
        if (!surface.mapped) return;

        const geom = self.toplevel.base.geometry;
        const target_w: i32 = @intFromFloat(self.animation.target_w);

        // Position the XDG geometry top-left within the wrapper. The scene tree
        // will render the actual buffer with its own geometry offset, so content
        // (not CSD shadow) starts at this position.
        //
        // The visible sliver is the on-screen portion of the wrapper:
        //   - A left peek is visible along the left edge of the wrapper, so show
        //     the leftmost content pixels (x = 0).
        //   - A right peek is visible along the right edge of the wrapper, so show
        //     the rightmost content pixels (x = target_w - geom.width).
        var x: i32 = 0;
        if (edges.left) {
            x = 0;
        } else {
            x = target_w - geom.width;
        }
        const y: i32 = 0;

        self.setSurfaceOffset(x, y);
    }

    /// Focused window: scale and offset the surface so its content geometry
    /// exactly fills the wrapper. CSD shadows/padding are pushed under the
    /// chrome border ring, eliminating the inner gap.
    pub fn setSurfaceOffsetForFocus(self: *Window) void {
        const surface = self.toplevel.base.surface;
        if (!surface.mapped) return;

        const geom = self.toplevel.base.geometry;
        const target_w: f64 = self.animation.target_w;
        const target_h: f64 = self.animation.target_h;

        // Avoid division by zero: if geometry reports zero, fall back to no-op.
        if (geom.width <= 0 or geom.height <= 0) return;

        // Buffer size (full client buffer including CSD padding).
        const buf_w: f64 = @floatFromInt(surface.current.width);
        const buf_h: f64 = @floatFromInt(surface.current.height);

        // Scale so the content area maps to the wrapper.
        const sx = target_w / @as(f64, @floatFromInt(geom.width));
        const sy = target_h / @as(f64, @floatFromInt(geom.height));

        const dest_w: i32 = @intFromFloat(@round(buf_w * sx));
        const dest_h: i32 = @intFromFloat(@round(buf_h * sy));

        const off_x: i32 = @intFromFloat(@round(-@as(f64, @floatFromInt(geom.x)) * sx));
        const off_y: i32 = @intFromFloat(@round(-@as(f64, @floatFromInt(geom.y)) * sy));

        self.setSurfaceDestSize(dest_w, dest_h);
        self.setSurfaceOffset(off_x, off_y);
    }

    /// Regenerate the compositor-drawn chrome overlay for this window.
    /// The overlay follows the layout target size and focus state, ensuring
    /// KidulWM owns the signature corner look regardless of client CSD.
    pub fn updateChrome(self: *Window, focused: bool, edges: chrome_renderer.EdgeMode) void {
        const w: i32 = @intFromFloat(@round(self.animation.cur_w));
        const h: i32 = @intFromFloat(@round(self.animation.cur_h));
        if (w <= 0 or h <= 0) return;

        // Pick output scale from the output this window is on.
        var scale: u32 = 1;
        if (self.output) |output| {
            scale = @intFromFloat(@max(1.0, output.wlr_output.scale));
        }

        const style_gen = self.server.chrome_style_generation;
        const label = if (edges.eql(chrome_renderer.EdgeMode.all)) null else self.chrome_label.asSlice();
        const same = self.chrome_tree != null and
            self.chrome_width == w and
            self.chrome_height == h and
            self.chrome_focused == focused and
            self.chrome_edges.eql(edges) and
            self.chrome_scale == scale and
            self.chrome_style_generation == style_gen and
            std.mem.eql(u8, self.chrome_label.asSlice(), if (label) |l| l else "");
        if (same) return;

        if (self.chrome_tree) |tree| {
            tree.node.destroy();
            self.chrome_tree = null;
        }

        // Put the chrome inside the window's own scene tree so it always stays
        // in front of the client surface. The chrome is translated by the
        // wrapper tree, so it is positioned at (0, 0) inside it.
        const tree = self.scene_tree.createSceneTree() catch return;
        tree.node.setPosition(0, 0);
        // Raise above the surface tree so rounded-corner and border drawing hide
        // any client pixels that extend past the chrome shape.
        tree.node.raiseToTop();
        self.chrome_tree = tree;
        self.chrome_width = w;
        self.chrome_height = h;
        self.chrome_focused = focused;
        self.chrome_edges = edges;
        self.chrome_scale = scale;
        self.chrome_style_generation = style_gen;

        // Clip the client surface to the full window bounds. The chrome overlay
        // already masks the border/corner ring, so the surface does not need to
        // be inset by the border width here.
        self.surface_tree.node.subsurfaceTreeSetClip(&wlr.Box{
            .x = 0,
            .y = 0,
            .width = w,
            .height = h,
        });

        const style = self.server.theme;
        const surface = chrome_renderer.renderChrome(style, w, h, focused, scale, edges, label) orelse {
            tree.node.destroy();
            self.chrome_tree = null;
            return;
        };
        defer c.cairo_surface_destroy(surface);
        const pixels = chrome_renderer.surfacePixels(surface);

        const buffer = DataBuffer.create(pixels.pixels, pixels.width, pixels.height, pixels.stride) catch {
            tree.node.destroy();
            self.chrome_tree = null;
            return;
        };

        const scene_buffer = tree.createSceneBuffer(buffer) catch {
            wlr.Buffer.drop(buffer);
            tree.node.destroy();
            self.chrome_tree = null;
            return;
        };
        wlr.Buffer.drop(buffer);
        scene_buffer.setDestSize(w, h);
    }

    fn handleMap(listener: *wl.Listener(void)) void {
        const window: *Window = @fieldParentPtr("map", listener);
        std.log.info("KidulWM: window mapped", .{});
        window.server.assignOutput(window);
        window.server.deckForWindow(window).addWindow(window.id);
        window.server.focusWindow(window);
        if (window.output) |output| window.server.focused_output = output;
        window.server.requestLayout();
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

        // Also destroy any dim overlay left behind.
        if (window.dim_rect) |rect| {
            rect.node.destroy();
            window.dim_rect = null;
        }
        if (window.server.focused_window == window) {
            window.server.clearFocus();
        }
        window.server.requestLayout();
    }

    fn handleDestroy(listener: *wl.Listener(void)) void {
        const window: *Window = @fieldParentPtr("destroy", listener);
        std.log.info("KidulWM: window destroyed", .{});
        if (window.server.focused_window == window) {
            window.server.clearFocus();
        }
        // Remove all listeners. wlroots asserts that toplevel signal lists are
        // empty before freeing the object, so leaving set_title/set_app_id
        // attached triggers an assertion.
        window.destroy.link.remove();
        window.set_title.link.remove();
        window.set_app_id.link.remove();
        window.map.link.remove();
        window.unmap.link.remove();
        window.commit.link.remove();
        window.server.deckForWindow(window).removeWindow(window.id);
        window.link.remove();
        window.server.allocator.destroy(window);
    }

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), surface: *wlr.Surface) void {
        const window: *Window = @fieldParentPtr("commit", listener);
        _ = surface;
        if (window.toplevel.base.initial_commit) {
            // Send the initial configure now that the XDG surface role is initialized.
            _ = window.toplevel.setSize(0, 0);
        }

        // Do not request a layout pass here: map/unmap already trigger layout,
        // and running a full layout pass on every surface commit causes a
        // configure storm once multiple XDG toplevels are mapped.
        //
        // However, when this window is a side peek, the surface buffer may have
        // been committed/resized after the layout ran. Re-apply the peek offset
        // so the visible sliver stays aligned to the correct edge of the buffer.
        if (!window.chrome_edges.eql(chrome_renderer.EdgeMode.all)) {
            window.setSurfaceOffsetForPeek(window.chrome_edges);
        }
    }
};
