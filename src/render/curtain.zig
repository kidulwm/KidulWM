const std = @import("std");
const c = @import("dm").c;
const wlr = @import("wlroots");
const Style = @import("../core/style.zig").Style;
const DataBuffer = @import("buffer.zig").DataBuffer;
const chrome = @import("chrome.zig");
const animation = @import("../core/animation.zig");

/// Cinema masking panels — solid black rectangles with a 1px gold inner
/// edge, replacing the velvet curtain concept.  They cover the peek gaps
/// on each side of the focused slide, framing it like widescreen
/// letterbox bars.  On focus change the masks animate in from the screen
/// edges (opacity 0→1 + slight inward slide), then settle to static.

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

    /// Raise mask panels above all chrome in the overlay tree.
    pub fn raiseAboveChrome(self: *OutputCurtains) void {
        self.left.tree.node.raiseToTop();
        self.right.tree.node.raiseToTop();
    }

    pub fn tickAnimation(self: *OutputCurtains, now_us: animation.TimeUs) bool {
        const left_moving = self.left.tickAnimation(now_us);
        const right_moving = self.right.tickAnimation(now_us);
        return left_moving or right_moving;
    }

    pub fn triggerEntrance(self: *OutputCurtains, now_us: animation.TimeUs) void {
        self.left.triggerEntrance(now_us);
        self.right.triggerEntrance(now_us);
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
        self.left.update(style, style_generation, scale, output_box, false, left_peek, has_left_peek);
        self.right.update(style, style_generation, scale, output_box, true, right_peek, has_right_peek);
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
    right_side: bool,
    final_x: i32,
    final_y: i32,
    panel_w: i32,
    panel_h: i32,
    opacity: f32,
    opacity_target: f32,
    anim_start_us: animation.TimeUs,
    anim_duration_us: animation.TimeUs,
    animating: bool,
    slide_offset: f32,
    slide_initial: f32,

    const anim_duration: animation.TimeUs = 320_000;
    const slide_distance: f32 = 40.0;

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
            .right_side = right_side,
            .final_x = 0,
            .final_y = 0,
            .panel_w = 0,
            .panel_h = 0,
            .opacity = 0.0,
            .opacity_target = 0.0,
            .anim_start_us = 0,
            .anim_duration_us = anim_duration,
            .animating = false,
            .slide_offset = 0.0,
            .slide_initial = 0.0,
        };
        return panel;
    }

    fn destroy(self: *Panel) void {
        self.tree.node.destroy();
        self.allocator.destroy(self);
    }

    fn triggerEntrance(self: *Panel, now_us: animation.TimeUs) void {
        if (self.opacity_target < 0.5) return;
        self.opacity = 0.0;
        self.slide_offset = self.slide_initial;
        self.anim_start_us = now_us;
        self.animating = true;
    }

    fn tickAnimation(self: *Panel, now_us: animation.TimeUs) bool {
        if (!self.animating) return false;
        const elapsed = now_us - self.anim_start_us;
        if (elapsed >= self.anim_duration_us) {
            self.opacity = self.opacity_target;
            self.slide_offset = 0.0;
            self.animating = false;
            self.applyPosition();
            self.applyOpacity();
            return false;
        }
        const t = @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(self.anim_duration_us));
        const eased = 1.0 - std.math.pow(f32, 1.0 - t, 3.0);
        self.opacity = self.opacity_target * eased;
        self.slide_offset = self.slide_initial * (1.0 - eased);
        self.applyPosition();
        self.applyOpacity();
        return true;
    }

    fn applyOpacity(self: *Panel) void {
        if (self.buffer) |buf| {
            buf.setOpacity(self.opacity);
        }
    }

    fn applyPosition(self: *Panel) void {
        const offset_x: i32 = if (self.right_side)
            @intFromFloat(@as(f32, @floatFromInt(self.final_x)) + self.slide_offset)
        else
            @intFromFloat(@as(f32, @floatFromInt(self.final_x)) - self.slide_offset);
        self.tree.node.setPosition(offset_x, self.final_y);
    }

    fn update(
        self: *Panel,
        style: Style,
        style_generation: u32,
        scale: u32,
        output_box: wlr.Box,
        right_side: bool,
        peek_ratio: f32,
        has_peek: bool,
    ) void {
        _ = peek_ratio;

        const s: u32 = @max(1, scale);
        const output_height: u32 = @intCast(output_box.height);
        const panel_h: i32 = @intCast(output_height);
        const peek_w: i32 = @intFromFloat(@as(f32, @floatFromInt(output_box.width)) * 0.06);
        const panel_w: i32 = @max(peek_w, 24);

        const final_x: i32 = if (right_side)
            output_box.x + output_box.width - panel_w
        else
            output_box.x;
        const final_y: i32 = output_box.y;

        const should_show = has_peek;
        self.opacity_target = if (should_show) 1.0 else 0.0;

        if (should_show and self.opacity < 0.01 and !self.animating) {
            self.opacity = 1.0;
        }
        if (!should_show and self.opacity > 0.01 and !self.animating) {
            self.opacity = 0.0;
        }

        self.final_x = final_x;
        self.final_y = final_y;
        self.panel_w = panel_w;
        self.panel_h = panel_h;
        self.slide_initial = slide_distance;

        self.tree.node.setEnabled(panel_w >= 24 and self.opacity > 0.005);
        if (panel_w < 24) {
            self.width = 0;
            self.height = 0;
            self.right_side = right_side;
            return;
        }

        self.applyPosition();

        const same =
            self.buffer != null and
            self.width == panel_w and
            self.height == panel_h and
            self.scale == s and
            self.style_generation == style_generation and
            self.right_side == right_side;
        if (same) {
            self.right_side = right_side;
            self.applyOpacity();
            return;
        }

        self.width = panel_w;
        self.height = panel_h;
        self.scale = s;
        self.style_generation = style_generation;
        self.right_side = right_side;
        self.regenerate(style, s, panel_w, panel_h, right_side);
        self.applyOpacity();
    }

    fn regenerate(self: *Panel, style: Style, scale: u32, width: i32, height: i32, right_side: bool) void {
        if (self.buffer) |buf| {
            buf.node.destroy();
            self.buffer = null;
        }

        const dest_w: i32 = width * @as(i32, @intCast(scale));
        const dest_h: i32 = height * @as(i32, @intCast(scale));
        const surface = paintMask(style, dest_w, dest_h, right_side) orelse {
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

fn paintMask(style: Style, dest_w: i32, dest_h: i32, right_side: bool) ?*c.cairo_surface_t {
    if (dest_w < 2 or dest_h < 2) return null;
    const surf = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, dest_w, dest_h) orelse return null;
    const cr = c.cairo_create(surf) orelse {
        c.cairo_surface_destroy(surf);
        return null;
    };
    defer c.cairo_destroy(cr);

    const w: f64 = @floatFromInt(dest_w);
    const h: f64 = @floatFromInt(dest_h);

    const bg = style.tray_bg_color.toF64();
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_set_source_rgba(cr, bg[0], bg[1], bg[2], 1.0);
    c.cairo_rectangle(cr, 0.0, 0.0, w, h);
    c.cairo_fill(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    const border = style.color_border_focused.toF64();
    c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.35);
    c.cairo_set_line_width(cr, 1.0);
    if (right_side) {
        c.cairo_move_to(cr, 0.5, 0.0);
        c.cairo_line_to(cr, 0.5, h);
    } else {
        c.cairo_move_to(cr, w - 0.5, 0.0);
        c.cairo_line_to(cr, w - 0.5, h);
    }
    c.cairo_stroke(cr);

    return surf;
}
