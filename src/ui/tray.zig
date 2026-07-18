const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const c = @import("../dm/c.zig").c;
const theme_mod = @import("../core/theme.zig");
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
    is_transition_active: *const fn (ctx: *anyopaque) bool,
    focused_window_box: *const fn (ctx: *anyopaque) ?wlr.Box,
    theme: *const theme_mod.Theme,
};

const Action = union(enum) {
    toggle_tray,
    cycle_animation,
    card_clock,
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

    // Desired pose for Bob (immediate) and Barry (delayed).
    barry_state_target: BarryState = .laying,

    // Bob's pose interpolation.
    bob_state_t: f32 = 0.0,
    bob_state_vel: f32 = 0.0,

    // Barry's pose interpolation.
    barry_state: BarryState = .laying,
    barry_state_t: f32 = 0.0,
    barry_state_vel: f32 = 0.0,

    barry_breath_t: f64 = 0.0,
    bob_breath_amp: f64 = 0.0,
    bob_bob_amp: f64 = 0.0,
    barry_breath_amp: f64 = 0.0,
    barry_bob_amp: f64 = 0.0,
    bob_was_moving: bool = false,
    bob_settle_t: f64 = 0.0,
    barry_was_moving: bool = false,
    barry_settle_t: f64 = 0.0,
    underline_x: f32 = 0.0,
    underline_vel: f32 = 0.0,
    close_after_us: u64 = 0,

    // Lazy Barry mirror state.
    barry_follow_deadline_us: u64 = 0,

    // Focused-slide card (clock/calendar/etc).
    card_open: bool = false,
    card_open_amount: f32 = 0.0,
    card_open_amount_vel: f32 = 0.0,
    card_box: wlr.Box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    card_tree: ?*wlr.SceneTree = null,
    card_scene_buffer: ?*wlr.SceneBuffer = null,
    card_buffer: ?*wlr.Buffer = null,
    card_last_w: i32 = 0,
    card_last_h: i32 = 0,
    card_last_open: f32 = -1.0,
    card_last_generation: u32 = 0,

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
        const items = try allocator.alloc(TrayItem, 5);
        items[0] = .{ .id = "term", .label = "Terminal", .action = .{ .spawn = "" } };
        items[1] = .{ .id = "files", .label = "Files", .action = .{ .spawn = "" } };
        items[2] = .{ .id = "browser", .label = "Browser", .action = .{ .spawn = "" } };
        items[3] = .{ .id = "motion", .label = "Motion", .action = .cycle_animation };
        items[4] = .{ .id = "clock", .label = "Clock", .action = .card_clock };

        var manual_order: std.ArrayList(usize) = .empty;
        errdefer manual_order.deinit(allocator);
        try manual_order.appendSlice(allocator, &[_]usize{ 0, 1, 2, 3, 4 });

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

        const card_tree = root.createSceneTree() catch null;

        return .{
            .allocator = allocator,
            .host = host,
            .root = root,
            .outputs = .empty,
            .barry_pets = .empty,
            .card_tree = card_tree,
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
        if (self.card_scene_buffer) |sb| sb.node.destroy();
        if (self.card_buffer) |buf| wlr.Buffer.drop(buf);
        if (self.card_tree) |tree| tree.node.destroy();
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
            self.bobChangedState(.sitting);
        } else {
            self.close_after_us = 0;
            self.selected_index = 0;
            self.hover_index = null;
            self.bobChangedState(.laying);
        }
        self.requestUpdate();
        self.host.request_frame(self.host.ctx);
    }

    pub fn toggleCard(self: *Self) void {
        self.card_open = !self.card_open;
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
            self.bobChangedState(.sitting);
        } else {
            self.bobChangedState(.standing);
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
            self.bobChangedState(.standing);
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
            .card_clock => self.toggleCard(),
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
            self.bobChangedState(.standing);
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

    fn bobChangedState(self: *Self, state: BarryState) void {
        if (self.barry_state_target == state) return;
        self.barry_state_target = state;
        self.bob_state_vel = 0.0;
        // Barry waits until Bob has fully settled, then follows ~3 s later.
        const delay_us: u64 = if (state == .laying) 3_500_000 else 3_000_000;
        self.barry_follow_deadline_us = animation.nowUs() + delay_us;
        self.requestUpdate();
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
            animation.Spring{ .stiffness = 6.0, .damping = 0.94, .epsilon = 0.001 }
        else
            animation.Spring{ .stiffness = 80.0, .damping = 0.95, .epsilon = 0.001 };
        const open_step = open_spring.step(self.open_amount, self.open_amount_vel, desired, dt);
        self.open_amount = @floatCast(open_step.value);
        self.open_amount_vel = @floatCast(open_step.velocity);

        // Selection underline position spring.
        const target_underline: f32 = self.underlineTarget();
        const us = animation.Spring{ .stiffness = 18.0, .damping = 0.85, .epsilon = 0.5 };
        const us_step = us.step(self.underline_x, self.underline_vel, target_underline, dt);
        self.underline_x = @floatCast(us_step.value);
        self.underline_vel = @floatCast(us_step.velocity);

        // Freeze Bob/Barry while slides/windows are moving so they stay rock solid.
        const windows_moving = self.host.is_transition_active(self.host.ctx);

        var bob_settled: bool = true;
        var barry_settled: bool = true;

        if (!windows_moving) {
            const target_state: f32 = switch (self.barry_state_target) {
                .laying => 0.0,
                .sitting => 1.0,
                .standing => 2.0,
            };

            // Bob snaps to the target pose.
            const bob_state_spring = animation.Spring{ .stiffness = 28.0, .damping = 0.92, .epsilon = 0.005 };
            const bob_state_step = bob_state_spring.step(self.bob_state_t, self.bob_state_vel, target_state, dt);
            self.bob_state_t = @floatCast(bob_state_step.value);
            self.bob_state_vel = @floatCast(bob_state_step.velocity);
            bob_settled = bob_state_step.settled;

            // Barry follows Bob after his lazy delay.
            const barry_state_spring = animation.Spring{ .stiffness = 28.0, .damping = 0.92, .epsilon = 0.005 };
            const barry_state_step = barry_state_spring.step(self.barry_state_t, self.barry_state_vel, target_state, dt);
            self.barry_state_t = @floatCast(barry_state_step.value);
            self.barry_state_vel = @floatCast(barry_state_step.velocity);
            barry_settled = barry_state_step.settled;

            if (animation.nowUs() >= self.barry_follow_deadline_us and self.barry_follow_deadline_us != 0) {
                self.barry_follow_deadline_us = 0;
                self.setBarryState(self.barry_state_target);
            }

            // Bob animates during tray/underline/state movement; short settle pulse after.
            const bob_moving = !open_step.settled or !bob_state_step.settled or !us_step.settled;
            if (bob_moving) {
                self.barry_breath_t += dt * 1.5;
                self.bob_breath_amp = @min(0.04, self.bob_breath_amp + dt * 0.4);
                self.bob_bob_amp = @min(1.0, self.bob_bob_amp + dt * 5.0);
                self.bob_was_moving = true;
            } else if (self.bob_was_moving) {
                const settle_dur: f64 = 0.17;
                self.bob_settle_t += dt;
                if (self.bob_settle_t >= settle_dur) {
                    self.bob_was_moving = false;
                    self.bob_settle_t = 0.0;
                    self.bob_breath_amp = 0.0;
                    self.bob_bob_amp = 0.0;
                } else {
                    const pulse = std.math.sin((self.bob_settle_t / settle_dur) * std.math.pi);
                    self.bob_breath_amp = 0.025 * pulse;
                    self.bob_bob_amp = 0.9 * pulse;
                    self.barry_breath_t += dt * 0.7;
                }
            } else {
                self.bob_breath_amp = 0.0;
                self.bob_bob_amp = 0.0;
            }

            // Barry mirrors Bob's pose with a delay, then does his own short pulse.
            const barry_moving = !barry_state_step.settled;
            if (barry_moving) {
                self.barry_breath_t += dt * 1.5;
                self.barry_breath_amp = @min(0.04, self.barry_breath_amp + dt * 0.4);
                self.barry_bob_amp = @min(1.0, self.barry_bob_amp + dt * 5.0);
                self.barry_was_moving = true;
            } else if (self.barry_was_moving) {
                const settle_dur: f64 = 0.17;
                self.barry_settle_t += dt;
                if (self.barry_settle_t >= settle_dur) {
                    self.barry_was_moving = false;
                    self.barry_settle_t = 0.0;
                    self.barry_breath_amp = 0.0;
                    self.barry_bob_amp = 0.0;
                } else {
                    const pulse = std.math.sin((self.barry_settle_t / settle_dur) * std.math.pi);
                    self.barry_breath_amp = 0.025 * pulse;
                    self.barry_bob_amp = 0.9 * pulse;
                    self.barry_breath_t += dt * 0.7;
                }
            } else {
                self.barry_breath_amp = 0.0;
                self.barry_bob_amp = 0.0;
            }
        } else {
            // Slides/windows moving: keep poses and amplitudes frozen.
            self.bob_state_vel = 0.0;
            self.barry_state_vel = 0.0;
            self.bob_breath_amp = 0.0;
            self.bob_bob_amp = 0.0;
            self.barry_breath_amp = 0.0;
            self.barry_bob_amp = 0.0;
            self.bob_was_moving = false;
            self.bob_settle_t = 0.0;
            self.barry_was_moving = false;
            self.barry_settle_t = 0.0;
            // Push Barry's deadline so he doesn't start until motion has stopped.
            if (self.barry_follow_deadline_us != 0) {
                const delay_us: u64 = if (self.barry_state_target == .laying) 3_500_000 else 3_000_000;
                self.barry_follow_deadline_us = animation.nowUs() + delay_us;
            }
        }

        var needs_redraw = prev == 0 or
            (self.open_amount > 0.001 and self.open_amount < 0.999) or
            !bob_settled or
            !barry_settled or
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

        self.updateCard();

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
        // Keep Barry exactly within the left peek panel width, not wider.
        return self.panelWidth(info);
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
        const t: f64 = @as(f64, std.math.clamp(self.bob_state_t, 0.0, 2.0));
        const idx0: usize = @intFromFloat(@floor(t));
        const idx1: usize = @min(idx0 + 1, 2);
        const blend: f64 = t - @floor(t);

        // Movement-driven breath + bob for Bob.
        const breath: f64 = 1.0 + self.bob_breath_amp * @sin(self.barry_breath_t * 2.0);
        const bob: f64 = self.bob_bob_amp * s * @sin(self.barry_breath_t * 2.0);

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
            const c4 = self.host.theme.style.tray_text_focused_color.toF64();
            c.cairo_pattern_add_color_stop_rgba(glass, 0.5, c4[0], c4[1], c4[2], 0.22 * alpha);
        }
        c.cairo_pattern_add_color_stop_rgba(glass, 1.0, 0.04, 0.04, 0.05, 0.78 * alpha);
        c.cairo_set_source(cr, glass);
        c.cairo_fill_preserve(cr);
        c.cairo_pattern_destroy(glass);

        // Gold rim.
        const rim4 = self.host.theme.style.color_gold.toF64();
        c.cairo_set_source_rgba(cr, rim4[0], rim4[1], rim4[2], 0.45 * alpha);
        c.cairo_set_line_width(cr, 1.0 * s);
        c.cairo_stroke(cr);

        // Render label.
        const label_c: [*c]const u8 = @ptrCast(it.label);
        const font_size = self.host.theme.style.tray_font_size * s;
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

        const text_color = if (focused) self.host.theme.style.tray_text_focused_color else self.host.theme.style.tray_text_color;
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
        const gold = self.host.theme.style.tray_text_focused_color.toF64();
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



    fn updateCard(self: *Self) void {
        const now_us = animation.nowUs();
        const prev = self.last_update_us;
        const dt = if (prev == 0) 0.0 else @as(f64, @floatFromInt(now_us - prev)) / 1_000_000.0;

        const desired: f32 = if (self.card_open) 1.0 else 0.0;
        const closing = desired < self.card_open_amount;
        const spring = if (closing)
            animation.Spring{ .stiffness = 8.0, .damping = 0.92, .epsilon = 0.001 }
        else
            animation.Spring{ .stiffness = 60.0, .damping = 0.95, .epsilon = 0.001 };
        const step = spring.step(self.card_open_amount, self.card_open_amount_vel, desired, dt);
        self.card_open_amount = @floatCast(step.value);
        self.card_open_amount_vel = @floatCast(step.velocity);

        if (self.card_open_amount < 0.005 and !self.card_open) {
            if (self.card_tree) |tree| tree.node.setEnabled(false);
            return;
        }

        const box = self.host.focused_window_box(self.host.ctx) orelse {
            if (self.card_tree) |tree| tree.node.setEnabled(false);
            return;
        };
        self.card_box = box;

        var w = box.width;
        var h = box.height;
        if (w <= 260 or h <= 260) {
            w = @min(w, 320);
            h = @min(h, 240);
        } else {
            w -= 160;
            h -= 160;
        }
        if (w <= 0 or h <= 0) {
            if (self.card_tree) |tree| tree.node.setEnabled(false);
            return;
        }
        const card_x = box.x + @divTrunc(box.width - w, 2);
        const card_y = box.y + @divTrunc(box.height - h, 2);

        const needs_redraw = self.card_last_w != w or
            self.card_last_h != h or
            @abs(self.card_last_open - self.card_open_amount) > 0.0001 or
            self.card_last_generation != self.host.theme.generation or
            !step.settled;

        if (self.card_tree) |tree| {
            tree.node.setEnabled(true);
            tree.node.raiseToTop();
            tree.node.setPosition(card_x, card_y);
        }

        if (needs_redraw) {
            self.card_last_w = w;
            self.card_last_h = h;
            self.card_last_open = self.card_open_amount;
            self.card_last_generation = self.host.theme.generation;
            self.renderCardBuffer(w, h);
        }
    }

    fn renderCardBuffer(self: *Self, w_i: i32, h_i: i32) void {
        const DataBuffer = @import("../render/buffer.zig").DataBuffer;
        const w = w_i;
        const h = h_i;

        const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, w);
        if (stride <= 0) return;
        const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(h));
        const temp = self.allocator.alloc(u8, buf_size) catch |err| {
            std.log.err("KidulWM: card buffer alloc failed: {}", .{err});
            return;
        };
        defer self.allocator.free(temp);
        @memset(temp, 0);

        const surface = c.cairo_image_surface_create_for_data(temp.ptr, c.CAIRO_FORMAT_ARGB32, w, h, stride);
        defer c.cairo_surface_destroy(surface);
        const cr = c.cairo_create(surface) orelse {
            std.log.err("KidulWM: failed to create cairo context for card", .{});
            return;
        };
        defer c.cairo_destroy(cr);

        self.drawClockCalendarCard(cr, @floatFromInt(w), @floatFromInt(h));

        const buffer = DataBuffer.create(temp, w, h, @intCast(stride)) catch |err| {
            std.log.err("KidulWM: failed to create card buffer: {}", .{err});
            return;
        };
        if (self.card_buffer) |old| wlr.Buffer.drop(old);
        self.card_buffer = buffer;
        if (self.card_scene_buffer) |old| old.node.destroy();
        const tree = self.card_tree orelse return;
        self.card_scene_buffer = tree.createSceneBuffer(buffer) catch |err| {
            std.log.err("KidulWM: failed to create card scene buffer: {}", .{err});
            return;
        };
        if (self.card_scene_buffer) |sb| sb.node.raiseToTop();
    }

        const CalendarCell = struct {
            day: i32,
            col: i32,
            row: i32,
            in_month: bool,
            is_today: bool,
        };

        /// Build a 7×6 grid anchored to the current month. Returns the current
        /// month’s days plus leading/trailing days so the grid never has holes.
        fn calendarCells(cells: []CalendarCell, year: i32, month: i32, today_mday: i32) void {
            const dim = daysInMonth(month, year);
            var probe: c.struct_tm = std.mem.zeroes(c.struct_tm);
            probe.tm_year = year - 1900;
            probe.tm_mon = month - 1;
            probe.tm_mday = 1;
            probe.tm_hour = 12;
            probe.tm_min = 0;
            probe.tm_sec = 0;
            probe.tm_isdst = -1;
            const first_t: c.time_t = c.mktime(&probe);
            var first_local: c.struct_tm = undefined;
            const first_tm = c.localtime_r(&first_t, &first_local);
            const start_wday = @as(i32, @intCast(first_tm.*.tm_wday));

            // Pad with previous month when the month does not start on Sunday.
            var prev_year = year;
            var prev_month = month - 1;
            if (prev_month < 1) {
                prev_month = 12;
                prev_year -= 1;
            }
            const prev_dim = daysInMonth(prev_month, prev_year);
            var i: usize = 0;
            const leading = start_wday;
            var col: i32 = 0;
            while (col < leading) : (col += 1) {
                cells[i] = .{
                    .day = prev_dim - leading + 1 + col,
                    .col = col,
                    .row = 0,
                    .in_month = false,
                    .is_today = false,
                };
                i += 1;
            }

            var day: i32 = 1;
            while (day <= dim) : (day += 1) {
                const cell_index = start_wday + day - 1;
                cells[i] = .{
                    .day = day,
                    .col = @mod(cell_index, 7),
                    .row = @divTrunc(cell_index, 7),
                    .in_month = true,
                    .is_today = day == today_mday,
                };
                i += 1;
            }

            // Fill remainder with next month to complete 6 rows.
            var next_year = year;
            var next_month = month + 1;
            if (next_month > 12) {
                next_month = 1;
                next_year += 1;
            }
            day = 1;
            while (i < cells.len) : (i += 1) {
                const cell_index = start_wday + dim + day - 1;
                cells[i] = .{
                    .day = day,
                    .col = @mod(cell_index, 7),
                    .row = @divTrunc(cell_index, 7),
                    .in_month = false,
                    .is_today = false,
                };
                day += 1;
            }
        }

        fn drawClockCalendarCard(self: *const Self, cr: *c.cairo_t, w: f64, h: f64) void {
            const tstyle = self.host.theme.style;
            const bg = tstyle.tray_bg_color;
            const gold = tstyle.color_gold;
            const text = tstyle.tray_text_focused_color;
            const muted = tstyle.color_text_muted;
            const card_font = "Fantasque Sans Mono";

            // Respect theme font sizes, scaled slightly down to fit glass card.
            const time_font_size = tstyle.font_size_l * 1.2;
            const date_font_size = tstyle.font_size_m;
            const day_font_size = tstyle.font_size_s;

            // Clear; draw glass rounded body with gold rim, then crop all content inside.
            c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
            c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
            c.cairo_paint(cr);
            c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

            const radius: f64 = @min(14.0, @min(w, h) * 0.05);
            cairoRoundedRect(cr, 0.0, 0.0, w, h, radius);

            // Body fill.
            const bg4 = bg.toF64();
            c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], bg4[3]);
            c.cairo_fill_preserve(cr);

            // Gold rim.
            const gold4 = gold.toF64();
            c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], gold4[3]);
            c.cairo_set_line_width(cr, 2.0);
            c.cairo_stroke(cr);

            // Clip to rounded interior so nothing spills past the rim.
            cairoRoundedRect(cr, 1.0, 1.0, w - 2.0, h - 2.0, radius - 1.0);
            c.cairo_clip(cr);

            const pad_x: f64 = 30.0;
            const pad_y: f64 = 22.0;
            const content_w = w - 2.0 * pad_x;
            const content_h = h - 2.0 * pad_y;

            var now: c.time_t = c.time(null);
            var local: c.struct_tm = undefined;
            const tm = c.localtime_r(&now, &local);
            const year = @as(i32, @intCast(tm.*.tm_year)) + 1900;
            const month = @as(i32, @intCast(tm.*.tm_mon)) + 1;
            const today_mday = @as(i32, @intCast(tm.*.tm_mday));

            // ---- Time: HH:MM ----
            c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
            c.cairo_set_font_size(cr, time_font_size);
            const text_color = text.toF64();
            c.cairo_set_source_rgba(cr, text_color[0], text_color[1], text_color[2], text_color[3]);

            var time_buf: [16:0]u8 = undefined;
            {
                @memset(&time_buf, 0);
                const hour = @rem(@as(i32, @intCast(tm.*.tm_hour)), 24);
                const minute = @as(i32, @intCast(tm.*.tm_min));
                time_buf[0] = @intCast('0' + @divFloor(hour, 10));
                time_buf[1] = @intCast('0' + @mod(hour, 10));
                time_buf[2] = ':';
                time_buf[3] = @intCast('0' + @divFloor(minute, 10));
                time_buf[4] = @intCast('0' + @mod(minute, 10));
                time_buf[5] = 0;
            }
            const time_str: [*:0]const u8 = @ptrCast(&time_buf);

            var time_ext: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, time_str, &time_ext);
            const time_x = pad_x + (content_w - time_ext.width) * 0.5;
            var time_y = pad_y + time_font_size * 0.9;
            if (content_w > time_ext.width + 10.0) {
                time_y = pad_y + time_font_size;
            }
            c.cairo_move_to(cr, time_x, time_y);
            c.cairo_show_text(cr, time_str);

            // ---- Cinematic stacked date block ----
            const date_color = muted.toF64();
            const weekday_name = weekdayName(tm.*.tm_wday);
            const month_name = monthName(tm.*.tm_mon);

            var cursor_y = time_y + time_font_size * 0.6;

            // 1) Weekday
            c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
            c.cairo_set_font_size(cr, date_font_size * 1.25);
            c.cairo_set_source_rgba(cr, text_color[0], text_color[1], text_color[2], text_color[3]);
            var tmp_ext: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, weekday_name.ptr, &tmp_ext);
            cursor_y += date_font_size * 1.0;
            c.cairo_move_to(cr, pad_x + (content_w - tmp_ext.width) * 0.5, cursor_y);
            c.cairo_show_text(cr, weekday_name.ptr);

            // 2) "the 12th of" — outer words dimmed/small, day number prominent
            const outer_font_size = date_font_size * 0.65;
            const num_font_size = date_font_size * 1.05;
            const inner_y = cursor_y + date_font_size * 1.15;

            const the_str = "the";
            var num_buf: [12:0]u8 = undefined;
            const suffix = ordinalSuffix(today_mday);
            const num_str = std.fmt.bufPrintZ(&num_buf, "{d}{s}", .{ today_mday, suffix }) catch return;
            const of_str = "of";

            c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
            c.cairo_set_font_size(cr, outer_font_size);
            c.cairo_set_source_rgba(cr, date_color[0], date_color[1], date_color[2], date_color[3]);
            c.cairo_text_extents(cr, the_str, &tmp_ext);
            const the_w = tmp_ext.width;
            c.cairo_text_extents(cr, of_str, &tmp_ext);
            const of_w = tmp_ext.width;

            c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
            c.cairo_set_font_size(cr, num_font_size);
            c.cairo_set_source_rgba(cr, text_color[0], text_color[1], text_color[2], text_color[3]);
            c.cairo_text_extents(cr, num_str, &tmp_ext);
            const num_w = tmp_ext.width;
            const total_mid_w = the_w + 4.0 + num_w + 4.0 + of_w;
            const mid_x = pad_x + (content_w - total_mid_w) * 0.5;

            // draw "the"
            c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
            c.cairo_set_font_size(cr, outer_font_size);
            c.cairo_set_source_rgba(cr, date_color[0], date_color[1], date_color[2], date_color[3]);
            c.cairo_move_to(cr, mid_x, inner_y);
            c.cairo_show_text(cr, the_str);

            // draw day number
            c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
            c.cairo_set_font_size(cr, num_font_size);
            c.cairo_set_source_rgba(cr, text_color[0], text_color[1], text_color[2], text_color[3]);
            c.cairo_move_to(cr, mid_x + the_w + 4.0, inner_y);
            c.cairo_show_text(cr, num_str);

            // draw "of"
            c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
            c.cairo_set_font_size(cr, outer_font_size);
            c.cairo_set_source_rgba(cr, date_color[0], date_color[1], date_color[2], date_color[3]);
            c.cairo_move_to(cr, mid_x + the_w + 4.0 + num_w + 4.0, inner_y);
            c.cairo_show_text(cr, of_str);

            // 3) Month
            cursor_y = inner_y + date_font_size * 0.9;
            c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
            c.cairo_set_font_size(cr, date_font_size * 1.25);
            c.cairo_set_source_rgba(cr, text_color[0], text_color[1], text_color[2], text_color[3]);
            c.cairo_text_extents(cr, month_name.ptr, &tmp_ext);
            c.cairo_move_to(cr, pad_x + (content_w - tmp_ext.width) * 0.5, cursor_y);
            c.cairo_show_text(cr, month_name.ptr);

            // ---- Calendar grid ----
            const header = &[_][]const u8{ "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" };
            const rows: i32 = 6;
            // extra gap between weekday letters and first row of numbers
            const header_margin: f64 = day_font_size * 1.0;
            const grid_top = cursor_y + date_font_size * 0.7;
            const usable_h = content_h - (grid_top - pad_y);
            const cell_w = content_w / 7.0;
            const cell_h = if (usable_h > 0.0) @max(day_font_size * 1.7, usable_h / @as(f64, @floatFromInt(rows + 1))) else day_font_size * 1.7;

            c.cairo_set_font_size(cr, day_font_size);
            var day_ext: c.cairo_text_extents_t = undefined;

            // Weekday header row in muted gold.
            c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
            c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.85);
            const header_baseline = grid_top + day_font_size;
            for (header, 0..) |txt, ci| {
                c.cairo_text_extents(cr, txt.ptr, &day_ext);
                const hx = pad_x + @as(f64, @floatFromInt(ci)) * cell_w + (cell_w - day_ext.width) * 0.5;
                c.cairo_move_to(cr, hx, header_baseline);
                c.cairo_show_text(cr, txt.ptr);
            }

            var cells: [42]CalendarCell = undefined;
            calendarCells(&cells, year, month, today_mday);

            const grid_origin_y = header_baseline + header_margin;
            for (cells) |cell| {
                const cx = pad_x + @as(f64, @floatFromInt(cell.col)) * cell_w;
                const cy = grid_origin_y + @as(f64, @floatFromInt(cell.row)) * cell_h + cell_h * 0.55;

                const cell_pad: f64 = 1.5;
                const cell_rect_x = cx + cell_pad;
                const cell_rect_y = cy - cell_h * 0.45;
                const cell_rect_w = cell_w - 2.0 * cell_pad;
                const cell_rect_h = cell_h * 0.9;

                if (cell.in_month) {
                    // subtle glass cell border
                    cairoRoundedRect(cr, cell_rect_x, cell_rect_y, cell_rect_w, cell_rect_h, 4.0);
                    c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.35);
                    c.cairo_set_line_width(cr, 1.0);
                    c.cairo_stroke(cr);
                }

                // Today gets a gold-tinted background.
                if (cell.is_today) {
                    cairoRoundedRect(cr, cell_rect_x + 2.0, cell_rect_y + 2.0, cell_rect_w - 4.0, cell_rect_h - 4.0, 4.0);
                    c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.22);
                    c.cairo_fill_preserve(cr);
                    c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.65);
                    c.cairo_set_line_width(cr, 1.0);
                    c.cairo_stroke(cr);
                }

                var day_buf: [4:0]u8 = undefined;
                const day_str = std.fmt.bufPrintZ(&day_buf, "{d}", .{cell.day}) catch continue;
                c.cairo_text_extents(cr, day_str.ptr, &day_ext);

                c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, if (cell.is_today) c.CAIRO_FONT_WEIGHT_BOLD else c.CAIRO_FONT_WEIGHT_NORMAL);
                if (cell.in_month) {
                    if (cell.is_today) {
                        c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], gold4[3]);
                    } else {
                        c.cairo_set_source_rgba(cr, text_color[0], text_color[1], text_color[2], text_color[3]);
                    }
                } else {
                    c.cairo_set_source_rgba(cr, date_color[0], date_color[1], date_color[2], date_color[3] * 0.5);
                }
                const tx = cx + (cell_w - day_ext.width) * 0.5;
                const ty = cy;
                c.cairo_move_to(cr, tx, ty);
                c.cairo_show_text(cr, day_str.ptr);
            }
        }


        fn ordinalSuffix(n: i32) []const u8 {
            const m = @mod(n, 100);
            if (m >= 11 and m <= 13) return "th";
            return switch (@mod(n, 10)) {
                1 => "st",
                2 => "nd",
                3 => "rd",
                else => "th",
            };
        }

        fn weekdayName(wday: c_int) []const u8 {
            return switch (wday) {
                0 => "Sunday",
                1 => "Monday",
                2 => "Tuesday",
                3 => "Wednesday",
                4 => "Thursday",
                5 => "Friday",
                6 => "Saturday",
                else => "",
            };
        }

        fn monthName(mon: c_int) []const u8 {
            return switch (mon) {
                0 => "January",
                1 => "February",
                2 => "March",
                3 => "April",
                4 => "May",
                5 => "June",
                6 => "July",
                7 => "August",
                8 => "September",
                9 => "October",
                10 => "November",
                11 => "December",
                else => "",
            };
        }

    fn daysInMonth(month: i32, year: i32) i32 {
        return switch (month) {
            1, 3, 5, 7, 8, 10, 12 => 31,
            4, 6, 9, 11 => 30,
            2 => if ((@mod(year, 4) == 0 and @mod(year, 100) != 0) or @mod(year, 400) == 0) 29 else 28,
            else => 0,
        };
    }

    fn cairoRoundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
        const radius = @min(r, w / 2.0);
        const radius_h = @min(radius, h / 2.0);
        c.cairo_new_sub_path(cr);
        c.cairo_arc(cr, x + w - radius_h, y + radius_h, radius_h, -std.math.pi / 2.0, 0.0);
        c.cairo_arc(cr, x + w - radius_h, y + h - radius_h, radius_h, 0.0, std.math.pi / 2.0);
        c.cairo_arc(cr, x + radius_h, y + h - radius_h, radius_h, std.math.pi / 2.0, std.math.pi);
        c.cairo_arc(cr, x + radius_h, y + radius_h, radius_h, std.math.pi, 3.0 * std.math.pi / 2.0);
        c.cairo_close_path(cr);
    }
};
