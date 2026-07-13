const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const Server = @import("server.zig").Server;
const Output = @import("server.zig").Output;
const animation = @import("core/animation.zig");
const c = @import("dm/c.zig").c;
const chrome_renderer = @import("render/chrome.zig");
const DataBuffer = @import("render/buffer.zig").DataBuffer;
const Style = @import("core/style.zig").Style;

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

    map: wl.Listener(void),
    unmap: wl.Listener(void),
    destroy: wl.Listener(void),
    commit: wl.Listener(*wlr.Surface),

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
            .map = wl.Listener(void).init(handleMap),
            .unmap = wl.Listener(void).init(handleUnmap),
            .destroy = wl.Listener(void).init(handleDestroy),
            .commit = wl.Listener(*wlr.Surface).init(handleCommit),
        };

        window.map.link.init();
        window.unmap.link.init();
        window.destroy.link.init();
        window.commit.link.init();
        window.link.init();

        toplevel.base.surface.events.map.add(&window.map);
        toplevel.base.surface.events.unmap.add(&window.unmap);
        toplevel.base.events.destroy.add(&window.destroy);
        toplevel.base.surface.events.commit.add(&window.commit);

        return window;
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

        // Reset the destination size to the natural buffer size so a window
        // that was previously focused (and scaled) returns to full resolution
        // when it becomes a peek.
        self.setSurfaceDestSize(@intCast(surface.current.width), @intCast(surface.current.height));

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

        std.log.info("KidulWM peek offset window={d} edges={s} buf={d}x{d} geom={d},{d} {d}x{d} target_w={d} offset={d},{d}", .{
            self.id,
            if (edges.left) "left" else "right",
            surface.current.width,
            surface.current.height,
            geom.x,
            geom.y,
            geom.width,
            geom.height,
            target_w,
            x,
            y,
        });

        self.setSurfaceOffset(x, y);
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

        const tree = self.scene_tree.createSceneTree() catch return;
        self.chrome_tree = tree;
        self.chrome_width = w;
        self.chrome_height = h;
        self.chrome_focused = focused;
        self.chrome_edges = edges;
        self.chrome_scale = scale;
        self.chrome_style_generation = style_gen;

        const style = self.server.theme;
        const surface = chrome_renderer.renderChrome(style, w, h, focused, scale, edges) orelse {
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
        // The scene buffer took a reference; drop ours so it owns the only one.
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
        // wlroots emits the destroy signal while the surface and its signals still
        // exist, so it is safe and required to remove our listeners now.
        window.map.link.remove();
        window.unmap.link.remove();
        window.commit.link.remove();
        // Remove the destroy listener itself from the signal currently emitting us.
        window.destroy.link.remove();
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
