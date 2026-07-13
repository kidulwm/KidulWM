const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const c = @import("../dm/c.zig").c;
const style = @import("../core/style.zig");
const animation = @import("../core/animation.zig");

pub const OutputInfo = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    scale: f32,
    focus_left: i32,
};

pub const TrayHost = struct {
    ctx: *anyopaque,
    output_count: *const fn (ctx: *anyopaque) usize,
    output_info: *const fn (ctx: *anyopaque, index: usize) OutputInfo,
    get_animation_kind: *const fn (ctx: *anyopaque) animation.AnimationKind,
    cycle_animation: *const fn (ctx: *anyopaque) void,
    request_frame: *const fn (ctx: *anyopaque) void,
    theme: *const style.Style,
};

const Action = union(enum) {
    cycle_animation,
    toggle_tray,
    next_animation,
    spawn: []const u8,
    none,
};

const TrayItem = struct {
    id: []const u8,
    label: []const u8,
    action: Action,
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

    open: bool = false,
    pinned: bool = false,
    hovered: bool = false,
    open_amount: f32 = 0.0,
    selected_index: usize = 0,
    hover_index: ?usize = null,
    scroll_offset: f32 = 0.0,
    last_update_us: u64 = 0,

    outputs: std.ArrayList(PerOutput),
    items: []const TrayItem,

    const button_height: i32 = 44;
    const button_gap: i32 = 8;
    const hmargin: i32 = 8;
    const bottom_margin: i32 = 10;
    const top_margin: i32 = 10;
    const max_stack_items_visible: usize = 12;
    const update_rate_hz: f32 = 30.0;
    const slide_rate: f32 = 16.0;

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, host: TrayHost, root: *wlr.SceneTree) !Self {
        const items = try allocator.alloc(TrayItem, 6);
        items[0] = .{ .id = "settings", .label = "Settings", .action = .toggle_tray };
        items[1] = .{ .id = "term", .label = "Terminal", .action = .{ .spawn = "" } };
        items[2] = .{ .id = "files", .label = "Files", .action = .{ .spawn = "" } };
        items[3] = .{ .id = "browser", .label = "Browser", .action = .{ .spawn = "" } };
        items[4] = .{ .id = "anim", .label = "Motion", .action = .cycle_animation };
        items[5] = .{ .id = "hide", .label = "Hide", .action = .toggle_tray };
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
            .info = .{ .x = 0, .y = 0, .width = 0, .height = 0, .scale = 1.0, .focus_left = 0 },
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

    fn destroyPerOutput(_: *Self, po: *PerOutput) void {
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
        self.open = !self.open;
        self.pinned = self.open;
        self.hovered = self.open;
        self.scroll_offset = 0.0;
        if (!self.open) self.hover_index = null;
        self.requestUpdate();
        self.host.request_frame(self.host.ctx);
    }

    pub fn selectNext(self: *Self) void {
        if (!self.isOpen()) {
            self.toggle();
            return;
        }
        self.selected_index = (self.selected_index + 1) % self.items.len;
        self.hover_index = self.selected_index;
        self.ensureSelectedVisible();
        self.requestUpdate();
    }

    pub fn selectPrev(self: *Self) void {
        if (!self.isOpen()) {
            self.toggle();
            return;
        }
        if (self.selected_index == 0) {
            self.selected_index = self.items.len - 1;
        } else {
            self.selected_index -= 1;
        }
        self.hover_index = self.selected_index;
        self.ensureSelectedVisible();
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
        return self.open or self.open_amount > 0.01;
    }

    pub fn scroll(self: *Self, delta: f32) void {
        if (!self.isOpen()) return;
        const max_scroll = self.maxScroll();
        self.scroll_offset = std.math.clamp(self.scroll_offset - delta, 0.0, max_scroll);
        self.requestUpdate();
    }

    fn ensureSelectedVisible(self: *Self) void {
        const visible_count = @min(max_stack_items_visible, self.items.len - 1);
        if (visible_count == 0) return;
        const item_size: f32 = @floatFromInt(button_height + button_gap);
        const first_in_stack = self.selected_index;
        if (first_in_stack == 0) {
            self.scroll_offset = 0.0;
            return;
        }
        const max_visible_first: f32 = @floatFromInt(self.items.len -| visible_count);
        const desired_first: f32 = @max(@as(f32, @floatFromInt(first_in_stack -| visible_count)) + 1.0, 0.0);
        const desired_offset: f32 = @min(desired_first, max_visible_first) * item_size;
        self.scroll_offset = desired_offset;
    }

    fn maxScroll(self: *const Self) f32 {
        const stack_count = self.items.len -| 1;
        const needed_items = @min(max_stack_items_visible, stack_count);
        const item_size: f32 = @floatFromInt(button_height + button_gap);
        const stack_h = @as(f32, @floatFromInt(stack_count)) * item_size - @as(f32, @floatFromInt(button_gap));
        const view_h = @as(f32, @floatFromInt(needed_items)) * item_size - @as(f32, @floatFromInt(button_gap));
        return @max(0.0, stack_h - view_h);
    }

    fn activateItem(self: *Self, index: usize) void {
        if (index >= self.items.len) return;
        const it = &self.items[index];
        std.log.info("KidulWM: tray activate {s}", .{it.id});
        switch (it.action) {
            .cycle_animation => self.host.cycle_animation(self.host.ctx),
            .next_animation => {
                var k: u8 = 0;
                while (k < 1) : (k += 1) self.host.cycle_animation(self.host.ctx);
            },
            .toggle_tray => self.toggle(),
            .spawn => {},
            .none => {},
        }
    }

    pub fn update(self: *Self) void {
        const now_us = animation.nowUs();
        const prev = self.last_update_us;
        defer self.last_update_us = now_us;

        const should_redraw = prev == 0 or (now_us - prev) > @as(u64, @intFromFloat(1_000_000.0 / update_rate_hz));

        const desired: f32 = if (self.open or self.pinned or self.hovered) 1.0 else 0.0;
        if (self.open_amount != desired) {
            const dt = if (prev == 0) 0.0 else @as(f32, @floatFromInt(now_us - prev)) / 1_000_000.0;
            const step = std.math.clamp(dt * slide_rate, 0.0, 1.0);
            if (desired > self.open_amount) {
                self.open_amount = @min(desired, self.open_amount + step);
            } else {
                self.open_amount = @max(desired, self.open_amount - step);
            }
        }

        for (self.outputs.items) |*po| {
            self.updatePerOutput(po, should_redraw);
        }
    }

    fn panelWidth(self: *const Self, info: OutputInfo) i32 {
        _ = self;
        const base = info.focus_left - info.x;
        return @max(80, base - 2 * hmargin);
    }

    fn panelHeightFor(self: *const Self, info: OutputInfo, stack_open_amount: f32) i32 {
        const stack_count = self.items.len -| 1;
        const visible_items = @min(max_stack_items_visible, stack_count);
        const item_size = button_height + button_gap;
        const max_stack_h = @min(
            info.height - top_margin - bottom_margin - button_height,
            @as(i32, @intCast(visible_items)) * item_size - button_gap,
        );
        const actual_stack_h: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(max_stack_h)) * stack_open_amount));
        return button_height + bottom_margin + actual_stack_h;
    }

    fn totalStackHeight(self: *const Self) i32 {
        const count = @as(i32, @intCast(self.items.len -| 1));
        if (count <= 0) return 0;
        return count * (button_height + button_gap) - button_gap;
    }

    fn updatePerOutput(self: *Self, po: *PerOutput, should_redraw: bool) void {
        const info = po.info;
        const s = info.scale;
        const w = self.panelWidth(info);
        const h = self.panelHeightFor(info, self.open_amount);
        const x: i32 = info.x + hmargin;
        const y: i32 = info.y + info.height - h;

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
        const bw: f64 = @as(f64, dev_w);
        const bh: f64 = @as(f64, button_height) * scale_d;
        const gap: f64 = @as(f64, button_gap) * scale_d;

        // Transparent background.
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        const settings_top: f64 = @as(f64, dev_h) - bh - @as(f64, bottom_margin) * scale_d;
        const item_size = bh + gap;

        // Settings button is always index 0 and sits at the bottom.
        self.drawButton(cr, 0.0, settings_top, bw, bh, self.items[0], self.selected_index == 0, self.hover_index == 0, scale_d);

        if (self.open_amount > 0.01 and self.items.len > 1) {
            const scroll_px: f64 = @floor(@as(f64, self.scroll_offset) * scale_d);
            for (self.items[1..], 1..) |it, idx| {
                const i: f64 = @floatFromInt(idx);
                const top = settings_top - i * item_size + scroll_px;
                if (top + bh < 0.0 or top > @as(f64, dev_h)) continue;
                self.drawButton(cr, 0.0, top, bw, bh, it, self.selected_index == idx, self.hover_index == idx, scale_d);
            }
        }

        const DataBuffer = @import("../render/buffer.zig").DataBuffer;
        const buffer = DataBuffer.create(temp, dev_w, dev_h, @intCast(stride)) catch |err| {
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

    fn drawButton(self: *const Self, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, it: TrayItem, selected: bool, hover: bool, s: f64) void {
        const r: f64 = 6.0 * s;
        const accent_bright = self.host.theme.color_gold;
        const accent_dim = self.host.theme.color_gold_dim;

        // Black glass button fill.
        roundedRect(cr, x + 1.0 * s, y + 1.0 * s, w - 2.0 * s, h - 2.0 * s, r);
        c.cairo_set_source_rgba(cr, 0.04, 0.04, 0.05, 0.92);
        c.cairo_fill(cr);

        // Border / raised effect on hover/selection.
        const border_alpha: f64 = if (hover or selected) 0.70 else 0.35;
        const gold = if (hover or selected) accent_bright else accent_dim;
        c.cairo_set_source_rgba(cr, @as(f64, gold.r) / 255.0, @as(f64, gold.g) / 255.0, @as(f64, gold.b) / 255.0, border_alpha);
        c.cairo_set_line_width(cr, if (hover or selected) 1.8 * s else 1.2 * s);
        roundedRect(cr, x + 1.0 * s, y + 1.0 * s, w - 2.0 * s, h - 2.0 * s, r);
        c.cairo_stroke(cr);

        // Gold text label.
        const label_c: [*c]const u8 = @ptrCast(it.label);
        var extents: c.cairo_text_extents_t = undefined;
        c.cairo_select_font_face(cr, "serif", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
        c.cairo_set_font_size(cr, 13.0 * s);
        c.cairo_text_extents(cr, label_c, &extents);
        c.cairo_set_source_rgba(cr, @as(f64, gold.r) / 255.0, @as(f64, gold.g) / 255.0, @as(f64, gold.b) / 255.0, 1.0);
        const tx = x + (w - extents.width) / 2.0;
        const ty = y + (h + extents.height) / 2.0;
        c.cairo_move_to(cr, tx, ty);
        c.cairo_show_text(cr, label_c);
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

    fn pointInside(self: *const Self, info: OutputInfo, px: f64, py: f64) bool {
        const w = self.panelWidth(info);
        const h = self.panelHeightFor(info, self.open_amount);
        const x: f64 = @floatFromInt(info.x + hmargin);
        const y: f64 = @floatFromInt(info.y + info.height - h);
        return px >= x and px < x + @as(f64, @floatFromInt(w)) and py >= y and py < y + @as(f64, @floatFromInt(h));
    }

    pub fn handlePointerMove(self: *Self, px: f64, py: f64) bool {
        const out_count = self.host.output_count(self.host.ctx);
        var inside_any = false;
        var new_hover: ?usize = null;
        for (0..out_count) |i| {
            const info = self.host.output_info(self.host.ctx, i);
            if (i < self.outputs.items.len) self.outputs.items[i].info = info;
            if (!self.pointInside(info, px, py)) continue;
            inside_any = true;
            // local coordinates relative to top-left of tree
            const local_y = py - @as(f64, @floatFromInt(info.y + info.height - self.panelHeightFor(info, self.open_amount)));
            const bh: f64 = @as(f64, button_height) * info.scale;
            const gap: f64 = @as(f64, button_gap) * info.scale;
            const settings_top: f64 = @as(f64, self.panelHeightFor(info, self.open_amount) - bottom_margin) * info.scale - bh;
            const scroll_px: f64 = self.scroll_offset * info.scale;
            if (local_y >= settings_top and local_y < settings_top + bh) {
                new_hover = 0;
            } else if (local_y < settings_top and self.items.len > 1) {
                const dist = settings_top - local_y + scroll_px;
                const idx: usize = @as(usize, @intFromFloat(@floor(dist / (bh + gap)))) + 1;
                if (idx < self.items.len) new_hover = idx;
            }
        }
        self.hovered = inside_any;
        if (new_hover) |hi| self.hover_index = hi;
        if (inside_any and !self.open and !self.pinned) {
            self.open = true;
            self.requestUpdate();
            self.host.request_frame(self.host.ctx);
        } else if (!inside_any and self.open and !self.pinned) {
            self.open = false;
            self.hover_index = null;
            self.requestUpdate();
            self.host.request_frame(self.host.ctx);
        }
        return inside_any;
    }

    pub fn handlePointerClick(self: *Self, px: f64, py: f64) bool {
        const out_count = self.host.output_count(self.host.ctx);
        var inside = false;
        var output_index: usize = 0;
        for (0..out_count) |i| {
            const info = self.host.output_info(self.host.ctx, i);
            if (i < self.outputs.items.len) self.outputs.items[i].info = info;
            if (self.pointInside(info, px, py)) {
                inside = true;
                output_index = i;
            }
        }
        if (!inside) {
            if (self.pinned) {
                self.pinned = false;
                self.open = false;
                self.hovered = false;
                self.hover_index = null;
                self.requestUpdate();
                self.host.request_frame(self.host.ctx);
            }
            return self.pinned;
        }

        const info = self.host.output_info(self.host.ctx, output_index);
        const local_y = py - @as(f64, @floatFromInt(info.y + info.height - self.panelHeightFor(info, self.open_amount)));
        const bh: f64 = @as(f64, button_height) * info.scale;
        const settings_top: f64 = @as(f64, self.panelHeightFor(info, self.open_amount) - bottom_margin) * info.scale - bh;
        const scroll_px: f64 = self.scroll_offset * info.scale;
        var idx: usize = 0;
        if (local_y < settings_top) {
            const dist = settings_top - local_y + scroll_px;
            idx = @as(usize, @intFromFloat(@floor(dist / (bh + @as(f64, button_gap) * info.scale)))) + 1;
            if (idx >= self.items.len) idx = 0;
        }
        self.selected_index = idx;
        self.hover_index = idx;
        self.activateItem(idx);
        return true;
    }
};
