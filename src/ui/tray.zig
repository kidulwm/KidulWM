const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const c = @import("../dm/c.zig").c;
const style = @import("../core/style.zig");

/// Per-output geometry and scale published by the compositor host.
pub const OutputInfo = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    scale: f32,
};

/// Minimal host interface passed at init. Implementing it in server.zig
/// keeps this module free of a circular import with server.zig.
pub const TrayHost = struct {
    ctx: *anyopaque,
    output_count: *const fn (ctx: *anyopaque) usize,
    output_info: *const fn (ctx: *anyopaque, index: usize) OutputInfo,
    get_animation_kind: *const fn (ctx: *anyopaque) @import("../core/animation.zig").AnimationKind,
    cycle_animation: *const fn (ctx: *anyopaque) void,
    request_layout: *const fn (ctx: *anyopaque) void,
    theme: *const style.Style,
};

const Anchor = enum { left, right };

const PerOutput = struct {
    output_ctx: *anyopaque,
    tree: *wlr.SceneTree,
    scene_buffer: ?*wlr.SceneBuffer,
    buffer: ?*wlr.Buffer,
    info: OutputInfo,
};

pub const Tray = struct {
    allocator: std.mem.Allocator,
    host: TrayHost,
    root: *wlr.SceneTree,

    anchor: Anchor = .left,
    pinned: bool = false,
    hovered: bool = false,
    open_amount: f32 = 0.0,
    last_update_us: u64 = 0,

    outputs: std.ArrayList(PerOutput),

    const handle_width: i32 = 12;
    const full_width: i32 = 120;
    const update_rate_hz: f32 = 15.0;

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, host: TrayHost, root: *wlr.SceneTree) !Self {
        return .{
            .allocator = allocator,
            .host = host,
            .root = root,
            .outputs = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.outputs.items) |*po| {
            self.destroyPerOutput(po);
        }
        self.outputs.deinit(self.allocator);
    }

    pub fn addOutput(self: *Self, output_ctx: *anyopaque) void {
        for (self.outputs.items) |po| {
            if (po.output_ctx == output_ctx) return;
        }
        const tree = self.root.createSceneTree() catch |err| {
            std.log.err("KidulWM: failed to create tray scene tree: {}", .{err});
            return;
        };
        const po = PerOutput{
            .output_ctx = output_ctx,
            .tree = tree,
            .scene_buffer = null,
            .buffer = null,
            .info = .{ .x = 0, .y = 0, .width = 0, .height = 0, .scale = 1.0 },
        };
        self.outputs.append(self.allocator, po) catch |err| {
            std.log.err("KidulWM: failed to append tray output: {}", .{err});
            tree.node.destroy();
        };
        self.requestUpdate();
    }

    pub fn removeOutput(self: *Self, output_ctx: *anyopaque) void {
        for (self.outputs.items, 0..) |*po, i| {
            if (po.output_ctx == output_ctx) {
                self.destroyPerOutput(po);
                _ = self.outputs.orderedRemove(i);
                return;
            }
        }
    }

    fn destroyPerOutput(self: *Self, po: *PerOutput) void {
        _ = self;
        if (po.scene_buffer) |sb| sb.node.destroy();
        if (po.buffer) |buf| wlr.Buffer.drop(buf);
        po.tree.node.destroy();
        po.scene_buffer = null;
        po.buffer = null;
    }

    pub fn requestUpdate(self: *Self) void {
        self.last_update_us = 0;
    }

    pub fn update(self: *Self) void {
        const now_us = @import("../core/animation.zig").nowUs();
        defer self.last_update_us = now_us;

        // Throttle Cairo redraws to a sensible rate; position updates still happen every frame.
        const should_redraw = self.last_update_us == 0 or (now_us - self.last_update_us) > @as(u64, @intFromFloat(1_000_000.0 / update_rate_hz));

        const desired: f32 = if (self.hovered or self.pinned) 1.0 else 0.0;
        if (self.open_amount != desired) {
            const dt = if (self.last_update_us == 0) 0.0 else @as(f32, @floatFromInt(now_us - self.last_update_us)) / 1_000_000.0;
            const rate: f32 = 12.0;
            const step = std.math.clamp(dt * rate, 0.0, 1.0);
            if (desired > self.open_amount) {
                self.open_amount = @min(desired, self.open_amount + step);
            } else {
                self.open_amount = @max(desired, self.open_amount - step);
            }
        }

        // Re-sync per-output scene state and redraw if needed.
        _ = self.host.output_count(self.host.ctx);
        for (self.outputs.items) |*po| {
            // Simplification for the skeleton: assume outputs list aligns 1:1 with host outputs.
            // Refresh geometry from the host on every frame and redraw when dirty.
            self.updatePerOutput(po, now_us, should_redraw);
        }
    }

    fn updatePerOutput(self: *Self, po: *PerOutput, now_us: u64, should_redraw: bool) void {
        _ = now_us;
        const info = po.info;
        const peek_margin: f32 = @as(f32, @floatFromInt(info.width)) * 0.08;
        const max_width: i32 = @intFromFloat(@floor(@min(@as(f32, full_width), peek_margin)));
        const visible_width: i32 = @max(handle_width, @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(max_width)) * self.open_amount))));
        const x: i32 = if (self.anchor == .left) info.x else info.x + info.width - visible_width;
        const y: i32 = info.y;
        const height: i32 = info.height;

        po.tree.node.setPosition(x, y);

        if (visible_width <= 0 or height <= 0) return;
        if (!should_redraw) return;

        const dev_w: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(visible_width)) * info.scale));
        const dev_h: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(height)) * info.scale));
        const s = info.scale;

        // Create Cairo surface backed by a temporary pixel buffer.
        const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, dev_w);
        if (stride <= 0) return;
        const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(dev_h));
        const temp = self.allocator.alloc(u8, buf_size) catch |err| {
            std.log.err("KidulWM: tray buffer alloc failed: {}", .{err});
            return;
        };
        defer self.allocator.free(temp);

        const surface = c.cairo_image_surface_create_for_data(temp.ptr, c.CAIRO_FORMAT_ARGB32, dev_w, dev_h, stride);
        defer c.cairo_surface_destroy(surface);
        const cr = c.cairo_create(surface);
        defer c.cairo_destroy(cr);

        // Panel background.
        const bg = self.host.theme.color_background;
        c.cairo_set_source_rgba(cr, @as(f64, bg.r) / 255.0, @as(f64, bg.g) / 255.0, @as(f64, bg.b) / 255.0, 0.88);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_paint(cr);

        // Handle strip flush to anchored edge.
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);
        const handle_alpha: f64 = if (self.hovered or self.pinned) 0.45 else 0.18;
        const accent = self.host.theme.color_gold;
        c.cairo_set_source_rgba(cr, @as(f64, accent.r) / 255.0, @as(f64, accent.g) / 255.0, @as(f64, accent.b) / 255.0, handle_alpha);
        if (self.anchor == .left) {
            c.cairo_rectangle(cr, 0, 0, @as(f64, handle_width) * @as(f64, s), @as(f64, dev_h));
        } else {
            c.cairo_rectangle(cr, @as(f64, dev_w) - @as(f64, handle_width) * @as(f64, s), 0, @as(f64, handle_width) * @as(f64, s), @as(f64, dev_h));
        }
        c.cairo_fill(cr);

        // Animation selector button.
        if (self.open_amount > 0.5) {
            const label = switch (self.host.get_animation_kind(self.host.ctx)) {
                .snap => "Snap",
                .wobble => "Wobble",
                .ripple => "Ripple",
            };
            const btn_h: f64 = 28.0 * @as(f64, s);
            const btn_w: f64 = (@as(f64, visible_width) - 12.0) * @as(f64, s);
            const bx: f64 = 6.0 * @as(f64, s);
            const by: f64 = 48.0 * @as(f64, s);
            if (btn_w > 1 and btn_h > 1) {
                c.cairo_set_source_rgba(cr, @as(f64, accent.r) / 255.0, @as(f64, accent.g) / 255.0, @as(f64, accent.b) / 255.0, 0.22);
                c.cairo_rectangle(cr, bx, by, btn_w, btn_h);
                c.cairo_fill(cr);
                c.cairo_set_source_rgba(cr, 0.9, 0.9, 0.9, 1.0);
                c.cairo_select_font_face(cr, "sans-serif", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
                c.cairo_set_font_size(cr, 12.0 * @as(f64, s));
                const text_c = @as([*c]const u8, @ptrCast(label));
                var extents: c.cairo_text_extents_t = undefined;
                c.cairo_text_extents(cr, text_c, &extents);
                const tx = bx + (btn_w - extents.width) / 2.0;
                const ty = by + (btn_h + extents.height) / 2.0;
                c.cairo_move_to(cr, tx, ty);
                c.cairo_show_text(cr, text_c);
            }
        }

        // Replace the scene buffer for this output.
        const db_stride: i32 = @intCast(stride);
        const DataBuffer = @import("../render/buffer.zig").DataBuffer;
        const buffer = DataBuffer.create(temp, dev_w, dev_h, db_stride) catch |err| {
            std.log.err("KidulWM: failed to create tray buffer: {}", .{err});
            return;
        };
        if (po.buffer) |old| wlr.Buffer.drop(old);
        po.buffer = buffer;
        if (po.scene_buffer) |old| old.node.destroy();
        const sb = po.tree.createSceneBuffer(buffer) catch |err| {
            std.log.err("KidulWM: failed to create tray scene buffer: {}", .{err});
            wlr.Buffer.drop(buffer);
            po.buffer = null;
            return;
        };
        sb.setDestSize(visible_width, height);
        po.scene_buffer = sb;
        po.tree.node.raiseToTop();
    }

    fn visibleWidth(self: *const Self, info: OutputInfo) i32 {
        const peek_margin: f32 = @as(f32, @floatFromInt(info.width)) * 0.08;
        const max_width: i32 = @intFromFloat(@floor(@min(@as(f32, full_width), peek_margin)));
        return @max(handle_width, @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(max_width)) * self.open_amount))));
    }

    pub fn handlePointerMove(self: *Self, x: f64, y: f64) bool {
        const out_count = self.host.output_count(self.host.ctx);
        var inside_any = false;
        for (0..out_count) |i| {
            const info = self.host.output_info(self.host.ctx, i);
            const vw = self.visibleWidth(info);
            const min_x: f64 = if (self.anchor == .left) @floatFromInt(info.x) else @floatFromInt(info.x + info.width - vw);
            const max_x: f64 = if (self.anchor == .left) @floatFromInt(info.x + vw) else @floatFromInt(info.x + info.width);
            const min_y: f64 = @floatFromInt(info.y);
            const max_y: f64 = @floatFromInt(info.y + info.height);
            if (x >= min_x and x < max_x and y >= min_y and y < max_y) {
                inside_any = true;
            }
            // Update stored info from host so the tray tracks live output geometry.
            if (i < self.outputs.items.len) {
                self.outputs.items[i].info = info;
            }
        }
        self.hovered = inside_any;
        return inside_any;
    }

    pub fn handlePointerClick(self: *Self, x: f64, y: f64) bool {
        const out_count = self.host.output_count(self.host.ctx);
        var inside = false;
        var output_index: usize = 0;
        for (0..out_count) |i| {
            const info = self.host.output_info(self.host.ctx, i);
            const vw = self.visibleWidth(info);
            const min_x: f64 = if (self.anchor == .left) @floatFromInt(info.x) else @floatFromInt(info.x + info.width - vw);
            const max_x: f64 = if (self.anchor == .left) @floatFromInt(info.x + vw) else @floatFromInt(info.x + info.width);
            const min_y: f64 = @floatFromInt(info.y);
            const max_y: f64 = @floatFromInt(info.y + info.height);
            if (x >= min_x and x < max_x and y >= min_y and y < max_y) {
                inside = true;
                output_index = i;
            }
            if (i < self.outputs.items.len) self.outputs.items[i].info = info;
        }
        if (!inside) {
            if (self.pinned) {
                self.pinned = false;
                self.hovered = false;
                return true;
            }
            return false;
        }

        const info = self.host.output_info(self.host.ctx, output_index);
        // If open enough, check for selector button click.
        if (self.open_amount > 0.5 and self.isInSelectorButton(x, y, info)) {
            self.host.cycle_animation(self.host.ctx);
            return true;
        }

        // Click on the tray toggles pin.
        self.pinned = !self.pinned;
        return true;
    }

    fn isInSelectorButton(self: *const Self, x: f64, y: f64, info: OutputInfo) bool {
        const vw_i = self.visibleWidth(info);
        const vw: f64 = @floatFromInt(vw_i);
        const scale: f64 = @as(f64, info.scale);
        const btn_x = 6.0 * scale;
        const btn_y = 48.0 * scale;
        const btn_w = (vw - 12.0) * scale;
        const btn_h = 28.0 * scale;
        const local_x = if (self.anchor == .left) x - @as(f64, @floatFromInt(info.x)) else @as(f64, @floatFromInt(info.x + info.width)) - x;
        const local_y = y - @as(f64, @floatFromInt(info.y));
        return local_x >= btn_x and local_x <= btn_x + btn_w and local_y >= btn_y and local_y <= btn_y + btn_h;
    }
};
