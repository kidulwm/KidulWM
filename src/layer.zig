// SPDX-License-Identifier: GPL-3.0-or-later
// Layer-shell (zwlr_layer_shell_v1) support — the proper fix for slurp and
// any future layer client. Design constraints from
// references/layer-shell-crash-notes.md:
//   - Heap-allocate, add listeners only after the address is final.
//   - Never configure before layer_surface.initialized; gate on commit.
//   - Remove every listener in the destroy path.
// Slurp's shape: overlay layer, full-output anchor, exclusive_zone -1,
// keyboard_interactive exclusive — handled by scene configure + seat focus.

const std = @import("std");
const wlr = @import("wlroots");
const wayland = @import("wayland");
const wl = wayland.server.wl;

const server_mod = @import("server.zig");
const Server = server_mod.Server;

pub const LayerSurface = struct {
    server: *Server,
    layer_surface: *wlr.LayerSurfaceV1,
    scene_layer_surface: ?*wlr.SceneLayerSurfaceV1 = null,
    output: ?*server_mod.Output = null,
    link: wl.list.Link,
    mapped_logged: bool = false,

    commit: wl.Listener(*wlr.Surface),
    destroy: wl.Listener(*wlr.LayerSurfaceV1),
    new_popup: wl.Listener(*wlr.XdgPopup),

    pub fn create(server: *Server, layer_surface: *wlr.LayerSurfaceV1) !*LayerSurface {
        const self = try server.allocator.create(LayerSurface);
        self.* = .{
            .server = server,
            .layer_surface = layer_surface,
            .link = undefined,
            .commit = wl.Listener(*wlr.Surface).init(handleCommit),
            .destroy = wl.Listener(*wlr.LayerSurfaceV1).init(handleDestroy),
            .new_popup = wl.Listener(*wlr.XdgPopup).init(handleNewPopup),
        };
        // Address is final now — safe to add listeners.
        self.commit.link.init();
        self.destroy.link.init();
        self.new_popup.link.init();
        layer_surface.surface.events.commit.add(&self.commit);
        layer_surface.events.destroy.add(&self.destroy);
        layer_surface.events.new_popup.add(&self.new_popup);
        layer_surface.data = self;
        self.link.init();
        server.layer_surfaces.append(self);
        return self;
    }

    fn parentTree(self: *LayerSurface) *wlr.SceneTree {
        // Per-stratum trees live on the Server (created at init, before
        // overlay_tree so widgets/peeks stay above every layer client).
        return switch (self.layer_surface.current.layer) {
            .background => self.server.layer_trees[0],
            .bottom => self.server.layer_trees[1],
            .top => self.server.layer_trees[2],
            .overlay => self.server.layer_trees[3],
            _ => self.server.layer_trees[2],
        };
    }

    fn resolveOutput(self: *LayerSurface) void {
        const wlr_output = self.layer_surface.output orelse {
            // Client left output null: use the focused output, else the first.
            if (self.server.focused_output) |o| {
                self.output = o;
            } else {
                var it = self.server.outputs.iterator(.forward);
                self.output = it.next();
            }
            if (self.output) |o| self.layer_surface.output = o.wlr_output;
            return;
        };
        var it = self.server.outputs.iterator(.forward);
        while (it.next()) |o| {
            if (o.wlr_output == wlr_output) {
                self.output = o;
                return;
            }
        }
    }

    fn arrange(self: *LayerSurface) void {
        const output = self.output orelse return;
        const ls = self.layer_surface;
        if (!ls.initialized) return;

        if (self.scene_layer_surface == null) {
            self.scene_layer_surface = self.parentTree().createSceneLayerSurfaceV1(ls) catch |err| {
                std.log.err("KidulWM: layer surface scene create failed: {}", .{err});
                return;
            };
        }

        var box: wlr.Box = undefined;
        self.server.output_layout.getBox(output.wlr_output, &box);
        var usable = box;
        // wlroots computes anchor/margin/exclusive-zone geometry and sends
        // the configure for us; full_area is the output's layout box.
        self.scene_layer_surface.?.configure(&box, &usable);

        if (ls.current.keyboard_interactive == .exclusive and ls.surface.mapped) {
            self.grabKeyboard();
        }
    }

    fn grabKeyboard(self: *LayerSurface) void {
        const surface = self.layer_surface.surface;
        const seat = self.server.seat;
        if (seat.keyboard_state.focused_surface == surface) return;
        std.log.info("KidulWM: layer surface keyboard grab ns={s}", .{self.layer_surface.namespace});
        // modifiers=null: wlroots sends keymap FIRST then derives the
        // modifiers event from the keyboard's own state. Passing
        // &keyboard.modifiers raced the keymap event and segfaulted slurp
        // in xkb_state_update_mask (null client xkb_state).
        // No keyboard on the seat (headless, no input devices): skip the
        // grab entirely — notifying enter with no keyboard sends the client
        // an enter+modifiers with no keymap, and slurp dereferences its
        // null xkb_state (xkb_state_update_mask SIGSEGV).
        const keyboard = seat.getKeyboard() orelse return;
        var keycodes: [32]u32 = undefined;
        const pressed = keyboard.keycodes[0..@min(keycodes.len, keyboard.num_keycodes)];
        @memcpy(keycodes[0..pressed.len], pressed);
        seat.keyboardNotifyEnter(surface, keycodes[0..pressed.len], null);
    }

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), surface: *wlr.Surface) void {
        const self: *LayerSurface = @fieldParentPtr("commit", listener);
        _ = surface;
        const ls = self.layer_surface;
        // Crash-notes law: no configure before initialized.
        if (!ls.initialized) return;
        if (self.output == null) self.resolveOutput();
        if (ls.output == null) {
            std.log.warn("KidulWM: layer surface has no output; destroying (protocol)", .{});
            ls.destroy();
            return;
        }
        self.arrange();
        if (ls.surface.mapped and !self.mapped_logged) {
            self.mapped_logged = true;
            std.log.info("KidulWM: layer surface mapped ns={s} layer={s} {d}x{d}", .{
                ls.namespace,
                @tagName(ls.current.layer),
                ls.current.actual_width,
                ls.current.actual_height,
            });
        }
        // Keyboard interactivity can change per-commit; re-check.
        if (ls.surface.mapped and ls.current.keyboard_interactive == .exclusive) {
            self.grabKeyboard();
        }
    }

    fn handleDestroy(listener: *wl.Listener(*wlr.LayerSurfaceV1), layer_surface: *wlr.LayerSurfaceV1) void {
        const self: *LayerSurface = @fieldParentPtr("destroy", listener);
        std.log.info("KidulWM: layer surface destroy ns={s}", .{layer_surface.namespace});
        self.commit.link.remove();
        self.destroy.link.remove();
        self.new_popup.link.remove();
        self.link.remove();
        // The scene node is destroyed by wlroots (its own destroy listener);
        // drop our pointer so nothing touches freed memory.
        self.scene_layer_surface = null;
        // Hand keyboard focus back to the deck if we held it.
        if (self.server.seat.keyboard_state.focused_surface == layer_surface.surface) {
            self.server.seat.keyboardNotifyClearFocus();
            if (self.server.focused_window) |win| {
                self.server.focusWindow(win);
            }
        }
        self.server.allocator.destroy(self);
    }

    fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), popup: *wlr.XdgPopup) void {
        const self: *LayerSurface = @fieldParentPtr("new_popup", listener);
        _ = self;
        // wlroots' scene layer-surface tracks popups itself once the popup's
        // parent is set by the client; nothing to position manually here.
        _ = popup;
    }
};
