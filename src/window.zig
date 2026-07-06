const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const Server = @import("server.zig").Server;

pub const Window = struct {
    server: *Server,
    toplevel: *wlr.XdgToplevel,
    scene_tree: *wlr.SceneTree,

    link: wl.list.Link,

    map: wl.Listener(void),
    unmap: wl.Listener(void),
    destroy: wl.Listener(void),
    commit: wl.Listener(*wlr.Surface),

    pub fn create(server: *Server, toplevel: *wlr.XdgToplevel) !*Window {
        const window = try server.allocator.create(Window);
        errdefer server.allocator.destroy(window);

        const scene_tree = try server.scene.tree.createSceneXdgSurface(toplevel.base);

        window.* = .{
            .server = server,
            .toplevel = toplevel,
            .scene_tree = scene_tree,
            .link = undefined,
            .map = wl.Listener(void).init(handleMap),
            .unmap = wl.Listener(void).init(handleUnmap),
            .destroy = wl.Listener(void).init(handleDestroy),
            .commit = wl.Listener(*wlr.Surface).init(handleCommit),
        };

        toplevel.base.surface.events.map.add(&window.map);
        toplevel.base.surface.events.unmap.add(&window.unmap);
        toplevel.base.events.destroy.add(&window.destroy);
        toplevel.base.surface.events.commit.add(&window.commit);

        return window;
    }

    pub fn focus(self: *Window, seat: *wlr.Seat) void {
        const surface = self.toplevel.base.surface;
        if (seat.getKeyboard()) |keyboard| {
            const keycodes: []const u32 = keyboard.keycodes[0..keyboard.num_keycodes];
            seat.keyboardNotifyEnter(surface, keycodes, &keyboard.modifiers);
        } else {
            seat.keyboardNotifyEnter(surface, &.{}, null);
        }
        std.log.info("KidulWM: focused window", .{});
    }

    fn handleMap(listener: *wl.Listener(void)) void {
        const window: *Window = @fieldParentPtr("map", listener);
        std.log.info("KidulWM: window mapped", .{});
        window.server.requestLayout();
    }

    fn handleUnmap(listener: *wl.Listener(void)) void {
        const window: *Window = @fieldParentPtr("unmap", listener);
        std.log.info("KidulWM: window unmapped", .{});
        window.server.requestLayout();
    }

    fn handleDestroy(listener: *wl.Listener(void)) void {
        const window: *Window = @fieldParentPtr("destroy", listener);
        std.log.info("KidulWM: window destroyed", .{});

        window.map.link.remove();
        window.unmap.link.remove();
        window.commit.link.remove();
        window.destroy.link.remove();
        window.link.remove();

        window.server.allocator.destroy(window);
    }

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), surface: *wlr.Surface) void {
        const window: *Window = @fieldParentPtr("commit", listener);
        _ = surface;
        _ = window;
    }
};
