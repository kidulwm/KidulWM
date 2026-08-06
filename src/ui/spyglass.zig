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

const icon_size: u32 = 20; // px tall, unscaled
const icon_w: u32 = 72; // px wide for EXIT-style icons
const margin_from_bottom: u32 = 0; // 0 = vertically centered
const margin_from_edge: u32 = 17; // px from screen edge

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
        const left_changed = self.has_left != has_left;
        const right_changed = self.has_right != has_right;
        self.has_left = has_left;
        self.has_right = has_right;
        self.left.setEnabled(has_left);
        self.right.setEnabled(has_right);
        // Render icons when they become visible.
        if (left_changed and has_left) self.left.regenerate();
        if (right_changed and has_right) self.right.regenerate();
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
        const use_w: i32 = if (active_style == .exit_dots) @as(i32, @intCast(icon_w)) else @as(i32, @intCast(icon_size));
        const sz_w: i32 = use_w * s;
        const sz_h: i32 = @as(i32, @intCast(icon_size)) * s;

        self.x = switch (self.side) {
            .left => @as(i32, @intCast(margin_from_edge)) * s,
            .right => @as(i32, @intCast(output_width)) - sz_w - @as(i32, @intCast(margin_from_edge)) * s,
        };
        // Vertically center when margin_from_bottom == 0, otherwise offset up.
        if (margin_from_bottom == 0) {
            self.y = @divFloor(@as(i32, @intCast(output_height)) - sz_h, 2);
        } else {
            self.y = @as(i32, @intCast(output_height)) - sz_h - @as(i32, @intCast(margin_from_bottom)) * s;
        }

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
        const use_w: u32 = if (active_style == .exit_dots) icon_w else icon_size;
        const sx: f64 = @floatFromInt(self.x);
        const sy: f64 = @floatFromInt(self.y);
        const sw: f64 = @floatFromInt(use_w * self.scale);
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
        const use_w: i32 = if (active_style == .exit_dots) @as(i32, @intCast(icon_w)) else @as(i32, @intCast(icon_size));
        const px_w: i32 = use_w * @as(i32, @intCast(s));
        const px_h: i32 = @as(i32, @intCast(icon_size)) * @as(i32, @intCast(s));

        const surface = paintSpyglass(self.hovered, s, self.side) orelse return;
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
        const dest_w: i32 = if (active_style == .exit_dots) @as(i32, @intCast(icon_w)) else @as(i32, @intCast(icon_size));
        scene_buffer.setDestSize(dest_w, @as(i32, @intCast(icon_size)));
        self.buffer = scene_buffer;
        self.last_rendered_hovered = self.hovered;
        self.last_rendered_scale = self.scale;
    }
};

/// Paint a peek icon. Four styles available — set ICON_STYLE to test each one.
/// 0 = silk wisp, 1 = crescent sliver, 2 = curved arrow, 3 = spotlight beam.
/// At rest: faint (35%) in unfocused border color.  On hover: bright (70%)
/// in focused border color.
const IconStyle = enum { silk_wisp, crescent_sliver, curved_arrow, spotlight_beam, straight_arrow, exit_dots };
const active_style: IconStyle = .exit_dots;

fn paintSpyglass(hovered: bool, scale: u32, side: Side) ?*c.cairo_surface_t {
    const s: i32 = @max(1, @as(i32, @intCast(scale)));
    const use_w: i32 = if (active_style == .exit_dots) @as(i32, @intCast(icon_w)) else @as(i32, @intCast(icon_size));
    const w: i32 = use_w * s;
    const h: i32 = @as(i32, @intCast(icon_size)) * s;
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
    const alpha: f64 = if (hovered) 0.70 else 0.54;
    const color = if (hovered) [_]f64{ 0.41, 0.40, 0.33 } else [_]f64{ 0.30, 0.29, 0.25 };

    c.cairo_set_source_rgba(cr, color[0], color[1], color[2], alpha);

    const sw: f64 = @as(f64, @floatFromInt(s));

    switch (active_style) {
        .silk_wisp => paintSilkWisp(cr, wf, hf, sw),
        .crescent_sliver => paintCrescentSliver(cr, wf, hf, sw),
        .curved_arrow => paintCurvedArrow(cr, wf, hf, sw),
        .spotlight_beam => paintSpotlightBeam(cr, wf, hf, sw),
        .straight_arrow => paintStraightArrow(cr, wf, hf, sw, side),
        .exit_dots => paintExitDots(cr, wf, hf, sw),
    }

    return surface;
}

/// Silk wisp — a single calligraphic brush stroke curving toward the edge.
/// Like a wisp of smoke or silk thread. No arrowhead, just the curve.
fn paintSilkWisp(cr: *c.cairo_t, w: f64, h: f64, s: f64) void {
    c.cairo_set_line_width(cr, 3.0 * s);
    c.cairo_set_line_cap(cr, c.CAIRO_LINE_CAP_ROUND);

    // A single S-curve flowing from top to bottom, curving toward center.
    const cx: f64 = w * 0.5;
    const top_y: f64 = h * 0.15;
    const bot_y: f64 = h * 0.85;
    const curve_offset: f64 = w * 0.20;

    c.cairo_move_to(cr, cx, top_y);
    c.cairo_curve_to(
        cr,
        cx + curve_offset, h * 0.30,
        cx - curve_offset, h * 0.55,
        cx, h * 0.50,
    );
    c.cairo_curve_to(
        cr,
        cx + curve_offset, h * 0.65,
        cx - curve_offset, h * 0.80,
        cx, bot_y,
    );
    c.cairo_stroke(cr);
}

/// Crescent sliver — a thin gold crescent moon shape at the screen edge.
/// Directional by which way it curves.
fn paintCrescentSliver(cr: *c.cairo_t, w: f64, h: f64, s: f64) void {
    c.cairo_set_line_width(cr, 2.5 * s);
    c.cairo_set_line_cap(cr, c.CAIRO_LINE_CAP_ROUND);

    const cx: f64 = w * 0.5;
    const cy: f64 = h * 0.5;
    const radius: f64 = @min(w, h) * 0.30;

    // Outer arc — a crescent opening toward the center of the screen.
    c.cairo_arc(cr, cx, cy, radius, std.math.pi * 0.25, std.math.pi * 0.75);
    c.cairo_stroke(cr);

    // Inner arc — slightly tighter, creating the crescent shape.
    c.cairo_arc_negative(cr, cx, cy, radius * 0.75, std.math.pi * 0.30, std.math.pi * 0.70);
    c.cairo_stroke(cr);
}

/// Curved arrow — 1px crescent stroke with subtle arrowhead.
/// Tapers to 0.5px at the tips for a whispy feel.
fn paintCurvedArrow(cr: *c.cairo_t, w: f64, h: f64, s: f64) void {
    const cx: f64 = w * 0.5;
    const cy: f64 = h * 0.5;
    const radius: f64 = @min(w, h) * 0.32;
    const sw: f64 = s;

    // Draw the curve in segments with decreasing line width toward the tips
    // to create the taper. 1px at center, 0.5px at the ends.
    const arc_start: f64 = std.math.pi * 0.60;
    const arc_end: f64 = std.math.pi * 1.40;
    const num_segs: i32 = 12;
    var i: i32 = 0;
    while (i < num_segs) : (i += 1) {
        const t1 = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(num_segs));
        const t2 = @as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(num_segs));
        const a1 = arc_start + (arc_end - arc_start) * t1;
        const a2 = arc_start + (arc_end - arc_start) * t2;

        // Width tapers from 0.5px at tips to 1.0px at center.
        const mid_t = (t1 + t2) * 0.5;
        const dist_from_center = @abs(mid_t - 0.5) * 2.0; // 0 at center, 1 at tips
        const line_w = (1.0 - dist_from_center * 0.5) * sw;

        c.cairo_set_line_width(cr, line_w);
        c.cairo_set_line_cap(cr, c.CAIRO_LINE_CAP_ROUND);
        c.cairo_move_to(cr, cx + radius * @cos(a1), cy + radius * @sin(a1));
        c.cairo_line_to(cr, cx + radius * @cos(a2), cy + radius * @sin(a2));
        c.cairo_stroke(cr);
    }

    // Arrowhead — two short lines at the end, tapering to 0.5px.
    const arrow_angle: f64 = arc_end;
    const ax: f64 = cx + radius * @cos(arrow_angle);
    const ay: f64 = cy + radius * @sin(arrow_angle);

    c.cairo_set_line_width(cr, 0.5 * sw);
    c.cairo_set_line_cap(cr, c.CAIRO_LINE_CAP_ROUND);
    c.cairo_move_to(cr, ax, ay);
    c.cairo_line_to(cr, ax + radius * 0.25 * @cos(arrow_angle + 2.5),
                       ay + radius * 0.25 * @sin(arrow_angle + 2.5));
    c.cairo_stroke(cr);

    c.cairo_move_to(cr, ax, ay);
    c.cairo_line_to(cr, ax + radius * 0.25 * @cos(arrow_angle - 2.5),
                       ay + radius * 0.25 * @sin(arrow_angle - 2.5));
    c.cairo_stroke(cr);
}

/// Spotlight beam — a small cone of light radiating from the edge inward.
/// Like a stage spotlight catching the corner.
fn paintSpotlightBeam(cr: *c.cairo_t, w: f64, h: f64, s: f64) void {
    // Radial gradient from the edge fading inward.
    const cx: f64 = w * 0.5;
    const cy: f64 = h * 0.5;
    const r_outer: f64 = @min(w, h) * 0.45;
    const r_inner: f64 = @min(w, h) * 0.10;

    const grad = c.cairo_pattern_create_radial(cx, cy, r_inner, cx, cy, r_outer);
    defer c.cairo_pattern_destroy(grad);

    // Use the current source color for the gradient stops.
    // We need to get the current source color — but we already set it.
    // So we'll use the source color directly for the inner stop and
    // transparent for the outer stop.
    c.cairo_pattern_add_color_stop_rgba(grad, 0.0, 1.0, 1.0, 1.0, 0.8);
    c.cairo_pattern_add_color_stop_rgba(grad, 1.0, 1.0, 1.0, 1.0, 0.0);

    // Save/restore to use the gradient without losing the caller's color.
    c.cairo_save(cr);
    c.cairo_set_source(cr, grad);
    // A narrow cone shape — triangle from edge to center.
    c.cairo_move_to(cr, w * 0.5, h * 0.5 - r_outer);
    c.cairo_line_to(cr, w * 0.5 + r_outer * 0.3, h * 0.5);
    c.cairo_line_to(cr, w * 0.5, h * 0.5 + r_outer);
    c.cairo_line_to(cr, w * 0.5 - r_outer * 0.3, h * 0.5);
    c.cairo_close_path(cr);
    c.cairo_fill(cr);
    c.cairo_restore(cr);

    // Thin bright line at the center — the "beam" axis.
    c.cairo_set_line_width(cr, 1.5 * s);
    c.cairo_move_to(cr, w * 0.5, h * 0.5 - r_outer * 0.7);
    c.cairo_line_to(cr, w * 0.5, h * 0.5 + r_outer * 0.7);
    c.cairo_stroke(cr);
}

/// EXIT dot-matrix — 4x5 gold dots spelling E-X-I-T.
/// Theater exit signage.  Same dot language as the kmedia helix balls.
fn paintExitDots(cr: *c.cairo_t, w: f64, h: f64, _: f64) void {
    // 5x6 dot grid per letter, 4 letters.
    // X uses tighter dot spacing (it already looks good).
    // E, I, T use wider spacing so the letters don't bunch together.

    const dot_r: f64 = @min(w, h) * 0.05; // base dot radius — small balls
    const dot_spacing: f64 = dot_r * 3.0; // uniform spacing for all letters
    const letter_w: f64 = 5.0 * dot_spacing;
    const letter_h: f64 = 6.0 * dot_spacing;
    const letter_gap: f64 = dot_spacing * 0.8;

    const total_w: f64 = 4.0 * letter_w + 3.0 * letter_gap;
    const start_x: f64 = (w - total_w) / 2.0;
    const start_y: f64 = (h - letter_h) / 2.0;

    // Letter patterns: 6 rows x 5 cols, 1=on 0=off.
    const e = [6][5]u8{
        .{ 1, 1, 1, 1, 1 },
        .{ 1, 0, 0, 0, 0 },
        .{ 1, 1, 1, 1, 0 },
        .{ 1, 0, 0, 0, 0 },
        .{ 1, 0, 0, 0, 0 },
        .{ 1, 1, 1, 1, 1 },
    };
    const x_l = [6][5]u8{
        .{ 1, 0, 0, 0, 1 },
        .{ 0, 1, 0, 1, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 1, 0, 1, 0 },
        .{ 1, 0, 0, 0, 1 },
    };
    const i_l = [6][5]u8{
        .{ 0, 1, 1, 1, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 1, 1, 1, 0 },
    };
    const t_l = [6][5]u8{
        .{ 1, 1, 1, 1, 1 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
    };

    const letters = [_][6][5]u8{ e, x_l, i_l, t_l };

    for (letters, 0..) |letter, li| {
        const lx = start_x + @as(f64, @floatFromInt(li)) * (letter_w + letter_gap);
        for (letter, 0..) |row, ri| {
            for (row, 0..) |on, ci| {
                if (on == 1) {
                    const cx = lx + @as(f64, @floatFromInt(ci)) * dot_spacing + dot_r;
                    const cy = start_y + @as(f64, @floatFromInt(ri)) * dot_spacing + dot_r;
                    c.cairo_arc(cr, cx, cy, dot_r, 0.0, 2.0 * std.math.pi);
                    c.cairo_fill(cr);
                }
            }
        }
    }
}
/// 1px shaft, tapering to 0.5px at the tail.
/// Left icon points left, right icon points right.
fn paintStraightArrow(cr: *c.cairo_t, w: f64, h: f64, s: f64, side: Side) void {
    const cy: f64 = h * 0.5;
    // Left arrow: tip on the left, tail on the right.
    // Right arrow: tip on the right, tail on the left.
    const tip_x: f64 = if (side == .left) w * 0.20 else w * 0.80;
    const tail_x: f64 = if (side == .left) w * 0.80 else w * 0.20;
    const dir: f64 = if (side == .left) -1.0 else 1.0;

    // Shaft — 1px at tip, tapering to 0.5px at the tail.
    const num_segs: i32 = 8;
    var i: i32 = 0;
    while (i < num_segs) : (i += 1) {
        const t1 = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(num_segs));
        const t2 = @as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(num_segs));
        // t=0 at tail, t=1 at tip
        const x1 = tail_x + (tip_x - tail_x) * t1;
        const x2 = tail_x + (tip_x - tail_x) * t2;
        const mid_t = (t1 + t2) * 0.5;
        // Wider near tip (1px), narrower at tail (0.5px)
        const line_w = (0.5 + mid_t * 0.5) * s;
        c.cairo_set_line_width(cr, line_w);
        c.cairo_set_line_cap(cr, c.CAIRO_LINE_CAP_ROUND);
        c.cairo_move_to(cr, x1, cy);
        c.cairo_line_to(cr, x2, cy);
        c.cairo_stroke(cr);
    }

    // Arrowhead — bigger, two lines at 45 degrees from the tip.
    c.cairo_set_line_width(cr, 0.75 * s);
    c.cairo_set_line_cap(cr, c.CAIRO_LINE_CAP_ROUND);
    const head_len: f64 = @min(w, h) * 0.28;
    const angle: f64 = std.math.pi * 0.25; // 45 degrees
    // Head lines go from the tip backward (away from direction)
    c.cairo_move_to(cr, tip_x, cy);
    c.cairo_line_to(cr, tip_x - dir * head_len * @cos(angle), cy - head_len * @sin(angle));
    c.cairo_stroke(cr);
    c.cairo_move_to(cr, tip_x, cy);
    c.cairo_line_to(cr, tip_x - dir * head_len * @cos(angle), cy + head_len * @sin(angle));
    c.cairo_stroke(cr);
}
