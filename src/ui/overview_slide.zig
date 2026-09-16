const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const cairo = @import("dm").c;
const Style = @import("../core/style.zig").Style;
const slidedeck = @import("../core/slidedeck.zig");
const overview_card = @import("../render/overview_card.zig");
const DataBuffer = @import("../render/buffer.zig").DataBuffer;

/// The overview slide: one compositor-owned scene tree per output,
/// holding (a) the Cairo card background and (b) each real slide's scene
/// tree REPARENTED inside at mini position. Lives at the after_last slot.
/// Open = the card exists and minis are reparented in; close = minis go
/// back to the scene root and the card tree is destroyed.
pub const OverviewSlide = struct {
    tree: ?*wlr.SceneTree = null,
    card_buffer: ?*wlr.SceneBuffer = null,
    tiles: [16]overview_card.Tile = undefined,
    tile_count: usize = 0,
    /// Saved parents for reparented slide trees, parallel to tiles.
    saved_parents: [16]?*wlr.SceneTree = .{ null } ** 16,
    /// Saved positions for restoring on close.
    saved_x: [16]i32 = .{ 0 } ** 16,
    saved_y: [16]i32 = .{ 0 } ** 16,
    saved_w: [16]i32 = .{ 0 } ** 16,
    saved_h: [16]i32 = .{ 0 } ** 16,
    saved_enabled: [16]bool = .{ false } ** 16,

    pub fn isOpen(self: *const OverviewSlide) bool {
        return self.tree != null;
    }
};
