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
    last_draw_minute: i32 = -1,

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

    pub fn renderMoonTest(self: *const WeatherWidget, path: []const u8, theme: *const theme_mod.Theme) !void {
        _ = self;
        const outline = theme.style.color_border_focused.toF64();
        const shadow = theme.style.color_background.toF64();
        try moon.renderMoonTestStrip(path, outline, shadow);
    }
};
