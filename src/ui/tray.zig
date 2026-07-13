const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const c = @import("../dm/c.zig").c;
const style = @import("../core/style.zig");

pub const OutputInfo = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    scale: f32,
};

pub const TrayHost = struct {
    ctx: *anyopaque,
    output_count: *const fn (ctx: *anyopaque) usize,
    output_info: *const fn (ctx: *anyopaque, index: usize) OutputInfo,
    get_animation_kind: *const fn (ctx: *anyopaque) @import("../core/animation.zig").AnimationKind,
    cycle_animation: *const fn (ctx: *anyopaque) void,
    request_layout: *const fn (ctx: *anyopaque) void,
    theme: *const style.Style,
};

const Item = struct {
    id: []const u8,
    label: []const u8,
    icon_char: u8,
    preview_line: []const u8,
};

const ItemKind = enum { normal, toggle };
const TrayItem = struct {
    item: Item,
    kind: ItemKind = .normal,
    action: Action,
};

const Action = union(enum) {
    cycle_animation,
    toggle_tray,
    none,
};

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

    pinned: bool = false,
    hovered: bool = false,
    open_amount: f32 = 0.0,
    selected_index: usize = 0,
    hover_index: ?usize = null,
    last_update_us: u64 = 0,

    outputs: std.ArrayList(PerOutput),
    items: []const TrayItem,

    const panel_width: i32 = 120;
    const item_height: i32 = 56;
    const handle_height: i32 = 12;
    const preview_height: i32 = 90;
    const update_rate_hz: f32 = 30.0;
    const slide_rate: f32 = 14.0;

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, host: TrayHost, root: *wlr.SceneTree) !Self {
        const items = try allocator.alloc(TrayItem, 5);
        items[0] = .{
            .item = .{ .id = "weather", .label = "Weather", .icon_char = 'W', .preview_line = "22 C / cloudy" },
            .action = .none,
        };
        items[1] = .{
            .item = .{ .id = "vol", .label = "Volume", .icon_char = 'V', .preview_line = "50%" },
            .action = .none,
        };
        items[2] = .{
            .item = .{ .id = "bri", .label = "Brightness", .icon_char = 'B', .preview_line = "80%" },
            .action = .none,
        };
        items[3] = .{
            .item = .{ .id = "anim", .label = "Motion", .icon_char = 'M', .preview_line = "snap" },
            .action = .cycle_animation,
        };
        items[4] = .{
            .item = .{ .id = "hide", .label = "Hide", .icon_char = 'x', .preview_line = "close dock" },
            .action = .toggle_tray,
        };
        return .{
            .allocator = allocator,
            .host = host,
            .root = root,
            .outputs = .empty,
            .items = items,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.outputs.items) |*po| self.destroyPerOutput(po);
        self.outputs.deinit(self.allocator);
        self.allocator.free(self.items);
    }

    pub fn addOutput(self: *Self, output_ctx: *anyopaque) void {
        for (self.outputs.items) |po| if (po.output_ctx == output_ctx) return;
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

    pub fn toggle(self: *Self) void {
        self.pinned = !self.pinned;
        self.hovered = self.pinned;
        self.requestUpdate();
        self.host.request_layout(self.host.ctx);
        if (!self.pinned) self.hover_index = null;
        std.log.info("KidulWM: tray toggled -> {}", .{self.pinned});
    }

    pub fn selectNext(self: *Self) void {
        if (!self.isOpen()) return;
        self.selected_index = (self.selected_index + 1) % self.items.len;
        self.hover_index = self.selected_index;
        self.requestUpdate();
    }

    pub fn selectPrev(self: *Self) void {
        if (!self.isOpen()) return;
        if (self.selected_index == 0) {
            self.selected_index = self.items.len - 1;
        } else {
            self.selected_index -= 1;
        }
        self.hover_index = self.selected_index;
        self.requestUpdate();
    }

    pub fn activateSelected(self: *Self) void {
        if (!self.isOpen()) {
            self.toggle();
            return;
        }
        self.activateItem(self.selected_index);
    }

    pub fn isOpen(self: *const Self) bool {
        return self.pinned or self.open_amount > 0.5;
    }

    fn activateItem(self: *Self, index: usize) void {
        if (index >= self.items.len) return;
        const it = &self.items[index];
        std.log.info("KidulWM: tray activate {s}", .{it.item.id});
        switch (it.action) {
            .cycle_animation => self.host.cycle_animation(self.host.ctx),
            .toggle_tray => self.toggle(),
            .none => {},
        }
        // Later: spawn apps, adjust volume/brightness, etc.
    }

    pub fn update(self: *Self) void {
        const now_us = @import("../core/animation.zig").nowUs();
        const prev = self.last_update_us;
        defer self.last_update_us = now_us;

        const should_redraw = prev == 0 or (now_us - prev) > @as(u64, @intFromFloat(1_000_000.0 / update_rate_hz));

        // Preview labels can be updated here in the future; layout-time mutation
        // of comptime strings is avoided.

        const desired: f32 = if (self.hovered or self.pinned) 1.0 else 0.0;
        if (self.open_amount != desired) {
            const dt = if (prev == 0) 0.0 else @as(f32, @floatFromInt(now_us - prev)) / 1_000_000.0;
            const step = std.math.clamp(dt * slide_rate, 0.0, 1.0);
            if (desired > self.open_amount) {
                self.open_amount = @min(desired, self.open_amount + step);
            } else {
                self.open_amount = @max(desired, self.open_amount - step);
            }
        }

        _ = self.host.output_count(self.host.ctx);
        for (self.outputs.items) |*po| {
            self.updatePerOutput(po, should_redraw);
        }
    }

    fn visibleHeight(self: *const Self) i32 {
        const needed = self.items.len * item_height + handle_height + 16;
        return @max(handle_height, @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(needed)) * self.open_amount))));
    }

    fn updatePerOutput(self: *Self, po: *PerOutput, should_redraw: bool) void {
        const info = po.info;
        const h = self.visibleHeight();
        const w = panel_width;
        const x: i32 = info.x;
        const y: i32 = info.y + info.height - h;
        const s = info.scale;

        po.tree.node.setPosition(x, y);

        if (w <= 0 or h <= 0) return;
        if (!should_redraw) return;

        const dev_w: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(w)) * s));
        const dev_h: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(h)) * s));

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
        const cr = c.cairo_create(surface) orelse {
            std.log.err("KidulWM: failed to create cairo context for tray", .{});
            return;
        };
        defer c.cairo_destroy(cr);

        const scale_d: f64 = @as(f64, s);
        const panel_h = @as(f64, dev_h);

        // Background.
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);

        const bg = self.host.theme.color_background;
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);
        c.cairo_set_source_rgba(cr, @as(f64, bg.r) / 255.0, @as(f64, bg.g) / 255.0, @as(f64, bg.b) / 255.0, 0.85);
        c.cairo_rectangle(cr, 0, 0, @as(f64, dev_w), panel_h - @as(f64, handle_height) * scale_d);
        c.cairo_fill(cr);

        // Glassy dock border line on the right edge.
        const border = self.host.theme.color_border;
        c.cairo_set_source_rgba(cr, @as(f64, border.r) / 255.0, @as(f64, border.g) / 255.0, @as(f64, border.b) / 255.0, 0.55);
        c.cairo_set_line_width(cr, 2.0 * scale_d);
        c.cairo_move_to(cr, @as(f64, dev_w) - 1.0 * scale_d, 0);
        c.cairo_line_to(cr, @as(f64, dev_w) - 1.0 * scale_d, panel_h - @as(f64, handle_height) * scale_d);
        c.cairo_stroke(cr);

        // Items.
        if (self.open_amount > 0.1) {
            const cell_h_f: f64 = @as(f64, item_height) * scale_d;
            for (self.items, 0..) |it, idx| {
                const iy = @as(f64, @floatFromInt(idx)) * cell_h_f + 6.0 * scale_d;
                const selected = self.selected_index == idx;
                const hover = if (self.hover_index) |hi| hi == idx else false;
                self.drawItem(cr, @as(f64, dev_w), cell_h_f, iy, it, selected, hover, scale_d);
                if (hover and self.open_amount > 0.8) {
                    self.drawPreview(cr, @as(f64, dev_w), iy, it, scale_d);
                }
            }
        }

        // Bottom handle strip.
        const accent = self.host.theme.color_gold;
        const handle_alpha: f64 = if (self.hovered or self.pinned) 0.5 else 0.22;
        c.cairo_set_source_rgba(cr, @as(f64, accent.r) / 255.0, @as(f64, accent.g) / 255.0, @as(f64, accent.b) / 255.0, handle_alpha);
        c.cairo_rectangle(cr, 0, panel_h - @as(f64, handle_height) * scale_d, @as(f64, dev_w), @as(f64, handle_height) * scale_d);
        c.cairo_fill(cr);

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
        sb.setDestSize(w, h);
        po.scene_buffer = sb;
        po.tree.node.raiseToTop();
    }

    fn drawItem(self: *const Self, cr: *c.cairo_t, dev_w: f64, cell_h: f64, y: f64, it: TrayItem, selected: bool, hover: bool, s: f64) void {
        _ = self;
        const margin: f64 = 6.0 * s;
        const cell_w: f64 = dev_w - 2.0 * margin;
        const r: f64 = 8.0 * s;

        if (selected or hover) {
            c.cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, if (hover) 0.18 else 0.10);
            roundedRect(cr, margin, y, cell_w, cell_h - 4.0 * s, r);
            c.cairo_fill(cr);
        }

        const icon_size: f64 = 22.0 * s;
        const ix = margin + 8.0 * s;
        const iy = y + (cell_h - icon_size) / 2.0;

        // Glassy icon backing.
        roundedRect(cr, ix, iy, icon_size, icon_size, 5.0 * s);
        c.cairo_set_source_rgba(cr, 0.18, 0.52, 0.78, 0.60);
        c.cairo_fill(cr);
        c.cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.75);
        c.cairo_set_line_width(cr, 1.0 * s);
        roundedRect(cr, ix, iy, icon_size, icon_size, 5.0 * s);
        c.cairo_stroke(cr);

        // Icon glyph.
        c.cairo_set_source_rgba(cr, 0.95, 0.95, 0.95, 1.0);
        c.cairo_select_font_face(cr, "sans-serif", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
        c.cairo_set_font_size(cr, 13.0 * s);
        var extents: c.cairo_text_extents_t = undefined;
        const glyph_c: [*c]const u8 = @ptrCast(&it.item.icon_char);
        c.cairo_text_extents(cr, glyph_c, &extents);
        const gx = ix + (icon_size - extents.width) / 2.0;
        const gy = iy + (icon_size + extents.height) / 2.0;
        c.cairo_move_to(cr, gx, gy);
        c.cairo_show_text(cr, glyph_c);

        // Label.
        c.cairo_set_source_rgba(cr, 0.9, 0.9, 0.9, 1.0);
        c.cairo_select_font_face(cr, "sans-serif", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
        c.cairo_set_font_size(cr, 11.0 * s);
        const text_c: [*c]const u8 = @ptrCast(it.item.label);
        c.cairo_text_extents(cr, text_c, &extents);
        const tx = ix + icon_size + 8.0 * s;
        const ty = y + (cell_h + extents.height) / 2.0;
        c.cairo_move_to(cr, tx, ty);
        c.cairo_show_text(cr, text_c);
    }

    fn drawPreview(self: *const Self, cr: *c.cairo_t, dev_w: f64, item_y: f64, it: TrayItem, s: f64) void {
        const line = if (it.action == .cycle_animation)
            switch (self.host.get_animation_kind(self.host.ctx)) {
                .snap => "snap",
                .wobble => "wobble",
                .ripple => "ripple",
            }
        else
            it.item.preview_line;
        const pw: f64 = 170.0 * s;
        const ph: f64 = 70.0 * s;
        const px: f64 = dev_w + 10.0 * s;
        const py: f64 = item_y;
        roundedRect(cr, px, py, pw, ph, 8.0 * s);
        c.cairo_set_source_rgba(cr, 0.06, 0.06, 0.08, 0.92);
        c.cairo_fill(cr);
        c.cairo_set_source_rgba(cr, 0.9, 0.9, 0.9, 1.0);
        c.cairo_select_font_face(cr, "sans-serif", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
        c.cairo_set_font_size(cr, 12.0 * s);
        const line_c: [*c]const u8 = @ptrCast(line);
        var extents: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, line_c, &extents);
        const tx = px + (pw - extents.width) / 2.0;
        const ty = py + (ph + extents.height) / 2.0;
        c.cairo_move_to(cr, tx, ty);
        c.cairo_show_text(cr, line_c);
    }

    fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
        const radius = @min(r, w / 2.0, h / 2.0);
        c.cairo_new_sub_path(cr);
        c.cairo_arc(cr, x + w - radius, y + radius, radius, -std.math.pi / 2.0, 0);
        c.cairo_arc(cr, x + w - radius, y + h - radius, radius, 0, std.math.pi / 2.0);
        c.cairo_arc(cr, x + radius, y + h - radius, radius, std.math.pi / 2.0, std.math.pi);
        c.cairo_arc(cr, x + radius, y + radius, radius, std.math.pi, -std.math.pi / 2.0);
        c.cairo_close_path(cr);
    }

    pub fn handlePointerMove(self: *Self, x: f64, y: f64) bool {
        const out_count = self.host.output_count(self.host.ctx);
        var inside_any = false;
        self.hover_index = null;
        for (0..out_count) |i| {
            const info = self.host.output_info(self.host.ctx, i);
            const h = self.visibleHeight();
            const min_x: f64 = @floatFromInt(info.x);
            const max_x: f64 = @floatFromInt(info.x + panel_width);
            const min_y: f64 = @floatFromInt(info.y + info.height - h);
            const max_y: f64 = @floatFromInt(info.y + info.height);
            if (i < self.outputs.items.len) self.outputs.items[i].info = info;
            if (x >= min_x and x < max_x and y >= min_y and y < max_y) {
                inside_any = true;
                const local_y = y - min_y;
                const idx = @as(usize, @intFromFloat(@floor(local_y / @as(f64, item_height))));
                if (idx < self.items.len) self.hover_index = idx;
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
            const h = self.visibleHeight();
            const min_x: f64 = @floatFromInt(info.x);
            const max_x: f64 = @floatFromInt(info.x + panel_width);
            const min_y: f64 = @floatFromInt(info.y + info.height - h);
            const max_y: f64 = @floatFromInt(info.y + info.height);
            if (i < self.outputs.items.len) self.outputs.items[i].info = info;
            if (x >= min_x and x < max_x and y >= min_y and y < max_y) {
                inside = true;
                output_index = i;
            }
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
        const h = self.visibleHeight();
        const local_y = y - @as(f64, @floatFromInt(info.y + info.height - h));
        const idx: usize = @intFromFloat(@floor(local_y / @as(f64, item_height)));
        if (idx < self.items.len) {
            if (self.pinned) {
                self.selected_index = idx;
                self.activateItem(idx);
            } else {
                self.toggle();
            }
        } else {
            self.toggle();
        }
        return true;
    }
};
