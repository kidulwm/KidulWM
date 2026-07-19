const std = @import("std");
const c_std = @cImport({
    @cInclude("stdio.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/time.h");
    @cInclude("stdlib.h");
    @cInclude("time.h");
});
const c = @import("dm").c;
// Legacy alias to avoid churn below
const c_cairo = c;
const style = @import("../core/style.zig");
const theme_mod = @import("../core/theme.zig");
const moon = @import("../util/moon.zig");

pub const WeatherWidget = struct {
    allocator: std.mem.Allocator,
    card_open: bool = false,
    last_draw_minute: i32 = -1,

    cached_state: WeatherState = .{},
    last_cache_read_ms: u64 = 0,

    pub const WeatherState = struct {
        available: bool = false,
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
        location_name: [32]u8 = std.mem.zeroes([32]u8),
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

    pub fn update(self: *WeatherWidget) void {
        const now = nowMs();
        if (now -% self.last_cache_read_ms >= cache_read_interval_ms) {
            self.tryReadCache();
            self.last_cache_read_ms = now;
        }
    }

    pub fn needsRedraw(self: *const WeatherWidget, current_minute: i32) bool {
        return self.last_draw_minute != current_minute;
    }

    pub fn markDrawn(self: *WeatherWidget, minute: i32) void {
        self.last_draw_minute = minute;
    }

    pub fn state(self: *const WeatherWidget) *const WeatherState {
        return &self.cached_state;
    }

    pub fn renderMoonTest(self: *const WeatherWidget, path: []const u8, theme: *const theme_mod.Theme) !void {
        _ = self;
        const outline = theme.style.color_border_focused.toF64();
        const shadow = theme.style.color_background.toF64();
        try moon.renderMoonTestStrip(path, outline, shadow);
    }

    pub const PeekBox = struct { x: i32, y: i32, width: i32, height: i32 };

    pub fn renderPeek(self: *const WeatherWidget, cr: *c_cairo.cairo_t, box: PeekBox, style_: style.Style, scale: f32) void {
        const w_d: f64 = @floatFromInt(box.width);
        const h_d: f64 = @floatFromInt(box.height);
        if (w_d < 8.0 or h_d < 8.0) return;

        const gold = style_.color_border_focused.toF64();
        const muted = style_.color_text_muted.toF64();
        const bg = style_.color_background.toF64();

        const moon_r: f64 = @min(w_d, h_d) / 6.0 * 0.92;
        const moon_cx = w_d * 0.5;
        const moon_cy = moon_r + 26.0 * scale;

        const phase = moon.phaseForUnixSeconds(@intCast(c_std.time(null)));
        moon.renderMoon(cr, moon_cx, moon_cy, moon_r, phase, gold, bg);

        const state_ = self.state();

        c_cairo.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c_cairo.CAIRO_FONT_SLANT_NORMAL, c_cairo.CAIRO_FONT_WEIGHT_NORMAL);

        var current_buf: [16:0]u8 = undefined;
        @memset(&current_buf, 0);
        const current_str = std.fmt.bufPrintZ(&current_buf, "{d:.0}°", .{state_.current_temp}) catch "--°";

        const big_font_base: f64 = @as(f64, style_.font_size_m) * 1.75 * scale;
        var current_size = big_font_base;
        c_cairo.cairo_set_font_size(cr, current_size);

        var ext: c_cairo.cairo_text_extents_t = undefined;
        c_cairo.cairo_text_extents(cr, current_str, &ext);
        while (ext.width > w_d - 4.0 and current_size > 8.0) {
            current_size *= 0.92;
            c_cairo.cairo_set_font_size(cr, current_size);
            c_cairo.cairo_text_extents(cr, current_str, &ext);
        }

        const tmp_y = moon_cy + moon_r + ext.height + 6.0 * scale;
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
        c_cairo.cairo_move_to(cr, (w_d - ext.width) * 0.5, tmp_y);
        c_cairo.cairo_show_text(cr, current_str);

        var minmax_buf: [32:0]u8 = undefined;
        @memset(&minmax_buf, 0);
        const minmax_str = std.fmt.bufPrintZ(&minmax_buf, "{d:.0}° / {d:.0}°", .{ state_.temp_min, state_.temp_max }) catch "-- / --";

        const mm_size: f64 = @as(f64, style_.font_size_s) * 1.0 * scale;
        c_cairo.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c_cairo.CAIRO_FONT_SLANT_NORMAL, c_cairo.CAIRO_FONT_WEIGHT_NORMAL);
        c_cairo.cairo_set_font_size(cr, mm_size);
        var mm_ext: c_cairo.cairo_text_extents_t = undefined;
        c_cairo.cairo_text_extents(cr, minmax_str, &mm_ext);
        const mm_y = tmp_y + mm_size * 1.25;
        c_cairo.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
        c_cairo.cairo_move_to(cr, (w_d - mm_ext.width) * 0.5, mm_y);
        c_cairo.cairo_show_text(cr, minmax_str);

        if (!state_.available) {
            c_cairo.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
            c_cairo.cairo_set_font_size(cr, mm_size);
            const prompt = "set location";
            var p_ext: c_cairo.cairo_text_extents_t = undefined;
            c_cairo.cairo_text_extents(cr, prompt, &p_ext);
            c_cairo.cairo_move_to(cr, (w_d - p_ext.width) * 0.5, @min(h_d - 6.0 * scale, mm_y + mm_size * 2.0));
            c_cairo.cairo_show_text(cr, prompt);
        }
    }

    const cache_read_interval_ms: u64 = 10 * 60 * 1000;

    fn tryReadCache(self: *WeatherWidget) void {
        const path = cachePath(self.allocator) catch |err| {
            std.log.warn("KidulWM: weather cache path failed: {}", .{err});
            return;
        };
        defer self.allocator.free(path);

        var st: c_std.struct_stat = undefined;
        if (c_std.stat(pathZ(self.allocator, path).ptr, &st) != 0) {
            self.cached_state.available = false;
            return;
        }
        if (st.st_size == 0 or st.st_size > 512 * 1024) {
            std.log.warn("KidulWM: weather cache size out of range: {}", .{st.st_size});
            return;
        }
        const size: usize = @intCast(st.st_size);

        const json_text = self.allocator.alloc(u8, size) catch |err| {
            std.log.warn("KidulWM: weather cache alloc failed: {}", .{err});
            return;
        };
        defer self.allocator.free(json_text);

        const file = c_std.fopen(pathZ(self.allocator, path).ptr, "r") orelse {
            self.cached_state.available = false;
            return;
        };
        defer _ = c_std.fclose(file);
        if (c_std.fread(json_text.ptr, 1, size, file) != size) {
            std.log.warn("KidulWM: weather cache read incomplete", .{});
            return;
        }

        self.parseCacheJson(json_text);
    }

    fn parseCacheJson(self: *WeatherWidget, json_text: []const u8) void {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_text, .{}) catch |err| {
            std.log.warn("KidulWM: weather cache JSON parse failed: {}", .{err});
            return;
        };
        defer parsed.deinit();

        const root = parsed.value;
        self.cached_state.available = true;

        if (root.object.get("current")) |current| {
            self.cached_state.current_temp = jsonF64(current.object.get("temp"));
            self.cached_state.weather_code = jsonI32(current.object.get("weather_code"));
            self.cached_state.wind_speed = jsonF64(current.object.get("wind_speed"));
            self.cached_state.wind_dir = jsonI32(current.object.get("wind_dir"));
        }

        if (root.object.get("daily")) |daily_arr| {
            if (daily_arr.array.items.len > 0) {
                const first = daily_arr.array.items[0];
                self.cached_state.temp_min = jsonF64(first.object.get("temp_min"));
                self.cached_state.temp_max = jsonF64(first.object.get("temp_max"));
            }
        }

        if (root.object.get("hourly")) |hourly_arr| {
            for (hourly_arr.array.items) |hour| {
                const wave = hour.object.get("wave_height");
                const swell = hour.object.get("swell_height");
                const have_marine = wave != null or swell != null;
                if (have_marine) {
                    self.cached_state.wave_height = jsonF64(wave);
                    self.cached_state.swell_height = jsonF64(swell);
                    self.cached_state.swell_dir = jsonI32(hour.object.get("swell_dir"));
                    self.cached_state.swell_period = jsonF64(hour.object.get("swell_period"));
                    break;
                }
            }
        }

        if (root.object.get("location_name")) |loc| {
            const s = switch (loc) {
                .string => |str| str,
                else => "—",
            };
            const len = @min(s.len, self.cached_state.location_name.len - 1);
            @memset(&self.cached_state.location_name, 0);
            @memcpy(self.cached_state.location_name[0..len], s[0..len]);
        }
    }

    fn pathZ(allocator: std.mem.Allocator, path: []const u8) [:0]const u8 {
        const sentinel = allocator.allocSentinel(u8, path.len, 0) catch return "/tmp";
        @memcpy(sentinel[0..path.len], path);
        return sentinel;
    }

    fn nowMs() u64 {
        var tv: c_std.struct_timeval = undefined;
        _ = c_std.gettimeofday(&tv, null);
        return @intCast(tv.tv_sec * 1000 + @divFloor(tv.tv_usec, 1000));
    }

    fn cachePath(allocator: std.mem.Allocator) ![]const u8 {
        const home_c = c_std.getenv("HOME");
        const home: []const u8 = if (home_c) |p| std.mem.sliceTo(p, 0) else "/tmp";
        return std.fs.path.join(allocator, &[_][]const u8{ home, ".cache", "kidulwm", "weather", "home.json" });
    }
};

fn jsonF64(v: ?std.json.Value) f64 {
    const val = v orelse return 0;
    return switch (val) {
        .float => |f| f,
        .integer => |i| @floatFromInt(i),
        else => 0,
    };
}

fn jsonI32(v: ?std.json.Value) i32 {
    const val = v orelse return 0;
    return switch (val) {
        .integer => |i| @intCast(i),
        .float => |f| @intFromFloat(@floor(f)),
        else => 0,
    };
}
