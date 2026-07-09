const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const Server = @import("server.zig").Server;
const Output = @import("server.zig").Output;
const animation = @import("core/animation.zig");

pub const Window = struct {
    server: *Server,
    toplevel: *wlr.XdgToplevel,
    scene_tree: *wlr.SceneTree,

    output: ?*Output,
    id: u32,
    link: wl.list.Link,

    animation: animation.WindowAnimation,

    dim_rect: ?*wlr.SceneRect,
    dim_color: [4]f32,

    map: wl.Listener(void),
    unmap: wl.Listener(void),
    destroy: wl.Listener(void),
    commit: wl.Listener(*wlr.Surface),

    pub fn create(server: *Server, toplevel: *wlr.XdgToplevel) !*Window {
        const window = try server.allocator.create(Window);
        errdefer server.allocator.destroy(window);

        const scene_tree = try server.scene.tree.createSceneXdgSurface(toplevel.base);

        const id = server.next_window_id;
        server.next_window_id += 1;

        window.* = .{
            .server = server,
            .toplevel = toplevel,
            .scene_tree = scene_tree,
            .output = null,
            .id = id,
            .link = undefined,
            .animation = .{},
            .dim_rect = null,
            .dim_color = .{ 0.0, 0.0, 0.0, 0.18 },
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

    /// Set the animated layout target. On the first assignment, snap current
    /// geometry to the target so windows do not fly in from arbitrary origins.
    pub fn setLayoutTarget(self: *Window, x: i32, y: i32, w: u32, h: u32) void {
        const target = self.animation;
        const first = (target.target_w == 0 and target.target_h == 0);
        if (first) {
            self.animation.last_us = animation.nowUs();
        }
        self.animation.target_x = @floatFromInt(x);
        self.animation.target_y = @floatFromInt(y);
        self.animation.target_w = @floatFromInt(w);
        self.animation.target_h = @floatFromInt(h);
        if (first) {
            self.animation.cur_x = self.animation.target_x;
            self.animation.cur_y = self.animation.target_y;
            self.animation.cur_w = self.animation.target_w;
            self.animation.cur_h = self.animation.target_h;
            self.scene_tree.node.setPosition(x, y);
        }
    }

    /// Advance the animation by one frame and apply it to the scene node.
    pub fn tickAnimation(self: *Window, now_us: animation.TimeUs) bool {
        if (!self.toplevel.base.surface.mapped) return false;
        if (self.animation.tick(now_us)) {
            self.scene_tree.node.setPosition(
                @intFromFloat(self.animation.cur_x),
                @intFromFloat(self.animation.cur_y),
            );
            return true;
        }
        return false;
    }

    /// Dim or undim the window overlay depending on focus.
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
    }
};
