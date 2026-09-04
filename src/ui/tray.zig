const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const c = @import("dm").c;
const c_std = @cImport({
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("stdio.h");
    @cInclude("time.h");
    @cInclude("dirent.h");
    @cInclude("string.h");
});
const theme_mod = @import("../core/theme.zig");
const style = @import("../core/style.zig");
const animation = @import("../core/animation.zig");
const WeatherWidget = @import("./weather.zig").WeatherWidget;
const MediaWidget = @import("./media.zig").MediaWidget;
const NetworkWidget = @import("./network.zig").NetworkWidget;
const NetworkState = @import("./network.zig").NetworkState;
const FilesWidget = @import("./files_card.zig").FilesWidget;
const NotificationWidget = @import("./notifications.zig").NotificationWidget;
const notifications = @import("./notifications.zig");
const GaugeWidget = @import("./gauge.zig").GaugeWidget;
const DrivesWidget = @import("./drives.zig").DrivesWidget;
const discoverDrives = @import("./drives.zig").discoverDrives;
const DriveInfo = @import("./drives.zig").DriveInfo;
const card_frame = @import("card_frame.zig");
const gauge_data = @import("../core/gauge_data.zig");

// Logo assets: top-of-tray emblem (Bob) and bottom text wordmark.
const bob_logo_png = @embedFile("assets/bob/logo.png");
const bob_text_png = @embedFile("assets/bob/text.png");
const bob_text_mask_png = @embedFile("assets/bob/text_mask.png");
const bob_emblem_mask_png = @embedFile("assets/bob/emblem_mask.png");

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
    is_kfiles_open: *const fn (ctx: *anyopaque) bool,
    media_slide_toggle: *const fn (ctx: *anyopaque) void,
    theme: *const theme_mod.Theme,
};

const Action = union(enum) {
    toggle_tray,
    cycle_animation,
    media_card,
    files_card,
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
    click_box: wlr.Box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
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
    click_box: wlr.Box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    last_scale: f32 = 0.0,
    last_minute: i32 = -1,
    last_theme_generation: u32 = 0,
};

const PerOutputGauge = struct {
    output_ctx: *anyopaque,
    tree: *wlr.SceneTree,
    scene_buffer: ?*wlr.SceneBuffer,
    buffer: ?*wlr.Buffer,
    info: OutputInfo,
    last_w: i32 = 0,
    last_h: i32 = 0,
    last_x: i32 = 0,
    last_y: i32 = 0,
    click_box: wlr.Box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    cauldron_box: wlr.Box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    last_scale: f32 = 0.0,
    last_theme_generation: u32 = 0,
};

const PerOutputDrives = struct {
    output_ctx: *anyopaque,
    tree: *wlr.SceneTree,
    scene_buffer: ?*wlr.SceneBuffer,
    buffer: ?*wlr.Buffer,
    info: OutputInfo,
    last_w: i32 = 0,
    last_h: i32 = 0,
    last_x: i32 = 0,
    last_y: i32 = 0,
    click_box: wlr.Box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    drive_count: usize = 0,
    drive_boxes: [8]wlr.Box = undefined,
    last_scale: f32 = 0.0,
    last_theme_generation: u32 = 0,
};

const PerOutputMedia = struct {
    output_ctx: *anyopaque,
    tree: *wlr.SceneTree,
    scene_buffer: ?*wlr.SceneBuffer,
    buffer: ?*wlr.Buffer,
    info: OutputInfo,
    last_w: i32 = 0,
    last_h: i32 = 0,
    last_x: i32 = 0,
    last_y: i32 = 0,
    click_box: wlr.Box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    last_scale: f32 = 0.0,
    last_title_hash: u64 = 0,
    last_theme_generation: u32 = 0,
};

const PerOutputNotifications = struct {
    output_ctx: *anyopaque,
    tree: *wlr.SceneTree,
    scene_buffer: ?*wlr.SceneBuffer,
    buffer: ?*wlr.Buffer,
    info: OutputInfo,
    last_w: i32 = 0,
    last_h: i32 = 0,
    last_x: i32 = 0,
    last_y: i32 = 0,
    last_text_hash: u64 = 0,
    last_theme_generation: u32 = 0,
    last_count: usize = 0,
};

const PerOutputNetwork = struct {
    output_ctx: *anyopaque,
    tree: *wlr.SceneTree,
    scene_buffer: ?*wlr.SceneBuffer,
    buffer: ?*wlr.Buffer,
    info: OutputInfo,
    last_w: i32 = 0,
    last_h: i32 = 0,
    last_x: i32 = 0,
    last_y: i32 = 0,
    click_box: wlr.Box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    last_scale: f32 = 0.0,
    last_state: NetworkState = .none,
    last_theme_generation: u32 = 0,
};

// ── Signal pills ──────────────────────────────────────────────────
// Reads /tmp/kidul-signals/*.state files. The beacon (former network
// icon in the clock widget) changes color based on worst severity.
// Full slide card shows signal pills + details. Nothing in the peek.
// Format: "state_text severity icon_hint\n"

const SignalSeverity = enum { ok, warning, alert, muted };

const SignalEntry = struct {
    name: [32]u8 = [_]u8{0} ** 32,
    name_len: u8 = 0,
    state_text: [64]u8 = [_]u8{0} ** 64,
    state_len: u8 = 0,
    severity: SignalSeverity = .ok,
    icon_hint: [32]u8 = [_]u8{0} ** 32,
    icon_len: u8 = 0,
};

const MAX_SIGNALS: usize = 8;

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
    /// Prevents handlePointerMove from re-opening the tray via hover after
    /// a deliberate close (e.g. spawning an app). Cleared when pointer leaves panel.
    close_lock: bool = false,
    tray_anim: animation.AnimatedFloat = .{ .preset = &animation.presets.tray },
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
    card_anim: animation.AnimatedFloat = .{ .preset = &animation.presets.card },
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
    // Left peek widget (gauges), stacked below weather.
    gauge_widgets: std.ArrayList(PerOutputGauge),
    drives_widgets: std.ArrayList(PerOutputDrives),
    media_widgets: std.ArrayList(PerOutputMedia),
    network_widgets: std.ArrayList(PerOutputNetwork),
    weather: WeatherWidget,
    gauge: GaugeWidget,
    drives: DrivesWidget,
    network: NetworkWidget,
    media: MediaWidget,
    files: FilesWidget,
    media_card_open: bool = false,
    network_card_open: bool = false,
    files_card_open: bool = false,
    network_card_last_state: NetworkState = .none,
    media_card_click: MediaWidget.CardClick = .{},
    card_tree: ?*wlr.SceneTree = null,
    card_scene_buffer: ?*wlr.SceneBuffer = null,
    card_buffer: ?*wlr.Buffer = null,
    card_shadow_tree: ?*wlr.SceneTree = null,
    card_shadow_scene_buffer: ?*wlr.SceneBuffer = null,
    card_shadow_buffer: ?*wlr.Buffer = null,
    card_shadow_last_box: wlr.Box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    card_last_w: i32 = 0,
    card_last_h: i32 = 0,
    card_last_open: f32 = -1.0,
    card_last_generation: u32 = 0,
    card_last_mode: CardMode = .calendar,
    media_state_generation: u32 = 0,
    files_state_generation: usize = 0,
    signal_last_hash: u64 = 0,
    card_mode: CardMode = .calendar,
    card_close_dx: f32 = -1.0,
    card_close_dy: f32 = -1.0,

    // Notification typewriter stream.
    notifications: NotificationWidget,
    notification_widgets: std.ArrayList(PerOutputNotifications),

    // Signal pills — reads /tmp/kidul-signals/*.state, rendered in card slide
    signals: [MAX_SIGNALS]SignalEntry = [_]SignalEntry{.{}} ** MAX_SIGNALS,
    signal_count: usize = 0,
    signal_last_scan_ms: u64 = 0,
    signals_card_open: bool = false,

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
    bob_emblem_mask: *c.cairo_surface_t,

    const button_height: i32 = 44;
    const barry_button_height: i32 = 95;
    const button_gap: i32 = 8;
    const hmargin: i32 = 8;
    const bottom_margin: i32 = 10;
    const widget_hit_overhang: i32 = 12;
    const top_margin: i32 = 48;
    const max_stack_items_visible: usize = 12;
    const min_panel_w: i32 = 120;

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, host: TrayHost, root: *wlr.SceneTree) !Self {
        const items = try allocator.alloc(TrayItem, 8);
            items[0] = .{ .id = "assistant", .label = "Assistant", .action = .{ .spawn = "/usr/local/bin/kbrain-ui" } };
            items[1] = .{ .id = "browser", .label = "Browser", .action = .{ .spawn = "/usr/local/bin/launch-kbrowser.sh" } };
            items[2] = .{ .id = "files", .label = "Files", .action = .{ .spawn = "/usr/local/bin/kfiles" } };
            items[3] = .{ .id = "games", .label = "Games", .action = .none };
            items[4] = .{ .id = "maps", .label = "Maps", .action = .none };
            items[5] = .{ .id = "media", .label = "Media", .action = .media_card };
            items[6] = .{ .id = "office", .label = "Office", .action = .none };
            items[7] = .{ .id = "settings", .label = "Settings", .action = .none };

            var manual_order: std.ArrayList(usize) = .empty;
            errdefer manual_order.deinit(allocator);
            try manual_order.appendSlice(allocator, &[_]usize{ 0, 1, 2, 3, 4, 5, 6, 7 });

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
        const bob_emblem_mask = try loadPngFromBytes(bob_emblem_mask_png);
        errdefer c.cairo_surface_destroy(bob_emblem_mask);

        const card_shadow_tree = root.createSceneTree() catch null;
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
            .gauge_widgets = .empty,
            .drives_widgets = .empty,
            .media_widgets = .empty,
            .network_widgets = .empty,
            .notification_widgets = .empty,
            .weather = WeatherWidget.init(allocator),
            .gauge = GaugeWidget.init(allocator),
            .drives = DrivesWidget.init(allocator),
            .media = MediaWidget.init(allocator),
            .network = NetworkWidget.init(allocator),
            .files = FilesWidget.init(allocator),
            .notifications = NotificationWidget.init(allocator),
            .card_shadow_tree = card_shadow_tree,
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
            .bob_emblem_mask = bob_emblem_mask,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.outputs.items) |*po| self.destroyPerOutput(po);
        for (self.barry_pets.items) |*pet| self.destroyPet(pet);
        for (self.widgets.items) |*w| self.destroyWidget(w);
        for (self.weather_widgets.items) |*w| self.destroyWeatherWidget(w);
        for (self.gauge_widgets.items) |*w| self.destroyGaugeWidget(w);
        for (self.drives_widgets.items) |*w| self.destroyDrivesWidget(w);
        for (self.media_widgets.items) |*w| self.destroyMediaWidget(w);
        for (self.network_widgets.items) |*w| self.destroyNetworkWidget(w);
        for (self.notification_widgets.items) |*w| self.destroyNotificationWidget(w);
        self.weather.deinit();
        self.gauge.deinit();
        self.drives.deinit();
        self.media.deinit();
        self.network.deinit();
        self.files.deinit();
        self.notifications.deinit();
        self.outputs.deinit(self.allocator);
        self.barry_pets.deinit(self.allocator);
        self.widgets.deinit(self.allocator);
        self.weather_widgets.deinit(self.allocator);
        self.gauge_widgets.deinit(self.allocator);
        self.drives_widgets.deinit(self.allocator);
        self.media_widgets.deinit(self.allocator);
        self.network_widgets.deinit(self.allocator);
        self.notification_widgets.deinit(self.allocator);
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
        if (self.card_shadow_scene_buffer) |sb| sb.node.destroy();
        if (self.card_shadow_buffer) |buf| wlr.Buffer.drop(buf);
        if (self.card_shadow_tree) |tree| tree.node.destroy();
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
        const gauge_tree = self.root.createSceneTree() catch |err| {
            std.log.err("KidulWM: failed to create gauge widget scene tree: {}", .{err});
            return;
        };
        const gauge_widget = PerOutputGauge{
            .output_ctx = output_ctx,
            .tree = gauge_tree,
            .scene_buffer = null,
            .buffer = null,
            .info = .{ .x = 0, .y = 0, .width = 0, .height = 0, .scale = 1.0, .focus_left = 0 },
        };
        self.gauge_widgets.append(self.allocator, gauge_widget) catch |err| {
            std.log.err("KidulWM: failed to append gauge widget: {}", .{err});
            gauge_tree.node.destroy();
        };
        const drives_tree = self.root.createSceneTree() catch |err| {
            std.log.err("KidulWM: failed to create drives widget scene tree: {}", .{err});
            return;
        };
        const drives_widget = PerOutputDrives{
            .output_ctx = output_ctx,
            .tree = drives_tree,
            .scene_buffer = null,
            .buffer = null,
            .info = .{ .x = 0, .y = 0, .width = 0, .height = 0, .scale = 1.0, .focus_left = 0 },
        };
        self.drives_widgets.append(self.allocator, drives_widget) catch |err| {
            std.log.err("KidulWM: failed to append drives widget: {}", .{err});
            drives_tree.node.destroy();
        };
        const media_tree = self.root.createSceneTree() catch |err| {
            std.log.err("KidulWM: failed to create media widget scene tree: {}", .{err});
            return;
        };
        const media_widget = PerOutputMedia{
            .output_ctx = output_ctx,
            .tree = media_tree,
            .scene_buffer = null,
            .buffer = null,
            .info = .{ .x = 0, .y = 0, .width = 0, .height = 0, .scale = 1.0, .focus_left = 0 },
        };
        self.media_widgets.append(self.allocator, media_widget) catch |err| {
            std.log.err("KidulWM: failed to append media widget: {}", .{err});
            media_tree.node.destroy();
        };
        const notification_tree = self.root.createSceneTree() catch |err| {
            std.log.err("KidulWM: failed to create notification widget scene tree: {}", .{err});
            return;
        };
        const network_tree = self.root.createSceneTree() catch |err| {
            std.log.err("KidulWM: failed to create network widget scene tree: {}", .{err});
            return;
        };
        const network_widget = PerOutputNetwork{
            .output_ctx = output_ctx,
            .tree = network_tree,
            .scene_buffer = null,
            .buffer = null,
            .info = .{ .x = 0, .y = 0, .width = 0, .height = 0, .scale = 1.0, .focus_left = 0 },
        };
        self.network_widgets.append(self.allocator, network_widget) catch |err| {
            std.log.err("KidulWM: failed to append network widget: {}", .{err});
            network_tree.node.destroy();
        };
        const notification_widget = PerOutputNotifications{
            .output_ctx = output_ctx,
            .tree = notification_tree,
            .scene_buffer = null,
            .buffer = null,
            .info = .{ .x = 0, .y = 0, .width = 0, .height = 0, .scale = 1.0, .focus_left = 0 },
        };
        self.notification_widgets.append(self.allocator, notification_widget) catch |err| {
            std.log.err("KidulWM: failed to append notification widget: {}", .{err});
            notification_tree.node.destroy();
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
        for (self.gauge_widgets.items, 0..) |*w, i| {
            if (w.output_ctx == output_ctx) {
                self.destroyGaugeWidget(w);
                _ = self.gauge_widgets.orderedRemove(i);
                break;
            }
        }
        for (self.drives_widgets.items, 0..) |*w, i| {
            if (w.output_ctx == output_ctx) {
                self.destroyDrivesWidget(w);
                _ = self.drives_widgets.orderedRemove(i);
                break;
            }
        }
        for (self.media_widgets.items, 0..) |*w, i| {
            if (w.output_ctx == output_ctx) {
                self.destroyMediaWidget(w);
                _ = self.media_widgets.orderedRemove(i);
                break;
            }
        }
        for (self.network_widgets.items, 0..) |*w, i| {
            if (w.output_ctx == output_ctx) {
                self.destroyNetworkWidget(w);
                _ = self.network_widgets.orderedRemove(i);
                break;
            }
        }
        for (self.notification_widgets.items, 0..) |*w, i| {
            if (w.output_ctx == output_ctx) {
                self.destroyNotificationWidget(w);
                _ = self.notification_widgets.orderedRemove(i);
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

    fn destroyGaugeWidget(_: *Self, widget: *PerOutputGauge) void {
        if (widget.scene_buffer) |sb| sb.node.destroy();
        if (widget.buffer) |buf| wlr.Buffer.drop(buf);
        widget.tree.node.destroy();
        widget.scene_buffer = null;
        widget.buffer = null;
    }

    fn destroyDrivesWidget(_: *Self, widget: *PerOutputDrives) void {
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

    pub fn close(self: *Self) void {
        if (!self.open) return;
        self.open = false;
        self.pinned = false;
        self.hovered = false;
        self.close_after_us = 0;
        self.selected_index = 0;
        self.hover_index = null;
        self.bobChangedState(.laying);
        self.requestUpdate();
        self.host.request_frame(self.host.ctx);
    }

    pub fn closeAllCards(self: *Self) void {
        if (!self.calendar_card_open and !self.weather_card_open and !self.media_card_open and !self.network_card_open and !self.files_card_open and !self.signals_card_open) return;
        self.calendar_card_open = false;
        self.weather_card_open = false;
        self.media_card_open = false;
        self.network_card_open = false;
        self.files_card_open = false;
        self.signals_card_open = false;
        self.network.card.close();
        self.weather.card.open = false;
        self.media.setCardOpen(false);
        self.files.card.open = false;
        self.requestUpdate();
        self.host.request_frame(self.host.ctx);
    }

    /// Close any open card and return focus to the tray, leaving the tray open for navigation.
    pub fn backToTray(self: *Self) void {
        self.closeAllCards();
        if (!self.open) {
            self.open = true;
            self.pinned = true;
            self.hovered = true;
            self.scroll_offset = 0.0;
            self.keepOpen();
        }
        self.requestUpdate();
        self.host.request_frame(self.host.ctx);
    }

    pub fn toggleCard(self: *Self) void {
        if (self.weather_card_open) {
            self.weather_card_open = false;
            self.weather.card.open = false;
        }
        self.calendar_card_open = !self.calendar_card_open;
        if (self.calendar_card_open) {
            self.card_mode = .calendar;
            self.setCardCloseDirection(.calendar);
        }
        self.requestUpdate();
        self.host.request_frame(self.host.ctx);
    }

    // Weather click launches the kweather satellite (full slide) — the old
    // compositor weather card is dead. Pattern matches toggleSignalsCard.
    pub fn toggleWeatherCard(self: *Self) void {
        if (self.calendar_card_open) self.calendar_card_open = false;
        if (self.weather_card_open) {
            self.weather_card_open = false;
            self.weather.card.open = false;
        }
        if (self.media_card_open) {
            self.media_card_open = false;
            self.media.setCardOpen(false);
        }
        if (self.network_card_open) {
            self.network_card_open = false;
            self.network.card.close();
        }
        if (self.files_card_open) self.files_card_open = false;
        // Kill any orphaned kweather from a previous compositor session,
        // then spawn fresh. NOTE: pkill without -f.
        _ = c_std.system("pkill -9 kweather 2>/dev/null; sleep 0.2");
        var buf: [256]u8 = undefined;
        const cmd = std.fmt.bufPrintZ(&buf, "WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 /usr/local/bin/kweather &", .{}) catch return;
        _ = c_std.system(cmd.ptr);
        self.requestUpdate();
        self.host.request_frame(self.host.ctx);
    }

    pub fn toggleNetworkCard(self: *Self) void {
        if (self.calendar_card_open) {
            self.calendar_card_open = false;
        }
        if (self.weather_card_open) {
            self.weather_card_open = false;
            self.weather.card.open = false;
        }
        if (self.media_card_open) {
            self.media_card_open = false;
            self.media.setCardOpen(false);
        }
        self.network_card_open = !self.network_card_open;
        if (self.network_card_open) {
            self.network.card.open = true;
            self.card_mode = .network;
            self.setCardCloseDirection(.network);
        } else {
            self.network.card.close();
        }
        self.requestUpdate();
        self.host.request_frame(self.host.ctx);
    }

    // Beacon click launches the ksignals satellite (full slide) — the old
    // compositor signals card is dead. Pattern matches spawnKfiles.
    pub fn toggleSignalsCard(self: *Self) void {
        if (self.calendar_card_open) self.calendar_card_open = false;
        if (self.weather_card_open) {
            self.weather_card_open = false;
            self.weather.card.open = false;
        }
        if (self.media_card_open) {
            self.media_card_open = false;
            self.media.setCardOpen(false);
        }
        if (self.network_card_open) {
            self.network_card_open = false;
            self.network.card.close();
        }
        if (self.files_card_open) self.files_card_open = false;
        // Kill any orphaned ksignals from a previous compositor session,
        // then spawn fresh. Prevents duplicate slides on compositor restart.
        // NOTE: pkill without -f — -f matches the shell executing pkill too.
        _ = c_std.system("pkill -9 ksignals 2>/dev/null; sleep 0.2");
        var buf: [256]u8 = undefined;
        const cmd = std.fmt.bufPrintZ(&buf, "WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 /usr/local/bin/ksignals &", .{}) catch return;
        _ = c_std.system(cmd.ptr);
        self.requestUpdate();
        self.host.request_frame(self.host.ctx);
    }

    pub fn toggleMediaCard(self: *Self) void {
        if (self.calendar_card_open) {
            self.calendar_card_open = false;
        }
        if (self.weather_card_open) {
            self.weather_card_open = false;
            self.weather.card.open = false;
        }
        self.media_card_open = !self.media_card_open;
        self.media.setCardOpen(self.media_card_open);
        if (self.media_card_open) {
            self.card_mode = .media;
            self.setCardCloseDirection(.media);
            self.media.focusSearch();
        }
        self.requestUpdate();
        self.host.request_frame(self.host.ctx);
    }

    pub fn spawnKfiles(self: *Self) void {
        _ = self;
        var buf: [1024]u8 = undefined;
        const script = std.fmt.bufPrintZ(&buf, "WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 /usr/local/bin/launch-kfiles.sh &", .{}) catch return;
        _ = c_std.system(script.ptr);
    }

    pub fn toggleFilesCard(self: *Self) void {
        self.spawnKfiles();
    }

    fn anyCardOpen(self: *const Self) bool {
        return self.calendar_card_open or self.weather_card_open or self.media_card_open or self.network_card_open or self.files_card_open or self.signals_card_open;
    }

    pub fn selectNext(self: *Self) void {
        self.keepOpen();
        if (!self.isOpen() or self.items.len == 0) {
            self.toggle();
            return;
        }
        if (self.selected_index < self.items.len) {
            self.selected_index += 1;
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
        const action = it.action;
        switch (action) {
            .toggle_tray => self.toggle(),
            .cycle_animation => self.host.cycle_animation(self.host.ctx),
            .media_card => {
                // Media player is a deck SLIDE now, not a tray card.
                self.host.media_slide_toggle(self.host.ctx);
            },
            .files_card => {
                self.toggleFilesCard();
            },
            .spawn => |cmd| {
                if (cmd.len > 0) {
                    var buf: [1024]u8 = undefined;
                    const script = std.fmt.bufPrintZ(&buf, "WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 {s} &", .{cmd}) catch return;
                    _ = c_std.system(script.ptr);
                }
            },
            .settings_page => {},
            .none => {},
        }
        // When a card/slide/app is opened, close the tray and any cards so the
        // new surface owns the visual space and keyboard focus. The tray-toggle
        // action itself is the only exception.
        if (action != .toggle_tray) {
            self.close();
            self.closeAllCards();
        }
    }

    pub fn isOpen(self: *const Self) bool {
        return self.open or self.tray_anim.value > 0.005;
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

        self.media.stepSliderReveal(dt);

        // Use the shared tray preset: snap open quickly, ease closed slowly.
        self.tray_anim.setTarget(if (self.open or self.pinned or self.hovered) 1.0 else 0.0);
        _ = self.tray_anim.step(dt);

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
            const tray_moving = !self.tray_anim.isSettled();
            const bob_moving = tray_moving or !bob_state_step.settled or !us_step.settled;
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
            (self.tray_anim.value > 0.001 and self.tray_anim.value < 0.999) or
            !bob_settled or
            !barry_settled or
            !us_step.settled;

        for (self.outputs.items, 0..) |*po, i| {
            po.info = self.host.output_info(self.host.ctx, i);
            const w = self.panelWidth(po.info);
            const h = self.panelHeightFor(po.info);
            if (po.last_w != w or po.last_h != h or
                @abs(po.last_open_amount - self.tray_anim.value) > 0.0001 or
                po.last_selected != self.selected_index or
                po.last_hover != self.hover_index or
                po.last_order_mode != self.order_mode)
            {
                needs_redraw = true;
            }
            po.last_w = w;
            po.last_h = h;
            po.last_open_amount = self.tray_anim.value;
            po.last_selected = self.selected_index;
            po.last_hover = self.hover_index;
            po.last_order_mode = self.order_mode;
            self.updatePerOutput(po, needs_redraw);
        }

        self.updateCard();

        const notify_changed = self.notifications.update(now_us);
        if (notify_changed) needs_redraw = true;

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

        // Draw gauge widget below weather.
        for (self.gauge_widgets.items) |*gauge_widget| {
            gauge_widget.info = self.host.output_info(self.host.ctx, gaugeWidgetIndex(self, gauge_widget));
            self.drawGaugeWidget(gauge_widget);
        }

        // Draw drives widget below gauges.
        for (self.drives_widgets.items) |*drives_widget| {
            drives_widget.info = self.host.output_info(self.host.ctx, drivesWidgetIndex(self, drives_widget));
            self.drawDrivesWidget(drives_widget);
        }

        // Update media backend and draw bottom-right peek widget.
        self.media.update();
        for (self.media_widgets.items) |*media_widget| {
            media_widget.info = self.host.output_info(self.host.ctx, mediaWidgetIndex(self, media_widget));
            self.drawMediaWidget(media_widget);
        }

        // Update network state and draw top-right network icon.
        self.network.update();
        if (self.network.state != self.network_card_last_state) {
            self.network_card_last_state = self.network.state;
            self.requestUpdate();
        }
        for (self.network_widgets.items) |*network_widget| {
            network_widget.info = self.host.output_info(self.host.ctx, networkWidgetIndex(self, network_widget));
            self.drawNetworkWidget(network_widget);
        }

        // Scan signal state files for beacon color + card rendering.
        self.scanSignals();
        const worst = self.worstSeverity();
        self.network.beacon_override = (self.signal_count > 0);
        self.network.beacon_severity = switch (worst) {
            .ok => 0,
            .warning => 1,
            .alert => 2,
            .muted => 3,
        };
        if (self.signals_card_open) {
            needs_redraw = true;
        }

        if (self.media_card_open or self.media.cached.playing) {
            needs_redraw = true;
        }
        for (self.notification_widgets.items) |*notification_widget| {
            notification_widget.info = self.host.output_info(self.host.ctx, notificationWidgetIndex(self, notification_widget));
            self.drawNotificationWidget(notification_widget);
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
        // Center the stack in the panel, then shift up by one button height.
        const stack_content_h: f32 = @as(f32, @floatFromInt(self.items.len)) * item_size - @as(f32, @floatFromInt(button_gap));
        const stack_origin: f32 = (@as(f32, @floatFromInt(petHeight())) - stack_content_h) * 0.5;
        return stack_origin + @as(f32, @floatFromInt(stack_sel)) * item_size;
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
        const actual_stack_h: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(max_stack_h)) * self.tray_anim.value));
        // Panel height is just the stack — no barry button padding.
        return actual_stack_h;
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
        // Center the panel vertically on the peek.
        const peek_center: i32 = @divTrunc(info.height, 2);
        const y: i32 = info.y + peek_center - @divTrunc(h, 2);

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

        // Barry lozenge at top is disabled; the single Kidul button at the
        // bottom-left of the left peek is now the tray toggle.
        // const bh: f64 = @as(f64, barry_button_height) * scale_d;
        // const bmargin: f64 = @as(f64, bottom_margin) * scale_d;
        // const by: f64 = bmargin;
        // self.drawBarryButton(cr, 0.0, by, bw, bh, scale_d);

        // Stack is centered vertically in the panel buffer, shifted up by one button height.
        if (self.tray_anim.value > 0.001 and self.items.len > 0) {
            const gap: f64 = @as(f64, button_gap) * scale_d;
            const item_h: f64 = @as(f64, button_height) * scale_d;
            const item_size = item_h + gap;
            const scroll_px: f64 = @floor(@as(f64, self.scroll_offset) * scale_d);
            // Center the stack in the buffer, then shift up by one button height.
            const stack_content_h: f64 = @as(f64, @floatFromInt(self.items.len)) * item_size - gap;
            const stack_origin: f64 = (@as(f64, dev_h) - stack_content_h) * 0.5;
            const stagger_delay: f32 = 0.05;

            for (0..self.items.len) |raw_idx| {
                const idx = raw_idx;
                const stack_index: usize = idx;
                const top = stack_origin + @as(f64, @floatFromInt(idx)) * item_size - scroll_px;
                if (top + item_h < stack_origin or top >= @as(f64, dev_h)) continue;

                const stagger_t = std.math.clamp(self.tray_anim.value - @as(f32, @floatFromInt(stack_index)) * stagger_delay, 0.0, 1.0);
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
        const margin: f64 = 18.0 * s;
        const avail_w = w - 2.0 * margin;
        const avail_h = h - 2.0 * margin;
        const icon_r = @min(avail_w, avail_h) * 0.35 * 1.63;
        const center_x = x + w * 0.5 - 12.0 * s + 17.0 * s - 3.0 * s;
        const bottom_above_border: f64 = (@as(f64, @floatCast(self.host.theme.style.border_width)) + 1.0) * s;
        const pet_bottom_pad: f64 = @as(f64, @floatFromInt(bottom_margin)) * s;
        _ = bottom_above_border;
        // Anchor the belly bottom 17px above the screen edge. In drawGenieBottle
        // the belly bottom sits at cy + body_h * 0.68, so place cy accordingly.
        // (y + h + pet_bottom_pad == buffer bottom.)
        const body_h = icon_r * 1.05;
        const gap_above_screen: f64 = 17.0 * s;
        const center_y = y + h + pet_bottom_pad - gap_above_screen - body_h * 0.68;

        // Genie bottle: static at rest; wisp animates only while the tray is moving.
        const open_amt: f64 = @floatCast(self.tray_anim.value);
        const moving = !self.tray_anim.isSettled();
        self.drawGenieBottle(cr, center_x, center_y, icon_r, s, self.host.theme.style.color_border.toF64(), open_amt, moving);
    }

    fn drawGenieBottle(self: *const Self, cr: *c.cairo_t, cx: f64, cy: f64, icon_r: f64, s: f64, border_color: [4]f64, open_amt: f64, moving: bool) void {
        _ = self;
        const body_w = icon_r * 1.30;
        const body_h = icon_r * 1.05;
        const neck_w = icon_r * 0.34;
        const neck_h = icon_r * 0.42;
        const lip_w = icon_r * 0.52;
        const lip_h = icon_r * 0.10;

        // Geometry: belly sits at cy; neck rises above; stopper crowns it.
        const belly_cy = cy + body_h * 0.18;
        const belly_rx = body_w * 0.5;
        const belly_ry = body_h * 0.5;
        const neck_top = belly_cy - belly_ry - neck_h;
        const stopper_r = neck_w * 0.62;

        c.cairo_save(cr);

        // --- Wisp (only while tray is moving) -------------------------------
        if (moving) {
            var ts: c.timespec = undefined;
            _ = c.clock_gettime(c.CLOCK_MONOTONIC, &ts);
            const t: f64 = @as(f64, @floatFromInt(ts.tv_sec)) + @as(f64, @floatFromInt(ts.tv_nsec)) / 1.0e9;
            const mouth_y = neck_top - lip_h - stopper_r;
            const rise = icon_r * 2.4 * open_amt;
            const wisps = 3;
            var wi: usize = 0;
            while (wi < wisps) : (wi += 1) {
                const fwi = @as(f64, @floatFromInt(wi));
                const phase = @mod(t * 0.9 + fwi * 0.33, 1.0);
                const wy = mouth_y - rise * phase;
                const curl = std.math.sin(phase * 6.0 + fwi * 2.4) * icon_r * 0.28 * phase;
                const wx = cx + curl;
                const wr = (1.4 + 2.6 * phase) * s;
                const fade = (1.0 - phase) * 0.55 * open_amt;
                c.cairo_set_source_rgba(cr, border_color[0], border_color[1], border_color[2], fade);
                c.cairo_arc(cr, wx, wy, wr, 0, 2.0 * std.math.pi);
                c.cairo_fill(cr);
            }
            // Bright thread of smoke connecting mouth to the wisp field.
            c.cairo_set_source_rgba(cr, border_color[0], border_color[1], border_color[2], 0.45 * open_amt);
            c.cairo_set_line_width(cr, 1.2 * s);
            c.cairo_move_to(cr, cx, mouth_y);
            c.cairo_curve_to(cr,
                cx + std.math.sin(t * 2.0) * icon_r * 0.10, mouth_y - rise * 0.33,
                cx - std.math.sin(t * 1.6) * icon_r * 0.14, mouth_y - rise * 0.66,
                cx + std.math.sin(t * 1.2) * icon_r * 0.10, mouth_y - rise);
            c.cairo_stroke(cr);
        }

        // --- Stopper ---------------------------------------------------------
        c.cairo_set_source_rgba(cr, border_color[0], border_color[1], border_color[2], 1.0);
        c.cairo_set_line_width(cr, 2.2 * s);
        // Dome.
        c.cairo_arc(cr, cx, neck_top - lip_h - stopper_r * 0.4, stopper_r, std.math.pi, 0);
        c.cairo_stroke(cr);
        // Knob.
        c.cairo_arc(cr, cx, neck_top - lip_h - stopper_r * 1.1, stopper_r * 0.28, 0, 2.0 * std.math.pi);
        c.cairo_fill(cr);

        // --- One continuous vessel silhouette ----------------------------------
        // Right lip tip -> flare into neck -> S-curve down the neck -> sweep out
        // around the belly -> back up the left side in mirror image. Single path
        // so the glass fill and gold stroke share the same whispy outline.
        const belly_top = belly_cy - belly_ry;
        const belly_bot = belly_cy + belly_ry;
        const lip_top = neck_top - lip_h;

        // One continuous vessel silhouette, shared by fill, stroke and clips.
        const bottlePath = struct {
            fn trace(cr2: *c.cairo_t, cx2: f64, lip_w2: f64, lip_h2: f64, lip_top2: f64, neck_w2: f64, neck_top2: f64, neck_h2: f64, belly_rx2: f64, belly_ry2: f64, belly_top2: f64, belly_cy2: f64, belly_bot2: f64) void {
                c.cairo_move_to(cr2, cx2 + lip_w2 * 0.5, lip_top2 + lip_h2 * 0.5);
                c.cairo_curve_to(cr2,
                    cx2 + lip_w2 * 0.52, lip_top2 + lip_h2,
                    cx2 + neck_w2 * 0.55, neck_top2 + neck_h2 * 0.08,
                    cx2 + neck_w2 * 0.42, neck_top2 + neck_h2 * 0.30);
                c.cairo_curve_to(cr2,
                    cx2 + neck_w2 * 0.38, neck_top2 + neck_h2 * 0.55,
                    cx2 + neck_w2 * 0.42, neck_top2 + neck_h2 * 0.85,
                    cx2 + belly_rx2 * 0.62, belly_top2 + belly_ry2 * 0.12);
                c.cairo_curve_to(cr2,
                    cx2 + belly_rx2 * 0.85, belly_top2 + belly_ry2 * 0.32,
                    cx2 + belly_rx2 * 1.05, belly_top2 + belly_ry2 * 0.50,
                    cx2 + belly_rx2 * 1.05, belly_cy2);
                c.cairo_curve_to(cr2,
                    cx2 + belly_rx2 * 1.05, belly_bot2 - belly_ry2 * 0.28,
                    cx2 + belly_rx2 * 0.70, belly_bot2 + belly_ry2 * 0.02,
                    cx2 + belly_rx2 * 0.38, belly_bot2 + belly_ry2 * 0.04);
                c.cairo_curve_to(cr2,
                    cx2 + belly_rx2 * 0.14, belly_bot2 + belly_ry2 * 0.07,
                    cx2 - belly_rx2 * 0.14, belly_bot2 + belly_ry2 * 0.07,
                    cx2 - belly_rx2 * 0.38, belly_bot2 + belly_ry2 * 0.04);
                c.cairo_curve_to(cr2,
                    cx2 - belly_rx2 * 0.70, belly_bot2 + belly_ry2 * 0.02,
                    cx2 - belly_rx2 * 1.05, belly_bot2 - belly_ry2 * 0.28,
                    cx2 - belly_rx2 * 1.05, belly_cy2);
                c.cairo_curve_to(cr2,
                    cx2 - belly_rx2 * 1.05, belly_top2 + belly_ry2 * 0.50,
                    cx2 - belly_rx2 * 0.85, belly_top2 + belly_ry2 * 0.32,
                    cx2 - belly_rx2 * 0.62, belly_top2 + belly_ry2 * 0.12);
                c.cairo_curve_to(cr2,
                    cx2 - neck_w2 * 0.42, neck_top2 + neck_h2 * 0.85,
                    cx2 - neck_w2 * 0.38, neck_top2 + neck_h2 * 0.55,
                    cx2 - neck_w2 * 0.42, neck_top2 + neck_h2 * 0.30);
                c.cairo_curve_to(cr2,
                    cx2 - neck_w2 * 0.55, neck_top2 + neck_h2 * 0.08,
                    cx2 - lip_w2 * 0.52, lip_top2 + lip_h2,
                    cx2 - lip_w2 * 0.5, lip_top2 + lip_h2 * 0.5);
                c.cairo_close_path(cr2);
            }
        }.trace;

        bottlePath(cr, cx, lip_w, lip_h, lip_top, neck_w, neck_top, neck_h, belly_rx, belly_ry, belly_top, belly_cy, belly_bot);

        // Reversed scheme: body is the unfocused border color, shading is black.
        // Keep it muted so it reads as dark gold, not porcelain.
        const glass = c.cairo_pattern_create_linear(cx, lip_top, cx, belly_bot).?;
        c.cairo_pattern_add_color_stop_rgba(glass, 0.0, border_color[0] * 0.92, border_color[1] * 0.92, border_color[2] * 0.92, 1.0);
        c.cairo_pattern_add_color_stop_rgba(glass, 0.4, border_color[0] * 0.72, border_color[1] * 0.72, border_color[2] * 0.72, 1.0);
        c.cairo_pattern_add_color_stop_rgba(glass, 1.0, border_color[0] * 0.48, border_color[1] * 0.48, border_color[2] * 0.48, 1.0);
        c.cairo_set_source(cr, glass);
        c.cairo_fill_preserve(cr);
        c.cairo_pattern_destroy(glass);

        // Black 3D shading, clipped to the vessel: shadow lower-right,
        // soft occlusion at the bottom, gentle dark edge on the neck.
        c.cairo_save(cr);
        bottlePath(cr, cx, lip_w, lip_h, lip_top, neck_w, neck_top, neck_h, belly_rx, belly_ry, belly_top, belly_cy, belly_bot);
        c.cairo_clip(cr);
        // Shadow side.
        const shade = c.cairo_pattern_create_linear(cx + belly_rx, belly_bot, cx - belly_rx * 0.3, belly_cy).?;
        c.cairo_pattern_add_color_stop_rgba(shade, 0.0, 0.0, 0.0, 0.0, 0.45);
        c.cairo_pattern_add_color_stop_rgba(shade, 1.0, 0.0, 0.0, 0.0, 0.0);
        c.cairo_set_source(cr, shade);
        c.cairo_paint(cr);
        c.cairo_pattern_destroy(shade);
        // Highlight side: gentle border-color lift, no white (avoids porcelain).
        const light = c.cairo_pattern_create_linear(cx - belly_rx, belly_top, cx + belly_rx * 0.4, belly_cy).?;
        c.cairo_pattern_add_color_stop_rgba(light, 0.0, border_color[0], border_color[1], border_color[2], 0.18);
        c.cairo_pattern_add_color_stop_rgba(light, 1.0, border_color[0], border_color[1], border_color[2], 0.0);
        c.cairo_set_source(cr, light);
        c.cairo_paint(cr);
        c.cairo_pattern_destroy(light);
        // Bottom ambient occlusion.
        const ao = c.cairo_pattern_create_linear(cx, belly_bot - belly_ry * 0.5, cx, belly_bot + belly_ry * 0.1).?;
        c.cairo_pattern_add_color_stop_rgba(ao, 0.0, 0.0, 0.0, 0.0, 0.0);
        c.cairo_pattern_add_color_stop_rgba(ao, 1.0, 0.0, 0.0, 0.0, 0.40);
        c.cairo_set_source(cr, ao);
        c.cairo_paint(cr);
        c.cairo_pattern_destroy(ao);
        c.cairo_restore(cr);

        // Rim stroke in darkened border color so the edge reads on the light body.
        c.cairo_set_source_rgba(cr, border_color[0] * 0.45, border_color[1] * 0.45, border_color[2] * 0.45, 1.0);
        c.cairo_set_line_width(cr, 2.6 * s);
        c.cairo_stroke(cr);

        // Lip mouth line (the opening the wisp pours from).
        c.cairo_set_line_width(cr, 1.6 * s);
        c.cairo_move_to(cr, cx - lip_w * 0.42, lip_top + lip_h * 0.5);
        c.cairo_curve_to(cr,
            cx - lip_w * 0.15, lip_top + lip_h * 0.15,
            cx + lip_w * 0.15, lip_top + lip_h * 0.15,
            cx + lip_w * 0.42, lip_top + lip_h * 0.5);
        c.cairo_stroke(cr);

        // --- Static contents: thin gold crescent at RAM level -----------------
        const ram_value = ramUsageFraction() catch 0.0;
        const level = @max(0.05, @min(1.0, ram_value));
        c.cairo_save(cr);
        // Clip to the vessel silhouette so liquid respects the new shape.
        bottlePath(cr, cx, lip_w, lip_h, lip_top, neck_w, neck_top, neck_h, belly_rx, belly_ry, belly_top, belly_cy, belly_bot);
        c.cairo_clip(cr);
        // Liquid: quiet black, no motion (reversed scheme on light body).
        const fill_top = belly_cy + belly_ry - 2.0 * belly_ry * level;
        const liquid = c.cairo_pattern_create_linear(cx, fill_top, cx, belly_cy + belly_ry).?;
        c.cairo_pattern_add_color_stop_rgba(liquid, 0.0, 0.0, 0.0, 0.0, 0.25);
        c.cairo_pattern_add_color_stop_rgba(liquid, 1.0, 0.0, 0.0, 0.0, 0.55);
        c.cairo_set_source(cr, liquid);
        c.cairo_rectangle(cr, cx - belly_rx, fill_top, belly_rx * 2.0, belly_cy + belly_ry - fill_top);
        c.cairo_fill(cr);
        c.cairo_pattern_destroy(liquid);
        // Hairline surface line.
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.65);
        c.cairo_set_line_width(cr, 1.0 * s);
        c.cairo_move_to(cr, cx - belly_rx * 0.8, fill_top);
        c.cairo_line_to(cr, cx + belly_rx * 0.8, fill_top);
        c.cairo_stroke(cr);
        c.cairo_restore(cr);

        // --- Glass highlights (border color, no white) --------------------------
        // Slim vertical highlight on the upper-left belly.
        c.cairo_set_source_rgba(cr, border_color[0], border_color[1], border_color[2], 0.16);
        c.cairo_set_line_width(cr, 3.0 * s);
        c.cairo_move_to(cr, cx - belly_rx * 0.45, belly_cy - belly_ry * 0.55);
        c.cairo_curve_to(cr,
            cx - belly_rx * 0.62, belly_cy - belly_ry * 0.15,
            cx - belly_rx * 0.60, belly_cy + belly_ry * 0.15,
            cx - belly_rx * 0.45, belly_cy + belly_ry * 0.45);
        c.cairo_stroke(cr);
        // Small specular dot near the neck shoulder.
        c.cairo_set_source_rgba(cr, border_color[0], border_color[1], border_color[2], 0.22);
        c.cairo_arc(cr, cx - belly_rx * 0.30, belly_cy - belly_ry * 0.62, 1.6 * s, 0, 2.0 * std.math.pi);
        c.cairo_fill(cr);

        c.cairo_restore(cr);
    }


    fn ramUsageFraction() !f64 {
        var data = gauge_data.GaugeData.init(std.heap.page_allocator);
        const v = try data.sample(.ram_usage);
        return @max(0.0, @min(1.0, v.value));
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

    fn gaugeWidgetIndex(self: *const Self, widget: *PerOutputGauge) usize {
        for (self.gauge_widgets.items, 0..) |*w, i| {
            if (w == widget) return i;
        }
        return 0;
    }

    fn drivesWidgetIndex(self: *const Self, widget: *PerOutputDrives) usize {
        for (self.drives_widgets.items, 0..) |*w, i| {
            if (w == widget) return i;
        }
        return 0;
    }

    fn mediaWidgetIndex(self: *const Self, widget: *PerOutputMedia) usize {
        for (self.media_widgets.items, 0..) |*w, i| {
            if (w == widget) return i;
        }
        return 0;
    }

    fn networkWidgetIndex(self: *const Self, widget: *PerOutputNetwork) usize {
        for (self.network_widgets.items, 0..) |*w, i| {
            if (w == widget) return i;
        }
        return 0;
    }

    fn destroyMediaWidget(_: *Self, widget: *PerOutputMedia) void {
        if (widget.scene_buffer) |sb| sb.node.destroy();
        if (widget.buffer) |buf| wlr.Buffer.drop(buf);
        widget.tree.node.destroy();
        widget.scene_buffer = null;
        widget.buffer = null;
    }

    fn destroyNetworkWidget(_: *Self, widget: *PerOutputNetwork) void {
        if (widget.scene_buffer) |sb| sb.node.destroy();
        if (widget.buffer) |buf| wlr.Buffer.drop(buf);
        widget.tree.node.destroy();
        widget.scene_buffer = null;
        widget.buffer = null;
    }

    fn destroyNotificationWidget(_: *Self, widget: *PerOutputNotifications) void {
        if (widget.scene_buffer) |sb| sb.node.destroy();
        if (widget.buffer) |buf| wlr.Buffer.drop(buf);
        widget.tree.node.destroy();
        widget.scene_buffer = null;
        widget.buffer = null;
    }


    fn handleFilesCardClick(self: *Self, px: f64, py: f64) bool {
        if (!self.files_card_open) return false;
        const box = self.card_box;
        const w = self.card_last_w;
        const h = self.card_last_h;
        if (w <= 0 or h <= 0) return false;
        const card_x = @as(f64, @floatFromInt(box.x + @divTrunc(box.width - w, 2)));
        const card_y = @as(f64, @floatFromInt(box.y + @divTrunc(box.height - h, 2)));
        const lx = px - card_x;
        const ly = py - card_y;
        if (lx < 0 or ly < 0 or lx > @as(f64, @floatFromInt(w)) or ly > @as(f64, @floatFromInt(h))) return false;
        const scale = self.outputScaleForCard();
        if (self.files.handleClick(lx, ly, @as(f64, @floatFromInt(w)), @as(f64, @floatFromInt(h)), scale)) {
            self.requestUpdate();
            self.host.request_frame(self.host.ctx);
            return true;
        }
        return false;
    }

    fn handleMediaCardClick(self: *Self, px: f64, py: f64) bool {
        if (!self.media_card_open) return false;
        const box = self.card_box;
        const w = self.card_last_w;
        const h = self.card_last_h;
        if (w <= 0 or h <= 0) return false;
        const card_x = @as(f64, @floatFromInt(box.x + @divTrunc(box.width - w, 2)));
        const card_y = @as(f64, @floatFromInt(box.y + @divTrunc(box.height - h, 2)));
        const lx = px - card_x;
        const ly = py - card_y;
        if (lx < 0 or ly < 0 or lx > @as(f64, @floatFromInt(w)) or ly > @as(f64, @floatFromInt(h))) return false;

        const click = self.media_card_click;

        // Category pills.
        for (0..3) |i| {
            if (ly >= @as(f64, @floatFromInt(click.cat_y[i])) and
                ly <= @as(f64, @floatFromInt(click.cat_y[i] + click.cat_h[i])) and
                lx >= @as(f64, @floatFromInt(click.cat_x[i])) and
                lx <= @as(f64, @floatFromInt(click.cat_x[i] + click.cat_w[i]))) {
                self.media.setCategory(click.cat_for_index[i]);
                self.media.focusControl(.category);
                self.requestUpdate();
                self.host.request_frame(self.host.ctx);
                return true;
            }
        }

        // Search bar.
        if (lx >= @as(f64, @floatFromInt(click.search_x)) and
            ly >= @as(f64, @floatFromInt(click.search_y)) and
            lx <= @as(f64, @floatFromInt(click.search_x + click.search_w)) and
            ly <= @as(f64, @floatFromInt(click.search_y + click.search_h))) {
            self.media.focusSearch();
            self.requestUpdate();
            self.host.request_frame(self.host.ctx);
            return true;
        }

        // Result list tiles.
        if (lx >= @as(f64, @floatFromInt(click.list_x)) and
            ly >= @as(f64, @floatFromInt(click.list_y)) and
            lx <= @as(f64, @floatFromInt(click.list_x + click.list_w)) and
            ly <= @as(f64, @floatFromInt(click.list_y + click.list_h))) {
            if (click.tile_w > 0 and click.tile_h > 0 and click.cols > 0) {
                const local_x = lx - @as(f64, @floatFromInt(click.list_x));
                const local_y = ly - @as(f64, @floatFromInt(click.list_y));
                const gap = @as(f64, @floatFromInt(click.tile_gap));
                const col = @as(usize, @intFromFloat(@floor(local_x / (@as(f64, @floatFromInt(click.tile_w)) + gap))));
                const row = @as(usize, @intFromFloat(@floor(local_y / (@as(f64, @floatFromInt(click.tile_h)) + gap))));
                const cols = @as(usize, @intCast(click.cols));
                const idx = (click.scroll_offset_at_render + row) * cols + col;
                self.media.focusSearch();
                self.media.selected_result = idx;
                self.requestUpdate();
                self.host.request_frame(self.host.ctx);
                return true;
            }
        }

        // Vertical scroller channel, locked to right edge without overlapping grid.
        const scroll_left = @as(f64, @floatFromInt(click.scroll_x));
        const scroll_right = scroll_left + @as(f64, @floatFromInt(click.scroll_w));
        if (lx >= scroll_left - @as(f64, @floatFromInt(click.scroll_w)) * 2.0 and lx <= scroll_right and
            ly >= @as(f64, @floatFromInt(click.scroll_y)) and
            ly <= @as(f64, @floatFromInt(click.scroll_y + click.scroll_h))) {
            const track_len = @as(f64, @floatFromInt(click.scroll_h - click.scroll_w));
            const rel_y = ly - @as(f64, @floatFromInt(click.scroll_y)) - @as(f64, @floatFromInt(click.scroll_w)) * 0.5;
            const ratio = @max(0.0, @min(1.0, rel_y / track_len));
            const max_off = self.media.max_scroll_offset;
            self.media.list_scroll_offset = @intFromFloat(@round(ratio * @as(f64, @floatFromInt(max_off))));
            self.requestUpdate();
            self.host.request_frame(self.host.ctx);
            return true;
        }

        // Scrollbar top/bottom quick zones.
        const in_scrollbar = click.scroll_w > 0 and click.scroll_h > 0 and
            lx >= @as(f64, @floatFromInt(click.scroll_x)) and
            ly >= @as(f64, @floatFromInt(click.scroll_y)) and
            lx <= @as(f64, @floatFromInt(click.scroll_x + click.scroll_w)) and
            ly <= @as(f64, @floatFromInt(click.scroll_y + click.scroll_h));
        self.media.slider_hover = in_scrollbar;
        if (in_scrollbar) {
            const rel_y = ly - @as(f64, @floatFromInt(click.scroll_y));
            const ratio = rel_y / @as(f64, @floatFromInt(click.scroll_h));
            const max_off = self.media.max_scroll_offset;
            if (ratio < 0.5) {
                self.media.list_scroll_offset = 0;
            } else {
                self.media.list_scroll_offset = max_off;
            }
            self.media.focusSlider();
            self.requestUpdate();
            self.host.request_frame(self.host.ctx);
            return true;
        }

        return true;
    }

    pub fn handleCalendarCardKey(self: *Self, sym: @import("xkbcommon").Keysym) bool {
        if (!self.calendar_card_open) return false;
        switch (sym) {
            .Escape, .Return, .KP_Enter, .space => { self.closeAllCards(); return true; },
            .Left => { self.backToTray(); return true; },
            else => return true,
        }
    }

    pub fn handleFilesCardKey(self: *Self, sym: @import("xkbcommon").Keysym) bool {
        if (!self.files_card_open) return false;
        if (self.files.handleKey(sym)) {
            self.requestUpdate();
            self.host.request_frame(self.host.ctx);
            return true;
        }
        switch (sym) {
            .Escape => { self.closeAllCards(); return true; },
            else => return false,
        }
    }

    pub fn handleWeatherCardKey(self: *Self, sym: @import("xkbcommon").Keysym) bool {
        if (!self.weather_card_open) return false;
        switch (sym) {
            .Escape, .Return, .KP_Enter, .space => { self.closeAllCards(); return true; },
            .Left => { self.backToTray(); return true; },
            else => return true,
        }
    }

    pub fn handleMediaCardKey(self: *Self, sym: @import("xkbcommon").Keysym) bool {
        _ = @import("std");
        if (!self.media_card_open) return false;
        const xkb = @import("xkbcommon");
        const focused = self.media.focus;

        // Printable keys feed the search box when focused or auto-focus search.
        const printable = blk: {
            const v = @intFromEnum(sym);
            break :blk (v >= @intFromEnum(xkb.Keysym.a) and v <= @intFromEnum(xkb.Keysym.z)) or
                (v >= @intFromEnum(xkb.Keysym.@"0") and v <= @intFromEnum(xkb.Keysym.@"9")) or
                v == @intFromEnum(xkb.Keysym.space) or v == @intFromEnum(xkb.Keysym.minus) or
                v == @intFromEnum(xkb.Keysym.period);
        };
        if (self.media.search_focused) {
            switch (sym) {
                .Left => {
                    if (self.media.search_len > 0 and self.media.search_caret > 0) {
                        self.media.moveSearchCaret(-1);
                    } else {
                        self.media.focusControl(.category);
                    }
                    self.requestUpdate(); self.host.request_frame(self.host.ctx); return true;
                },
                .Right => {
                    if (self.media.search_caret < self.media.search_len) {
                        self.media.moveSearchCaret(1);
                    } else {
                        self.media.focusSlider();
                    }
                    self.requestUpdate(); self.host.request_frame(self.host.ctx); return true;
                },
                .Home => { self.media.search_caret = 0; self.requestUpdate(); self.host.request_frame(self.host.ctx); return true; },
                .End => { self.media.search_caret = self.media.search_len; self.requestUpdate(); self.host.request_frame(self.host.ctx); return true; },
                .BackSpace => { self.media.backspaceSearch(); self.requestUpdate(); self.host.request_frame(self.host.ctx); return true; },
                .Delete => { self.media.deleteSearch(); self.requestUpdate(); self.host.request_frame(self.host.ctx); return true; },
                .Return, .KP_Enter => {
                    const text = self.media.acceptSearch();
                    // Secret category easter egg: two-letter codes jump to category pills.
                    if (text.len == 2) {
                        const code = std.ascii.lowerString(&self.media.search_buf, text);
                        if (std.mem.eql(u8, code, "mo")) { self.media.setCategory(.movies); }
                        else if (std.mem.eql(u8, code, "tv")) { self.media.setCategory(.tv); }
                        else if (std.mem.eql(u8, code, "mu")) { self.media.setCategory(.music); }
                        else { self.media.jumpToSearchPrefix(text); }
                    } else if (text.len > 0) {
                        self.media.jumpToSearchPrefix(text);
                    }
                    self.media.focusControl(.result);
                    self.requestUpdate();
                    self.host.request_frame(self.host.ctx);
                    return true;
                },
                .Escape => { self.media.cancelSearch(); self.requestUpdate(); self.host.request_frame(self.host.ctx); return true; },
                .Tab => { self.media.focusSearch(); self.requestUpdate(); self.host.request_frame(self.host.ctx); return true; },
                .Up => { self.media.focusControl(.category); self.requestUpdate(); self.host.request_frame(self.host.ctx); return true; },
                .Down => {
                    self.media.focusControl(.result);
                    self.media.selected_result = self.media.grid_cols / 2;
                    self.media.adjustScrollToSelection();
                    self.requestUpdate(); self.host.request_frame(self.host.ctx); return true;
                },
                else => {
                    if (printable) {
                        const v = @intFromEnum(sym);
                        var ch: u8 = 0;
                        if (v >= @intFromEnum(xkb.Keysym.a) and v <= @intFromEnum(xkb.Keysym.z)) {
                            ch = @as(u8, @intCast(v - @intFromEnum(xkb.Keysym.a))) + 'a';
                        } else if (v >= @intFromEnum(xkb.Keysym.@"0") and v <= @intFromEnum(xkb.Keysym.@"9")) {
                            ch = @as(u8, @intCast(v - @intFromEnum(xkb.Keysym.@"0"))) + '0';
                        } else if (v == @intFromEnum(xkb.Keysym.space)) {
                            ch = ' ';
                        } else if (v == @intFromEnum(xkb.Keysym.minus)) {
                            ch = '-';
                        } else if (v == @intFromEnum(xkb.Keysym.period)) {
                            ch = '.';
                        }
                        if (ch != 0) {
                            self.media.appendSearch(ch);
                            self.requestUpdate();
                            self.host.request_frame(self.host.ctx);
                            return true;
                        }
                    }
                },
            }
            return false;
        }

        // Category / result navigation.
        switch (sym) {
            .Left => {
                switch (focused) {
                    // HARD STOP at the left edge — INPUT LAW says ←→ moves
                    // and Esc goes back, not the other way round.
                    .category => self.media.moveCategory(-1),
                    .subcategory => self.media.moveSubcategory(-1),
                    .search => self.media.moveSearchCaret(-1),
                    .result => self.media.moveResultSelection(-1),
                    .slider => self.media.focusControl(.result),
                }
                self.requestUpdate(); self.host.request_frame(self.host.ctx); return true;
            },
            .Right => {
                switch (focused) {
                    .category => self.media.moveCategory(1),
                    .subcategory => self.media.moveSubcategory(1),
                    .search => self.media.moveSearchCaret(1),
                    .result => {
                        if (self.media.isResultLastColumn()) {
                            self.media.focusSlider();
                        } else {
                            self.media.moveResultSelection(1);
                        }
                    },
                    .slider => {},
                }
                self.requestUpdate(); self.host.request_frame(self.host.ctx); return true;
            },
            .Up => {
                switch (focused) {
                    .category => {},
                    .subcategory => self.media.closeSubcategory(),
                    .search => self.media.focusControl(.category),
                    .result => {
                        if (self.media.atResultTopRow()) {
                            self.media.focusControl(.search);
                        } else {
                            self.media.moveResultVertical(-1);
                        }
                    },
                    .slider => self.media.moveSliderVertical(-1),
                }
                self.requestUpdate(); self.host.request_frame(self.host.ctx); return true;
            },
            .Down => {
                switch (focused) {
                    .category => {
                        if (self.media.subcategory_open) {
                            self.media.focusControl(.subcategory);
                        } else {
                            self.media.focusControl(.search);
                        }
                    },
                    .subcategory => self.media.focusControl(.search),
                    .search => {
                        if (self.media.hasResults()) {
                            self.media.focusControl(.result);
                            self.media.selected_result = self.media.grid_cols / 2;
                            self.media.adjustScrollToSelection();
                        } else {
                            self.media.focusControl(.slider);
                        }
                    },
                    .result => self.media.moveResultVertical(1),
                    .slider => self.media.moveSliderVertical(1),
                }
                self.requestUpdate(); self.host.request_frame(self.host.ctx); return true;
            },
            .Tab => {
                switch (focused) {
                    .category => self.media.focusControl(.search),
                    .subcategory => self.media.focusControl(.search),
                    .search => {
                        if (self.media.hasResults()) {
                            self.media.focusControl(.result);
                        } else {
                            self.media.focusControl(.slider);
                        }
                    },
                    .result => self.media.focusControl(.category),
                    .slider => self.media.focusControl(.category),
                }
                self.requestUpdate(); self.host.request_frame(self.host.ctx); return true;
            },
            .Page_Up => { self.media.pageList(-1); self.requestUpdate(); self.host.request_frame(self.host.ctx); return true; },
            .Page_Down => { self.media.pageList(1); self.requestUpdate(); self.host.request_frame(self.host.ctx); return true; },
            .space, .Return, .KP_Enter => {
                switch (focused) {
                    .category => {
                        if (self.media.canOpenSubcategory()) {
                            self.media.openSubcategory();
                        }
                    },
                    .subcategory => self.media.closeSubcategory(),
                    .search => {},
                    .result => {
                        const path = self.media.selectedResultPath();
                        if (path.len > 0) self.media.play(path);
                    },
                    .slider => {},
                }
                self.requestUpdate();
                self.host.request_frame(self.host.ctx);
                return true;
            },
            .Escape => { self.closeAllCards(); return true; },
            else => {
                if (printable) {
                    const v = @intFromEnum(sym);
                    var ch: u8 = 0;
                    if (v >= @intFromEnum(xkb.Keysym.a) and v <= @intFromEnum(xkb.Keysym.z)) {
                        ch = @as(u8, @intCast(v - @intFromEnum(xkb.Keysym.a))) + 'a';
                    } else if (v >= @intFromEnum(xkb.Keysym.@"0") and v <= @intFromEnum(xkb.Keysym.@"9")) {
                        ch = @as(u8, @intCast(v - @intFromEnum(xkb.Keysym.@"0"))) + '0';
                    } else if (v == @intFromEnum(xkb.Keysym.space)) {
                        ch = ' ';
                    } else if (v == @intFromEnum(xkb.Keysym.minus)) {
                        ch = '-';
                    } else if (v == @intFromEnum(xkb.Keysym.period)) {
                        ch = '.';
                    }
                    if (ch != 0) {
                        if (focused == .search) {
                            self.media.appendSearch(ch);
                        } else {
                            self.media.focusControl(.result);
                            self.media.jumpToLetter(if (ch >= 'a' and ch <= 'z') std.ascii.toUpper(ch) else ch);
                        }
                        self.requestUpdate();
                        self.host.request_frame(self.host.ctx);
                        return true;
                    }
                }
            },
        }
        return false;
    }

    fn pointInsideWidget(self: *const Self, px: f64, py: f64) bool {
        for (self.widgets.items) |w| {
            if (w.click_box.width <= 0 or w.click_box.height <= 0) continue;
            const b = w.click_box;
            const oh: i32 = widget_hit_overhang;
            if (px >= @as(f64, @floatFromInt(b.x - oh)) and
                px < @as(f64, @floatFromInt(b.x + @as(i32, @intCast(b.width)) + oh)) and
                py >= @as(f64, @floatFromInt(b.y - oh)) and
                py < @as(f64, @floatFromInt(b.y + @as(i32, @intCast(b.height)) + oh))) return true;
        }
        return false;
    }

    fn pointInsideWeatherWidget(self: *const Self, px: f64, py: f64) bool {
        for (self.weather_widgets.items) |w| {
            if (w.click_box.width <= 0 or w.click_box.height <= 0) continue;
            const b = w.click_box;
            const oh: i32 = widget_hit_overhang;
            if (px >= @as(f64, @floatFromInt(b.x - oh)) and
                px < @as(f64, @floatFromInt(b.x + @as(i32, @intCast(b.width)) + oh)) and
                py >= @as(f64, @floatFromInt(b.y - oh)) and
                py < @as(f64, @floatFromInt(b.y + @as(i32, @intCast(b.height)) + oh))) return true;
        }
        return false;
    }

    fn pointInsideMediaWidget(self: *const Self, px: f64, py: f64) bool {
        for (self.media_widgets.items) |w| {
            if (w.click_box.width <= 0 or w.click_box.height <= 0) continue;
            const b = w.click_box;
            const oh: i32 = widget_hit_overhang;
            if (px >= @as(f64, @floatFromInt(b.x - oh)) and
                px < @as(f64, @floatFromInt(b.x + @as(i32, @intCast(b.width)) + oh)) and
                py >= @as(f64, @floatFromInt(b.y - oh)) and
                py < @as(f64, @floatFromInt(b.y + @as(i32, @intCast(b.height)) + oh))) return true;
        }
        return false;
    }

    fn pointInsideNetworkWidget(self: *const Self, px: f64, py: f64) bool {
        // The network icon is rendered at the top of the clock widget buffer.
        // Treat the upper part of the right-peek box as the network/brightness
        // zone, with a generous click area.
        for (self.widgets.items) |w| {
            const b = w.click_box;
            if (b.width <= 0 or b.height <= 0) continue;
            const status_h: f64 = 52.0 * @as(f64, w.info.scale);
            const x0: f64 = @floatFromInt(b.x);
            const x1: f64 = @floatFromInt(b.x + b.width);
            const y0: f64 = @floatFromInt(b.y);
            const y1: f64 = y0 + status_h;
            if (px >= x0 and px < x1 and py >= y0 and py < y1) return true;
        }
        return false;
    }

    const GaugeHit = enum {
        cauldron,
    };

    fn pointInsideGaugeWidget(self: *const Self, px: f64, py: f64) ?GaugeHit {
        for (self.gauge_widgets.items) |w| {
            if (w.click_box.width <= 0 or w.click_box.height <= 0) continue;
            const b = w.click_box;
            const oh: i32 = widget_hit_overhang;
            if (px >= @as(f64, @floatFromInt(b.x - oh)) and
                px < @as(f64, @floatFromInt(b.x + @as(i32, @intCast(b.width)) + oh)) and
                py >= @as(f64, @floatFromInt(b.y - oh)) and
                py < @as(f64, @floatFromInt(b.y + @as(i32, @intCast(b.height)) + oh)))
            {
                if (w.cauldron_box.width > 0 and w.cauldron_box.height > 0 and
                    px >= @as(f64, @floatFromInt(w.cauldron_box.x)) and
                    px < @as(f64, @floatFromInt(w.cauldron_box.x + w.cauldron_box.width)) and
                    py >= @as(f64, @floatFromInt(w.cauldron_box.y)) and
                    py < @as(f64, @floatFromInt(w.cauldron_box.y + w.cauldron_box.height)))
                {
                    return .cauldron;
                }
            }
        }
        return null;
    }

    fn pointInsideDrivesWidget(self: *const Self, px: f64, py: f64) ?usize {
        for (self.drives_widgets.items) |w| {
            if (w.click_box.width <= 0 or w.click_box.height <= 0) continue;
            const b = w.click_box;
            const oh: i32 = widget_hit_overhang;
            if (px >= @as(f64, @floatFromInt(b.x - oh)) and
                px < @as(f64, @floatFromInt(b.x + @as(i32, @intCast(b.width)) + oh)) and
                py >= @as(f64, @floatFromInt(b.y - oh)) and
                py < @as(f64, @floatFromInt(b.y + @as(i32, @intCast(b.height)) + oh)))
            {
                var i: usize = 0;
                while (i < w.drive_count) : (i += 1) {
                    const db = w.drive_boxes[i];
                    if (db.width > 0 and db.height > 0 and
                        px >= @as(f64, @floatFromInt(db.x)) and
                        px < @as(f64, @floatFromInt(db.x + db.width)) and
                        py >= @as(f64, @floatFromInt(db.y)) and
                        py < @as(f64, @floatFromInt(db.y + db.height)))
                    {
                        return i;
                    }
                }
            }
        }
        return null;
    }

    fn sendKfilesNavigatePath(self: *Self, path: []const u8) void {
        _ = self;
        const f = c_std.fopen("/tmp/kfiles-navigate", "w");
        if (f == null) return;
        defer _ = c_std.fclose(f.?);
        _ = c_std.fprintf(f.?, "%s\n", path.ptr);
    }

    fn launchKidulFiles(self: *Self, path: []const u8) void {
        _ = self;
        var buf: [1024]u8 = undefined;
        const script = std.fmt.bufPrint(&buf, "WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 ghostty --font-size=36 --background=0a0a0b -e /usr/bin/kidul-files {s} &", .{path}) catch return;
        _ = c_std.system(script.ptr);
    }

    fn pointInsidePet(self: *const Self, px: f64, py: f64) bool {
        for (self.barry_pets.items) |pet| {
            const pw = pet.last_w;
            const ph = pet.last_h;
            if (pw <= 0 or ph <= 0) continue;
            const px_ = pet.info.x;
            const py_ = pet.info.y + pet.info.height - ph;
            if (px >= @as(f64, @floatFromInt(px_)) and
                px < @as(f64, @floatFromInt(px_ + pw)) and
                py >= @as(f64, @floatFromInt(py_)) and
                py < @as(f64, @floatFromInt(py_ + ph))) return true;
        }
        return false;
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

        // Tray hover: only the bottom-left pet logo opens the tray from a closed
        // state, but while the tray is open the whole panel keeps it open.
        const inside_pet = self.pointInsidePet(px, py);
        var inside_panel = inside_pet;
        var new_hover: ?usize = null;
        if (!inside_panel and (self.open or self.pinned or self.tray_anim.value > 0.01)) {
            for (0..out_count) |i| {
                const info = self.host.output_info(self.host.ctx, i);
                if (i < self.outputs.items.len) self.outputs.items[i].info = info;
                if (!self.pointInside(info, px, py)) continue;
                inside_panel = true;

                const panel_h = @as(f64, @floatFromInt(self.panelHeightFor(info)));
                const peek_center: f64 = @as(f64, @floatFromInt(info.height)) * 0.5;
                const panel_y: f64 = @as(f64, @floatFromInt(info.y)) + peek_center - panel_h * 0.5;
                const local_y = py - panel_y;
                const gap: f64 = button_gap;
                const item_h: f64 = button_height;
                const item_size = item_h + gap;
                const stack_content_h: f64 = @as(f64, @floatFromInt(self.items.len)) * item_size - gap;
                const stack_origin: f64 = (panel_h - stack_content_h) * 0.5;
                const scroll_px: f64 = self.scroll_offset;

                if (local_y >= stack_origin and local_y < panel_h and self.items.len > 0) {
                    const dist = local_y - stack_origin + scroll_px;
                    const idx: usize = @as(usize, @intFromFloat(@floor(dist / (item_h + gap)))) + 1;
                    if (idx <= self.items.len) new_hover = idx;
                }
            }
        }

        self.hovered = inside_panel;
        if (new_hover) |hi| self.hover_index = hi;

        if (inside_pet and !self.open and !self.pinned) {
            self.open = true;
            self.keepOpen();
            self.selected_index = 1;
            self.hover_index = 1;
            self.setBarryState(.sitting);
            self.requestUpdate();
            self.host.request_frame(self.host.ctx);
        } else if (!inside_panel and self.open and !self.pinned) {
            if (animation.nowUs() >= self.close_after_us) {
                self.open = false;
                self.close_after_us = 0;
                self.hover_index = null;
                self.selected_index = 0;
                self.setBarryState(.laying);
                self.closeAllCards();
                self.requestUpdate();
                self.host.request_frame(self.host.ctx);
            } else {
                self.requestUpdate();
                self.host.request_frame(self.host.ctx);
            }
        }
        return inside_pet or inside_panel;
    }

    pub fn handlePointerClick(self: *Self, px: f64, py: f64) bool {
        
        // Status icon (beacon) sits on top of the clock, so check it first.
        var need_close_card = false;
        if (self.pointInsideNetworkWidget(px, py)) {
            if (self.calendar_card_open or self.weather_card_open or self.media_card_open) self.closeAllCards();
            // The network icon is now the signal beacon — opens signals card.
            self.toggleSignalsCard();
            return true;
        }
        // Click on the clock/date peek widget toggles the calendar card.
        if (self.pointInsideWidget(px, py)) {
            if (self.weather_card_open) self.closeAllCards();
            self.toggleCard();
            return true;
        }
        // Click on the weather peek widget toggles the weather card.
        if (self.pointInsideWeatherWidget(px, py)) {
            if (self.calendar_card_open or self.media_card_open or self.network_card_open) self.closeAllCards();
            self.toggleWeatherCard();
            return true;
        }
        // Click on the media peek widget toggles the media card.
        if (self.pointInsideMediaWidget(px, py)) {
            if (self.calendar_card_open or self.weather_card_open) self.closeAllCards();
            self.toggleMediaCard();
            return true;
        }
        // Click on the RAM cauldron toggles the tray.
        if (self.pointInsideGaugeWidget(px, py)) |hit| {
            switch (hit) {
                .cauldron => {
                    self.toggle();
                    return true;
                },
            }
        }
        // Click on a drive pill navigates kfiles to that mount.
        if (self.pointInsideDrivesWidget(px, py)) |idx| {
            var drives_buf: [8]DriveInfo = undefined;
            const count = discoverDrives(&drives_buf);
            if (idx < count) {
                self.sendKfilesNavigatePath(if (drives_buf[idx].path_len > 0) drives_buf[idx].path[0..drives_buf[idx].path_len] else "/home/kidul");
            }
            return true;
        }
        // Click inside the currently open card:
        // - Calendar: keep open only if a day cell was actually hit.
        // - Weather/Media: no interactive hit regions yet, so any click inside closes it.
        // - Otherwise treat the click as "dismiss the overlay".
        if (self.anyCardOpen() and self.card_box.width > 0 and self.card_box.height > 0) {
            const cbx = @as(f64, @floatFromInt(self.card_box.x));
            const cby = @as(f64, @floatFromInt(self.card_box.y));
            const cbw = @as(f64, @floatFromInt(self.card_box.width));
            const cbh = @as(f64, @floatFromInt(self.card_box.height));
            if (px >= cbx and px < cbx + cbw and py >= cby and py < cby + cbh) {
                // Any click inside an open card is consumed by the card. Per-card
                // handlers may perform an selection/action; if they return false,
                // the click is still a no-op rather than a dismiss.
                if (self.calendar_card_open) {
                    if (self.handleCardDateClick(px, py)) return true;
                    return true;
                }
                if (self.media_card_open and self.handleMediaCardClick(px, py)) return true;
                if (self.files_card_open) {
                    _ = self.handleFilesCardClick(px, py);
                    return true;
                }
                // weather card (no interactive regions yet)
                return true;
            }
            // network card (no interactive regions yet)
            if (self.network_card_open) {
                self.closeAllCards();
                return true;
            }
            // Click inside a media card that misses every interactive region is ignored,
            // so the card stays open for hover inspection.
            if (self.media_card_open) return true;
            need_close_card = true;
        }
        if (need_close_card) {
            self.closeAllCards();
            return true;
        }

        // Bottom-left pet/logo button toggles the tray. This is the ONLY spot
        // that opens the tray, so it can never overlap the weather widget.
        if (self.pointInsidePet(px, py)) {
            self.toggle();
            return true;
        }

        const out_count = self.host.output_count(self.host.ctx);
        var inside_panel = false;
        var output_index: usize = 0;
        for (0..out_count) |i| {
            const info = self.host.output_info(self.host.ctx, i);
            if (i < self.outputs.items.len) self.outputs.items[i].info = info;
            if (self.pointInside(info, px, py)) {
                inside_panel = true;
                output_index = i;
            }
        }

        // Outside the open tray: close it if pinned/open.
        if (!inside_panel) {
            if (self.pinned) {
                self.pinned = false;
                self.open = false;
                self.hovered = false;
                self.hover_index = null;
                self.selected_index = 0;
                self.setBarryState(.laying);
                self.closeAllCards();
                self.requestUpdate();
                self.host.request_frame(self.host.ctx);
            }
            return self.pinned;
        }

        // Inside the open tray: click a stack item to activate, otherwise consume
        // the click but do not toggle the tray.
        const info = self.host.output_info(self.host.ctx, output_index);
        const panel_h = @as(f64, @floatFromInt(self.panelHeightFor(info)));
        const peek_center: f64 = @as(f64, @floatFromInt(info.height)) * 0.5;
        const panel_y: f64 = @as(f64, @floatFromInt(info.y)) + peek_center - panel_h * 0.5;
        const local_y = py - panel_y;
        const gap: f64 = button_gap;
        const item_h: f64 = button_height;
        const item_size = item_h + gap;
        const stack_content_h: f64 = @as(f64, @floatFromInt(self.items.len)) * item_size - gap;
        const stack_origin: f64 = (panel_h - stack_content_h) * 0.5;
        const scroll_px: f64 = self.scroll_offset;

        if (local_y >= stack_origin and local_y < panel_h and self.items.len > 0) {
            const dist = local_y - stack_origin + scroll_px;
            const stack_idx: usize = @as(usize, @intFromFloat(@floor(dist / (item_h + gap)))) + 1;
            if (stack_idx <= self.items.len) {
                self.selected_index = stack_idx;
                self.hover_index = stack_idx;
                self.activateSelected();
                return true;
            }
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

    pub fn handleAxis(self: *Self, px: f64, py: f64, delta: f64) bool {
        // Brightness scroll: only when hovering the top-right status tray (above the clock).
        if (!self.pointInsideNetworkWidget(px, py)) return false;
        self.network.adjustBrightness(delta);
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
        if (widget.last_time_minute != current_minute) {
            const log_hour = @as(i32, @intCast(tm.*.tm_hour));
            const log_min = @as(i32, @intCast(tm.*.tm_min));
            std.log.info("clock widget: now_time={d} hour={d} minute={d} current_minute={d} last={d}", .{ now_time, log_hour, log_min, current_minute, widget.last_time_minute });
        }
        const tstyle = self.host.theme.style;
        const theme_gen = self.host.theme.generation;
        const scale = widget.info.scale;

        // Content-sized widget, horizontally centered, filling the top of the right peek.
        const peek_hmargin = 2;
        const peek_vmargin = 20;
        const max_pill_side: i32 = @max(80, @as(i32, @intFromFloat(@as(f64, 185.0) * @as(f64, scale))));
        const pill_w: i32 = @max(20, @min(box.width - 2 * peek_hmargin, max_pill_side));
        const pill_h: i32 = @max(40, @min(box.height - 2 * peek_vmargin, max_pill_side));
        const pill_x = box.x + peek_hmargin + @divTrunc(box.width - 2 * peek_hmargin - pill_w, 2);
        const pill_y = box.y + peek_vmargin;

        const needs_redraw = widget.scene_buffer == null or
            widget.last_w != pill_w or
            widget.last_h != pill_h or
            widget.last_x != pill_x or
            widget.last_y != pill_y or
            widget.last_scale != scale or
            widget.last_time_minute != current_minute or
            widget.last_theme_generation != theme_gen;

        if (!needs_redraw) {
            widget.tree.node.setPosition(pill_x, pill_y);
            widget.tree.node.raiseToTop();
            return;
        }

        widget.last_w = pill_w;
        widget.last_h = pill_h;
        widget.last_x = pill_x;
        widget.last_y = pill_y;
        widget.click_box = .{ .x = pill_x, .y = pill_y, .width = @intCast(pill_w), .height = @intCast(pill_h) };
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
        const h_d: f64 = @floatFromInt(dev_h);
        const status_band_h: f64 = 34.0 * @as(f64, scale);

        // Network icon is drawn first at the top of the same buffer,
        // shifted 7px left with the clock content just underneath it.
        c.cairo_save(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);
        c.cairo_translate(cr, -7.0 * @as(f64, scale), 0.0);
        self.network.renderPeek(cr, .{
            .x = 0,
            .y = 0,
            .width = dev_w,
            .height = @as(i32, @intFromFloat(status_band_h)),
        }, tstyle, scale);
        c.cairo_restore(cr);

        // 24-hour time, natural font proportions, no squish.
        const hour = @as(i32, @intCast(tm.*.tm_hour));
        const minute = @as(i32, @intCast(tm.*.tm_min));

        var hour_buf: [4:0]u8 = undefined;
        @memset(&hour_buf, 0);
        const hour_str = std.fmt.bufPrintZ(&hour_buf, "{s}{d}", .{ if (hour < 10) "0" else "", hour }) catch "00";
        var minute_buf: [4:0]u8 = undefined;
        @memset(&minute_buf, 0);
        const minute_str = std.fmt.bufPrintZ(&minute_buf, "{s}{d}", .{ if (minute < 10) "0" else "", minute }) catch "00";
        var combined_buf: [16:0]u8 = undefined;
        @memset(&combined_buf, 0);
        const num_str = std.fmt.bufPrintZ(&combined_buf, "{s}:{s}", .{ hour_str, minute_str }) catch "00:00";

        const big_font_size: f64 = @as(f64, tstyle.font_size_m) * 1.9 * scale;

        const gold4 = tstyle.color_border_focused.toF64();

        c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);

        var num_ext: c.cairo_text_extents_t = undefined;
        var current_size = big_font_size;
        c.cairo_set_font_size(cr, current_size);
        c.cairo_text_extents(cr, num_str, &num_ext);
        while (num_ext.width > w_d - 8.0 and current_size > 6.0) {
            current_size *= 0.92;
            c.cairo_set_font_size(cr, current_size);
            c.cairo_text_extents(cr, num_str, &num_ext);
        }

        // Top buffer: 10pt gap between the status band and the clock digits,
        // matching the weather side.
        const top_pad: f64 = status_band_h + 10.0 * scale;
        const num_baseline_y = num_ext.height + top_pad;
        const time_x = (w_d - num_ext.width) * 0.5 - 9.0 * scale;

        c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 1.0);
        c.cairo_move_to(cr, time_x, num_baseline_y);
        c.cairo_show_text(cr, num_str);

        // 3-line date block below the time, each line centered.
        const weekday_name = weekdayName(tm.*.tm_wday);
        const day = @as(i32, @intCast(tm.*.tm_mday));
        var day_buf: [32:0]u8 = undefined;
        @memset(&day_buf, 0);
        const day_str = std.fmt.bufPrintZ(&day_buf, "{d}{s}", .{ day, ordinalSuffix(day) }) catch "1st";

        var date_font_size: f64 = @as(f64, tstyle.font_size_s) * 1.3 * scale;
        var line_gap = date_font_size * 1.25;
        while (num_baseline_y + line_gap * 3.6 + date_font_size * 0.3 > h_d and date_font_size > 6.0) {
            date_font_size *= 0.92;
            line_gap *= 0.92;
        }
        const date_block_top = num_baseline_y + line_gap * 1.5;

        const month_name = monthName(tm.*.tm_mon);
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
            // Date sits 7px left with the clock, plus 3px back right.
            c.cairo_move_to(cr, (w_d - ext2.width) * 0.5 - 4.0 * scale, y);
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
            return;
        };
        if (box.width <= 0 or box.height <= 0) {
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
        const peek_vmargin = 8;
        const max_pill_side: i32 = @max(80, @as(i32, @intFromFloat(@as(f64, 215.0) * @as(f64, scale))));
        const pill_w: i32 = @max(20, @min(box.width - 2 * peek_hmargin, max_pill_side));
        const pill_h: i32 = @max(40, @min(box.height - 2 * peek_vmargin, max_pill_side));
        const pill_x = box.x + peek_hmargin + @divTrunc(box.width - 2 * peek_hmargin - pill_w, 2);
        const pill_y = box.y + peek_vmargin + 4;

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
        widget.click_box = .{ .x = pill_x, .y = pill_y, .width = @intCast(pill_w), .height = @intCast(pill_h) };
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

    fn drawGaugeWidget(self: *Self, widget: *PerOutputGauge) void {
        const full_box = self.host.left_peek_box(self.host.ctx, gaugeWidgetIndex(self, widget)) orelse {
            return;
        };
        if (full_box.width <= 0 or full_box.height <= 0) {
            return;
        }

        const style_ = self.host.theme.style;
        const theme_gen = self.host.theme.generation;
        const scale = widget.info.scale;

        const peek_hmargin = 2;
        const peek_vmargin = 8;
        const weather_height: i32 = @max(80, @as(i32, @intFromFloat(@as(f64, 215.0) * @as(f64, scale))));
        // Split the remaining left-peek area: gauges at the top, drives below.
        const total_h = @max(0, full_box.height - weather_height - peek_vmargin * 2);
        const gauge_h_i: i32 = @max(40, total_h);
        const pill_w: i32 = @max(20, full_box.width - 2 * peek_hmargin);
        const pill_x = full_box.x + peek_hmargin + @divTrunc(full_box.width - 2 * peek_hmargin - pill_w, 2);
        const pill_y = full_box.y + weather_height + peek_vmargin + 4;
        const pill_h = gauge_h_i;

        const redraw = widget.scene_buffer == null or
            widget.last_w != pill_w or
            widget.last_h != pill_h or
            widget.last_x != pill_x or
            widget.last_y != pill_y or
            widget.last_scale != scale or
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
        widget.click_box = .{ .x = pill_x, .y = pill_y, .width = @intCast(pill_w), .height = @intCast(pill_h) };
        widget.last_scale = scale;
        widget.last_theme_generation = theme_gen;

        // Clickable cauldron box removed: cauldron is now the bottom pet button icon.
        widget.cauldron_box = .{ .x = 0, .y = 0, .width = 0, .height = 0 };

        const dev_w: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(pill_w)) * scale));
        const dev_h: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(pill_h)) * scale));
        const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, dev_w);
        if (stride <= 0) return;
        const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(dev_h));
        const temp = self.allocator.alloc(u8, buf_size) catch |err| {
            std.log.err("KidulWM: gauge widget buffer alloc failed: {}", .{err});
            return;
        };
        defer self.allocator.free(temp);
        @memset(temp, 0);

        const surface = c.cairo_image_surface_create_for_data(temp.ptr, c.CAIRO_FORMAT_ARGB32, dev_w, dev_h, stride);
        defer c.cairo_surface_destroy(surface);
        const cr = c.cairo_create(surface) orelse {
            std.log.err("KidulWM: failed to create cairo context for gauge widget", .{});
            return;
        };
        defer c.cairo_destroy(cr);

        c.cairo_save(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        self.gauge.renderPeek(cr, .{
            .x = pill_x,
            .y = pill_y,
            .width = dev_w,
            .height = dev_h,
        }, style_, scale);

        c.cairo_restore(cr);

        const DataBuffer = @import("../render/buffer.zig").DataBuffer;
        const buffer = DataBuffer.create(temp, dev_w, dev_h, @intCast(stride)) catch |err| {
            std.log.err("KidulWM: failed to create gauge widget buffer: {}", .{err});
            return;
        };
        if (widget.buffer) |old| wlr.Buffer.drop(old);
        widget.buffer = buffer;
        if (widget.scene_buffer) |old| old.node.destroy();
        const sb = widget.tree.createSceneBuffer(buffer) catch |err| {
            std.log.err("KidulWM: failed to create gauge widget scene buffer: {}", .{err});
            wlr.Buffer.drop(buffer);
            widget.buffer = null;
            return;
        };
        sb.setDestSize(pill_w, pill_h);
        widget.scene_buffer = sb;
        widget.tree.node.setPosition(pill_x, pill_y);
        widget.tree.node.raiseToTop();
    }

    fn drawDrivesWidget(self: *Self, widget: *PerOutputDrives) void {
        const full_box = self.host.left_peek_box(self.host.ctx, drivesWidgetIndex(self, widget)) orelse {
            return;
        };
        if (full_box.width <= 0 or full_box.height <= 0) {
            return;
        }

        const style_ = self.host.theme.style;
        const theme_gen = self.host.theme.generation;
        const scale = widget.info.scale;

        const peek_hmargin = 2;
        const peek_vmargin = 8;
        const weather_height: i32 = @max(80, @as(i32, @intFromFloat(@as(f64, 215.0) * @as(f64, scale))));
        const total_h = @max(0, full_box.height - weather_height - peek_vmargin * 2);
        const gauge_h_i: i32 = @max(40, @divTrunc(total_h * 4, 10));
        const drives_h_i: i32 = @max(40, total_h - gauge_h_i);
        const pill_w: i32 = @max(20, full_box.width - 2 * peek_hmargin);
        const pill_x = full_box.x + peek_hmargin + @divTrunc(full_box.width - 2 * peek_hmargin - pill_w, 2);
        const pill_y = full_box.y + weather_height + peek_vmargin + 4 + gauge_h_i;
        const pill_h = drives_h_i;

        const kfiles_open = self.host.is_kfiles_open(self.host.ctx);

        const redraw = widget.scene_buffer == null or
            widget.last_w != pill_w or
            widget.last_h != pill_h or
            widget.last_x != pill_x or
            widget.last_y != pill_y or
            widget.last_scale != scale or
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
        widget.click_box = .{ .x = pill_x, .y = pill_y, .width = @intCast(pill_w), .height = @intCast(pill_h) };
        widget.last_scale = scale;
        widget.last_theme_generation = theme_gen;

        // Compute per-drive click boxes based on the same layout used in drives.zig.
        const s_f = @as(f64, scale);
        const pad: f64 = 6.0 * s_f;
        const item_h: f64 = 28.0 * s_f;
        const gap: f64 = 4.0 * s_f;
        const top: f64 = 10.0 * s_f;
        widget.drive_count = 0;
        for (0..widget.drive_boxes.len) |i| {
            widget.drive_boxes[i] = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        }
        if (kfiles_open) {
            // Discover drives to know how many boxes to expose.
            var drives_buf: [8]DriveInfo = undefined;
            const count = discoverDrives(&drives_buf);
            const max_visible = @min(count, widget.drive_boxes.len);
            widget.drive_count = max_visible;
            var i: usize = 0;
            while (i < max_visible) : (i += 1) {
                const y = top + @as(f64, @floatFromInt(i)) * (item_h + gap);
                widget.drive_boxes[i] = .{
                    .x = @intFromFloat(@as(f64, @floatFromInt(pill_x)) + pad),
                    .y = @intFromFloat(@as(f64, @floatFromInt(pill_y)) + y),
                    .width = @intFromFloat(@as(f64, @floatFromInt(pill_w)) - 2.0 * pad),
                    .height = @intFromFloat(item_h),
                };
            }
        }

        const dev_w: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(pill_w)) * scale));
        const dev_h: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(pill_h)) * scale));
        const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, dev_w);
        if (stride <= 0) return;
        const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(dev_h));
        const temp = self.allocator.alloc(u8, buf_size) catch |err| {
            std.log.err("KidulWM: drives widget buffer alloc failed: {}", .{err});
            return;
        };
        defer self.allocator.free(temp);
        @memset(temp, 0);

        const surface = c.cairo_image_surface_create_for_data(temp.ptr, c.CAIRO_FORMAT_ARGB32, dev_w, dev_h, stride);
        defer c.cairo_surface_destroy(surface);
        const cr = c.cairo_create(surface) orelse {
            std.log.err("KidulWM: failed to create cairo context for drives widget", .{});
            return;
        };
        defer c.cairo_destroy(cr);

        c.cairo_save(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        self.drives.renderPeek(cr, .{
            .x = pill_x,
            .y = pill_y,
            .width = dev_w,
            .height = dev_h,
        }, style_, scale, kfiles_open);

        c.cairo_restore(cr);

        const DataBuffer = @import("../render/buffer.zig").DataBuffer;
        const buffer = DataBuffer.create(temp, dev_w, dev_h, @intCast(stride)) catch |err| {
            std.log.err("KidulWM: failed to create drives widget buffer: {}", .{err});
            return;
        };
        if (widget.buffer) |old| wlr.Buffer.drop(old);
        widget.buffer = buffer;
        if (widget.scene_buffer) |old| old.node.destroy();
        const sb = widget.tree.createSceneBuffer(buffer) catch |err| {
            std.log.err("KidulWM: failed to create drives widget scene buffer: {}", .{err});
            wlr.Buffer.drop(buffer);
            widget.buffer = null;
            return;
        };
        sb.setDestSize(pill_w, pill_h);
        widget.scene_buffer = sb;
        widget.tree.node.setPosition(pill_x, pill_y);
        widget.tree.node.raiseToTop();
    }

    fn drawMediaWidget(self: *Self, widget: *PerOutputMedia) void {
        const box = self.host.right_peek_box(self.host.ctx, mediaWidgetIndex(self, widget)) orelse {
            return;
        };
        if (box.width <= 0 or box.height <= 0) {
            return;
        }

        const style_ = self.host.theme.style;
        const theme_gen = self.host.theme.generation;
        const scale = widget.info.scale;

        const peek_hmargin = 2;
        const peek_vmargin = 4;
        // Butterfly cap: 130*scale was ~150% too big once the 4K reported 2x
        // (260px tall, hugging the bottom). 86 logical px matches the left-peek
        // logo's footprint; raise the bottom margin to the logo's 10px line.
        const max_pill_side: i32 = @max(60, @as(i32, @intFromFloat(@as(f64, 86.0) * @as(f64, scale))));
        const pill_w: i32 = @max(20, @min(box.width - 2 * peek_hmargin, max_pill_side));
        const pill_h: i32 = @max(40, @min(box.height - 2 * peek_vmargin, max_pill_side));
        const pill_x = box.x + peek_hmargin + @divTrunc(box.width - 2 * peek_hmargin - pill_w, 2);
        const pill_y = box.y + box.height - pill_h - @max(peek_vmargin, 10);

        const title = std.mem.sliceTo(&self.media.cached.title, 0);
        const title_hash: u64 = std.hash.Crc32.hash(title);
        // The helix animates every frame, so always redraw.
        const redraw = true;

        if (!redraw) {
            widget.tree.node.setPosition(pill_x, pill_y);
            widget.tree.node.raiseToTop();
            return;
        }

        widget.last_w = pill_w;
        widget.last_h = pill_h;
        widget.last_x = pill_x;
        widget.last_y = pill_y;
        widget.click_box = .{ .x = pill_x, .y = pill_y, .width = @intCast(pill_w), .height = @intCast(pill_h) };
        widget.last_scale = scale;
        widget.last_title_hash = title_hash;
        widget.last_theme_generation = theme_gen;

        const dev_w: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(pill_w)) * scale));
        const dev_h: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(pill_h)) * scale));
        const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, dev_w);
        if (stride <= 0) return;
        const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(dev_h));
        const temp = self.allocator.alloc(u8, buf_size) catch |err| {
            std.log.err("KidulWM: media widget buffer alloc failed: {}", .{err});
            return;
        };
        defer self.allocator.free(temp);
        @memset(temp, 0);

        const surface = c.cairo_image_surface_create_for_data(temp.ptr, c.CAIRO_FORMAT_ARGB32, dev_w, dev_h, stride);
        defer c.cairo_surface_destroy(surface);
        const cr = c.cairo_create(surface) orelse {
            std.log.err("KidulWM: failed to create cairo context for media widget", .{});
            return;
        };
        defer c.cairo_destroy(cr);

        c.cairo_save(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        self.media.renderPeek(cr, .{
            .x = pill_x,
            .y = pill_y,
            .width = dev_w,
            .height = dev_h,
        }, style_, scale);

        c.cairo_restore(cr);

        const DataBuffer = @import("../render/buffer.zig").DataBuffer;
        const buffer = DataBuffer.create(temp, dev_w, dev_h, @intCast(stride)) catch |err| {
            std.log.err("KidulWM: failed to create media widget buffer: {}", .{err});
            return;
        };
        if (widget.buffer) |old| wlr.Buffer.drop(old);
        widget.buffer = buffer;
        if (widget.scene_buffer) |old| old.node.destroy();
        const sb = widget.tree.createSceneBuffer(buffer) catch |err| {
            std.log.err("KidulWM: failed to create media widget scene buffer: {}", .{err});
            wlr.Buffer.drop(buffer);
            widget.buffer = null;
            return;
        };
        sb.setDestSize(pill_w, pill_h);
        widget.scene_buffer = sb;
        widget.tree.node.setPosition(pill_x, pill_y);
        widget.tree.node.raiseToTop();
    }

    fn drawNetworkWidget(self: *Self, widget: *PerOutputNetwork) void {
        // The network icon is now rendered inside the clock widget buffer, but
        // we still poll state here. Hide the dedicated network tree so it does
        // not draw a second copy or fight for z-order.
        widget.tree.node.setEnabled(false);
        if (widget.scene_buffer) |old| {
            old.node.destroy();
            widget.scene_buffer = null;
        }
        if (widget.buffer) |old| {
            wlr.Buffer.drop(old);
            widget.buffer = null;
        }
        widget.last_w = 0;
        widget.last_h = 0;
        widget.last_x = 0;
        widget.last_y = 0;
        widget.click_box = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        widget.last_scale = widget.info.scale;
        widget.last_state = self.network.state;
        widget.last_theme_generation = self.host.theme.generation;
    }

    // ── Signal pills ──────────────────────────────────────────────────

    fn signalNowMs() u64 {
        var ts: std.os.linux.timespec = undefined;
        if (std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts) != 0) {
            return 0;
        }
        return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / 1_000_000;
    }

    fn scanSignals(self: *Self) void {
        const now = signalNowMs();
        const scan_interval: u64 = 500;
        if (now -% self.signal_last_scan_ms < scan_interval) return;
        self.signal_last_scan_ms = now;

        self.signal_count = 0;
        const dir = c_std.opendir("/tmp/kidul-signals");
        if (dir == null) return;
        defer _ = c_std.closedir(dir);

        var entry: ?*c_std.dirent = null;
        while (self.signal_count < MAX_SIGNALS) {
            entry = c_std.readdir(dir);
            if (entry == null) break;
            const fname = std.mem.sliceTo(&entry.?.d_name, 0);
            if (fname.len == 0 or fname[0] == '.') continue;

            // Filename without .state extension is the signal name.
            const sig_name = if (std.mem.endsWith(u8, fname, ".state"))
                fname[0 .. fname.len - 6]
            else
                fname;

            // Read the state file.
            var path_buf: [256:0]u8 = undefined;
            @memset(&path_buf, 0);
            const path = std.fmt.bufPrintZ(&path_buf, "/tmp/kidul-signals/{s}", .{fname}) catch continue;
            const f = c_std.fopen(path, "r");
            if (f == null) continue;
            defer _ = c_std.fclose(f);

            var line_buf: [128:0]u8 = undefined;
            @memset(&line_buf, 0);
            if (c_std.fgets(&line_buf, @intCast(line_buf.len), f) == null) continue;
            const line = std.mem.sliceTo(&line_buf, 0);
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;

            // Parse: "state_text severity icon_hint"
            var it = std.mem.tokenizeAny(u8, trimmed, " \t");
            const state_text = it.next() orelse continue;
            const sev_str = it.next() orelse continue;
            const icon_hint = it.next() orelse "";

            const slot = &self.signals[self.signal_count];
            slot.* = .{};

            const name_copy = @min(sig_name.len, slot.name.len - 1);
            @memcpy(slot.name[0..name_copy], sig_name[0..name_copy]);
            slot.name_len = @intCast(name_copy);

            const state_copy = @min(state_text.len, slot.state_text.len - 1);
            @memcpy(slot.state_text[0..state_copy], state_text[0..state_copy]);
            slot.state_len = @intCast(state_copy);

            slot.severity = if (std.mem.eql(u8, sev_str, "warning"))
                .warning
            else if (std.mem.eql(u8, sev_str, "alert"))
                .alert
            else if (std.mem.eql(u8, sev_str, "muted"))
                .muted
            else
                .ok;

            const icon_copy = @min(icon_hint.len, slot.icon_hint.len - 1);
            @memcpy(slot.icon_hint[0..icon_copy], icon_hint[0..icon_copy]);
            slot.icon_len = @intCast(icon_copy);

            self.signal_count += 1;
        }
    }

    fn signalHash(self: *const Self) u64 {
        var h: u64 = 14695981039346656037; // FNV-1a basis
        for (0..self.signal_count) |i| {
            const sig = self.signals[i];
            const name = sig.name[0..sig.name_len];
            const state = sig.state_text[0..sig.state_len];
            for (name) |b| {
                h = (h ^ b) *% 1099511628211;
            }
            for (state) |b| {
                h = (h ^ b) *% 1099511628211;
            }
            h = (h ^ @intFromEnum(sig.severity)) *% 1099511628211;
        }
        return h;
    }

    fn severityColor(sev: SignalSeverity, style_: style.Style) [4]f64 {
        return switch (sev) {
            .ok => style_.color_gold.toF64(),
            .warning => .{ 0.851, 0.447, 0.18, 1.0 }, // amber
            .alert => .{ 0.72, 0.18, 0.18, 1.0 }, // red
            .muted => style_.color_text_muted.toF64(), // grey
        };
    }

    fn worstSeverity(self: *const Self) SignalSeverity {
        var worst: SignalSeverity = .ok;
        for (0..self.signal_count) |i| {
            const sig = self.signals[i];
            switch (sig.severity) {
                .alert => return .alert,
                .warning => worst = .warning,
                .muted => if (worst == .ok) { worst = .muted; },
                .ok => {},
            }
        }
        return worst;
    }

    fn drawSignalsCard(self: *const Self, cr: *c.cairo_t, w: f64, h: f64) void {
        const tstyle = self.host.theme.style;
        const scale = outputScaleForCard(self);
        const s_f: f64 = @as(f64, scale);
        const card_font = "Fantasque Sans Mono";
        const muted4 = tstyle.color_text_muted.toF64();
        const gold4 = tstyle.color_gold.toF64();

        // Full slide: fill background with card mat color, no card frame.
        const bg4 = tstyle.color_card_mat.toF64();
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], 0.91);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        c.cairo_save(cr);

        // Title at the top.
        c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
        c.cairo_set_font_size(cr, 20.0 * s_f);
        var title_ext: c.cairo_text_extents_t = undefined;
        const title_str = "Signals";
        c.cairo_text_extents(cr, @ptrCast(title_str), &title_ext);
        const title_x = (w - title_ext.width) * 0.5;
        const title_y = 30.0 * s_f + title_ext.height;
        c.cairo_move_to(cr, title_x + 1.0 * s_f, title_y + 1.0 * s_f);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.6);
        c.cairo_show_text(cr, @ptrCast(title_str));
        c.cairo_move_to(cr, title_x, title_y);
        c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.95);
        c.cairo_show_text(cr, @ptrCast(title_str));

        // Signal pills stacked below the title.
        const item_h: f64 = 36.0 * s_f;
        const item_gap: f64 = 8.0 * s_f;
        const top_pad: f64 = 60.0 * s_f;
        const pill_w: f64 = w - 40.0 * s_f;
        const pill_x: f64 = 20.0 * s_f;
        const depth: f64 = item_h / 2.0;

        for (0..self.signal_count) |i| {
            const sig = self.signals[i];
            const y = top_pad + @as(f64, @floatFromInt(i)) * (item_h + item_gap);
            if (y + item_h > h) break;
            drawSignalPill(cr, pill_x, y, pill_w, item_h, depth, &sig, s_f, tstyle);
        }

        // Details section below pills — state text, severity, icon hint.
        const details_y = top_pad + @as(f64, @floatFromInt(self.signal_count)) * (item_h + item_gap) + 20.0 * s_f;
        if (details_y < h) {
            c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
            c.cairo_set_font_size(cr, 13.0 * s_f);

            for (0..self.signal_count) |i| {
                const sig = self.signals[i];
                const dy = details_y + @as(f64, @floatFromInt(i)) * 18.0 * s_f;
                if (dy + 18.0 * s_f > h) break;

                const sev_color = severityColor(sig.severity, tstyle);
                const name = sig.name[0..sig.name_len];
                const state = sig.state_text[0..sig.state_len];

                // Name label
                var line_buf: [128:0]u8 = undefined;
                @memset(&line_buf, 0);
                const line = std.fmt.bufPrintZ(&line_buf, "{s}: {s}", .{ name, state }) catch "";
                c.cairo_set_source_rgba(cr, muted4[0], muted4[1], muted4[2], 0.8);
                c.cairo_move_to(cr, pill_x, dy + 13.0 * s_f);
                c.cairo_show_text(cr, @ptrCast(line));

                // Severity dot
                c.cairo_new_path(cr);
                c.cairo_arc(cr, pill_x + pill_w - 12.0 * s_f, dy + 8.0 * s_f, 4.0 * s_f, 0, 2.0 * std.math.pi);
                c.cairo_set_source_rgba(cr, sev_color[0], sev_color[1], sev_color[2], 0.9);
                c.cairo_fill(cr);
            }
        }

        c.cairo_restore(cr);
    }

    fn drawSignalPill(
        cr: *c.cairo_t,
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        depth: f64,
        sig: *const SignalEntry,
        s: f64,
        tstyle: style.Style,
    ) void {
        const sev_color = severityColor(sig.severity, tstyle);
        const margin: f64 = 2.0 * s;
        const pill_x = x + margin;
        const pill_w = w - margin * 2.0;
        const r: f64 = h / 2.0;

        c.cairo_save(cr);

        // Shadow.
        panelOutline(tstyle, cr, pill_x + 2.0 * s, y + 3.0 * s, pill_w, h, depth);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.35);
        c.cairo_fill(cr);

        // Glass body — severity-tinted.
        panelOutline(tstyle, cr, pill_x, y, pill_w, h, depth);
        const glass = c.cairo_pattern_create_linear(pill_x, y, pill_x, y + h).?;
        c.cairo_pattern_add_color_stop_rgba(glass, 0.0, 0.09, 0.09, 0.10, 0.85);
        c.cairo_pattern_add_color_stop_rgba(glass, 0.5, 0.06, 0.06, 0.07, 0.82);
        c.cairo_pattern_add_color_stop_rgba(glass, 0.5, sev_color[0], sev_color[1], sev_color[2], 0.15);
        c.cairo_pattern_add_color_stop_rgba(glass, 1.0, 0.04, 0.04, 0.05, 0.78);
        c.cairo_set_source(cr, glass);
        c.cairo_fill_preserve(cr);
        c.cairo_pattern_destroy(glass);

        // Severity-colored rim.
        c.cairo_set_source_rgba(cr, sev_color[0], sev_color[1], sev_color[2], 0.55);
        c.cairo_set_line_width(cr, 1.0 * s);
        c.cairo_stroke(cr);

        // Severity dot on the left.
        const dot_r: f64 = 4.0 * s;
        const dot_cx = pill_x + r;
        const dot_cy = y + r;
        c.cairo_new_path(cr);
        c.cairo_arc(cr, dot_cx, dot_cy, dot_r, 0, 2.0 * std.math.pi);
        c.cairo_set_source_rgba(cr, sev_color[0], sev_color[1], sev_color[2], 0.9);
        c.cairo_fill(cr);

        // Signal name text.
        const name = sig.name[0..sig.name_len];
        const state = sig.state_text[0..sig.state_len];
        const card_font = "Fantasque Sans Mono";
        const font_size = 13.0 * s;
        c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
        c.cairo_set_font_size(cr, font_size);

        var name_buf: [40:0]u8 = undefined;
        @memset(&name_buf, 0);
        const name_z = std.fmt.bufPrintZ(&name_buf, "{s}", .{name}) catch "";
        var name_ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, @ptrCast(name_z), &name_ext);

        const text_x = dot_cx + dot_r + 8.0 * s;
        const text_y = y + (h + name_ext.height) / 2.0;

        c.cairo_move_to(cr, text_x + 1.0 * s, text_y + 1.0 * s);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.7);
        c.cairo_show_text(cr, @ptrCast(name_z));

        const muted4 = tstyle.color_text_muted.toF64();
        c.cairo_move_to(cr, text_x, text_y);
        c.cairo_set_source_rgba(cr, muted4[0], muted4[1], muted4[2], 0.9);
        c.cairo_show_text(cr, @ptrCast(name_z));

        // State text (right-aligned, severity colored).
        var state_buf: [70:0]u8 = undefined;
        @memset(&state_buf, 0);
        const state_z = std.fmt.bufPrintZ(&state_buf, "{s}", .{state}) catch "";
        var state_ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, @ptrCast(state_z), &state_ext);
        const state_x = pill_x + pill_w - r - 8.0 * s - state_ext.width;
        const state_y = text_y;

        c.cairo_move_to(cr, state_x + 1.0 * s, state_y + 1.0 * s);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.7);
        c.cairo_show_text(cr, @ptrCast(state_z));

        c.cairo_move_to(cr, state_x, state_y);
        c.cairo_set_source_rgba(cr, sev_color[0], sev_color[1], sev_color[2], 0.9);
        c.cairo_show_text(cr, @ptrCast(state_z));

        c.cairo_restore(cr);
    }

    fn updateCard(self: *Self) void {
        const now_us = animation.nowUs();
        const prev = self.last_update_us;
        const dt = if (prev == 0) 0.0 else @as(f64, @floatFromInt(now_us - prev)) / 1_000_000.0;

        self.card_anim.setTarget(if (self.anyCardOpen()) 1.0 else 0.0);
        const more = self.card_anim.step(dt);
        if (self.card_anim.value < 0.005 and !self.anyCardOpen()) {
            if (self.card_tree) |tree| tree.node.setEnabled(false);
            if (self.card_shadow_tree) |shadow_tree| shadow_tree.node.setEnabled(false);
            return;
        }

        const box = self.host.focused_window_box(self.host.ctx) orelse blk: {
            const out_count = self.host.output_count(self.host.ctx);
            if (out_count == 0) {
                if (self.card_tree) |tree| tree.node.setEnabled(false);
                return;
            }
            const info = self.host.output_info(self.host.ctx, 0);
            break :blk wlr.Box{
                .x = info.x + 80,
                .y = info.y + 80,
                .width = @max(320, info.width - 160),
                .height = @max(220, info.height - 160),
            };
        };
        self.card_box = box;

        // Full slide: fill the entire focused window box, no shrinking.
        const w = box.width;
        const h = box.height;
        if (w <= 0 or h <= 0) {
            if (self.card_tree) |tree| tree.node.setEnabled(false);
            return;
        }
        const card_x = box.x;
        const card_y = box.y;

        const current_mode = self.card_mode;
        const needs_redraw = self.card_last_w != w or
            self.card_last_h != h or
            self.card_last_mode != current_mode or
            self.card_last_generation != self.host.theme.generation or
            @abs(self.card_last_open - self.card_anim.value) > 0.0001 or
            more or
            self.files.state_generation != self.files_state_generation or
            self.media.state_generation != self.media_state_generation or
            self.network_card_last_state != self.network.state or
            (self.signals_card_open and self.signalHash() != self.signal_last_hash);

        const closing = self.card_anim.isClosing();
        const slide_t: f32 = if (closing) (1.0 - self.card_anim.value) else 0.0;
        const slide_x: i32 = @intFromFloat(@round(@as(f64, @floatCast(slide_t * self.card_close_dx))));
        const slide_y: i32 = @intFromFloat(@round(@as(f64, @floatCast(slide_t * self.card_close_dy))));

        // No shadow for full slides.
        if (self.card_shadow_tree) |shadow_tree| {
            shadow_tree.node.setEnabled(false);
        }

        if (self.card_tree) |tree| {
            tree.node.setPosition(card_x + slide_x, card_y + slide_y);
            if (self.anyCardOpen()) {
                tree.node.setEnabled(true);
                tree.node.raiseToTop();
            }
        }

        if (needs_redraw) {
            self.card_last_w = w;
            self.card_last_h = h;
            self.card_last_open = self.card_anim.value;
            self.card_last_generation = self.host.theme.generation;
            self.card_last_mode = current_mode;
            self.files_state_generation = self.files.state_generation;
            self.media_state_generation = self.media.state_generation;
            self.network_card_last_state = self.network.state;
            self.signal_last_hash = self.signalHash();
            const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, w);
            if (stride <= 0) return;
            const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(h));
            const temp = self.allocator.alloc(u8, buf_size) catch |err| {
                std.log.err("KidulWM: slide buffer alloc failed: {}", .{err});
                return;
            };
            defer self.allocator.free(temp);
            @memset(temp, 0);
            const surface = c.cairo_image_surface_create_for_data(temp.ptr, c.CAIRO_FORMAT_ARGB32, w, h, stride);
            defer c.cairo_surface_destroy(surface);
            const cr = c.cairo_create(surface) orelse {
                std.log.err("KidulWM: failed to create cairo context for slide", .{});
                return;
            };
            defer c.cairo_destroy(cr);
            switch (current_mode) {
                .calendar => self.drawClockCalendarCard(cr, @floatFromInt(w), @floatFromInt(h)),
                .weather => self.weather.renderCard(cr, @floatFromInt(w), @floatFromInt(h), self.host.theme.style, outputScaleForCard(self)),
                .network => self.network.renderCard(cr, @floatFromInt(w), @floatFromInt(h), self.host.theme.style, outputScaleForCard(self)),
                .files => self.files.renderCard(cr, @floatFromInt(w), @floatFromInt(h), self.host.theme.style, outputScaleForCard(self)),
                .signals => self.drawSignalsCard(cr, @floatFromInt(w), @floatFromInt(h)),
                // Media player lives on the deck slide; the tray card mode
                // is dead. Draw nothing if we ever land here.
                .media => {},
            }
            const DataBuffer = @import("../render/buffer.zig").DataBuffer;
            const buffer = DataBuffer.create(temp, w, h, @intCast(stride)) catch |err| {
                std.log.err("KidulWM: failed to create slide buffer: {}", .{err});
                return;
            };
            if (self.card_buffer) |old| wlr.Buffer.drop(old);
            self.card_buffer = buffer;
            if (self.card_scene_buffer) |old| old.node.destroy();
            const tree = self.card_tree orelse return;
            self.card_scene_buffer = tree.createSceneBuffer(buffer) catch |err| {
                std.log.err("KidulWM: failed to create slide scene buffer: {}", .{err});
                return;
            };
        }
        if (self.card_scene_buffer) |sb| {
            sb.node.raiseToTop();
            const alpha = if (self.card_anim.isClosing() and self.card_anim.preset.fade_close)
                @max(0.0, @min(1.0, self.card_anim.value))
            else
                1.0;
            sb.setOpacity(alpha);
        }
    }

    const CardMode = enum { calendar, weather, media, network, files, signals };

    fn activeCardMode(self: *const Self) CardMode {
        if (self.weather_card_open) return .weather;
        if (self.media_card_open) return .media;
        if (self.network_card_open) return .network;
        if (self.files_card_open) return .files;
        if (self.signals_card_open) return .signals;
        return .calendar;
    }

    fn setCardCloseDirection(self: *Self, mode: CardMode) void {
        const mag: f32 = self.card_anim.preset.slide_close_px;
        switch (mode) {
            .weather => {
                // Weather widget lives at the top-left; close back toward it.
                self.card_close_dx = -mag;
                self.card_close_dy = -mag;
            },
            .media => {
                // Media widget lives at the bottom-right; close back toward it.
                self.card_close_dx = mag;
                self.card_close_dy = mag;
            },
            .calendar => {
                // Calendar widget lives at the top-right; close back toward it.
                self.card_close_dx = mag;
                self.card_close_dy = -mag;
            },
            .network => {
                // Network widget lives at the top-right; close back toward it.
                self.card_close_dx = mag;
                self.card_close_dy = -mag;
            },
            .files => {
                // Files card is opened from the disk gauge (left peek); close back toward it.
                self.card_close_dx = -mag;
                self.card_close_dy = mag;
            },
            .signals => {
                // Signals beacon is top-right; close back toward it.
                self.card_close_dx = mag;
                self.card_close_dy = -mag;
            },
        }
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
            const muted = tstyle.color_text_muted;
            const card_font = "Fantasque Sans Mono";
            // Match the weather card's accent: darker, softer gold used for all
            // panels, text, and rims. Consolidated here so every card looks
            // identical.
            const gold = tstyle.color_border_focused;

            // Respect theme font sizes, scaled slightly down to fit glass card.
            const date_font_size = tstyle.font_size_m;
            const day_font_size = tstyle.font_size_s;

            // Full slide: fill background, no card frame.
            c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
            const bg4 = tstyle.color_card_mat.toF64();
            c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], 0.91);
            c.cairo_paint(cr);
            c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

            const gold4 = gold.toF64();

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

            // Weather-card-style pill: dark gold tint with soft rim.
            panelOutline(tstyle, cr, date_pill_x, date_pill_y, date_pill_w, date_pill_h, pill_depth);
            c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.12);
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.45);
            c.cairo_set_line_width(cr, 1.0);
            c.cairo_stroke(cr);

            const date_text_x = date_pill_x + (date_pill_w - date_ext.width) * 0.5;
            const date_text_y = date_pill_y + (date_pill_h + date_ext.height) * 0.5 - 2.0;
            c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], gold4[3]);
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

            // Weekday header row in weather-card gold.
            c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
            c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], gold4[3]);
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
                    // Day rim only; no background shade on plain days.
                    panelOutline(tstyle, cr, cell_rect_x, cell_rect_y, cell_rect_w, cell_rect_h, 4.0);
                    c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.35);
                    c.cairo_set_line_width(cr, 1.0);
                    c.cairo_stroke(cr);
                }

                // Focused day: weather-card panel emphasis.
                if (cell.is_focused) {
                    const fx = cell_rect_x + 1.0;
                    const fy = cell_rect_y + 1.0;
                    const fw = cell_rect_w - 2.0;
                    const fh = cell_rect_h - 2.0;
                    panelOutline(tstyle, cr, fx, fy, fw, fh, 4.0);
                    c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.15);
                    c.cairo_fill_preserve(cr);
                    c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.45);
                    c.cairo_set_line_width(cr, 1.0);
                    c.cairo_stroke(cr);
                }

                // Today gets a thin rim mark; no panel fill.
                if (cell.is_today and !cell.is_focused) {
                    const fx = cell_rect_x + 2.0;
                    const fy = cell_rect_y + 2.0;
                    const fw = cell_rect_w - 4.0;
                    const fh = cell_rect_h - 4.0;
                    panelOutline(tstyle, cr, fx, fy, fw, fh, 4.0);
                    c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 0.45);
                    c.cairo_set_line_width(cr, 1.0);
                    c.cairo_stroke(cr);
                }

                // Hover: thin rim only, no fill.
                const hover_this = hover_col == cell.col and hover_row == cell.row and !cell.is_focused;
                if (hover_this) {
                    const hx0 = cell_rect_x + 1.0;
                    const hy0 = cell_rect_y + 1.0;
                    const hw = cell_rect_w - 2.0;
                    const hh = cell_rect_h - 2.0;
                    panelOutline(tstyle, cr, hx0, hy0, hw, hh, 4.0);
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
                    // All in-month days share the weather-card gold body color.
                    c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], gold4[3]);
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

fn notificationWidgetIndex(self: *const Tray, widget: *const PerOutputNotifications) usize {
    for (self.notification_widgets.items, 0..) |*w, i| {
        if (w == widget) return i;
    }
    return 0;
}

pub fn notificationAdd(self: *Self, title: []const u8, body: []const u8, source_id: []const u8, priority: ?[]const u8, action_id: ?[]const u8, display_mode: ?[]const u8) void {
    const opts = notifications.PushOptions{
        .priority = if (priority) |p| notifications.Priority.fromString(p) else null,
        .action_id = action_id,
        .display_mode = if (display_mode) |m| notifications.DisplayMode.fromString(m) else null,
    };
    self.notifications.push(title, body, source_id, opts) catch |err| {
        std.log.err("KidulWM: failed to add notification: {}", .{err});
        return;
    };
    self.requestUpdate();
    self.host.request_frame(self.host.ctx);
}

fn drawNotificationWidget(self: *Self, widget: *PerOutputNotifications) void {
    if (self.notifications.queue.activeCount() == 0) {
        if (widget.scene_buffer) |sb| {
            sb.node.destroy();
            widget.scene_buffer = null;
        }
        if (widget.buffer) |buf| {
            wlr.Buffer.drop(buf);
            widget.buffer = null;
        }
        widget.last_w = 0;
        widget.last_h = 0;
        return;
    }
    const box = self.host.right_peek_box(self.host.ctx, notificationWidgetIndex(self, widget)) orelse return;
    if (box.width <= 0 or box.height <= 0) return;

    const style_ = self.host.theme.style;
    const theme_gen = self.host.theme.generation;
    const scale = widget.info.scale;

    const peek_hmargin: i32 = 0;
    const panel_w: i32 = @max(40, box.width - 2 * peek_hmargin);
    const top_breathing: i32 = self.notifications.config.top_breathing_room;
    // Leave room below notifications for the future slide title/favicon band,
    // then the media widget starts below that.
    const title_band_h: i32 = 42;
    const media_gap: i32 = 8;
    const bottom_pad: i32 = 22 + title_band_h + media_gap;

    var clock_bottom: i32 = box.y + top_breathing;
    for (self.widgets.items) |w| {
        if (w.last_y + w.last_h > clock_bottom) {
            clock_bottom = w.last_y + w.last_h;
        }
    }

    var media_top: i32 = box.y + box.height - bottom_pad;
    for (self.media_widgets.items) |w| {
        if (w.last_y > box.y) {
            media_top = @min(media_top, w.last_y);
        }
    }

    const hard_stop = media_top - title_band_h - media_gap;
    const avail_h = hard_stop - clock_bottom - top_breathing;
    if (avail_h < 40) return;

    const panel_x = box.x + peek_hmargin;
    const panel_y = clock_bottom + top_breathing;
    const panel_h = avail_h;

    const active_item = if (self.notifications.queue.items.items.len > self.notifications.tw.queue_index and
        self.notifications.tw.queue_index < self.notifications.queue.items.items.len)
        &self.notifications.queue.items.items[self.notifications.tw.queue_index]
    else
        null;
    const text_hash: u64 = std.hash.Crc32.hash(
        if (active_item) |item| item.body[0..@min(item.body.len, self.notifications.tw.chars_revealed)] else "",
    );

    // First measure the natural content height on a device-width surface.
    const dev_w_for_measure: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(panel_w)) * scale));
    const measure_surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, dev_w_for_measure, 8);
    const measure_cr = c.cairo_create(measure_surface) orelse {
        c.cairo_surface_destroy(measure_surface);
        return;
    };
    const content_h = notifications.renderNotificationsHeight(measure_cr, .{
        .x = panel_x,
        .y = panel_y,
        .width = panel_w,
        .height = panel_h,
    }, style_, &self.notifications, animation.nowUs());
    c.cairo_destroy(measure_cr);
    c.cairo_surface_destroy(measure_surface);
    const final_h = @min(panel_h, @max(40, content_h));

    const redraw = widget.scene_buffer == null or
        widget.last_w != panel_w or
        widget.last_h != final_h or
        widget.last_x != panel_x or
        widget.last_y != panel_y or
        widget.last_text_hash != text_hash or
        widget.last_theme_generation != theme_gen;

    if (!redraw) {
        widget.tree.node.setPosition(panel_x, panel_y);
        widget.tree.node.raiseToTop();
        return;
    }

    widget.last_w = panel_w;
    widget.last_h = final_h;
    widget.last_x = panel_x;
    widget.last_y = panel_y;
    widget.last_text_hash = text_hash;
    widget.last_theme_generation = theme_gen;

    const dev_w: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(panel_w)) * scale));
    const dev_h: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(final_h)) * scale));
    const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, dev_w);
    if (stride <= 0) return;
    const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(dev_h));
    const temp = self.allocator.alloc(u8, buf_size) catch |err| {
        std.log.err("KidulWM: notification widget buffer alloc failed: {}", .{err});
        return;
    };
    defer self.allocator.free(temp);
    @memset(temp, 0);

    const surface = c.cairo_image_surface_create_for_data(temp.ptr, c.CAIRO_FORMAT_ARGB32, dev_w, dev_h, stride);
    defer c.cairo_surface_destroy(surface);
    const cr = c.cairo_create(surface) orelse {
        std.log.err("KidulWM: failed to create cairo context for notification widget", .{});
        return;
    };
    defer c.cairo_destroy(cr);

    c.cairo_save(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    c.cairo_paint(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    notifications.renderNotifications(cr, .{
        .x = panel_x,
        .y = panel_y,
        .width = dev_w,
        .height = dev_h,
    }, style_, &self.notifications, animation.nowUs());

    c.cairo_restore(cr);

    const DataBuffer = @import("../render/buffer.zig").DataBuffer;
    const buffer = DataBuffer.create(temp, dev_w, dev_h, @intCast(stride)) catch |err| {
        std.log.err("KidulWM: failed to create notification widget buffer: {}", .{err});
        return;
    };
    if (widget.buffer) |old| wlr.Buffer.drop(old);
    widget.buffer = buffer;
    if (widget.scene_buffer) |old| old.node.destroy();
    const sb = widget.tree.createSceneBuffer(buffer) catch |err| {
        std.log.err("KidulWM: failed to create notification widget scene buffer: {}", .{err});
        wlr.Buffer.drop(buffer);
        widget.buffer = null;
        return;
    };
    sb.setDestSize(panel_w, final_h);
    widget.scene_buffer = sb;
    widget.tree.node.setPosition(panel_x, panel_y);
    widget.tree.node.raiseToTop();
}
};
