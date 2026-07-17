const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const c = @import("../dm/c.zig").c;
const style = @import("../core/style.zig");
const animation = @import("../core/animation.zig");

const lay_png = @embedFile("assets/barry/lay.png");
const sit_png = @embedFile("assets/barry/sit.png");
const stand_png = @embedFile("assets/barry/stand.png");
const puppy_lay_png = @embedFile("assets/barry/puppy-lay.png");
const puppy_sit_png = @embedFile("assets/barry/puppy-sit.png");
const puppy_stand_png = @embedFile("assets/barry/puppy-stand.png");

const BarryPngStream = struct {
    data: []const u8,
    offset: usize,
};

fn readBarryPngStream(closure: *anyopaque, out: [*c]u8, len: c_uint) callconv(.c) c.cairo_status_t {
    const ctx: *BarryPngStream = @ptrCast(@alignCast(closure));
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

fn loadPngFromBytes(bytes: []const u8) !*c.cairo_surface_t {
    var ctx = BarryPngStream{ .data = bytes, .offset = 0 };
    const surf = c.cairo_image_surface_create_from_png_stream(
        @ptrCast(&readBarryPngStream),
        @ptrCast(&ctx),
    ) orelse return error.OutOfMemory;
    if (c.cairo_surface_status(surf) != c.CAIRO_STATUS_SUCCESS) {
        c.cairo_surface_destroy(surf);
        return error.InvalidPng;
    }
    const format = c.cairo_image_surface_get_format(surf);
    if (format == c.CAIRO_FORMAT_ARGB32) return surf;

    const w = c.cairo_image_surface_get_width(surf);
    const h = c.cairo_image_surface_get_height(surf);
    const argb = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, w, h) orelse {
        c.cairo_surface_destroy(surf);
        return error.OutOfMemory;
    };
    const cr = c.cairo_create(argb) orelse {
        c.cairo_surface_destroy(argb);
        c.cairo_surface_destroy(surf);
        return error.OutOfMemory;
    };
    defer c.cairo_destroy(cr);
    c.cairo_set_source_surface(cr, surf, 0, 0);
    c.cairo_paint(cr);
    c.cairo_surface_destroy(surf);
    return argb;
}

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
    toggle_tray,
    cycle_animation,
    spawn: []const u8,
    settings_page: []const u8,
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
    last_w: i32 = 0,
    last_h: i32 = 0,
    last_open_amount: f32 = 0.0,
    last_selected: usize = 9999,
    last_hover: ?usize = null,
    last_order_mode: OrderMode = .preset,
};

const BarryPet = struct {
    output_ctx: *anyopaque,
    tree: *wlr.SceneTree,
    scene_buffer: ?*wlr.SceneBuffer,
    buffer: ?*wlr.Buffer,
    info: OutputInfo,
    last_w: i32 = 0,
    last_h: i32 = 0,
    last_barry_state: BarryState = .laying,
};

pub const OrderMode = enum { manual, alphabetical, preset };

const BarryState = enum { laying, sitting, standing };

pub const Tray = struct {
    allocator: std.mem.Allocator,
    host: TrayHost,
    root: *wlr.SceneTree,

    open: bool = false,
    pinned: bool = false,
    hovered: bool = false,
    open_amount: f32 = 0.0,
    open_amount_vel: f32 = 0.0,
    selected_index: usize = 0,
    hover_index: ?usize = null,
    scroll_offset: f32 = 0.0,
    last_update_us: u64 = 0,

    order_mode: OrderMode = .preset,

    // Animation state.
    barry_state: BarryState = .laying,
    barry_state_t: f32 = 0.0,
    barry_state_vel: f32 = 0.0,
    barry_breath_t: f64 = 0.0,
    barry_breath_amp: f64 = 0.0,
    barry_bob_amp: f64 = 0.0,
    was_moving: bool = false,
    settle_t: f64 = 0.0,
    underline_x: f32 = 0.0,
    underline_vel: f32 = 0.0,
    close_after_us: u64 = 0,

    outputs: std.ArrayList(PerOutput),
    barry_pets: std.ArrayList(BarryPet),
    items: []TrayItem,
    manual_order: std.ArrayList(usize),
    icon_cache: std.StringHashMap(*c.cairo_surface_t),
    barry_lay: *c.cairo_surface_t,
    barry_sit: *c.cairo_surface_t,
    barry_stand: *c.cairo_surface_t,
    barry_puppy_lay: *c.cairo_surface_t,
    barry_puppy_sit: *c.cairo_surface_t,
    barry_puppy_stand: *c.cairo_surface_t,

    const button_height: i32 = 44;
    const barry_button_height: i32 = 84;
    const button_gap: i32 = 8;
    const hmargin: i32 = 8;
    const bottom_margin: i32 = 10;
    const top_margin: i32 = 48;
    const max_stack_items_visible: usize = 12;
    const min_panel_w: i32 = 120;

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, host: TrayHost, root: *wlr.SceneTree) !Self {
        const items = try allocator.alloc(TrayItem, 4);
        items[0] = .{ .id = "term", .label = "Terminal", .action = .{ .spawn = "" } };
        items[1] = .{ .id = "files", .label = "Files", .action = .{ .spawn = "" } };
        items[2] = .{ .id = "browser", .label = "Browser", .action = .{ .spawn = "" } };
        items[3] = .{ .id = "motion", .label = "Motion", .action = .cycle_animation };

        var manual_order: std.ArrayList(usize) = .empty;
        errdefer manual_order.deinit(allocator);
        try manual_order.appendSlice(allocator, &[_]usize{ 0, 1, 2, 3 });

        const barry_lay = try loadPngFromBytes(lay_png);
        errdefer c.cairo_surface_destroy(barry_lay);
        const barry_sit = try loadPngFromBytes(sit_png);
        errdefer c.cairo_surface_destroy(barry_sit);
        const barry_stand = try loadPngFromBytes(stand_png);
        errdefer c.cairo_surface_destroy(barry_stand);
        const barry_puppy_lay = try loadPngFromBytes(puppy_lay_png);
        errdefer c.cairo_surface_destroy(barry_puppy_lay);
        const barry_puppy_sit = try loadPngFromBytes(puppy_sit_png);
        errdefer c.cairo_surface_destroy(barry_puppy_sit);
        const barry_puppy_stand = try loadPngFromBytes(puppy_stand_png);
        errdefer c.cairo_surface_destroy(barry_puppy_stand);

        return .{
            .allocator = allocator,
            .host = host,
            .root = root,
            .outputs = .empty,
            .barry_pets = .empty,
            .items = items,
            .manual_order = manual_order,
            .icon_cache = std.StringHashMap(*c.cairo_surface_t).init(allocator),
            .barry_lay = barry_lay,
            .barry_sit = barry_sit,
            .barry_stand = barry_stand,
            .barry_puppy_lay = barry_puppy_lay,
            .barry_puppy_sit = barry_puppy_sit,
            .barry_puppy_stand = barry_puppy_stand,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.outputs.items) |*po| self.destroyPerOutput(po);
        for (self.barry_pets.items) |*pet| self.destroyPet(pet);
        self.outputs.deinit(self.allocator);
        self.barry_pets.deinit(self.allocator);
        var it = self.icon_cache.iterator();
        while (it.next()) |entry| {
            c.cairo_surface_destroy(entry.value_ptr.*);
        }
        self.icon_cache.deinit();
        c.cairo_surface_destroy(self.barry_lay);
        c.cairo_surface_destroy(self.barry_sit);
        c.cairo_surface_destroy(self.barry_stand);
        c.cairo_surface_destroy(self.barry_puppy_lay);
        c.cairo_surface_destroy(self.barry_puppy_sit);
        c.cairo_surface_destroy(self.barry_puppy_stand);
        self.manual_order.deinit(self.allocator);
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
        const pet_tree = self.root.createSceneTree() catch |err| {
            std.log.err("KidulWM: failed to create barry pet scene tree: {}", .{err});
            tree.node.destroy();
            return;
        };
        self.outputs.append(self.allocator, po) catch |err| {
            std.log.err("KidulWM: failed to append tray output: {}", .{err});
            tree.node.destroy();
            pet_tree.node.destroy();
            return;
        };
        const pet = BarryPet{
            .output_ctx = output_ctx,
            .tree = pet_tree,
            .scene_buffer = null,
            .buffer = null,
            .info = .{ .x = 0, .y = 0, .width = 0, .height = 0, .scale = 1.0, .focus_left = 0 },
        };
        self.barry_pets.append(self.allocator, pet) catch |err| {
            std.log.err("KidulWM: failed to append barry pet: {}", .{err});
            pet_tree.node.destroy();
            return;
        };
        self.requestUpdate();
        self.update();
    }

    pub fn removeOutput(self: *Self, output_ctx: *anyopaque) void {
        for (self.outputs.items, 0..) |*po, i| {
            if (po.output_ctx == output_ctx) {
                self.destroyPerOutput(po);
                _ = self.outputs.orderedRemove(i);
                break;
            }
        }
        for (self.barry_pets.items, 0..) |*pet, i| {
            if (pet.output_ctx == output_ctx) {
                self.destroyPet(pet);
                _ = self.barry_pets.orderedRemove(i);
                return;
            }
        }
    }

    fn destroyPet(_: *Self, pet: *BarryPet) void {
        if (pet.scene_buffer) |sb| sb.node.destroy();
        if (pet.buffer) |buf| wlr.Buffer.drop(buf);
        pet.tree.node.destroy();
        pet.scene_buffer = null;
        pet.buffer = null;
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
        if (self.open) {
            self.keepOpen();
            self.selected_index = 1;
            self.hover_index = 1;
            self.setBarryState(.sitting);
        } else {
            self.close_after_us = 0;
            self.selected_index = 0;
            self.hover_index = null;
            self.setBarryState(.laying);
        }
        self.requestUpdate();
        self.host.request_frame(self.host.ctx);
    }

    pub fn selectNext(self: *Self) void {
        self.keepOpen();
        if (!self.isOpen() or self.items.len == 0) {
            self.toggle();
            return;
        }
        if (self.selected_index > 0) {
            self.selected_index -= 1;
        }
        if (self.selected_index == 0) {
            self.setBarryState(.sitting);
        } else {
            self.setBarryState(.standing);
        }
        self.hover_index = self.selected_index;
        self.ensureSelectedVisible();
        self.requestUpdate();
    }

    pub fn selectPrev(self: *Self) void {
        self.keepOpen();
        if (!self.isOpen() or self.items.len == 0) {
            self.toggle();
            return;
        }
        if (self.selected_index < self.items.len) {
            self.selected_index += 1;
            self.setBarryState(.standing);
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
        if (self.selected_index == 0) {
            self.toggle();
            return;
        }
        const idx = self.selected_index - 1;
        if (idx >= self.items.len) return;
        const it = self.activeItemAt(idx);
        std.log.info("KidulWM: tray activate {s}", .{it.id});
        switch (it.action) {
            .cycle_animation => self.host.cycle_animation(self.host.ctx),
            .toggle_tray => self.toggle(),
            .spawn => {},
            .settings_page => {},
            .none => {},
        }
    }

    pub fn isOpen(self: *const Self) bool {
        return self.open or self.open_amount > 0.005;
    }

    pub fn scroll(self: *Self, delta: f32) void {
        self.keepOpen();
        if (!self.isOpen()) return;
        const max_scroll = self.maxScroll();
        self.scroll_offset = std.math.clamp(self.scroll_offset - delta, 0.0, max_scroll);
        if (self.scroll_offset > 0.1) {
            self.setBarryState(.standing);
        }
        self.requestUpdate();
    }

    pub fn toggle_order_mode(self: *Self) void {
        const next: OrderMode = switch (self.order_mode) {
            .manual => .alphabetical,
            .alphabetical => .preset,
            .preset => .manual,
        };
        self.order_mode = next;
        self.requestUpdate();
    }


    fn keepOpen(self: *Self) void {
        self.close_after_us = animation.nowUs() + 4_000_000; // 4 s idle timeout
    }

    fn setBarryState(self: *Self, state: BarryState) void {
        if (self.barry_state == state) return;
        self.barry_state = state;
        self.barry_state_vel = 0.0;
        self.requestUpdate();
    }

    fn ensureSelectedVisible(self: *Self) void {
        const max_scroll = self.maxScroll();
        if (max_scroll <= 0.0) {
            self.scroll_offset = 0.0;
            return;
        }
        if (self.selected_index <= 1) {
            self.scroll_offset = 0.0;
            return;
        }
        const visible_count = @min(max_stack_items_visible, self.items.len);
        const item_size: f32 = @floatFromInt(button_height + button_gap);
        const first_visible: usize = @intFromFloat(@floor(self.scroll_offset / item_size));
        const stack_sel = self.selected_index - 1;
        if (stack_sel < first_visible) {
            self.scroll_offset = @as(f32, @floatFromInt(stack_sel)) * item_size;
        } else if (stack_sel >= first_visible + visible_count) {
            self.scroll_offset = @as(f32, @floatFromInt(stack_sel + 1 - visible_count)) * item_size;
        }
        self.scroll_offset = std.math.clamp(self.scroll_offset, 0.0, max_scroll);
    }

    fn maxScroll(self: *const Self) f32 {
        const stack_count = self.items.len;
        if (stack_count == 0) return 0.0;
        const item_size: f32 = @floatFromInt(button_height + button_gap);
        const total_h = @as(f32, @floatFromInt(stack_count)) * item_size;
        var max_v = total_h;
        for (self.outputs.items) |po| {
            const avail: f32 = @floatFromInt(po.info.height - top_margin - bottom_margin - barry_button_height);
            const view_h: f32 = @as(f32, @floatFromInt(@min(max_stack_items_visible, stack_count))) * item_size;
            const local_max = @max(0.0, total_h - @min(view_h, avail));
            if (local_max < max_v) max_v = local_max;
        }
        return max_v;
    }

    fn activeItemAt(self: *const Self, idx: usize) TrayItem {
        switch (self.order_mode) {
            .manual => {
                if (idx < self.manual_order.items.len and self.manual_order.items[idx] < self.items.len) {
                    return self.items[self.manual_order.items[idx]];
                }
                return self.items[idx];
            },
            .alphabetical => {
                // For readability, find the item whose label would sort to idx.
                var buf: [8]usize = undefined;
                if (self.items.len <= buf.len) {
                    for (0..self.items.len) |j| buf[j] = j;
                    const Context = struct {
                        items: []const TrayItem,
                        pub fn less(ctx: @This(), a: usize, b: usize) bool {
                            return std.mem.lessThan(u8, ctx.items[a].label, ctx.items[b].label);
                        }
                    };
                    const indices = buf[0..self.items.len];
                    std.mem.sort(usize, indices, Context{ .items = self.items }, Context.less);
                    return self.items[indices[idx]];
                }
                return self.items[idx];
            },
            .preset => return self.items[idx],
        }
    }

    pub fn update(self: *Self) void {
        const now_us = animation.nowUs();
        const prev = self.last_update_us;
        defer self.last_update_us = now_us;

        const dt = if (prev == 0) 0.0 else @as(f64, @floatFromInt(now_us - prev)) / 1_000_000.0;

        // Snap open quickly, ease closed slowly.
        const desired: f32 = if (self.open or self.pinned or self.hovered) 1.0 else 0.0;
        const closing = desired < self.open_amount;
        const open_spring = if (closing)
            animation.Spring{ .stiffness = 2.5, .damping = 0.92, .epsilon = 0.001 }
        else
            animation.Spring{ .stiffness = 80.0, .damping = 0.95, .epsilon = 0.001 };
        const open_step = open_spring.step(self.open_amount, self.open_amount_vel, desired, dt);
        self.open_amount = @floatCast(open_step.value);
        self.open_amount_vel = @floatCast(open_step.velocity);

        // Spring Barry state blend.
        const target_state: f32 = switch (self.barry_state) {
            .laying => 0.0,
            .sitting => 1.0,
            .standing => 2.0,
        };
        const state_spring = animation.Spring{ .stiffness = 12.0, .damping = 0.88, .epsilon = 0.005 };
        const state_step = state_spring.step(self.barry_state_t, self.barry_state_vel, target_state, dt);
        self.barry_state_t = @floatCast(state_step.value);
        self.barry_state_vel = @floatCast(state_step.velocity);

        // Selection underline position spring.
        const target_underline: f32 = self.underlineTarget();
        const us = animation.Spring{ .stiffness = 18.0, .damping = 0.85, .epsilon = 0.5 };
        const us_step = us.step(self.underline_x, self.underline_vel, target_underline, dt);
        self.underline_x = @floatCast(us_step.value);
        self.underline_vel = @floatCast(us_step.velocity);

        // Barry/Bob animation only during movement; short settle wobble after.
        const moving = !open_step.settled or !state_step.settled or !us_step.settled;
        if (moving) {
            self.barry_breath_t += dt * 3.0;
            self.barry_breath_amp = @min(0.04, self.barry_breath_amp + dt * 0.4);
            self.barry_bob_amp = @min(2.0, self.barry_bob_amp + dt * 5.0);
            self.was_moving = true;
        } else if (self.was_moving) {
            self.settle_t += dt;
            if (self.settle_t >= 0.8) {
                self.was_moving = false;
                self.settle_t = 0.0;
                self.barry_breath_amp = 0.0;
                self.barry_bob_amp = 0.0;
            } else {
                const decay = 1.0 - (self.settle_t / 0.8);
                const wobble = std.math.sin(self.settle_t * 18.0) * decay;
                self.barry_breath_amp = 0.02 + 0.02 * wobble;
                self.barry_bob_amp = 1.2 * wobble;
                self.barry_breath_t += dt * 2.0;
            }
        } else {
            self.barry_breath_amp = 0.0;
            self.barry_bob_amp = 0.0;
        }

        var needs_redraw = prev == 0 or
            (self.open_amount > 0.001 and self.open_amount < 0.999) or
            !state_step.settled or
            self.barry_state != .laying or
            !us_step.settled;

        for (self.outputs.items, 0..) |*po, i| {
            po.info = self.host.output_info(self.host.ctx, i);
            const w = self.panelWidth(po.info);
            const h = self.panelHeightFor(po.info);
            if (po.last_w != w or po.last_h != h or
                @abs(po.last_open_amount - self.open_amount) > 0.0001 or
                po.last_selected != self.selected_index or
                po.last_hover != self.hover_index or
                po.last_order_mode != self.order_mode)
            {
                needs_redraw = true;
            }
            po.last_w = w;
            po.last_h = h;
            po.last_open_amount = self.open_amount;
            po.last_selected = self.selected_index;
            po.last_hover = self.hover_index;
            po.last_order_mode = self.order_mode;
            self.updatePerOutput(po, needs_redraw);
        }

        for (self.barry_pets.items, 0..) |*pet, i| {
            pet.info = self.host.output_info(self.host.ctx, i);
            const pw = self.panelWidth(pet.info);
            const ph = petHeight();
            if (pet.last_w != pw or pet.last_h != ph or
                pet.last_barry_state != self.barry_state)
            {
                needs_redraw = true;
            }
            pet.last_w = pw;
            pet.last_h = ph;
            pet.last_barry_state = self.barry_state;
            self.updatePetPerOutput(pet, needs_redraw);
        }

        if (needs_redraw) {
            self.host.request_frame(self.host.ctx);
        }
    }

    fn underlineTarget(self: *const Self) f32 {
        const stack_sel = if (self.selected_index == 0) 0 else self.selected_index;
        const item_size: f32 = @floatFromInt(button_height + button_gap);
        const stack_origin_offset: f32 = @floatFromInt(barry_button_height + bottom_margin + button_gap);
        return stack_origin_offset + @as(f32, @floatFromInt(stack_sel)) * item_size;
    }

    fn panelWidth(self: *const Self, info: OutputInfo) i32 {
        _ = self;
        const peek_w = info.focus_left - info.x;
        const desired = @as(f64, @floatFromInt(peek_w)) * 0.97;
        const desired_i: i32 = @intFromFloat(@round(desired));
        return @max(min_panel_w, desired_i);
    }

    fn panelHeightFor(self: *const Self, info: OutputInfo) i32 {
        const stack_count = self.items.len;
        const visible_items = @min(max_stack_items_visible, stack_count);
        const item_size = button_height + button_gap;
        const stack_buffer = item_size;
        const max_stack_h = @min(
            info.height - top_margin - bottom_margin - barry_button_height,
            @as(i32, @intCast(visible_items)) * item_size - button_gap + stack_buffer,
        );
        const actual_stack_h: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(max_stack_h)) * self.open_amount));
        return barry_button_height + bottom_margin + actual_stack_h;
    }

    fn petWidth(self: *const Self, info: OutputInfo) i32 {
        return @intFromFloat(@round(@as(f32, @floatFromInt(self.panelWidth(info))) * 1.5));
    }

    fn petHeight() i32 {
        return barry_button_height + bottom_margin * 2;
    }

    fn updatePetPerOutput(self: *Self, pet: *BarryPet, should_redraw: bool) void {
        const info = pet.info;
        const s = info.scale;
        const w = self.petWidth(info);
        const h = petHeight();
        const x: i32 = info.x;
        const y: i32 = info.y + info.height - h;

        pet.tree.node.setPosition(x, y);

        if (w <= 0 or h <= 0) return;
        if (!should_redraw) return;

        const dev_w: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(w)) * s));
        const dev_h: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(h)) * s));

        const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, dev_w);
        if (stride <= 0) return;
        const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(dev_h));
        const temp = self.allocator.alloc(u8, buf_size) catch |err| {
            std.log.err("KidulWM: barry pet buffer alloc failed: {}", .{err});
            return;
        };
        defer self.allocator.free(temp);

        const surface = c.cairo_image_surface_create_for_data(temp.ptr, c.CAIRO_FORMAT_ARGB32, dev_w, dev_h, stride);
        defer c.cairo_surface_destroy(surface);
        const cr = c.cairo_create(surface) orelse {
            std.log.err("KidulWM: failed to create cairo context for barry pet", .{});
            return;
        };
        defer c.cairo_destroy(cr);

        const scale_d: f64 = @as(f64, s);
        const bw: f64 = @as(f64, dev_w);

        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        const bh: f64 = @as(f64, barry_button_height) * scale_d;
        const bmargin: f64 = @as(f64, bottom_margin) * scale_d;
        const by: f64 = @as(f64, dev_h) - bh - bmargin;
        self.drawPetButton(cr, 0.0, by, bw, bh, scale_d);

        const DataBuffer = @import("../render/buffer.zig").DataBuffer;
        const buffer = DataBuffer.create(temp, dev_w, dev_h, @intCast(stride)) catch |err| {
            std.log.err("KidulWM: failed to create barry pet buffer: {}", .{err});
            return;
        };
        if (pet.buffer) |old| wlr.Buffer.drop(old);
        pet.buffer = buffer;
        if (pet.scene_buffer) |old| old.node.destroy();
        const sb = pet.tree.createSceneBuffer(buffer) catch |err| {
            std.log.err("KidulWM: failed to create barry pet scene buffer: {}", .{err});
            wlr.Buffer.drop(buffer);
            pet.buffer = null;
            return;
        };
        sb.setDestSize(w, h);
        pet.scene_buffer = sb;
        pet.tree.node.raiseToTop();
    }

    fn updatePerOutput(self: *Self, po: *PerOutput, should_redraw: bool) void {
        const info = po.info;
        const s = info.scale;
        const w = self.panelWidth(info);
        const h = self.panelHeightFor(info);
        const x: i32 = info.x;
        const y: i32 = info.y + top_margin;

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

        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        // Barry lozenge at top.
        const bh: f64 = @as(f64, barry_button_height) * scale_d;
        const bmargin: f64 = @as(f64, bottom_margin) * scale_d;
        const by: f64 = bmargin;
        self.drawBarryButton(cr, 0.0, by, bw, bh, scale_d);

        // Stack below Barry with stagger.
        if (self.open_amount > 0.001 and self.items.len > 0) {
            const gap: f64 = @as(f64, button_gap) * scale_d;
            const item_h: f64 = @as(f64, button_height) * scale_d;
            const item_size = item_h + gap;
            const scroll_px: f64 = @floor(@as(f64, self.scroll_offset) * scale_d);
            const stack_origin: f64 = by + bh + gap;
            const stagger_delay: f32 = 0.05;

            for (0..self.items.len) |raw_idx| {
                const idx = raw_idx;
                const stack_index: usize = idx;
                const top = stack_origin + @as(f64, @floatFromInt(idx)) * item_size - scroll_px;
                if (top + item_h < stack_origin or top >= @as(f64, dev_h)) continue;

                const stagger_t = std.math.clamp(self.open_amount - @as(f32, @floatFromInt(stack_index)) * stagger_delay, 0.0, 1.0);
                const local_top = top - item_size * @as(f64, 1.0 - @as(f64, @floatCast(easeOutCubic(stagger_t))));
                const alpha: f64 = @floatCast(stagger_t);
                const focused = self.selected_index == stack_index + 1;
                const hovered = self.hover_index == stack_index + 1;
                self.drawStackButton(cr, 0.0, local_top, bw, item_h, stack_index, focused, hovered, alpha, scale_d);
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

    fn easeOutCubic(t: f32) f32 {
        const u = 1.0 - t;
        return 1.0 - u * u * u;
    }

    fn drawBarryButton(self: *Self, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, s: f64) void {
        const margin: f64 = @as(f64, hmargin) * s;
        const rx: f64 = h / 3.0;
        const loz_w: f64 = w - 2.0 * margin;
        const loz_x: f64 = x + margin;

        c.cairo_save(cr);
        roundedRect(cr, loz_x, y, loz_w, h, rx);
        c.cairo_clip(cr);
        self.drawBarry(cr, loz_x, y, loz_w, h, s);
        c.cairo_restore(cr);
    }
    fn drawBarry(self: *const Self, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, s: f64) void {
        const surfs = [_]*c.cairo_surface_t{ self.barry_lay, self.barry_sit, self.barry_stand };
        const t: f64 = @as(f64, std.math.clamp(self.barry_state_t, 0.0, 2.0));
        const idx0: usize = @intFromFloat(@floor(t));
        const idx1: usize = @min(idx0 + 1, 2);
        const blend: f64 = t - @floor(t);

        // Movement-driven breath + bob.
        const breath: f64 = 1.0 + self.barry_breath_amp * @sin(self.barry_breath_t * 2.0);
        const bob: f64 = self.barry_bob_amp * s * @sin(self.barry_breath_t * 2.0);

        const margin: f64 = 4.0 * s;
        const avail_w = w - 2.0 * margin;

        for ([_]usize{ idx0, idx1 }) |idx| {
            if (idx > 2) continue;
            const alpha: f64 = if (idx == idx0) (1.0 - blend) else if (idx == idx1) blend else 0.0;
            if (alpha < 0.001) continue;
            const surf = surfs[idx];
            const img_w = @as(f64, @floatFromInt(c.cairo_image_surface_get_width(surf)));
            const img_h = @as(f64, @floatFromInt(c.cairo_image_surface_get_height(surf)));
            if (img_w <= 0.0 or img_h <= 0.0) continue;

            // Scale so the icon occupies ~90 % of the button height.
            const scale = @min(avail_w / img_w, h * 0.90 / img_h) * breath;
            const draw_x = x + (w - img_w * scale) / 2.0;
            const draw_y = y + (h - img_h * scale) / 2.0 + bob;

            c.cairo_save(cr);
            c.cairo_translate(cr, draw_x, draw_y);
            c.cairo_scale(cr, scale, scale);
            c.cairo_set_source_surface(cr, surf, 0, 0);
            c.cairo_paint_with_alpha(cr, alpha);
            c.cairo_restore(cr);
        }
    }


    fn drawPetButton(self: *Self, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, s: f64) void {
        const margin: f64 = @as(f64, hmargin) * s;
        const rx: f64 = h / 3.0;
        const loz_w: f64 = w - 2.0 * margin;
        const loz_x: f64 = x + margin;

        c.cairo_save(cr);
        roundedRect(cr, loz_x, y, loz_w, h, rx);
        c.cairo_clip(cr);
        self.drawPet(cr, loz_x, y, loz_w, h, s);
        c.cairo_restore(cr);
    }
    fn drawPet(self: *const Self, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, s: f64) void {
        const surfs = [_]*c.cairo_surface_t{ self.barry_puppy_lay, self.barry_puppy_sit, self.barry_puppy_stand };
        const t: f64 = @as(f64, std.math.clamp(self.barry_state_t, 0.0, 2.0));
        const idx0: usize = @intFromFloat(@floor(t));
        const idx1: usize = @min(idx0 + 1, 2);
        const blend: f64 = t - @floor(t);

        const breath: f64 = 1.0 + 0.03 * @sin(self.barry_breath_t * 2.0);
        const bob: f64 = 1.5 * s * @sin(self.barry_breath_t * 2.0);

        const margin: f64 = 4.0 * s;
        const avail_w = w - 2.0 * margin;

        for ([_]usize{ idx0, idx1 }) |idx| {
            if (idx > 2) continue;
            const alpha: f64 = if (idx == idx0) (1.0 - blend) else if (idx == idx1) blend else 0.0;
            if (alpha < 0.001) continue;
            const surf = surfs[idx];
            const img_w = @as(f64, @floatFromInt(c.cairo_image_surface_get_width(surf)));
            const img_h = @as(f64, @floatFromInt(c.cairo_image_surface_get_height(surf)));
            if (img_w <= 0.0 or img_h <= 0.0) continue;

            const scale = @min(avail_w / img_w, h * 1.15 / img_h) * breath;
            const draw_x = x + margin;
            const draw_y = y + (h - img_h * scale) / 2.0 + bob;

            c.cairo_save(cr);
            c.cairo_translate(cr, draw_x, draw_y);
            c.cairo_scale(cr, scale, scale);
            c.cairo_set_source_surface(cr, surf, 0, 0);
            c.cairo_paint_with_alpha(cr, alpha);
            c.cairo_restore(cr);
        }
    }

    fn drawStackButton(self: *const Self, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, stack_index: usize, focused: bool, hovered: bool, alpha: f64, s: f64) void {
        const it = self.activeItemAt(stack_index);
        const margin: f64 = @as(f64, hmargin) * s;
        const left_nudge: f64 = 2.0 * s;
        const peek_border: f64 = 6.0 * s;
        const pill_x: f64 = x + margin - left_nudge;
        const pill_w: f64 = w - margin - peek_border;
        const r: f64 = h / 2.0;
        const chamfer: f64 = r * 0.30;

        c.cairo_save(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        // Shadow.
        chamferedRect(cr, pill_x + 2.0 * s, y + 3.0 * s, pill_w, h, chamfer);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.35 * alpha);
        c.cairo_fill(cr);

        // Glass body.
        _ = hovered;
        chamferedRect(cr, pill_x, y, pill_w, h, chamfer);
        const glass = c.cairo_pattern_create_linear(pill_x, y, pill_x, y + h).?;
        c.cairo_pattern_add_color_stop_rgba(glass, 0.0, 0.09, 0.09, 0.10, 0.85 * alpha);
        c.cairo_pattern_add_color_stop_rgba(glass, 0.5, 0.06, 0.06, 0.07, 0.82 * alpha);
        if (focused) {
            const c4 = self.host.theme.tray_text_focused_color.toF64();
            c.cairo_pattern_add_color_stop_rgba(glass, 0.5, c4[0], c4[1], c4[2], 0.22 * alpha);
        }
        c.cairo_pattern_add_color_stop_rgba(glass, 1.0, 0.04, 0.04, 0.05, 0.78 * alpha);
        c.cairo_set_source(cr, glass);
        c.cairo_fill_preserve(cr);
        c.cairo_pattern_destroy(glass);

        // Gold rim.
        const rim4 = self.host.theme.color_gold.toF64();
        c.cairo_set_source_rgba(cr, rim4[0], rim4[1], rim4[2], 0.45 * alpha);
        c.cairo_set_line_width(cr, 1.0 * s);
        c.cairo_stroke(cr);

        // Render label.
        const label_c: [*c]const u8 = @ptrCast(it.label);
        const font_size = self.host.theme.tray_font_size * s;
        c.cairo_select_font_face(cr, "Fantasque Sans Mono", c.CAIRO_FONT_SLANT_NORMAL, if (focused) c.CAIRO_FONT_WEIGHT_BOLD else c.CAIRO_FONT_WEIGHT_NORMAL);
        c.cairo_set_font_size(cr, font_size);

        var extents: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, label_c, &extents);
        const char_w = self.measureChar(cr, s);
        const text_avail = @max(0.0, pill_w - 2.0 * char_w);
        if (text_avail > 0.0 and extents.width > text_avail) {
            const shrink = text_avail / extents.width;
            c.cairo_set_font_size(cr, font_size * shrink);
            c.cairo_text_extents(cr, label_c, &extents);
        }

        const text_color = if (focused) self.host.theme.tray_text_focused_color else self.host.theme.tray_text_color;
        const c4 = text_color.toF64();
        c.cairo_set_source_rgba(cr, c4[0], c4[1], c4[2], alpha);
        const shadow_offset: f64 = 1.0 * s;
        const ty = y + (h + extents.height) / 2.0;
        const text_x = pill_x + char_w + (text_avail - extents.width) / 2.0;

        // Dark shadow.
        c.cairo_move_to(cr, text_x + shadow_offset, ty + shadow_offset);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.7 * alpha);
        c.cairo_show_text(cr, label_c);

        // Gold text.
        c.cairo_move_to(cr, text_x, ty);
        c.cairo_set_source_rgba(cr, c4[0], c4[1], c4[2], alpha);
        c.cairo_show_text(cr, label_c);

        // Gradient underline for selected items.
        if (focused) {
            const border_h: f64 = h * 0.12;
            const by = y + h - border_h - 2.0 * s;
            const ux = pill_x + char_w;
            const uw = pill_w - 2.0 * char_w;
            roundedRect(cr, ux, by, uw, border_h, 2.0 * s);

            const grad = self.createGradient(cr, ux, by, uw, border_h);
            c.cairo_set_source(cr, grad);
            c.cairo_fill_preserve(cr);
            c.cairo_pattern_destroy(grad);

            c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.6);
            c.cairo_set_line_width(cr, 0.5 * s);
            c.cairo_stroke(cr);
        }

        c.cairo_restore(cr);
    }

    fn createGradient(self: *const Self, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64) *c.cairo_pattern_t {
        const grad = c.cairo_pattern_create_linear(x, y, x, y + h).?;
        const gold = self.host.theme.tray_text_focused_color.toF64();
        // Top of underline matches the muted goldish focus highlight of the button.
        c.cairo_pattern_add_color_stop_rgba(grad, 0.0, gold[0], gold[1], gold[2], 0.70);
        c.cairo_pattern_add_color_stop_rgba(grad, 0.45, gold[0], gold[1], gold[2], 0.35);
        // Bottom fades to the same translucent grey-black used for the bottom of the button body.
        c.cairo_pattern_add_color_stop_rgba(grad, 1.0, 0.04, 0.04, 0.05, 0.30);
        _ = cr;
        _ = w;
        return grad;
    }

    fn measureChar(self: *const Self, cr: *c.cairo_t, s: f64) f64 {
        _ = self;
        _ = s;
        var ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, @ptrCast("M"), &ext);
        return ext.width;
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

    fn chamferedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, ch: f64) void {
        const chamfer = @min(ch, w / 2.0, h / 2.0);
        c.cairo_new_sub_path(cr);
        c.cairo_move_to(cr, x + chamfer, y);
        c.cairo_line_to(cr, x + w - chamfer, y);
        c.cairo_line_to(cr, x + w, y + chamfer);
        c.cairo_line_to(cr, x + w, y + h - chamfer);
        c.cairo_line_to(cr, x + w - chamfer, y + h);
        c.cairo_line_to(cr, x + chamfer, y + h);
        c.cairo_line_to(cr, x, y + h - chamfer);
        c.cairo_line_to(cr, x, y + chamfer);
        c.cairo_close_path(cr);
    }

    fn pointInside(self: *const Self, info: OutputInfo, px: f64, py: f64) bool {
        const w = self.panelWidth(info);
        const h = self.panelHeightFor(info);
        const x: f64 = @floatFromInt(info.x);
        const y: f64 = @floatFromInt(info.y + top_margin);
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

            const panel_h = @as(f64, @floatFromInt(self.panelHeightFor(info)));
            const local_y = py - @as(f64, @floatFromInt(info.y + top_margin));
            const by: f64 = bottom_margin;
            const bh: f64 = barry_button_height;
            const gap: f64 = button_gap;
            const item_h: f64 = button_height;
            const stack_origin: f64 = by + bh + gap;
            const scroll_px: f64 = self.scroll_offset;

            if (local_y >= by and local_y < by + bh) {
                new_hover = 0;
            } else if (local_y >= stack_origin and local_y < panel_h and self.items.len > 0) {
                const dist = local_y - stack_origin + scroll_px;
                const idx: usize = @as(usize, @intFromFloat(@floor(dist / (item_h + gap)))) + 1;
                if (idx <= self.items.len) new_hover = idx;
            }
        }

        self.hovered = inside_any;
        if (new_hover) |hi| self.hover_index = hi;

        if (inside_any and !self.open and !self.pinned) {
            self.open = true;
            self.keepOpen();
            self.selected_index = 1;
            self.hover_index = 1;
            self.setBarryState(.sitting);
            self.requestUpdate();
            self.host.request_frame(self.host.ctx);
        } else if (!inside_any and self.open and !self.pinned) {
            if (animation.nowUs() >= self.close_after_us) {
                self.open = false;
                self.close_after_us = 0;
                self.hover_index = null;
                self.selected_index = 0;
                self.setBarryState(.laying);
                self.requestUpdate();
                self.host.request_frame(self.host.ctx);
            } else {
                self.requestUpdate();
                self.host.request_frame(self.host.ctx);
            }
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
                self.selected_index = 0;
                self.setBarryState(.laying);
                self.requestUpdate();
                self.host.request_frame(self.host.ctx);
            }
            return self.pinned;
        }

        const info = self.host.output_info(self.host.ctx, output_index);
        const panel_h = @as(f64, @floatFromInt(self.panelHeightFor(info)));
        const local_y = py - @as(f64, @floatFromInt(info.y + top_margin));
        const by: f64 = bottom_margin;
        const bh: f64 = barry_button_height;
        const gap: f64 = button_gap;
        const item_h: f64 = button_height;
        const stack_origin: f64 = by + bh + gap;
        const scroll_px: f64 = self.scroll_offset;

        var idx: usize = 0;
        if (local_y >= stack_origin and local_y < panel_h and self.items.len > 0) {
            const dist = local_y - stack_origin + scroll_px;
            const stack_idx: usize = @as(usize, @intFromFloat(@floor(dist / (item_h + gap)))) + 1;
            if (stack_idx <= self.items.len) idx = stack_idx;
        }
        self.selected_index = idx;
        self.hover_index = idx;
        if (idx == 0) {
            self.toggle();
        } else {
            self.activateSelected();
        }
        return true;
    }

};
