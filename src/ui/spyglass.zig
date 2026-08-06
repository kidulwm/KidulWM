const std = @import("std");
const wlr = @import("wlroots");
const c = @import("dm").c;
const Style = @import("../core/style.zig").Style;
const DataBuffer = @import("../render/buffer.zig").DataBuffer;

/// Spyglass — whispy magnifying glass icons that sit near the bottom-left
/// and bottom-right edges of the screen.  Hover reveals the icon in the
/// focused border color; at rest it's a faint ghost in the unfocused color.
///
/// The spyglass is the "peek at the neighbor" affordance.  When the user
/// hovers an icon, the adjacent slide temporarily enables at a sliver
/// width so they can glance at what's there.  Click commits — the peeked
/// slide becomes the new focused slide.
///
/// Icons live in the overlay_tree so they render above client surfaces.

const icon_size: u32 = 32; // px square, unscaled
const margin_from_bottom: u32 = 200; // ~1/3 up from bottom on 1080p
const margin_from_edge: u32 = 24; // px from screen edge

pub const Side = enum { left, right };

pub const Spyglass = struct {
    allocator: std.mem.Allocator,
    overlay_tree: *wlr.SceneTree,
    style: Style,
    scale: u32,

    left: Icon,
    right: Icon,

    // Output dimensions, updated on layout.
    output_width: u32 = 0,
    output_height: u32 = 0,

    // Which sides have neighbors (slides to peek at).
    has_left: bool = false,
    has_right: bool = false,

    pub fn create(allocator: std.mem.Allocator, overlay_tree: *wlr.SceneTree, style: Style) !*Spyglass {
        const sg = try allocator.create(Spyglass);
        sg.* = .{
            .allocator = allocator,
            .overlay_tree = overlay_tree,
            .style = style,
            .scale = 1,
            .left = Icon.init(overlay_tree, .left),
            .right = Icon.init(overlay_tree, .right),
        };
        return sg;
    }

    pub fn destroy(self: *Spyglass) void {
        self.left.deinit();
        self.right.deinit();
        self.allocator.destroy(self);
    }

    pub fn updateOutput(self: *Spyglass, width: u32, height: u32, scale: u32) void {
        self.output_width = width;
        self.output_height = height;
        self.scale = scale;
        self.left.updateLayout(width, height, scale);
        self.right.updateLayout(width, height, scale);
    }

    pub fn setNeighbors(self: *Spyglass, has_left: bool, has_right: bool) void {
        self.has_left = has_left;
        self.has_right = has_right;
        self.left.setEnabled(has_left);
        self.right.setEnabled(has_right);
    }

    /// Handle pointer motion. Returns true if the spyglass consumed the event.
    pub fn handlePointerMove(self: *Spyglass, x: f64, y: f64) bool {
        var handled = false;
        if (self.has_left and self.left.contains(x, y)) {
            self.left.setHovered(true);
            handled = true;
        } else {
            self.left.setHovered(false);
        }
        if (self.has_right and self.right.contains(x, y)) {
            self.right.setHovered(true);
            handled = true;
        } else {
            self.right.setHovered(false);
        }
        return handled;
    }

    /// Handle pointer click. Returns the side that was clicked, or null.
    pub fn handlePointerClick(self: *Spyglass, x: f64, y: f64) ?Side {
        if (self.has_left and self.left.contains(x, y)) {
            return .left;
        }
        if (self.has_right and self.right.contains(x, y)) {
            return .right;
        }
        return null;
    }

    /// Returns true if either icon is currently hovered.
    pub fn isHovered(self: *const Spyglass) bool {
        return self.left.hovered or self.right.hovered;
    }
};

const Icon = struct {
    tree: ?*wlr.SceneTree,
    buffer: ?*wlr.SceneBuffer,
    side: Side,
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    scale: u32,
    hovered: bool,
    last_rendered_hovered: bool,
    last_rendered_scale: u32,

    fn init(overlay_tree: *wlr.SceneTree, side: Side) Icon {
        const tree = overlay_tree.createSceneTree() catch null;
        return .{
            .tree = tree,
            .buffer = null,
            .side = side,
            .x = 0,
            .y = 0,
            .width = icon_size,
            .height = icon_size,
            .scale = 1,
            .hovered = false,
            .last_rendered_hovered = false,
            .last_rendered_scale = 0,
        };
    }

    fn deinit(self: *Icon) void {
        if (self.tree) |tree| {
            tree.node.destroy();
            self.tree = null;
            self.buffer = null;
        }
    }

    fn updateLayout(self: *Icon, output_width: u32, output_height: u32, scale: u32) void {
        self.scale = scale;
        const s: i32 = @max(1, @as(i32, @intCast(scale)));
        const sz: i32 = @as(i32, @intCast(icon_size)) * s;

        self.x = switch (self.side) {
            .left => @as(i32, @intCast(margin_from_edge)) * s,
            .right => @as(i32, @intCast(output_width)) - sz - @as(i32, @intCast(margin_from_edge)) * s,
        };
        self.y = @as(i32, @intCast(output_height)) - sz - @as(i32, @intCast(margin_from_bottom)) * s;

        if (self.tree) |tree| {
            tree.node.setPosition(self.x, self.y);
        }
    }

    fn setEnabled(self: *Icon, enabled: bool) void {
        if (self.tree) |tree| {
            tree.node.setEnabled(enabled);
        }
    }

    fn setHovered(self: *Icon, hovered: bool) void {
        if (self.hovered == hovered) return;
        self.hovered = hovered;
        self.regenerate();
    }

    fn contains(self: *const Icon, px: f64, py: f64) bool {
        const sx: f64 = @floatFromInt(self.x);
        const sy: f64 = @floatFromInt(self.y);
        const sw: f64 = @floatFromInt(self.width * self.scale);
        const sh: f64 = @floatFromInt(self.height * self.scale);
        return px >= sx and px < sx + sw and py >= sy and py < sy + sh;
    }

    fn regenerate(self: *Icon) void {
        if (self.tree == null) return;
        const tree = self.tree.?;

        // Destroy old buffer if hover state or scale changed.
        if (self.buffer != null and (self.last_rendered_hovered != self.hovered or self.last_rendered_scale != self.scale)) {
            self.buffer.?.node.destroy();
            self.buffer = null;
        }
        if (self.buffer != null) return;

        const s: u32 = @max(1, self.scale);
        const px_w: i32 = @as(i32, @intCast(icon_size)) * @as(i32, @intCast(s));
        const px_h: i32 = px_w;

        const surface = paintSpyglass(self.hovered, s) orelse return;
        defer c.cairo_surface_destroy(surface);

        const stride = c.cairo_image_surface_get_stride(surface);
        const data = c.cairo_image_surface_get_data(surface);
        const bytes = @as([*]u8, @ptrCast(data))[0..@intCast(stride * px_h)];

        const buf = DataBuffer.create(bytes, px_w, px_h, stride) catch return;
        errdefer wlr.Buffer.drop(buf);

        const scene_buffer = tree.createSceneBuffer(buf) catch {
            wlr.Buffer.drop(buf);
            return;
        };
        wlr.Buffer.drop(buf);
        scene_buffer.setDestSize(icon_size, icon_size);
        self.buffer = scene_buffer;
        self.last_rendered_hovered = self.hovered;
        self.last_rendered_scale = self.scale;
    }
};

/// Draw a whispy magnifying glass icon.  At rest it's faint (25% opacity)
/// in the unfocused border color.  On hover it brightens to the focused
/// border color at 70% opacity.
fn paintSpyglass(hovered: bool, scale: u32) ?*c.cairo_surface_t {
    const s: i32 = @max(1, @as(i32, @intCast(scale)));
    const w: i32 = @as(i32, @intCast(icon_size)) * s;
    const h: i32 = w;
    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, w, h) orelse return null;
    const cr = c.cairo_create(surface) orelse {
        c.cairo_surface_destroy(surface);
        return null;
    };
    defer c.cairo_destroy(cr);

    const wf: f64 = @floatFromInt(w);
    const hf: f64 = @floatFromInt(h);

    // Transparent background.
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_paint(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    // Colors — whispy at rest, brighter on hover.
    const alpha: f64 = if (hovered) 0.70 else 0.25;
    const color = if (hovered) [_]f64{ 0.41, 0.40, 0.33 } else [_]f64{ 0.30, 0.29, 0.25 };

    c.cairo_set_source_rgba(cr, color[0], color[1], color[2], alpha);
    c.cairo_set_line_width(cr, 1.5 * @as(f64, @floatFromInt(s)));

    // Magnifying glass geometry — centered, slightly left of center.
    const cx: f64 = wf * 0.42;
    const cy: f64 = hf * 0.42;
    const radius: f64 = wf * 0.28;
    const handle_angle: f64 = std.math.pi / 4.0; // 45 degrees
    const handle_start_r: f64 = radius * 0.85;
    const handle_end_r: f64 = radius * 1.35;

    // Lens circle.
    c.cairo_arc(cr, cx, cy, radius, 0.0, 2.0 * std.math.pi);
    c.cairo_stroke(cr);

    // Handle — from bottom-right of lens outward at 45 degrees.
    const hx1 = cx + handle_start_r * @cos(handle_angle);
    const hy1 = cy + handle_start_r * @sin(handle_angle);
    const hx2 = cx + handle_end_r * @cos(handle_angle);
    const hy2 = cy + handle_end_r * @sin(handle_angle);
    c.cairo_set_line_width(cr, 2.0 * @as(f64, @floatFromInt(s)));
    c.cairo_move_to(cr, hx1, hy1);
    c.cairo_line_to(cr, hx2, hy2);
    c.cairo_stroke(cr);

    return surface;
}
