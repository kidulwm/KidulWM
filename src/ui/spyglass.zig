const std = @import("std");
const wlr = @import("wlroots");
const c = @import("dm").c;
const Style = @import("../core/style.zig").Style;
const DataBuffer = @import("../render/buffer.zig").DataBuffer;

/// Peek signage widget — pack "spyglass".
///
/// The peek icons sit at the left/right screen edges, vertically centered.
/// They are the "peek at the neighbor" affordance: hover reveals the icon,
/// click navigates to the adjacent slide. Icons live in the overlay_tree so
/// they render above client surfaces.
///
/// WIDGET PACK LAW (2026-09-15): the icon visuals are SKINS, not one-off
/// branches. Every skin declares its geometry (surface width, pointer
/// hitbox width) and a paint function in the Skin table below. Selecting a
/// skin is a one-line change (`active_skin`); upgrading a skin never
/// touches Icon/Server code. Display-only surface area (e.g. the slide
/// count strip) must NOT be part of the hitbox — skins declare `hit_w`
/// separately from `surface_w`.
const icon_size: u32 = 20; // px tall, unscaled
const margin_from_bottom: u32 = 0; // 0 = vertically centered
/// Peek geometry: the visible neighbor-slide strip at each screen edge is
/// `peek_fraction` of the output width (style layout horizontal_split).
/// EXIT dot-matrix sits 1 char-space from the slide border (inner peek
/// edge); the slide-count digit sits 1 char-space from the screen edge.
const peek_fraction: f64 = 0.06;

/// Skin descriptor — one entry per pack skin.
const Skin = struct {
    /// Full cairo surface width in px (unscaled), including display-only strips.
    surface_w: u32,
    /// Pointer hitbox width in px (unscaled), measured from the CENTER-side
    /// of the surface (the side facing the slides). Must be <= surface_w.
    hit_w: u32,
    /// Paint into a surface_w x icon_size surface.
    paint: *const fn (cr: *c.cairo_t, w: f64, h: f64, s: f64, side: Side, hovered: bool, slide_count: u32) void,
};

const exit_dots_w: u32 = 72; // px wide for the EXIT dot-matrix itself
/// Slide-count digit size relative to the icon height (was 1.2 — too big).
const num_font_scale: f64 = 0.9;

const skins = .{
    .silk_wisp = Skin{ .surface_w = icon_size, .hit_w = icon_size, .paint = paintSilkWispSkin },
    .crescent_sliver = Skin{ .surface_w = icon_size, .hit_w = icon_size, .paint = paintCrescentSliverSkin },
    .curved_arrow = Skin{ .surface_w = icon_size, .hit_w = icon_size, .paint = paintCurvedArrowSkin },
    .spotlight_beam = Skin{ .surface_w = icon_size, .hit_w = icon_size, .paint = paintSpotlightBeamSkin },
    .straight_arrow = Skin{ .surface_w = icon_size, .hit_w = icon_size, .paint = paintStraightArrowSkin },
    // EXIT dots + slide-count digit, centered as one pair inside the peek.
    // surface_w is nominal — regenerate() sizes the surface to the peek band.
    .exit_dots = Skin{ .surface_w = exit_dots_w + 48, .hit_w = exit_dots_w + 48, .paint = paintExitDotsSkin },
};

const SkinId = enum { silk_wisp, crescent_sliver, curved_arrow, spotlight_beam, straight_arrow, exit_dots };

/// The pack's selected skin. One line to swap.
const active_skin: SkinId = .exit_dots;

fn skin() Skin {
    return switch (active_skin) {
        inline else => |id| @field(skins, @tagName(id)),
    };
}

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

    // Which sides have neighbors (slides to peek at), and how many slides
    // sit on that side of the current slide (printed at the screen edge,
    // level with the EXIT signs).
    has_left: bool = false,
    has_right: bool = false,
    left_count: u32 = 0,
    right_count: u32 = 0,

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

    pub fn setNeighbors(self: *Spyglass, has_left: bool, has_right: bool, left_count: u32, right_count: u32) void {
        const left_changed = self.has_left != has_left;
        const right_changed = self.has_right != has_right;
        const left_count_changed = self.left_count != left_count;
        const right_count_changed = self.right_count != right_count;
        self.has_left = has_left;
        self.has_right = has_right;
        self.left_count = left_count;
        self.right_count = right_count;
        self.left.setEnabled(has_left);
        self.right.setEnabled(has_right);
        self.left.setCount(if (has_left) left_count else 0);
        self.right.setCount(if (has_right) right_count else 0);
        // Render icons when they become visible.
        if (left_changed and has_left) self.left.regenerate();
        if (right_changed and has_right) self.right.regenerate();
        // Re-render when the slide count changes while visible.
        if (has_left and left_count_changed and !left_changed) self.left.regenerate();
        if (has_right and right_count_changed and !right_changed) self.right.regenerate();
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
    slide_count: u32,
    last_rendered_count: u32,
    last_rendered_peek_w: i32,
    output_width: u32,

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
            .slide_count = 0,
            .last_rendered_count = 0,
            .last_rendered_peek_w = 0,
            .output_width = 0,
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
        self.output_width = output_width;
        const s: i32 = @max(1, @as(i32, @intCast(scale)));
        const sk = skin();
        _ = sk;
        const sz_h: i32 = @as(i32, @intCast(icon_size)) * s;

        const out_w: i32 = @intCast(output_width);
        const peek_w: i32 = @intFromFloat(@as(f64, @floatFromInt(out_w)) * peek_fraction);

        // The surface is peek_w wide and covers the peek band exactly; the
        // skin centers the EXIT+number pair inside it (see paintExitDotsSkin).
        self.x = switch (self.side) {
            .left => 0,
            .right => out_w - peek_w,
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

    fn setCount(self: *Icon, count: u32) void {
        self.slide_count = count;
    }

    fn contains(self: *const Icon, px: f64, py: f64) bool {
        // Hitbox spans the whole peek band (the surface covers it exactly).
        const out_w: f64 = @floatFromInt(self.output_width);
        const peek_w: f64 = out_w * peek_fraction;
        const hx: f64 = @floatFromInt(self.x);
        const sy: f64 = @floatFromInt(self.y);
        const sh: f64 = @floatFromInt(self.height * self.scale);
        return px >= hx and px < hx + peek_w and py >= sy and py < sy + sh;
    }

    fn regenerate(self: *Icon) void {
        if (self.tree == null) return;
        const tree = self.tree.?;

        // Destroy old buffer if hover state, scale, slide count, or peek
        // width changed.
        const out_w: i32 = @intCast(self.output_width);
        const peek_w: i32 = @intFromFloat(@as(f64, @floatFromInt(out_w)) * peek_fraction);
        if (self.buffer != null and (self.last_rendered_hovered != self.hovered or self.last_rendered_scale != self.scale or self.last_rendered_count != self.slide_count or self.last_rendered_peek_w != peek_w)) {
            self.buffer.?.node.destroy();
            self.buffer = null;
        }
        if (self.buffer != null) return;

        const s: u32 = @max(1, self.scale);
        const sk = skin();
        const px_w: i32 = if (active_skin == .exit_dots) peek_w else @as(i32, @intCast(sk.surface_w)) * @as(i32, @intCast(s));
        const px_h: i32 = @as(i32, @intCast(icon_size)) * @as(i32, @intCast(s));

        const surface = paintSpyglass(self.hovered, s, self.side, self.slide_count, peek_w) orelse return;
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
        if (active_skin == .exit_dots) {
            // Buffer is already peek_w x icon_size*s device px; let the
            // scene scale it back down by the output scale.
            scene_buffer.setDestSize(@intCast(@divTrunc(px_w, @as(i32, @intCast(s)))), @intCast(icon_size));
        } else {
            scene_buffer.setDestSize(@intCast(sk.surface_w), @intCast(icon_size));
        }
        self.buffer = scene_buffer;
        self.last_rendered_hovered = self.hovered;
        self.last_rendered_scale = self.scale;
        self.last_rendered_count = self.slide_count;
        self.last_rendered_peek_w = peek_w;
    }
};

/// Paint a peek icon via the pack's active skin.
/// At rest: faint ghost; on hover: brighter, in the focused-border tone.
fn paintSpyglass(hovered: bool, scale: u32, side: Side, slide_count: u32, peek_w: i32) ?*c.cairo_surface_t {
    const s: i32 = @max(1, @as(i32, @intCast(scale)));
    const sk = skin();
    const w: i32 = if (active_skin == .exit_dots) peek_w else @as(i32, @intCast(sk.surface_w)) * s;
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
    const alpha: f64 = if (hovered) 0.96 else 0.86;
    const color = if (hovered) [_]f64{ 0.41, 0.40, 0.33 } else [_]f64{ 0.30, 0.29, 0.25 };

    c.cairo_set_source_rgba(cr, color[0], color[1], color[2], alpha);

    sk.paint(cr, wf, hf, @floatFromInt(s), side, hovered, slide_count);

    return surface;
}

/// Measure the slide-count digit at the pair's font size. Returns its
/// advance width in px (0 when count == 0). Uses the caller's cairo state.
fn measureSlideCount(cr: *c.cairo_t, h: f64, count: u32) f64 {
    if (count == 0) return 0;
    var buf: [8]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, "{d}", .{count}) catch return 0;
    c.cairo_save(cr);
    c.cairo_set_font_size(cr, h * num_font_scale);
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, text.ptr, &ext);
    c.cairo_restore(cr);
    return ext.width;
}

/// Measure one character space at the digit font size (advance of "0").
/// Used as the house spacing unit for EXIT/digit edge offsets.
fn measureCharSpace(cr: *c.cairo_t, h: f64) f64 {
    c.cairo_save(cr);
    c.cairo_set_font_size(cr, h * num_font_scale);
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, "0", &ext);
    c.cairo_restore(cr);
    return ext.x_advance;
}

/// Draw the slide-count digit with its LEFT edge at tx, vertically centered.
/// Inherits the caller's source (same color/alpha as the EXIT dots).
fn drawSlideCount(cr: *c.cairo_t, h: f64, count: u32, tx: f64) void {
    var buf: [8]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, "{d}", .{count}) catch return;
    c.cairo_save(cr);
    c.cairo_set_font_size(cr, h * num_font_scale);
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, text.ptr, &ext);
    const ty: f64 = (h - ext.height) / 2.0 - ext.y_bearing;
    c.cairo_move_to(cr, tx - ext.x_bearing, ty);
    c.cairo_show_text(cr, text.ptr);
    c.cairo_restore(cr);
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
        cx + curve_offset,
        h * 0.30,
        cx - curve_offset,
        h * 0.55,
        cx,
        h * 0.50,
    );
    c.cairo_curve_to(
        cr,
        cx + curve_offset,
        h * 0.65,
        cx - curve_offset,
        h * 0.80,
        cx,
        bot_y,
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
    c.cairo_line_to(cr, ax + radius * 0.25 * @cos(arrow_angle + 2.5), ay + radius * 0.25 * @sin(arrow_angle + 2.5));
    c.cairo_stroke(cr);

    c.cairo_move_to(cr, ax, ay);
    c.cairo_line_to(cr, ax + radius * 0.25 * @cos(arrow_angle - 2.5), ay + radius * 0.25 * @sin(arrow_angle - 2.5));
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

// ────────────────────────────────────────────────────────────────────────
// Skin wrappers — the pack interface. Each adapts a painter to the Skin
// paint signature (cr, w, h, s, side, hovered, slide_count).
// ────────────────────────────────────────────────────────────────────────

fn paintSilkWispSkin(cr: *c.cairo_t, w: f64, h: f64, s: f64, _: Side, _: bool, _: u32) void {
    paintSilkWisp(cr, w, h, s);
}

fn paintCrescentSliverSkin(cr: *c.cairo_t, w: f64, h: f64, s: f64, _: Side, _: bool, _: u32) void {
    paintCrescentSliver(cr, w, h, s);
}

fn paintCurvedArrowSkin(cr: *c.cairo_t, w: f64, h: f64, s: f64, _: Side, _: bool, _: u32) void {
    paintCurvedArrow(cr, w, h, s);
}

fn paintSpotlightBeamSkin(cr: *c.cairo_t, w: f64, h: f64, s: f64, _: Side, _: bool, _: u32) void {
    paintSpotlightBeam(cr, w, h, s);
}

fn paintStraightArrowSkin(cr: *c.cairo_t, w: f64, h: f64, s: f64, side: Side, _: bool, _: u32) void {
    paintStraightArrow(cr, w, h, s, side);
}

/// EXIT dot-matrix pinned 1 char-space from the SLIDE BORDER (inner side of
/// the peek): left peek puts the dots at the right, right peek at the left —
/// opposite math per side. The slide-count digit is pinned 1 char-space from
/// the OUTER screen edge. The digit is ALWAYS drawn when count > 0 (never
/// dropped by a fit check).
fn paintExitDotsSkin(cr: *c.cairo_t, w: f64, h: f64, s: f64, side: Side, _: bool, slide_count: u32) void {
    const dots_f: f64 = @as(f64, @floatFromInt(exit_dots_w)) * s;
    const char_sp: f64 = measureCharSpace(cr, h);
    const num_w: f64 = measureSlideCount(cr, h, slide_count);

    // EXIT dots: 1 char-space in from the slide-border side.
    const dots_x: f64 = if (side == .left) w - char_sp - dots_f else char_sp;
    c.cairo_save(cr);
    c.cairo_translate(cr, dots_x, 0.0);
    paintExitDots(cr, dots_f, h, s);
    c.cairo_restore(cr);

    // Digit: 1 char-space in from the screen-edge side.
    if (num_w > 0) {
        const num_x: f64 = if (side == .left) char_sp else w - char_sp - num_w;
        drawSlideCount(cr, h, slide_count, num_x);
    }
}
