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
    icon_cache: std.StringHashMap(*c.cairo_surface_t),

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
        var it = self.icon_cache.iterator();
        while (it.next()) |entry| {
            c.cairo_surface_destroy(entry.value_ptr.*);
        }
        self.icon_cache.deinit();
        self.outputs.deinit(self.allocator);
        self.allocator.free(self.items);
    }

    pub fn addOutput(self: *Self, output_ctx: *anyopaque) void {
        const info = self.host.output_info(self.host.ctx, self.outputs.items.len);
        self.outputs.append(self.allocator, .{ .output_ctx = output_ctx, .info = info }) catch |err| {
            std.log.err("KidulWM: tray addOutput failed: {}", .{err});
            return;
        };
        self.requestUpdate();
    }

    pub fn removeOutput(self: *Self, output_ctx: *anyopaque) void {
        for (self.outputs.items, 0..) |po, i| {
            if (po.output_ctx == output_ctx) {
                _ = self.outputs.orderedRemove(i);
                return;
            }
        }
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
        self.requestUpdate();
    }

    pub fn selectPrev(self: *Self) void {
        if (!self.isOpen()) {
            self.toggle();
            return;
        }
        if (self.selected_index > 0) {
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
        switch (self.items[self.selected_index].action) {
            .cycle_animation => self.host.cycle_animation(self.host.ctx),
            .toggle_tray => self.toggle(),
            .next_animation => self.host.cycle_animation(self.host.ctx),
            .spawn => {},
            .none => {},
        }
    }

    pub fn isOpen(self: *const Self) bool {
        return self.open or self.open_amount > 0.01;
    }

    pub fn scroll(self: *Self, delta: f32) void {
        if (!self.isOpen()) return;
        _ = delta;
        self.requestUpdate();
    }

    pub fn handlePointerMove(self: *Self, px: f64, py: f64) bool {
        _ = self;
        _ = px;
        _ = py;
        return false;
    }

    pub fn handlePointerClick(self: *Self, px: f64, py: f64) bool {
        _ = self;
        _ = px;
        _ = py;
        return false;
    }

    pub fn update(self: *Self) void {
        const now_us = animation.nowUs();
        const prev = self.last_update_us;
        defer self.last_update_us = now_us;

        const desired: f32 = if (self.open or self.pinned or self.hovered) 1.0 else 0.0;
        if (self.open_amount != desired) {
            const dt = if (prev == 0) 0.0 else @as(f32, @floatFromInt(now_us - prev)) / 1_000_000.0;
            const step = std.math.clamp(dt * slide_rate, 0.0, 1.0);
            if (desired > self.open_amount) {
                self.open_amount = @min(desired, self.open_amount + step);
            } else {
                self.open_amount = @max(desired, self.open_amount - step);
            }
            self.host.request_frame(self.host.ctx);
        }

        _ = update_rate_hz;
    }

    fn pointInside(self: *const Self, info: OutputInfo, px: f64, py: f64) bool {
        _ = self;
        const x = @as(f64, @floatFromInt(info.x));
        const y = @as(f64, @floatFromInt(info.y));
        const w = @as(f64, @floatFromInt(info.focus_left - info.x));
        const h = @as(f64, @floatFromInt(info.height));
        return px >= x and px < x + w and py >= y and py < y + h;
    }
};
