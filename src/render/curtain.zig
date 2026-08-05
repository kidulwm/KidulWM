const std = @import("std");
const c = @import("dm").c;
const wlr = @import("wlroots");
const Style = @import("../core/style.zig").Style;
const DataBuffer = @import("buffer.zig").DataBuffer;
const chrome = @import("chrome.zig");

const curtain_left_tied_png = @embedFile("assets/curtain_left_tied.png");

pub const OutputCurtains = struct {
    allocator: std.mem.Allocator,
    left: *Panel,
    right: *Panel,

    pub fn create(allocator: std.mem.Allocator, parent: *wlr.SceneTree) !*OutputCurtains {
        const oc = try allocator.create(OutputCurtains);
        errdefer allocator.destroy(oc);
        const left = try Panel.create(allocator, parent, false);
        errdefer left.destroy();
        const right = try Panel.create(allocator, parent, true);
        oc.* = .{
            .allocator = allocator,
            .left = left,
            .right = right,
        };
        return oc;
    }

    pub fn destroy(self: *OutputCurtains) void {
        self.left.destroy();
        self.right.destroy();
        self.allocator.destroy(self);
    }

    pub fn update(
        self: *OutputCurtains,
        style: Style,
        style_generation: u32,
        scale: u32,
        output_box: wlr.Box,
        left_peek: f32,
        right_peek: f32,
        has_left_peek: bool,
        has_right_peek: bool,
    ) void {
        _ = left_peek;
        _ = right_peek;
        _ = has_left_peek;
        _ = has_right_peek;
        self.left.update(style, style_generation, scale, output_box, false);
        self.right.update(style, style_generation, scale, output_box, true);
    }
};

const Panel = struct {
    allocator: std.mem.Allocator,
    tree: *wlr.SceneTree,
    buffer: ?*wlr.SceneBuffer,
    width: i32,
    height: i32,
    scale: u32,
    style_generation: u32,
    last_right_side: bool,

    const asset_width = 190;
    const asset_height = 1440;
    const edge_nudge: i32 = 13;

    fn create(allocator: std.mem.Allocator, parent: *wlr.SceneTree, right_side: bool) !*Panel {
        const panel = try allocator.create(Panel);
        errdefer allocator.destroy(panel);
        const tree = try parent.createSceneTree();
        tree.node.setPosition(0, 0);
        tree.node.lowerToBottom();
        panel.* = .{
            .allocator = allocator,
            .tree = tree,
            .buffer = null,
            .width = 0,
            .height = 0,
            .scale = 1,
            .style_generation = 0,
            .last_right_side = right_side,
        };
        return panel;
    }

    fn destroy(self: *Panel) void {
        self.tree.node.destroy();
        self.allocator.destroy(self);
    }

    fn update(
        self: *Panel,
        style: Style,
        style_generation: u32,
        scale: u32,
        output_box: wlr.Box,
        right_side: bool,
    ) void {
        const s: u32 = @max(1, scale);
        const output_height: u32 = @intCast(output_box.height);
        const panel_h: i32 = @intCast(output_height);

        const scaled_w_f: f32 = @as(f32, @floatFromInt(asset_width)) * (@as(f32, @floatFromInt(panel_h)) / @as(f32, @floatFromInt(asset_height)));
        const panel_w: i32 = @intFromFloat(@max(24.0, scaled_w_f));

        const local_x = if (right_side)
            output_box.x + output_box.width - panel_w + edge_nudge
        else
            output_box.x - edge_nudge;

        self.tree.node.setEnabled(panel_w >= 24);
        if (panel_w < 24) {
            self.width = 0;
            self.height = 0;
            self.last_right_side = right_side;
            return;
        }

        self.tree.node.setPosition(local_x, output_box.y - edge_nudge);

        const same =
            self.buffer != null and
            self.width == panel_w and
            self.height == panel_h and
            self.scale == s and
            self.style_generation == style_generation and
            self.last_right_side == right_side;
        if (same) {
            self.last_right_side = right_side;
            return;
        }

        self.width = panel_w;
        self.height = panel_h;
        self.scale = s;
        self.style_generation = style_generation;
        self.last_right_side = right_side;
        self.regenerate(style, s, panel_w, panel_h, right_side);
    }

    fn regenerate(self: *Panel, style: Style, scale: u32, width: i32, height: i32, right_side: bool) void {
        if (self.buffer) |buf| {
            buf.node.destroy();
            self.buffer = null;
        }

        const dest_w: i32 = width * @as(i32, @intCast(scale));
        const dest_h: i32 = height * @as(i32, @intCast(scale));
        const surface = paintCurtain(style, dest_w, dest_h, right_side) orelse {
            self.tree.node.setEnabled(false);
            return;
        };
        defer c.cairo_surface_destroy(surface);

        const pixels = chrome.surfacePixels(surface);
        const buffer = DataBuffer.create(pixels.pixels, pixels.width, pixels.height, pixels.stride) catch {
            self.tree.node.setEnabled(false);
            return;
        };
        errdefer wlr.Buffer.drop(buffer);

        const scene_buffer = self.tree.createSceneBuffer(buffer) catch {
            wlr.Buffer.drop(buffer);
            self.tree.node.setEnabled(false);
            return;
        };
        wlr.Buffer.drop(buffer);
        scene_buffer.setDestSize(width, height);
        self.buffer = scene_buffer;
    }
};

// Procedural "Kidul fold" curtain: straight black-velvet drop drawn in
// Cairo. Vertical fold columns (soft gradient valleys/peaks with phase
// jitter so they read organic), scalloped gather at the top, and a hem
// that sweeps up toward the center-facing edge. Vector-crisp at any width.
fn paintCurtain(style: Style, dest_w: i32, dest_h: i32, right_side: bool) ?*c.cairo_surface_t {
    if (dest_w < 8 or dest_h < 8) return null;
    const surf = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, dest_w, dest_h) orelse return null;
    const cr = c.cairo_create(surf) orelse {
        c.cairo_surface_destroy(surf);
        return null;
    };
    defer c.cairo_destroy(cr);

    // Transparent base.
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_set_source_rgba(cr, 0, 0, 0, 0);
    c.cairo_paint(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    const w: f64 = @floatFromInt(dest_w);
    const h: f64 = @floatFromInt(dest_h);

    const bg = style.tray_bg_color.toF64();
    const border = style.color_border.toF64();

    // Work in a normalized left-panel space; mirror for the right panel so
    // the hem curve always sweeps up toward the screen center.
    c.cairo_save(cr);
    if (right_side) {
        c.cairo_translate(cr, w, 0.0);
        c.cairo_scale(cr, -1.0, 1.0);
    }

    // --- Silhouette ---------------------------------------------------------
    // Straight drop along the outer (left) edge; the inner (right) edge has
    // a slight inward taper near the bottom and the hem curves up toward it.
    const inner_x = w; // inner edge at the panel's right side (center-facing)
    const hem_rise = h * 0.035; // how far the hem lifts at the inner corner
    const hem_curve_span = w * 0.85;

    c.cairo_move_to(cr, 0.0, 0.0);
    c.cairo_line_to(cr, inner_x, 0.0);
    // Inner edge: straight down to just above the hem.
    c.cairo_line_to(cr, inner_x, h - hem_rise);
    // Hem: sweep up from outer bottom corner to the inner edge.
    c.cairo_curve_to(cr,
        inner_x - hem_curve_span * 0.35, h - hem_rise * 0.35,
        hem_curve_span * 0.4, h,
        0.0, h - hem_rise * 0.15);
    c.cairo_close_path(cr);

    // Base velvet fill.
    c.cairo_set_source_rgba(cr, bg[0], bg[1], bg[2], 1.0);
    c.cairo_fill_preserve(cr);

    // --- Fold columns ---------------------------------------------------------
    c.cairo_save(cr);
    c.cairo_clip(cr);

    const fold_count = 6;
    const fold_w = w / @as(f64, @floatFromInt(fold_count));
    var f: usize = 0;
    while (f < fold_count) : (f += 1) {
        const fi = @as(f64, @floatFromInt(f));
        // Deterministic phase jitter so folds don't look machined.
        const jitter = std.math.sin(fi * 12.9898 + 78.233) * 0.5 + 0.5; // 0..1
        const x0 = fi * fold_w + (jitter - 0.5) * fold_w * 0.3;

        // Valley -> sheen peak -> valley, one gradient per fold.
        const grad = c.cairo_pattern_create_linear(x0, 0.0, x0 + fold_w, 0.0).?;
        c.cairo_pattern_add_color_stop_rgba(grad, 0.0, 0.0, 0.0, 0.0, 0.30);
        c.cairo_pattern_add_color_stop_rgba(grad, 0.35 + jitter * 0.2, border[0], border[1], border[2], 0.10);
        c.cairo_pattern_add_color_stop_rgba(grad, 0.5 + jitter * 0.15, border[0], border[1], border[2], 0.16);
        c.cairo_pattern_add_color_stop_rgba(grad, 0.75, 0.0, 0.0, 0.0, 0.22);
        c.cairo_pattern_add_color_stop_rgba(grad, 1.0, 0.0, 0.0, 0.0, 0.32);
        c.cairo_set_source(cr, grad);
        c.cairo_rectangle(cr, x0 - 1.0, 0.0, fold_w + 2.0, h);
        c.cairo_fill(cr);
        c.cairo_pattern_destroy(grad);
    }

    // Deepen the outer edge (pinned side) slightly so the panel sits into the bezel.
    const edge_grad = c.cairo_pattern_create_linear(0.0, 0.0, w * 0.25, 0.0).?;
    c.cairo_pattern_add_color_stop_rgba(edge_grad, 0.0, 0.0, 0.0, 0.0, 0.35);
    c.cairo_pattern_add_color_stop_rgba(edge_grad, 1.0, 0.0, 0.0, 0.0, 0.0);
    c.cairo_set_source(cr, edge_grad);
    c.cairo_rectangle(cr, 0.0, 0.0, w * 0.25, h);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(edge_grad);

    // --- Scalloped gather at the top ----------------------------------------
    const gather_h = @min(h * 0.06, 60.0);
    var g: usize = 0;
    while (g < fold_count) : (g += 1) {
        const gi = @as(f64, @floatFromInt(g));
        const gx = gi * fold_w + fold_w * 0.5;
        const ggrad = c.cairo_pattern_create_radial(gx, -gather_h * 0.4, 2.0, gx, -gather_h * 0.4, gather_h * 1.6).?;
        c.cairo_pattern_add_color_stop_rgba(ggrad, 0.0, border[0], border[1], border[2], 0.12);
        c.cairo_pattern_add_color_stop_rgba(ggrad, 1.0, 0.0, 0.0, 0.0, 0.0);
        c.cairo_set_source(cr, ggrad);
        c.cairo_rectangle(cr, gx - fold_w, 0.0, fold_w * 2.0, gather_h);
        c.cairo_fill(cr);
        c.cairo_pattern_destroy(ggrad);
    }

    // Hem shading: soft dark pooling just above the hem line.
    const hem_grad = c.cairo_pattern_create_linear(0.0, h - hem_rise * 3.0, 0.0, h).?;
    c.cairo_pattern_add_color_stop_rgba(hem_grad, 0.0, 0.0, 0.0, 0.0, 0.0);
    c.cairo_pattern_add_color_stop_rgba(hem_grad, 1.0, 0.0, 0.0, 0.0, 0.30);
    c.cairo_set_source(cr, hem_grad);
    c.cairo_rectangle(cr, 0.0, h - hem_rise * 3.0, w, hem_rise * 3.0);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(hem_grad);

    c.cairo_restore(cr); // unclip

    // Inner edge rim light: a hairline of border color so the drop reads
    // against the focused slide, matching the rest of the chrome.
    c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.25);
    c.cairo_set_line_width(cr, 1.0);
    c.cairo_move_to(cr, inner_x - 0.5, 0.0);
    c.cairo_line_to(cr, inner_x - 0.5, h - hem_rise);
    c.cairo_stroke(cr);

    c.cairo_restore(cr); // unmirror
    return surf;
}

const PngStream = struct {
    data: []const u8,
    offset: usize,
};

fn readPngStream(closure: *anyopaque, out: [*c]u8, len: c_uint) callconv(.c) c.cairo_status_t {
    const ctx: *PngStream = @ptrCast(@alignCast(closure));
    const l: usize = len;
    if (ctx.offset >= ctx.data.len) {
        @memset(out[0..l], 0);
    } else {
        const remaining = ctx.data.len - ctx.offset;
        const copy = @min(remaining, l);
        if (copy > 0) {
            @memcpy(out[0..copy], ctx.data[ctx.offset .. ctx.offset + copy]);
            ctx.offset += copy;
        }
        if (copy < l) {
            @memset(out[copy..l], 0);
        }
    }
    return c.CAIRO_STATUS_SUCCESS;
}
