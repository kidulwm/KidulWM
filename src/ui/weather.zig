const std = @import("std");
const wlr = @import("wlroots");
const c = @import("../dm/c.zig").c;
const style = @import("../core/style.zig");
const theme_mod = @import("../core/theme.zig");
const moon = @import("../util/moon.zig");
const DataBuffer = @import("../render/buffer.zig").DataBuffer;

pub const WeatherWidget = struct {
    allocator: std.mem.Allocator,
    card_open: bool = false,

    pub const WeatherState = struct {
        current_temp: f64 = 0,
        temp_min: f64 = 0,
        temp_max: f64 = 0,
        weather_code: i32 = 0,
        wind_speed: f64 = 0,
        wind_dir: i32 = 0,
        wave_height: f64 = 0,
        swell_height: f64 = 0,
        swell_dir: i32 = 0,
        swell_period: f64 = 0,
        location_name: []const u8 = "—",
    };

    pub fn init(allocator: std.mem.Allocator) WeatherWidget {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *WeatherWidget) void {
        _ = self;
    }

    pub fn toggleCard(self: *WeatherWidget) void {
        self.card_open = !self.card_open;
    }

    pub fn onKeyActivity(self: *WeatherWidget) void {
        _ = self;
    }

    pub fn update(self: *WeatherWidget, box: wlr.Box) void {
        _ = self;
        _ = box;
    }

    pub fn renderPeek(self: *const WeatherWidget, cr: *c.cairo_t, box: wlr.Box, theme: *const theme_mod.Theme, now_s: i64) void {
        _ = self;
        const phase = moon.phaseForUnixSeconds(now_s);
        const cx: f64 = @floatFromInt(box.x + @divTrunc(box.width, 2));
        const cy: f64 = @floatFromInt(box.y + @divTrunc(box.height, 4));
        const r: f64 = @floatFromInt(@min(box.width, box.height) / 5);
        const outline = theme.style.color_border_focused.toF64();
        const shadow = theme.style.color_background.toF64();
        moon.renderMoon(cr, cx, cy, r, phase, outline, shadow);
    }
};
