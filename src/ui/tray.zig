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
    icon: ?[]const u8 = null,
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
    bottom_activated: bool = false,

    outputs: std.ArrayList(PerOutput),
    items: []const TrayItem,
    icon_cache: std.StringHashMap(*c.cairo_surface_t),

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
        const items = try allocator.alloc(TrayItem, 5);
        items[0] = .{ .id = "all-things", .label = "All The Things", .action = .toggle_tray };
        items[1] = .{ .id = "term", .label = "Terminal", .action = .{ .spawn = "" } };
        items[2] = .{ .id = "files", .label = "Files", .action = .{ .spawn = "" } };
        items[3] = .{ .id = "browser", .label = "Browser", .action = .{ .spawn = "" } };
        items[4] = .{ .id = "anim", .label = "Motion", .action = .cycle_animation };
        return .{
            .allocator = allocator,
            .host = host,
            .root = root,
            .outputs = .empty,
            .items = items,
            .icon_cache = std.StringHashMap(*c.cairo_surface_t).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.outputs.items) |*po| self.destroyPerOutput(po);
        self.outputs.deinit(self.allocator);
        var it = self.icon_cache.iterator();
        while (it.next()) |entry| {
            c.cairo_surface_destroy(entry.value_ptr.*);
        }
        self.icon_cache.deinit();
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
        // Synchronously draw the tray once so the buffer exists before the first
        // output frame. This avoids the tray popping in after the background.
        self.update();
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
        if (self.selected_index < self.items.len - 1) {
            self.selected_index += 1;
        }
        self.hover_index = self.selected_index;
        self.ensureSelectedVisible();
        self.requestUpdate();
    }

    pub fn selectPrev(self: *Self) void {
        if (!self.isOpen()) {
            self.toggle();
            return;
        }
        if (self.selected_index > 1) {
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
        const max_scroll = self.maxScroll();
        if (max_scroll <= 0.0) {
            self.scroll_offset = 0.0;
            return;
        }
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
        self.scroll_offset = std.math.clamp(desired_offset, 0.0, max_scroll);
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
            .toggle_tray => {
                if (index == 0 and !self.bottom_activated) {
                    self.bottom_activated = true;
                    self.open = true;
                    self.pinned = true;
                    self.hovered = true;
                    self.selected_index = 0;
                    self.hover_index = 0;
                    self.requestUpdate();
                    self.host.request_frame(self.host.ctx);
                } else {
                    self.toggle();
                }
            },
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

        if (self.open_amount <= 0.01 and self.bottom_activated) {
            self.bottom_activated = false;
        }

        for (self.outputs.items, 0..) |*po, i| {
            // Refresh output geometry before drawing; pointer events handle this
            // otherwise, but on boot the first draw may happen before any input.
            po.info = self.host.output_info(self.host.ctx, i);
            self.updatePerOutput(po, should_redraw);
        }
    }

    fn panelWidth(self: *const Self, info: OutputInfo) i32 {
        _ = self;
        const base = info.focus_left - info.x;
        return @max(80, base);
    }


    fn panelHeightFor(self: *const Self, info: OutputInfo, stack_open_amount: f32) i32 {
        const stack_count = self.items.len -| 1;
        const visible_items = @min(max_stack_items_visible, stack_count);
        const item_size = button_height + button_gap;
        // Reserve a full button row as a buffer between the bottom button and the stack.
        const stack_buffer = item_size;
        const max_stack_h = @min(
            info.height - top_margin - bottom_margin - button_height,
            @as(i32, @intCast(visible_items)) * item_size - button_gap + stack_buffer,
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
        const x: i32 = info.x;
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

        // Bottom slot shows "All The Things" when closed, "Hide" when open.
        const bottom_focused = self.open_amount > 0.01 and (self.selected_index == 0 or self.hover_index == 0);
        var bottom_item = self.items[0];
        if (self.bottom_activated and self.open_amount > 0.01) {
            bottom_item.label = "Hide";
        }
        self.drawButton(cr, 0.0, settings_top, bw, bh, bottom_item, bottom_focused, scale_d);

        // Stack items sit one full row above the bottom button, never overlapping it.
        const stack_origin: f64 = settings_top - item_size;

        if (self.open_amount > 0.01 and self.items.len > 1) {
            const scroll_px: f64 = @floor(@as(f64, self.scroll_offset) * scale_d);
            for (self.items[1..], 1..) |it, idx| {
                const i: f64 = @floatFromInt(idx);
                const top = stack_origin - i * item_size + scroll_px;
                if (top + bh < 0.0 or top >= stack_origin) continue;
                const focused = self.selected_index == idx or self.hover_index == idx;
                self.drawButton(cr, 0.0, top, bw, bh, it, focused, scale_d);
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


    fn loadIcon(self: *Self, path: []const u8) ?*c.cairo_surface_t {
        if (self.icon_cache.get(path)) |surf| return surf;
        if (!std.mem.endsWith(u8, path, ".png")) {
            std.log.err("KidulWM: only PNG icons are currently supported ({s})", .{path});
            return null;
        }
        const zpath = self.allocator.dupeZ(u8, path) catch return null;
        defer self.allocator.free(zpath);
        const surf = c.cairo_image_surface_create_from_png(@ptrCast(zpath.ptr)) orelse return null;
        if (c.cairo_surface_status(surf) != c.CAIRO_STATUS_SUCCESS) {
            c.cairo_surface_destroy(surf);
            return null;
        }
        self.icon_cache.put(path, surf) catch {
            c.cairo_surface_destroy(surf);
            return null;
        };
        return surf;
    }

    fn drawIcon(cr: *c.cairo_t, icon: *c.cairo_surface_t, x: f64, y: f64, target_h: f64) void {
        const sw_f: f64 = @floatFromInt(c.cairo_image_surface_get_width(icon));
        const sh_f: f64 = @floatFromInt(c.cairo_image_surface_get_height(icon));
        const target_w = target_h * (sw_f / sh_f);
        c.cairo_save(cr);
        c.cairo_translate(cr, x, y);
        c.cairo_scale(cr, target_w / sw_f, target_h / sh_f);
        c.cairo_set_source_surface(cr, icon, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_restore(cr);
    }

    fn drawButton(self: *Self, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, it: TrayItem, focused: bool, s: f64) void {
        const text_color = if (focused) self.host.theme.tray_text_focused_color else self.host.theme.tray_text_color;
        const font_size = self.host.theme.tray_font_size * s;

        const label_c: [*c]const u8 = @ptrCast(it.label);
        const m_c: [*c]const u8 = @ptrCast("M");
        if (focused) {
            c.cairo_select_font_face(cr, "Fantasque Sans Mono", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
        } else {
            c.cairo_select_font_face(cr, "Fantasque Sans Mono", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
        }
        c.cairo_set_font_size(cr, font_size);

        var extents: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, label_c, &extents);

        var m_ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, m_c, &m_ext);
        var char_width = m_ext.width;

        // Load optional icon and compute its size.
        var icon: ?*c.cairo_surface_t = null;
        var icon_w: f64 = 0.0;
        var icon_h: f64 = 0.0;
        if (it.icon) |icon_path| {
            icon = self.loadIcon(icon_path);
            if (icon) |surf| {
                icon_h = @min(self.host.theme.tray_icon_size * s, h - 2.0 * char_width);
                const sw_f: f64 = @floatFromInt(c.cairo_image_surface_get_width(surf));
                const sh_f: f64 = @floatFromInt(c.cairo_image_surface_get_height(surf));
                icon_w = icon_h * (sw_f / sh_f);
            }
        }

        // Compute text area with a 1-char left buffer/margin.
        var text_x = x + char_width;
        var text_avail = @max(0.0, w - 2.0 * char_width);
        if (icon != null and extents.width > 0.0) {
            const gap = self.host.theme.tray_icon_gap * s;
            text_x += icon_w + gap;
            text_avail = @max(0.0, w - text_x - char_width);
        }

        // Fit font to available width if needed.
        if (text_avail > 0.0 and extents.width > text_avail) {
            const shrink = text_avail / extents.width;
            c.cairo_set_font_size(cr, font_size * shrink);
            c.cairo_text_extents(cr, label_c, &extents);
            c.cairo_text_extents(cr, m_c, &m_ext);
            char_width = m_ext.width;
            text_x = x + char_width;
            text_avail = @max(0.0, w - 2.0 * char_width);
            if (icon != null and extents.width > 0.0) {
                const gap = self.host.theme.tray_icon_gap * s;
                text_x += icon_w + gap;
                text_avail = @max(0.0, w - text_x - char_width);
            }
        }

        const has_text = extents.width > 0.0;
        const content_w = if (has_text and icon != null)
            icon_w + self.host.theme.tray_icon_gap * s + extents.width
        else if (icon != null)
            icon_w
        else
            extents.width;

        // Glass-look underline under the active button only.
        if (focused and content_w > 0.0) {
            const border_h: f64 = h * 0.12;
            const by = y + h - border_h;
            const r: f64 = 3.0 * s;
            var ux = x + char_width;
            if (icon != null and !has_text) {
                ux = x + (w - content_w) / 2.0 - char_width;
            }
            const uw = content_w + 2.0 * char_width;
            roundedRect(cr, ux, by, uw, border_h, r);

            const grad = c.cairo_pattern_create_linear(ux, by, ux, by + border_h);
            c.cairo_pattern_add_color_stop_rgba(grad, 0.0, 5.0 / 255.0, 5.0 / 255.0, 5.0 / 255.0, 235.0 / 255.0);
            c.cairo_pattern_add_color_stop_rgba(grad, 0.5, 5.0 / 255.0, 5.0 / 255.0, 5.0 / 255.0, 140.0 / 255.0);
            c.cairo_pattern_add_color_stop_rgba(grad, 1.0, 5.0 / 255.0, 5.0 / 255.0, 5.0 / 255.0, 235.0 / 255.0);
            c.cairo_set_source(cr, grad);
            c.cairo_fill_preserve(cr);
            c.cairo_pattern_destroy(grad);

            c.cairo_set_source_rgba(cr, 245.0 / 255.0, 250.0 / 255.0, 255.0 / 255.0, 50.0 / 255.0);
            c.cairo_set_line_width(cr, 1.0 * s);
            c.cairo_stroke(cr);
        }

        // Draw icon if present.
        if (icon) |surf| {
            const icon_y = y + (h - icon_h) / 2.0;
            if (has_text) {
                const gap = self.host.theme.tray_icon_gap * s;
                drawIcon(cr, surf, text_x - icon_w - gap, icon_y, icon_h);
            } else {
                const icon_x = x + (w - icon_w) / 2.0;
                drawIcon(cr, surf, icon_x, icon_y, icon_h);
            }
        }

        // Draw text if present.
        if (has_text) {
            const c4 = text_color.toF64();
            c.cairo_set_source_rgba(cr, c4[0], c4[1], c4[2], 1.0);
            const ty = y + (h + extents.height) / 2.0;
            c.cairo_move_to(cr, text_x, ty);
            c.cairo_show_text(cr, label_c);
        }
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
        const x: f64 = @floatFromInt(info.x);
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
            const item_size_ptr: f64 = bh + gap;
            const stack_origin: f64 = settings_top - item_size_ptr;
            const scroll_px: f64 = self.scroll_offset * info.scale;
            if (local_y >= settings_top and local_y < settings_top + bh) {
                new_hover = 0;
            } else if (local_y < stack_origin and self.items.len > 1) {
                const dist = stack_origin - local_y + scroll_px;
                const idx: usize = @as(usize, @intFromFloat(@floor(dist / item_size_ptr))) + 1;
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
        const item_size_ptr: f64 = bh + @as(f64, button_gap) * info.scale;
        const stack_origin: f64 = settings_top - item_size_ptr;
        const scroll_px: f64 = self.scroll_offset * info.scale;
        var idx: usize = 0;
        if (local_y < stack_origin and local_y >= 0.0) {
            const dist = stack_origin - local_y + scroll_px;
            idx = @as(usize, @intFromFloat(@floor(dist / item_size_ptr))) + 1;
            if (idx >= self.items.len) idx = 0;
        }
        self.selected_index = idx;
        self.hover_index = idx;
        self.activateItem(idx);
        return true;
    }
};
