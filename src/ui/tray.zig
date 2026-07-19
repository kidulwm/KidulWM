const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const c = @import("dm").c;
const theme_mod = @import("../core/theme.zig");
const style = @import("../core/style.zig");
const animation = @import("../core/animation.zig");
const WeatherWidget = @import("./weather.zig").WeatherWidget;

// Logo assets: top-of-tray emblem (Bob) and bottom text wordmark.
const bob_logo_png = @embedFile("assets/bob/logo.png");
const bob_text_png = @embedFile("assets/bob/text.png");
const bob_text_mask_png = @embedFile("assets/bob/text_mask.png");

// Archived Barry pose assets (tag tray-logo-animation-backup).
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
    right_peek_box: *const fn (ctx: *anyopaque, output_index: usize) ?wlr.Box,
    left_peek_box: *const fn (ctx: *anyopaque, output_index: usize) ?wlr.Box,
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

const PerOutputWidget = struct {
    output_ctx: *anyopaque,
    tree: *wlr.SceneTree,
    scene_buffer: ?*wlr.SceneBuffer,
    buffer: ?*wlr.Buffer,
    info: OutputInfo,
    last_w: i32 = 0,
    last_h: i32 = 0,
    last_x: i32 = 0,
    last_y: i32 = 0,
    last_scale: f32 = 0.0,
    last_corner_style: style.Style.CornerStyle = .round,
    last_time_minute: i32 = -1,
    last_theme_generation: u32 = 0,
};


const PerOutputWeather = struct {
    output_ctx: *anyopaque,
    tree: *wlr.SceneTree,
    scene_buffer: ?*wlr.SceneBuffer,
    buffer: ?*wlr.Buffer,
    info: OutputInfo,
    last_w: i32 = 0,
    last_h: i32 = 0,
    last_x: i32 = 0,
    last_y: i32 = 0,
    last_scale: f32 = 0.0,
    last_minute: i32 = -1,
    last_theme_generation: u32 = 0,
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

    // Focused-slide card (clock/calendar/weather).
    calendar_card_open: bool = false,
    weather_card_open: bool = false,
    card_open_amount: f32 = 0.0,
    card_open_amount_vel: f32 = 0.0,
    card_box: wlr.Box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    card_year: i32 = 0,
    card_month: i32 = 0,
    card_focused_year: i32 = 0,
    card_focused_month: i32 = 0,
    card_focused_day: i32 = 0,
    card_focused_generation: u32 = 0,
    card_hover_row: ?i32 = null,
    card_hover_col: ?i32 = null,

    // Top-right peek widget (clock/date).
    widgets: std.ArrayList(PerOutputWidget),
    // Top-left peek widget (weather).
    weather_widgets: std.ArrayList(PerOutputWeather),
    weather: WeatherWidget,
    card_tree: ?*wlr.SceneTree = null,
    card_scene_buffer: ?*wlr.SceneBuffer = null,
    card_buffer: ?*wlr.Buffer = null,
    card_last_w: i32 = 0,
    card_last_h: i32 = 0,
    card_last_open: f32 = -1.0,
    card_last_generation: u32 = 0,
    card_last_mode: CardMode = .calendar,

    // Last clickable bounding box of the clock/date peek widget (scene coords).
    widget_click_box: wlr.Box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    // Last clickable bounding box of the left-peek weather widget (scene coords).
    weather_click_box: wlr.Box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },

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
    // Simplified static logos (pose animation archived under tag tray-logo-animation-backup).
    bob_logo: *c.cairo_surface_t,
    bob_text: *c.cairo_surface_t,
    bob_text_mask: *c.cairo_surface_t,

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

        const bob_logo = try loadPngFromBytes(bob_logo_png);
        errdefer c.cairo_surface_destroy(bob_logo);
        const bob_text = try loadPngFromBytes(bob_text_png);
        errdefer c.cairo_surface_destroy(bob_text);
        const bob_text_mask = try loadPngFromBytes(bob_text_mask_png);
        errdefer c.cairo_surface_destroy(bob_text_mask);

        const card_tree = root.createSceneTree() catch null;
        var now: c.time_t = c.time(null);
        var local_tmp: c.struct_tm = undefined;
        const local_now = c.localtime_r(&now, &local_tmp).*;

        return .{
            .allocator = allocator,
            .host = host,
            .root = root,
            .outputs = .empty,
            .barry_pets = .empty,
            .widgets = .empty,
            .weather_widgets = .empty,
            .weather = WeatherWidget.init(allocator),
            .card_tree = card_tree,
            .card_year = @as(i32, @intCast(local_now.tm_year)) + 1900,
            .card_month = @as(i32, @intCast(local_now.tm_mon)) + 1,
            .card_focused_year = @as(i32, @intCast(local_now.tm_year)) + 1900,
            .card_focused_month = @as(i32, @intCast(local_now.tm_mon)) + 1,
            .card_focused_day = @as(i32, @intCast(local_now.tm_mday)),
            .items = items,
            .manual_order = manual_order,
            .icon_cache = std.StringHashMap(*c.cairo_surface_t).init(allocator),
            .barry_lay = barry_lay,
            .barry_sit = barry_sit,
            .barry_stand = barry_stand,
            .barry_puppy_lay = barry_puppy_lay,
            .barry_puppy_sit = barry_puppy_sit,
            .barry_puppy_stand = barry_puppy_stand,
            .bob_logo = bob_logo,
            .bob_text = bob_text,
            .bob_text_mask = bob_text_mask,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.outputs.items) |*po| self.destroyPerOutput(po);
        for (self.barry_pets.items) |*pet| self.destroyPet(pet);
        for (self.widgets.items) |*w| self.destroyWidget(w);
        for (self.weather_widgets.items) |*w| self.destroyWeatherWidget(w);
        self.weather.deinit();
        self.outputs.deinit(self.allocator);
        self.barry_pets.deinit(self.allocator);
        self.widgets.deinit(self.allocator);
        self.weather_widgets.deinit(self.allocator);
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
        c.cairo_surface_destroy(self.bob_logo);
        c.cairo_surface_destroy(self.bob_text);
        c.cairo_surface_destroy(self.bob_text_mask);
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
        const widget_tree = self.root.createSceneTree() catch |err| {
            std.log.err("KidulWM: failed to create clock widget scene tree: {}", .{err});
            return;
        };
        const widget = PerOutputWidget{
            .output_ctx = output_ctx,
            .tree = widget_tree,
            .scene_buffer = null,
            .buffer = null,
            .info = .{ .x = 0, .y = 0, .width = 0, .height = 0, .scale = 1.0, .focus_left = 0 },
        };
        self.widgets.append(self.allocator, widget) catch |err| {
            std.log.err("KidulWM: failed to append clock widget: {}", .{err});
            widget_tree.node.destroy();
        };

        const weather_tree = self.root.createSceneTree() catch |err| {
            std.log.err("KidulWM: failed to create weather widget scene tree: {}", .{err});
            return;
        };
        const weather_widget = PerOutputWeather{
            .output_ctx = output_ctx,
            .tree = weather_tree,
            .scene_buffer = null,
            .buffer = null,
            .info = .{ .x = 0, .y = 0, .width = 0, .height = 0, .scale = 1.0, .focus_left = 0 },
        };
        self.weather_widgets.append(self.allocator, weather_widget) catch |err| {
            std.log.err("KidulWM: failed to append weather widget: {}", .{err});
            weather_tree.node.destroy();
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
        for (self.widgets.items, 0..) |*w, i| {
            if (w.output_ctx == output_ctx) {
                self.destroyWidget(w);
                _ = self.widgets.orderedRemove(i);
                break;
            }
        }
        for (self.weather_widgets.items, 0..) |*w, i| {
            if (w.output_ctx == output_ctx) {
                self.destroyWeatherWidget(w);
                _ = self.weather_widgets.orderedRemove(i);
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

    fn destroyWidget(_: *Self, widget: *PerOutputWidget) void {
        if (widget.scene_buffer) |sb| sb.node.destroy();
        if (widget.buffer) |buf| wlr.Buffer.drop(buf);
        widget.tree.node.destroy();
        widget.scene_buffer = null;
        widget.buffer = null;
    }


    fn destroyWeatherWidget(_: *Self, widget: *PerOutputWeather) void {
        if (widget.scene_buffer) |sb| sb.node.destroy();
        if (widget.buffer) |buf| wlr.Buffer.drop(buf);
        widget.tree.node.destroy();
        widget.scene_buffer = null;
        widget.buffer = null;
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
        self.calendar_card_open = !self.calendar_card_open;
        if (self.calendar_card_open) self.weather_card_open = false;
        self.requestUpdate();
        self.host.request_frame(self.host.ctx);
    }

    pub fn toggleWeatherCard(self: *Self) void {
        const now_open = !self.weather_card_open;
        self.weather_card_open = now_open;
        self.calendar_card_open = false;
        self.weather.toggleCard();
        self.requestUpdate();
        self.host.request_frame(self.host.ctx);
    }

    fn anyCardOpen(self: *const Self) bool {
        return self.calendar_card_open or self.weather_card_open;
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

        for (self.widgets.items) |*widget| {
            widget.info = self.host.output_info(self.host.ctx, widgetIndex(self, widget));
            self.drawWidget(widget);
        }

        // Update weather cache and draw left-peek widget.
        self.weather.update();
        for (self.weather_widgets.items) |*weather_widget| {
            weather_widget.info = self.host.output_info(self.host.ctx, weatherWidgetIndex(self, weather_widget));
            self.drawWeatherWidget(weather_widget);
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
        const surf = self.bob_logo;
        const img_w = @as(f64, @floatFromInt(c.cairo_image_surface_get_width(surf)));
        const img_h = @as(f64, @floatFromInt(c.cairo_image_surface_get_height(surf)));
        if (img_w <= 0.0 or img_h <= 0.0) return;

        const margin: f64 = 4.0 * s;
        const avail_w = w - 2.0 * margin;
        const scale = @min(avail_w / img_w, h * 0.90 / img_h);
        const draw_x = x + (w - img_w * scale) / 2.0;
        const draw_y = y + (h - img_h * scale) / 2.0;

        c.cairo_save(cr);
        c.cairo_translate(cr, draw_x, draw_y);
        c.cairo_scale(cr, scale, scale);
        c.cairo_set_source_surface(cr, surf, 0, 0);
        c.cairo_paint(cr);
        c.cairo_restore(cr);
    }


    fn drawPetButton(self: *Self, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, s: f64) void {
        _ = hmargin; // no lozenge margin needed; logo spans button bounds
        self.drawPet(cr, x, y, w, h, s);
    }
    fn drawPet(self: *const Self, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, s: f64) void {
        const surf = self.bob_text_mask;
        const img_w = @as(f64, @floatFromInt(c.cairo_image_surface_get_width(surf)));
        const img_h = @as(f64, @floatFromInt(c.cairo_image_surface_get_height(surf)));
        if (img_w <= 0.0 or img_h <= 0.0) return;

        const margin: f64 = 4.0 * s;
        const avail_w = w - 2.0 * margin;
        const avail_h = h - 2.0 * margin;
        const scale = @min(avail_w / img_w, avail_h / img_h);
        const left_nudge: f64 = 20.0 * s;
        const draw_x = x + (w - img_w * scale) / 2.0 - left_nudge;
        const bottom_above_border: f64 = (@as(f64, @floatCast(self.host.theme.style.border_width)) + 13.0) * s;
        const pet_bottom_pad: f64 = @as(f64, @floatFromInt(bottom_margin)) * s;
        const draw_y = y + h + pet_bottom_pad - bottom_above_border - img_h * scale;

        c.cairo_save(cr);
        c.cairo_translate(cr, draw_x, draw_y);
        c.cairo_scale(cr, scale, scale);

        const grad = c.cairo_pattern_create_linear(0.0, 0.0, 0.0, img_h);
        defer c.cairo_pattern_destroy(grad);
        const c1 = self.host.theme.style.color_border_focused.toF64();
        const c2 = self.host.theme.style.color_border.toF64();
        c.cairo_pattern_add_color_stop_rgba(grad, 0.0, c1[0], c1[1], c1[2], c1[3]);
        c.cairo_pattern_add_color_stop_rgba(grad, 1.0, c2[0], c2[1], c2[2], c2[3]);

        c.cairo_set_source(cr, grad);
        c.cairo_mask_surface(cr, surf, 0.0, 0.0);
        c.cairo_restore(cr);
    }


    fn drawStackButton(self: *const Self, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, stack_index: usize, focused: bool, hovered: bool, alpha: f64, s: f64) void {
        const it = self.activeItemAt(stack_index);
        const margin: f64 = @as(f64, hmargin) * s;
        const left_nudge: f64 = 2.0 * s;
        const peek_border: f64 = 6.0 * s;
        const pill_x: f64 = x + margin - left_nudge;
        const pill_w: f64 = w - margin - peek_border;
        const r: f64 = h / 2.0;
        const depth: f64 = r * 0.30;
        const tstyle = self.host.theme.style;

        c.cairo_save(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        // Shadow.
        panelOutline(tstyle, cr, pill_x + 2.0 * s, y + 3.0 * s, pill_w, h, depth);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.35 * alpha);
        c.cairo_fill(cr);

        // Glass body.
        _ = hovered;
        panelOutline(tstyle, cr, pill_x, y, pill_w, h, depth);
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
            panelOutline(tstyle, cr, ux, by, uw, border_h, 2.0 * s);

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

    fn squareRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64) void {
        c.cairo_rectangle(cr, x, y, w, h);
    }

    fn widgetIndex(self: *const Self, widget: *PerOutputWidget) usize {
        for (self.widgets.items, 0..) |*w, i| {
            if (w == widget) return i;
        }
        return 0;
    }

    fn weatherWidgetIndex(self: *const Self, widget: *PerOutputWeather) usize {
        for (self.weather_widgets.items, 0..) |*w, i| {
            if (w == widget) return i;
        }
        return 0;
    }

    fn pointInsideWidget(self: *const Self, px: f64, py: f64) bool {
        const b = self.widget_click_box;
        if (b.width <= 0 or b.height <= 0) return false;
        return px >= @as(f64, @floatFromInt(b.x)) and
            px < @as(f64, @floatFromInt(b.x + b.width)) and
            py >= @as(f64, @floatFromInt(b.y)) and
            py < @as(f64, @floatFromInt(b.y + b.height));
    }

    fn pointInsideWeatherWidget(self: *const Self, px: f64, py: f64) bool {
        const b = self.weather_click_box;
        if (b.width <= 0 or b.height <= 0) return false;
        return px >= @as(f64, @floatFromInt(b.x)) and
            px < @as(f64, @floatFromInt(b.x + b.width)) and
            py >= @as(f64, @floatFromInt(b.y)) and
            py < @as(f64, @floatFromInt(b.y + b.height));
    }


    fn fit_and_draw(
        cr: *c.cairo_t,
        font: [*:0]const u8,
        base_size: f64,
        weight: c.cairo_font_weight_t,
        txt: []const u8,
        r: f64,
        g: f64,
        b: f64,
        a: f64,
        max_w: f64,
        margin: f64,
    ) void {
        c.cairo_select_font_face(cr, font, c.CAIRO_FONT_SLANT_NORMAL, weight);
        var size = base_size;
        c.cairo_set_font_size(cr, size);
        var ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, @ptrCast(txt.ptr), &ext);
        while (ext.width > max_w - 2.0 * margin and size > 6.0) {
            size *= 0.92;
            c.cairo_set_font_size(cr, size);
            c.cairo_text_extents(cr, @ptrCast(txt.ptr), &ext);
        }
        c.cairo_set_source_rgba(cr, r, g, b, a);
    }


    fn panelOutline(tstyle: style.Style, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, depth: f64) void {
        switch (tstyle.corner_style) {
            .round => roundedRect(cr, x, y, w, h, depth),
            .chamfer => chamferedRect(cr, x, y, w, h, depth),
            .square => squareRect(cr, x, y, w, h),
        }
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

        // Track calendar card hover.
        if (self.calendar_card_open and self.card_box.width > 0 and self.card_box.height > 0) {
            const cbx = @as(f64, @floatFromInt(self.card_box.x));
            const cby = @as(f64, @floatFromInt(self.card_box.y));
            const cbw = @as(f64, @floatFromInt(self.card_box.width));
            const cbh = @as(f64, @floatFromInt(self.card_box.height));
            if (px >= cbx and px < cbx + cbw and py >= cby and py < cby + cbh) {
                if (self.handleCardDateHover(px - cbx, py - cby)) {
                    self.requestUpdate();
                }
            } else {
                if (self.card_hover_row != null or self.card_hover_col != null) {
                    self.card_hover_row = null;
                    self.card_hover_col = null;
                    self.requestUpdate();
                }
            }
        } else if (self.card_hover_row != null or self.card_hover_col != null) {
            self.card_hover_row = null;
            self.card_hover_col = null;
        }

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
        if (self.pointInsideWidget(px, py)) {
            self.toggleCard();
            _ = self.handleCardDateClick(px, py);
            return true;
        }
        if (self.pointInsideWeatherWidget(px, py)) {
            self.toggleWeatherCard();
            return true;
        }
        if (self.calendar_card_open and self.handleCardDateClick(px, py)) return true;

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

    fn handleCardDateClick(self: *Self, px: f64, py: f64) bool {
        if (!self.calendar_card_open) return false;
        const box = self.card_box;
        if (box.width <= 0 or box.height <= 0) return false;
        if (px < @as(f64, @floatFromInt(box.x)) or px >= @as(f64, @floatFromInt(box.x + box.width)) or
            py < @as(f64, @floatFromInt(box.y)) or py >= @as(f64, @floatFromInt(box.y + box.height)))
        {
            return false;
        }
        const pad_x: f64 = 30.0;
        const pad_y: f64 = 22.0;
        const day_font_size: f64 = @as(f64, self.host.theme.style.font_size_s);
        const date_font_size: f64 = @as(f64, self.host.theme.style.font_size_m);
        const pill_h: f64 = date_font_size + 16.0;
        const date_pill_y: f64 = pad_y + @as(f64, date_font_size) * 0.0;
        const local_px = px - @as(f64, @floatFromInt(box.x));
        const local_py = py - @as(f64, @floatFromInt(box.y));
        const content_w: f64 = @as(f64, @floatFromInt(box.width)) - 2.0 * pad_x;
        const content_h: f64 = @as(f64, @floatFromInt(box.height)) - 2.0 * pad_y;
        const header_margin: f64 = day_font_size * 0.4;
        const grid_top: f64 = date_pill_y + pill_h + date_font_size * 1.3;
        const usable_h: f64 = content_h - (grid_top - pad_y);
        const cell_w: f64 = content_w / 7.0;
        const cell_h: f64 = if (usable_h > 0.0) @max(day_font_size * 1.4, usable_h / 7.0) else day_font_size * 1.4;
        const header_baseline = grid_top + day_font_size;
        const grid_origin_y = header_baseline + header_margin;
        if (local_py < grid_top) return false;
        const col: i32 = @intFromFloat(@floor((local_px - pad_x) / cell_w));
        const row: i32 = @intFromFloat(@floor((local_py - grid_origin_y) / cell_h));
        if (col < 0 or col >= 7 or row < 0 or row >= 6) return false;

        var cells: [42]CalendarCell = undefined;
        calendarCells(&cells, self.card_year, self.card_month, self.card_focused_day, self.card_focused_year, self.card_focused_month, self.card_focused_day);
        const cell_index = @as(usize, @intCast(row)) * 7 + @as(usize, @intCast(col));
        if (cell_index >= cells.len) return false;
        const cell = cells[cell_index];
        if (cell.day <= 0) return false;

        var year = self.card_year;
        var month = self.card_month;
        if (!cell.in_month) {
            if (cell.day > 20) {
                month -= 1;
            } else {
                month += 1;
            }
            if (month < 1) {
                month = 12;
                year -= 1;
            } else if (month > 12) {
                month = 1;
                year += 1;
            }
        }
        if (self.card_focused_year == year and self.card_focused_month == month and self.card_focused_day == cell.day) return true;
        self.card_focused_year = year;
        self.card_focused_month = month;
        self.card_focused_day = cell.day;
        self.requestUpdate();
        self.host.request_frame(self.host.ctx);
        return true;
    }

    fn handleCardDateHover(self: *Self, local_px: f64, local_py: f64) bool {
        const pad_x: f64 = 30.0;
        const pad_y: f64 = 22.0;
        const day_font_size: f64 = @as(f64, self.host.theme.style.font_size_s);
        const cell_h: f64 = day_font_size * 1.15;
        const cell_w: f64 = (@as(f64, @floatFromInt(self.card_box.width)) - 2.0 * pad_x) / 7.0;
        const grid_origin_y: f64 = @as(f64, @floatFromInt(self.card_box.height)) - pad_y - 6.0 * cell_h;
        const col: i32 = @intFromFloat(@floor((local_px - pad_x) / cell_w));
        const row: i32 = @intFromFloat(@floor((local_py - grid_origin_y) / cell_h));
        const new_col = if (col >= 0 and col < 7) col else null;
        const new_row = if (row >= 0 and row < 6) row else null;
        const changed = (new_col != self.card_hover_col) or (new_row != self.card_hover_row);
        self.card_hover_col = new_col;
        self.card_hover_row = new_row;
        return changed;
    }

    fn drawWidget(self: *Self, widget: *PerOutputWidget) void {
        const box = self.host.right_peek_box(self.host.ctx, widgetIndex(self, widget)) orelse return;
        if (box.width <= 0 or box.height <= 0) return;

        var now_time: c.time_t = c.time(null);
        var local: c.struct_tm = undefined;
        const tm = c.localtime_r(&now_time, &local);
        const current_minute = @as(i32, @intCast(tm.*.tm_min)) + @as(i32, @intCast(tm.*.tm_hour)) * 60;
        const tstyle = self.host.theme.style;
        const theme_gen = self.host.theme.generation;
        const scale = widget.info.scale;

        // Full peek width minus 2 px each side. Push widget up to leave empty peek space above for future title.
        const peek_hmargin = 2;
        const peek_vmargin = 2;
        const pill_w: i32 = @max(20, box.width - 2 * peek_hmargin);
        const pill_x = box.x + peek_hmargin;
        const pill_h: i32 = @max(40, box.height - 2 * peek_vmargin);
        const pill_y = box.y + peek_vmargin;
        self.weather_click_box = .{ .x = pill_x, .y = pill_y, .width = pill_w, .height = pill_h };

        const needs_redraw = widget.scene_buffer == null or
            widget.last_w != pill_w or
            widget.last_h != pill_h or
            widget.last_x != pill_x or
            widget.last_y != pill_y or
            widget.last_scale != scale or
            widget.last_time_minute != current_minute or
            widget.last_theme_generation != theme_gen;

        self.widget_click_box = .{
            .x = pill_x,
            .y = pill_y,
            .width = pill_w,
            .height = pill_h,
        };

        if (!needs_redraw) {
            widget.tree.node.setPosition(pill_x, pill_y);
            widget.tree.node.raiseToTop();
            return;
        }

        widget.last_w = pill_w;
        widget.last_h = pill_h;
        widget.last_x = pill_x;
        widget.last_y = pill_y;
        widget.last_scale = scale;
        widget.last_time_minute = current_minute;
        widget.last_theme_generation = theme_gen;
        widget.last_corner_style = tstyle.corner_style;

        const dev_w: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(pill_w)) * scale));
        const dev_h: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(pill_h)) * scale));
        const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, dev_w);
        if (stride <= 0) return;
        const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(dev_h));
        const temp = self.allocator.alloc(u8, buf_size) catch |err| {
            std.log.err("KidulWM: clock widget buffer alloc failed: {}", .{err});
            return;
        };
        defer self.allocator.free(temp);
        @memset(temp, 0);

        const surface = c.cairo_image_surface_create_for_data(temp.ptr, c.CAIRO_FORMAT_ARGB32, dev_w, dev_h, stride);
        defer c.cairo_surface_destroy(surface);
        const cr = c.cairo_create(surface) orelse {
            std.log.err("KidulWM: failed to create cairo context for clock widget", .{});
            return;
        };
        defer c.cairo_destroy(cr);

        c.cairo_save(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        const card_font = "Fantasque Sans Mono";
        const muted_color = tstyle.color_text_muted.toF64();
        const w_d: f64 = @floatFromInt(dev_w);

        // 12-hour time with smaller am/pm suffix, packed near the top of the peek.
        const hour12 = @mod(@as(i32, @intCast(tm.*.tm_hour)), 12);
        const fixed_hour = if (hour12 == 0) 12 else hour12;
        const minute = @as(i32, @intCast(tm.*.tm_min));

        var num_buf: [16:0]u8 = undefined;
        @memset(&num_buf, 0);
        const num_str = std.fmt.bufPrintZ(&num_buf, "{d}:{d}{s}", .{
            fixed_hour,
            minute,
            if (minute < 10) "0" else "",
        }) catch "12:00";

        const suffix_str = if (@as(i32, @intCast(tm.*.tm_hour)) >= 12) "pm" else "am";

        const big_font_size: f64 = @as(f64, tstyle.font_size_m) * 2.9 * scale;
        const suffix_ratio = 0.45;

        var saved_font_matrix: c.cairo_matrix_t = undefined;

        c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);

        var num_ext: c.cairo_text_extents_t = undefined;
        var current_size = big_font_size;
        c.cairo_set_font_size(cr, current_size);
        c.cairo_get_font_matrix(cr, &saved_font_matrix);
        var fm = saved_font_matrix;
        fm.xx = saved_font_matrix.xx * 0.75;
        c.cairo_set_font_matrix(cr, &fm);
        c.cairo_text_extents(cr, num_str, &num_ext);
        while (num_ext.width > w_d - 4.0 and current_size > 6.0) {
            current_size *= 0.92;
            c.cairo_set_font_size(cr, current_size);
            c.cairo_get_font_matrix(cr, &fm);
            fm.xx = fm.xx * 0.75;
            c.cairo_set_font_matrix(cr, &fm);
            c.cairo_text_extents(cr, num_str, &num_ext);
        }

        var suffix_ext: c.cairo_text_extents_t = undefined;
        c.cairo_set_font_size(cr, current_size * suffix_ratio);
        c.cairo_get_font_matrix(cr, &fm);
        fm.xx = fm.xx * 0.75;
        c.cairo_set_font_matrix(cr, &fm);
        c.cairo_text_extents(cr, suffix_str, &suffix_ext);

        const top_pad: f64 = 6.0 * scale;
        const time_gap: f64 = -37.0 * scale;
        const num_baseline_y = num_ext.height + top_pad;
        const total_time_w = num_ext.width + time_gap + suffix_ext.width;
        const time_x = (w_d - total_time_w) * 0.5;

        c.cairo_set_source_rgba(cr, 0.78, 0.78, 0.78, 0.95);
        c.cairo_move_to(cr, time_x, num_baseline_y);
        c.cairo_show_text(cr, num_str);

        const num_visual_center = num_baseline_y + num_ext.y_bearing + num_ext.height * 0.5;
        const suffix_baseline_y = num_visual_center - (suffix_ext.y_bearing + suffix_ext.height * 0.5);
        c.cairo_move_to(cr, time_x + num_ext.width + time_gap, suffix_baseline_y);
        c.cairo_show_text(cr, suffix_str);

        // Restore normal (non-squished) font matrix for the date lines.
        c.cairo_set_font_matrix(cr, &saved_font_matrix);

        // 3-line date block below the time, each line centered.
        const weekday_name = weekdayName(tm.*.tm_wday);
        const day = @as(i32, @intCast(tm.*.tm_mday));
        const month_name = monthName(tm.*.tm_mon);
        var day_buf: [32:0]u8 = undefined;
        @memset(&day_buf, 0);
        const day_str = std.fmt.bufPrintZ(&day_buf, "{d}{s}", .{ day, ordinalSuffix(day) }) catch "1st";

        const date_font_size: f64 = @as(f64, tstyle.font_size_s) * 1.3 * scale;
        const line_gap = date_font_size * 1.25;
        const date_block_top = num_baseline_y + line_gap * 1.5;

        const date_lines = [_][]const u8{ weekday_name, day_str, month_name };
        const date_weights = [_]c.cairo_font_weight_t{
            c.CAIRO_FONT_WEIGHT_NORMAL,
            c.CAIRO_FONT_WEIGHT_NORMAL,
            c.CAIRO_FONT_WEIGHT_NORMAL,
        };
        for (date_lines, date_weights, 0..) |line_txt, weight, i| {
            fit_and_draw(
                cr,
                card_font,
                date_font_size,
                weight,
                line_txt,
                muted_color[0],
                muted_color[1],
                muted_color[2],
                0.95,
                w_d,
                4.0 * scale,
            );
            var ext2: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, @ptrCast(line_txt.ptr), &ext2);
            const y = date_block_top + @as(f64, @floatFromInt(i)) * line_gap;
            c.cairo_move_to(cr, (w_d - ext2.width) * 0.5, y);
            c.cairo_show_text(cr, @ptrCast(line_txt.ptr));
        }
        c.cairo_restore(cr);

        const DataBuffer = @import("../render/buffer.zig").DataBuffer;
        const buffer = DataBuffer.create(temp, dev_w, dev_h, @intCast(stride)) catch |err| {
            std.log.err("KidulWM: failed to create clock widget buffer: {}", .{err});
            return;
        };
        if (widget.buffer) |old| wlr.Buffer.drop(old);
        widget.buffer = buffer;
        if (widget.scene_buffer) |old| old.node.destroy();
        const sb = widget.tree.createSceneBuffer(buffer) catch |err| {
            std.log.err("KidulWM: failed to create clock widget scene buffer: {}", .{err});
            wlr.Buffer.drop(buffer);
            widget.buffer = null;
            return;
        };
        sb.setDestSize(pill_w, pill_h);
        widget.scene_buffer = sb;
        widget.tree.node.setPosition(pill_x, pill_y);
        widget.tree.node.raiseToTop();
    }


    fn drawWeatherWidget(self: *Self, widget: *PerOutputWeather) void {
        const box = self.host.left_peek_box(self.host.ctx, weatherWidgetIndex(self, widget)) orelse {
            self.weather_click_box = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
            return;
        };
        if (box.width <= 0 or box.height <= 0) {
            self.weather_click_box = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
            return;
        }

        var now_time: c.time_t = c.time(null);
        var local: c.struct_tm = undefined;
        const tm = c.localtime_r(&now_time, &local);
        const current_minute = @as(i32, @intCast(tm.*.tm_min)) + @as(i32, @intCast(tm.*.tm_hour)) * 60;
        const style_ = self.host.theme.style;
        const theme_gen = self.host.theme.generation;
        const scale = widget.info.scale;

        const peek_hmargin = 2;
        const peek_vmargin = 4;
        const pill_w: i32 = @max(20, box.width - 2 * peek_hmargin);
        const pill_x = box.x + peek_hmargin;
        const pill_h: i32 = @max(40, box.height - 2 * peek_vmargin);
        const pill_y = box.y + peek_vmargin;

        const redraw = widget.scene_buffer == null or
            widget.last_w != pill_w or
            widget.last_h != pill_h or
            widget.last_x != pill_x or
            widget.last_y != pill_y or
            widget.last_scale != scale or
            widget.last_minute != current_minute or
            widget.last_theme_generation != theme_gen;

        if (!redraw) {
            widget.tree.node.setPosition(pill_x, pill_y);
            widget.tree.node.raiseToTop();
            return;
        }

        widget.last_w = pill_w;
        widget.last_h = pill_h;
        widget.last_x = pill_x;
        widget.last_y = pill_y;
        widget.last_scale = scale;
        widget.last_minute = current_minute;
        widget.last_theme_generation = theme_gen;

        const dev_w: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(pill_w)) * scale));
        const dev_h: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(pill_h)) * scale));
        const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, dev_w);
        if (stride <= 0) return;
        const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(dev_h));
        const temp = self.allocator.alloc(u8, buf_size) catch |err| {
            std.log.err("KidulWM: weather widget buffer alloc failed: {}", .{err});
            return;
        };
        defer self.allocator.free(temp);
        @memset(temp, 0);

        const surface = c.cairo_image_surface_create_for_data(temp.ptr, c.CAIRO_FORMAT_ARGB32, dev_w, dev_h, stride);
        defer c.cairo_surface_destroy(surface);
        const cr = c.cairo_create(surface) orelse {
            std.log.err("KidulWM: failed to create cairo context for weather widget", .{});
            return;
        };
        defer c.cairo_destroy(cr);

        c.cairo_save(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        self.weather.renderPeek(cr, .{
            .x = pill_x,
            .y = pill_y,
            .width = dev_w,
            .height = dev_h,
        }, style_, scale);

        c.cairo_restore(cr);

        const DataBuffer = @import("../render/buffer.zig").DataBuffer;
        const buffer = DataBuffer.create(temp, dev_w, dev_h, @intCast(stride)) catch |err| {
            std.log.err("KidulWM: failed to create weather widget buffer: {}", .{err});
            return;
        };
        if (widget.buffer) |old| wlr.Buffer.drop(old);
        widget.buffer = buffer;
        if (widget.scene_buffer) |old| old.node.destroy();
        const sb = widget.tree.createSceneBuffer(buffer) catch |err| {
            std.log.err("KidulWM: failed to create weather widget scene buffer: {}", .{err});
            wlr.Buffer.drop(buffer);
            widget.buffer = null;
            return;
        };
        sb.setDestSize(pill_w, pill_h);
        widget.scene_buffer = sb;
        widget.tree.node.setPosition(pill_x, pill_y);
        widget.tree.node.raiseToTop();
    }

    fn updateCard(self: *Self) void {
        const now_us = animation.nowUs();
        const prev = self.last_update_us;
        const dt = if (prev == 0) 0.0 else @as(f64, @floatFromInt(now_us - prev)) / 1_000_000.0;

        const desired: f32 = if (self.anyCardOpen()) 1.0 else 0.0;
        const closing = desired < self.card_open_amount;
        const spring = if (closing)
            animation.Spring{ .stiffness = 8.0, .damping = 0.92, .epsilon = 0.001 }
        else
            animation.Spring{ .stiffness = 60.0, .damping = 0.95, .epsilon = 0.001 };
        const step = spring.step(self.card_open_amount, self.card_open_amount_vel, desired, dt);
        self.card_open_amount = @floatCast(step.value);
        self.card_open_amount_vel = @floatCast(step.velocity);

        if (self.card_open_amount < 0.005 and !self.anyCardOpen()) {
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
            h = @min(h, 220);
        } else {
            w -= 140;
            h -= 120;
        }
        if (w <= 0 or h <= 0) {
            if (self.card_tree) |tree| tree.node.setEnabled(false);
            return;
        }
        const card_x = box.x + @divTrunc(box.width - w, 2);
        const card_y = box.y + @divTrunc(box.height - h, 2);

        const current_mode = self.activeCardMode();
        const needs_redraw = self.card_last_w != w or
            self.card_last_h != h or
            @abs(self.card_last_open - self.card_open_amount) > 0.0001 or
            self.card_last_generation != self.host.theme.generation or
            self.card_last_mode != current_mode or
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
            self.card_last_mode = current_mode;
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
            switch (current_mode) {
                .calendar => self.drawClockCalendarCard(cr, @floatFromInt(w), @floatFromInt(h)),
                .weather => self.weather.renderCard(cr, @floatFromInt(w), @floatFromInt(h), self.host.theme.style, outputScaleForCard(self)),
            }
            const DataBuffer = @import("../render/buffer.zig").DataBuffer;
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
    }

    const CardMode = enum { calendar, weather };

    fn activeCardMode(self: *const Self) CardMode {
        if (self.weather_card_open) return .weather;
        return .calendar;
    }

    fn outputScaleForCard(self: *const Self) f32 {
        const out_count = self.host.output_count(self.host.ctx);
        if (out_count == 0) return 1.0;
        const info = self.host.output_info(self.host.ctx, 0);
        return info.scale;
    }

    fn renderCardBuffer(self: *Self, w_i: i32, h_i: i32) void {
        _ = self;
        _ = w_i;
        _ = h_i;
        // Merged into updateCard to avoid an extra allocation and to support mode switching.
    }


        const CalendarCell = struct {
            day: i32,
            col: i32,
            row: i32,
            in_month: bool,
            is_today: bool,
            is_focused: bool,
        };

        fn card_focused_day_wday(self: *const Self) i32 {
            var probe: c.struct_tm = std.mem.zeroes(c.struct_tm);
            probe.tm_year = self.card_focused_year - 1900;
            probe.tm_mon = self.card_focused_month - 1;
            probe.tm_mday = self.card_focused_day;
            probe.tm_hour = 12;
            probe.tm_min = 0;
            probe.tm_sec = 0;
            probe.tm_isdst = -1;
            const t = c.mktime(&probe);
            var local: c.struct_tm = undefined;
            const result = c.localtime_r(&t, &local);
            return @intCast(result.*.tm_wday);
        }

        /// Build a 7×6 grid anchored to the current month. Returns the current
        /// month’s days plus leading/trailing days so the grid never has holes.
        fn calendarCells(cells: []CalendarCell, year: i32, month: i32, today_mday: i32, focused_year: i32, focused_month: i32, focused_day: i32) void {
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
                    .is_focused = false,
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
                    .is_focused = (day == focused_day and month == focused_month and year == focused_year),
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
                    .is_focused = false,
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
            const date_font_size = tstyle.font_size_m;
            const day_font_size = tstyle.font_size_s;

            // Clear; draw glass rounded body with gold rim, then crop all content inside.
            c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
            c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
            c.cairo_paint(cr);
            c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

            const corner_depth: f64 = @min(14.0, @min(w, h) * 0.05);
            panelOutline(tstyle, cr, 0.0, 0.0, w, h, corner_depth);

            // Body fill.
            const bg4 = bg.toF64();
            c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], bg4[3]);
            c.cairo_fill_preserve(cr);

            // Gold rim.
            const gold4 = gold.toF64();
            c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], gold4[3]);
            c.cairo_set_line_width(cr, 2.0);
            c.cairo_stroke(cr);

            // Clip to interior so nothing spills past the rim.
            panelOutline(tstyle, cr, 1.0, 1.0, w - 2.0, h - 2.0, corner_depth - 1.0);
            c.cairo_clip(cr);

            const pad_x: f64 = 30.0;
            const pad_y: f64 = 22.0;
            const top_shift: f64 = @as(f64, date_font_size) * 1.0;
            const content_w = w - 2.0 * pad_x;

            var now: c.time_t = c.time(null);
            var local: c.struct_tm = undefined;
            const tm = c.localtime_r(&now, &local);
            const year = @as(i32, @intCast(tm.*.tm_year)) + 1900;
            const month = @as(i32, @intCast(tm.*.tm_mon)) + 1;
            const today_mday = @as(i32, @intCast(tm.*.tm_mday));

            // ---- Top month/year or selected-date pill ----
            const text_color = text.toF64();

            var date_buf: [128:0]u8 = undefined;
            @memset(&date_buf, 0);
            const focused_month = monthName(self.card_focused_month - 1);
            const date_label = std.fmt.bufPrintZ(&date_buf, "{s} {d}", .{
                focused_month,
                self.card_focused_year,
            }) catch "July 2026";

            c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
            c.cairo_set_font_size(cr, date_font_size);
            var date_ext: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, date_label, &date_ext);
            const pill_pad_x: f64 = 24.0;
            const pill_pad_y: f64 = 8.0;
            const date_pill_w = @min(content_w, date_ext.width + 2.0 * pill_pad_x);
            const date_pill_h = date_font_size + 2.0 * pill_pad_y;
            const date_pill_x = pad_x + (content_w - date_pill_w) * 0.5;
            const date_pill_y = pad_y + top_shift;

            const pill_depth: f64 = @min(10.0, @min(date_pill_w, date_pill_h) * 0.25);

            // Shadow.
            panelOutline(tstyle, cr, date_pill_x + 2.0, date_pill_y + 3.0, date_pill_w, date_pill_h, pill_depth);
            c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.35);
            c.cairo_fill(cr);

            // Tray-style gradient glass body.
            panelOutline(tstyle, cr, date_pill_x, date_pill_y, date_pill_w, date_pill_h, pill_depth);
            const glass = c.cairo_pattern_create_linear(date_pill_x, date_pill_y, date_pill_x, date_pill_y + date_pill_h).?;
            c.cairo_pattern_add_color_stop_rgba(glass, 0.0, 0.09, 0.09, 0.10, 0.85);
            c.cairo_pattern_add_color_stop_rgba(glass, 0.5, 0.06, 0.06, 0.07, 0.82);
            c.cairo_pattern_add_color_stop_rgba(glass, 1.0, 0.04, 0.04, 0.05, 0.78);
            c.cairo_set_source(cr, glass);
            c.cairo_fill_preserve(cr);
            c.cairo_pattern_destroy(glass);

            // 1px gold rim matching tray buttons.
            c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.45);
            c.cairo_set_line_width(cr, 1.0);
            c.cairo_stroke(cr);

            const date_text_x = date_pill_x + (date_pill_w - date_ext.width) * 0.5;
            const date_text_y = date_pill_y + (date_pill_h + date_ext.height) * 0.5 - 2.0;
            c.cairo_set_source_rgba(cr, text_color[0], text_color[1], text_color[2], text_color[3]);
            c.cairo_move_to(cr, date_text_x, date_text_y);
            c.cairo_show_text(cr, date_label);

            // ---- Calendar grid ----
            const date_color = muted.toF64();
            const header = &[_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
            // extra gap between weekday letters and first row of numbers
            const cell_w = content_w / 7.0;
            // Original coderBob cell sizing, pinned to bottom.
            const rows: i32 = 6;
            const top_buffer: f64 = date_pill_y + date_pill_h + date_font_size * 0.8;
            const usable_h = h - 2.0 * pad_y - (top_buffer - pad_y);
            const cell_h = if (usable_h > 0.0) @max(day_font_size * 1.4, usable_h / @as(f64, @floatFromInt(rows + 1))) else day_font_size * 1.4;
            const header_margin: f64 = day_font_size * 0.4;
            const grid_origin_y = h - pad_y - @as(f64, @floatFromInt(rows)) * cell_h;
            const header_text_size: f64 = day_font_size * 1.35;
            const header_baseline = grid_origin_y - header_margin - day_font_size * 0.5;

            c.cairo_set_font_size(cr, header_text_size);
            var day_ext: c.cairo_text_extents_t = undefined;

            // Weekday header row in muted gold.
            c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
            c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.85);
            for (header, 0..) |txt, ci| {
                c.cairo_text_extents(cr, txt.ptr, &day_ext);
                const hx = pad_x + @as(f64, @floatFromInt(ci)) * cell_w + (cell_w - day_ext.width) * 0.5;
                c.cairo_move_to(cr, hx, header_baseline);
                c.cairo_show_text(cr, txt.ptr);
            }

            const hover_row = self.card_hover_row;
            const hover_col = self.card_hover_col;
            var cells: [42]CalendarCell = undefined;
            calendarCells(&cells, year, month, today_mday, self.card_focused_year, self.card_focused_month, self.card_focused_day);
            for (cells) |cell| {
                const cx = pad_x + @as(f64, @floatFromInt(cell.col)) * cell_w;
                const cy = grid_origin_y + @as(f64, @floatFromInt(cell.row)) * cell_h + cell_h * 0.45;

                // Tiny uniform gap between cells, applied both horizontally and vertically.
                const gap: f64 = 2.5;
                const cell_rect_x = cx + gap;
                const cell_rect_y = grid_origin_y + @as(f64, @floatFromInt(cell.row)) * cell_h + gap;
                const cell_rect_w = cell_w - 2.0 * gap;
                const cell_rect_h = cell_h - 2.0 * gap;

                if (cell.in_month) {
                    // subtle glass cell border
                    panelOutline(tstyle, cr, cell_rect_x, cell_rect_y, cell_rect_w, cell_rect_h, 4.0);
                    c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.35);
                    c.cairo_set_line_width(cr, 1.0);
                    c.cairo_stroke(cr);
                }

                // Focused day: exact Bob button glass shading, slightly exaggerated.
                if (cell.is_focused) {
                    const fx = cell_rect_x + 1.0;
                    const fy = cell_rect_y + 1.0;
                    const fw = cell_rect_w - 2.0;
                    const fh = cell_rect_h - 2.0;
                    panelOutline(tstyle, cr, fx, fy, fw, fh, 4.0);

                    const cell_glass = c.cairo_pattern_create_linear(fx, fy, fx, fy + fh).?;
                    c.cairo_pattern_add_color_stop_rgba(cell_glass, 0.0, 0.04, 0.04, 0.05, 0.80);
                    c.cairo_pattern_add_color_stop_rgba(cell_glass, 0.5, 0.07, 0.07, 0.08, 0.84);
                    c.cairo_pattern_add_color_stop_rgba(cell_glass, 1.0, 0.11, 0.11, 0.12, 0.88);
                    c.cairo_set_source(cr, cell_glass);
                    c.cairo_fill_preserve(cr);
                    c.cairo_pattern_destroy(cell_glass);

                    c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.45);
                    c.cairo_set_line_width(cr, 1.0);
                    c.cairo_stroke(cr);
                }

                // Today gets a dim gold-tinted glass background, unless focused.
                if (cell.is_today and !cell.is_focused) {
                    const fx = cell_rect_x + 2.0;
                    const fy = cell_rect_y + 2.0;
                    const fw = cell_rect_w - 4.0;
                    const fh = cell_rect_h - 4.0;
                    panelOutline(tstyle, cr, fx, fy, fw, fh, 4.0);
                    const grad = c.cairo_pattern_create_linear(fx, fy, fx, fy + fh).?;
                    c.cairo_pattern_add_color_stop_rgba(grad, 0.0, gold4[0], gold4[1], gold4[2], 0.12);
                    c.cairo_pattern_add_color_stop_rgba(grad, 1.0, gold4[0], gold4[1], gold4[2], 0.05);
                    c.cairo_set_source(cr, grad);
                    c.cairo_fill_preserve(cr);
                    c.cairo_pattern_destroy(grad);
                    c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.45);
                    c.cairo_set_line_width(cr, 1.0);
                    c.cairo_stroke(cr);
                }

                // Hover: very subtle dark glass lift (only when not focused).
                const hover_this = hover_col == cell.col and hover_row == cell.row and !cell.is_focused;
                if (hover_this) {
                    const hx0 = cell_rect_x + 1.0;
                    const hy0 = cell_rect_y + 1.0;
                    const hw = cell_rect_w - 2.0;
                    const hh = cell_rect_h - 2.0;
                    panelOutline(tstyle, cr, hx0, hy0, hw, hh, 4.0);
                    const lift = c.cairo_pattern_create_linear(hx0, hy0, hx0, hy0 + hh).?;
                    c.cairo_pattern_add_color_stop_rgba(lift, 0.0, 0.11, 0.11, 0.12, 0.75);
                    c.cairo_pattern_add_color_stop_rgba(lift, 0.5, 0.07, 0.07, 0.08, 0.72);
                    c.cairo_pattern_add_color_stop_rgba(lift, 1.0, 0.04, 0.04, 0.05, 0.70);
                    c.cairo_set_source(cr, lift);
                    c.cairo_fill_preserve(cr);
                    c.cairo_pattern_destroy(lift);
                    c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.25);
                    c.cairo_set_line_width(cr, 1.0);
                    c.cairo_stroke(cr);
                }

                var day_buf: [4:0]u8 = undefined;
                const day_str = std.fmt.bufPrintZ(&day_buf, "{d}", .{cell.day}) catch continue;
                c.cairo_text_extents(cr, day_str.ptr, &day_ext);

                c.cairo_set_font_size(cr, day_font_size * 1.15);
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
