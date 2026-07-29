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
        _ = style;
        _ = left_peek;
        _ = right_peek;
        _ = has_left_peek;
        _ = has_right_peek;
        self.left.update(style_generation, scale, output_box, false);
        self.right.update(style_generation, scale, output_box, true);
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

    const asset_width = 160;
    const asset_height = 1397;
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
        self.regenerate(s, panel_w, panel_h, right_side);
    }

    fn regenerate(self: *Panel, scale: u32, width: i32, height: i32, right_side: bool) void {
        if (self.buffer) |buf| {
            buf.node.destroy();
            self.buffer = null;
        }

        const dest_w: i32 = width * @as(i32, @intCast(scale));
        const dest_h: i32 = height * @as(i32, @intCast(scale));
        const surface = loadAndScaleAsset(dest_w, dest_h, right_side) orelse {
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

fn loadAndScaleAsset(dest_w: i32, dest_h: i32, right_side: bool) ?*c.cairo_surface_t {
    var png_stream = PngStream{
        .data = curtain_left_tied_png,
        .offset = 0,
    };
    const source = c.cairo_image_surface_create_from_png_stream(
        @ptrCast(&readPngStream),
        @ptrCast(&png_stream),
    ) orelse return null;
    if (c.cairo_surface_status(source) != c.CAIRO_STATUS_SUCCESS) {
        c.cairo_surface_destroy(source);
        return null;
    }

    const surf = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, dest_w, dest_h) orelse {
        c.cairo_surface_destroy(source);
        return null;
    };
    const cr = c.cairo_create(surf) orelse {
        c.cairo_surface_destroy(surf);
        c.cairo_surface_destroy(source);
        return null;
    };
    defer c.cairo_destroy(cr);

    c.cairo_pattern_set_filter(c.cairo_get_source(cr), c.CAIRO_FILTER_BEST);

    const src_w = c.cairo_image_surface_get_width(source);
    const src_h = c.cairo_image_surface_get_height(source);
    const sx = @as(f64, @floatFromInt(dest_w)) / @as(f64, @floatFromInt(src_w));
    const sy = @as(f64, @floatFromInt(dest_h)) / @as(f64, @floatFromInt(src_h));

    c.cairo_save(cr);
    if (right_side) {
        c.cairo_translate(cr, @as(f64, @floatFromInt(dest_w)), 0.0);
        c.cairo_scale(cr, -1.0, 1.0);
    }
    c.cairo_scale(cr, sx, sy);
    c.cairo_set_source_surface(cr, source, 0, 0);
    c.cairo_paint(cr);
    c.cairo_restore(cr);

    c.cairo_surface_destroy(source);
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
