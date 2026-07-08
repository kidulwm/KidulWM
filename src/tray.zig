const std = @import("std");
const wl = @import("wayland").server.wl;
const zwlr = @import("wayland").server.zwlr;
const wlr = @import("wlroots");

const Server = @import("server.zig").Server;

/// GTK4 settings tray protocol skeleton.
///
/// Owns the wlr_layer_shell_v1 global and creates scene layer surface nodes for
/// each client surface.  Arranges surfaces on output layout changes so exclusive
/// zones and anchors are applied.
pub const TrayManager = struct {
    server: *Server,
    layer_shell: *wlr.LayerShellV1,
    trees: LayerTrees,
    surfaces: std.ArrayList(*LayerSurfaceEntry),
    new_surface: wl.Listener(*wlr.LayerSurfaceV1),

    const LayerTrees = struct {
        background: *wlr.SceneTree,
        bottom: *wlr.SceneTree,
        top: *wlr.SceneTree,
        overlay: *wlr.SceneTree,

        fn forLayer(self: LayerTrees, layer: zwlr.LayerShellV1.Layer) *wlr.SceneTree {
            return switch (layer) {
                .background => self.background,
                .bottom => self.bottom,
                .top => self.top,
                .overlay => self.overlay,
                _ => self.bottom,
            };
        }
    };

    pub fn init(server: *Server, tray_out: *TrayManager) !void {
        const layer_shell = try wlr.LayerShellV1.create(server.wl_server, 5);

        // Separate scene trees for each layer so ordering is well-defined.
        const root = try server.scene.tree.createSceneTree();
        const trees = LayerTrees{
            .background = try root.createSceneTree(),
            .bottom = try root.createSceneTree(),
            .top = try root.createSceneTree(),
            .overlay = try root.createSceneTree(),
        };

        tray_out.* = TrayManager{
            .server = server,
            .layer_shell = layer_shell,
            .trees = trees,
            .surfaces = std.ArrayList(*LayerSurfaceEntry).empty,
            .new_surface = wl.Listener(*wlr.LayerSurfaceV1).init(handleNewSurface),
        };
        tray_out.new_surface.link.init();
        layer_shell.events.new_surface.add(&tray_out.new_surface);
    }

    pub fn deinit(self: *TrayManager) void {
        self.new_surface.link.remove();
        while (self.surfaces.items.len > 0) {
            const entry = self.surfaces.pop().?;
            entry.destroy.link.remove();
            entry.commit.link.remove();
            self.server.allocator.destroy(entry);
        }
        self.surfaces.deinit(self.server.allocator);
    }

    /// Recompute layer-surface geometry for every output.  For now we only have
    /// a single-output skeleton, but the loop is structured so multi-output is a
    /// small extension.
    pub fn arrange(self: *TrayManager) void {
        if (self.surfaces.items.len == 0) return;

        var it = self.server.output_layout.outputs.iterator(.forward);
        while (it.next()) |layout_output| {
            const output = layout_output.output;
            var full_area = wlr.Box{
                .x = layout_output.x,
                .y = layout_output.y,
                .width = output.width,
                .height = output.height,
            };
            var usable_area = full_area;

            for (self.surfaces.items) |entry| {
                if (entry.layer_surface.output) |ls_output| {
                    if (ls_output != output) continue;
                }
                entry.scene.configure(&full_area, &usable_area);
            }
        }
    }

    fn handleNewSurface(listener: *wl.Listener(*wlr.LayerSurfaceV1), layer_surface: *wlr.LayerSurfaceV1) void {
        const self: *TrayManager = @fieldParentPtr("new_surface", listener);
        std.log.info("KidulWM: new layer surface raw", .{});

        std.log.info("KidulWM: new layer surface namespace={s} layer={}", .{
            layer_surface.namespace,
            @intFromEnum(layer_surface.pending.layer),
        });

        const parent_tree = self.trees.forLayer(layer_surface.pending.layer);
        std.log.info("KidulWM: selected parent tree", .{});
        const scene = parent_tree.createSceneLayerSurfaceV1(layer_surface) catch |err| {
            std.log.err("failed to create scene layer surface: {}", .{err});
            return;
        };
        std.log.info("KidulWM: scene layer surface created", .{});

        const entry = self.server.allocator.create(LayerSurfaceEntry) catch |err| {
            std.log.err("failed to allocate layer surface entry: {}", .{err});
            return;
        };
        entry.* = .{
            .manager = self,
            .layer_surface = layer_surface,
            .scene = scene,
            .destroy = wl.Listener(*wlr.LayerSurfaceV1).init(handleDestroy),
            .commit = wl.Listener(*wlr.Surface).init(handleCommit),
        };
        entry.destroy.link.init();
        entry.commit.link.init();
        layer_surface.events.destroy.add(&entry.destroy);
        layer_surface.surface.events.commit.add(&entry.commit);

        self.surfaces.append(self.server.allocator, entry) catch |err| {
            std.log.err("failed to track layer surface: {}", .{err});
            entry.destroy.link.remove();
            entry.commit.link.remove();
            self.server.allocator.destroy(entry);
            return;
        };

        // Do not arrange here; the layer surface must commit and become
        // initialized before any configure calls are allowed.
        if (layer_surface.initialized) {
            self.arrange();
        }
    }

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), surface: *wlr.Surface) void {
        _ = surface;
        const entry: *LayerSurfaceEntry = @fieldParentPtr("commit", listener);
        if (entry.layer_surface.initialized) {
            entry.manager.arrange();
        }
    }

    fn handleDestroy(listener: *wl.Listener(*wlr.LayerSurfaceV1), layer_surface: *wlr.LayerSurfaceV1) void {
        _ = layer_surface;
        const entry: *LayerSurfaceEntry = @fieldParentPtr("destroy", listener);
        const manager = entry.manager;
        for (manager.surfaces.items, 0..) |e, i| {
            if (e == entry) {
                _ = manager.surfaces.swapRemove(i);
                break;
            }
        }
        entry.destroy.link.remove();
        entry.commit.link.remove();
        manager.server.allocator.destroy(entry);
    }
};

const LayerSurfaceEntry = struct {
    manager: *TrayManager,
    layer_surface: *wlr.LayerSurfaceV1,
    scene: *wlr.SceneLayerSurfaceV1,
    destroy: wl.Listener(*wlr.LayerSurfaceV1),
    commit: wl.Listener(*wlr.Surface),
};

const kidul = @import("wayland").server.kidul;

/// GTK4 settings tray global binder.
///
/// Advertises `kidul_settings_tray_v1` so a dedicated GTK4 settings client can
/// detect the compositor and create a panel surface.  The implementation is
/// intentionally a stub: it binds and logs, deferring real surface plumbing to
/// a later pass.
pub const SettingsTray = struct {
    server: *Server,
    global: *wl.Global,

    const Binding = struct {
        fn bind(client: *wl.Client, data: *SettingsTray, version: u32, id: u32) void {
            _ = wl.Resource.create(client, kidul.SettingsTrayV1, version, id) catch |err| {
                std.log.err("failed to create kidul_settings_tray_v1 resource: {}", .{err});
                client.postNoMemory();
                return;
            };
            std.log.info("KidulWM: kidul_settings_tray_v1 bound by client pid={d}", .{client.getFd()});
            _ = data;
        }
    };

    pub fn init(server: *Server, tray_out: *SettingsTray) !void {
        tray_out.* = .{
            .server = server,
            .global = try wl.Global.create(
                server.wl_server,
                kidul.SettingsTrayV1,
                1,
                *SettingsTray,
                tray_out,
                Binding.bind,
            ),
        };
    }

    pub fn deinit(self: *SettingsTray) void {
        self.global.destroy();
    }
};
