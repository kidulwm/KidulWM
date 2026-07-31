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

pub const CardMode = enum { calendar, weather };

pub const WeatherCard = struct {
    open: bool = false,
    open_count: u32 = 0,
    selected_hour: usize = 0,
    timeline_hours: usize = 24,
    no_surf_index: usize = 0,

    const no_surf_quips = [_][]const u8{
        "Yeah Nah",
        "No surf today",
        "Should've brought the board",
        "Flat as a tack",
        "Time for a coffee, mate",
        "Ocean's asleep",
        "Waves? What waves?",
        "Maybe tomorrow",
        "Go check the coast",
        "No swell, no stress",
    };

    pub fn nextNoSurfQuip(self: *WeatherCard) []const u8 {
        const idx = self.no_surf_index % no_surf_quips.len;
        self.no_surf_index += 1;
        return no_surf_quips[idx];
    }

    pub fn onOpen(self: *WeatherCard) void {
        self.open_count += 1;
        self.open = true;
    }

    pub fn toggle(self: *WeatherCard) void {
        if (self.open) {
            self.open = false;
        } else {
            self.onOpen();
        }
    }
};

pub const WeatherWidget = struct {
    allocator: std.mem.Allocator,
    card: WeatherCard = .{},
    last_draw_minute: i32 = -1,

    cached_state: WeatherState = .{},
    last_cache_read_ms: u64 = 0,

    pub const WeatherState = struct {
        available: bool = false,
        current_temp: f64 = 0,
        temp_min: f64 = 0,
        temp_max: f64 = 0,
        weather_code: i32 = 0,
        is_day: i32 = 0,
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
        self.card.toggle();
    }

    pub fn isCardOpen(self: *const WeatherWidget) bool {
        return self.card.open;
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
        const state_ = self.state();
        const scale_f: f64 = @as(f64, scale);

        // Moon phase stays at the very top, separate from the weather icon.
        const margin: f64 = 14.0 * scale_f;
        const moon_r = @max(5.0 * scale_f, @min(w_d * 0.39, 12.0 * scale_f, (h_d - margin * 2.0) * 0.16));
        const moon_cx = w_d * 0.5;
        const moon_cy = margin + moon_r;
        const phase = moon.phaseForUnixSeconds(@intCast(c_std.time(null)));
        moon.renderMoon(cr, moon_cx, moon_cy, moon_r, phase, gold, bg);

        c_cairo.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c_cairo.CAIRO_FONT_SLANT_NORMAL, c_cairo.CAIRO_FONT_WEIGHT_NORMAL);

        var current_buf: [16:0]u8 = undefined;
        @memset(&current_buf, 0);
        const current_str = std.fmt.bufPrintZ(&current_buf, "{d:.0}°", .{state_.current_temp}) catch "--°";

        const big_font_base: f64 = @as(f64, style_.font_size_m) * 1.7 * scale_f;
        var current_size = big_font_base;
        c_cairo.cairo_set_font_size(cr, current_size);

        var ext: c_cairo.cairo_text_extents_t = undefined;
        c_cairo.cairo_text_extents(cr, current_str, &ext);
        while (ext.width > w_d - margin * 2.0 and current_size > 8.0) {
            current_size *= 0.92;
            c_cairo.cairo_set_font_size(cr, current_size);
            c_cairo.cairo_text_extents(cr, current_str, &ext);
        }

        const tmp_y = moon_cy + moon_r + 10.0 * scale_f + current_size * 0.85;
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
        c_cairo.cairo_move_to(cr, (w_d - ext.width) * 0.5, tmp_y);
        c_cairo.cairo_show_text(cr, current_str);

        var minmax_buf: [32:0]u8 = undefined;
        @memset(&minmax_buf, 0);
        const minmax_str = std.fmt.bufPrintZ(&minmax_buf, "{d:.0}° / {d:.0}°", .{ state_.temp_min, state_.temp_max }) catch "-- / --";

        const mm_size: f64 = @as(f64, style_.font_size_s) * 1.0 * scale_f;
        c_cairo.cairo_set_font_size(cr, mm_size);
        var mm_ext: c_cairo.cairo_text_extents_t = undefined;
        c_cairo.cairo_text_extents(cr, minmax_str, &mm_ext);
        const mm_y = tmp_y + mm_size * 1.25;
        c_cairo.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
        c_cairo.cairo_move_to(cr, (w_d - mm_ext.width) * 0.5, mm_y);
        c_cairo.cairo_show_text(cr, minmax_str);

        // Weather condition icon below the min/max line.
        var icon_r: f64 = 60.0 * scale_f;
        const icon_bottom_margin: f64 = 1.0 * scale_f;
        const max_icon_r = @min(w_d * 0.5 - 4.0 * scale_f, (h_d - (mm_y + icon_bottom_margin)) * 0.5);
        icon_r = @min(icon_r, @max(0.0, max_icon_r));
        if (icon_r >= 8.0 * scale_f) {
            const icon_cx = w_d * 0.5 - 2.0 * scale_f;
            const icon_cy = mm_y + icon_bottom_margin + icon_r;
            renderConditionIcon(cr, icon_cx, icon_cy, icon_r, state_.weather_code, state_.is_day != 0, state_.wind_speed, gold);
        }

        if (!state_.available) {
            // Location prompt intentionally suppressed; user configures location in the weather card.
        }
    }

    pub fn renderCard(self: *WeatherWidget, cr: *c_cairo.cairo_t, w_d: f64, h_d: f64, style_: style.Style, scale: f32) void {
        const gold = style_.color_border_focused.toF64();
        const muted = style_.color_text_muted.toF64();
        const bg = style_.color_background.toF64();
        const state_ = self.state();
        const scale_f: f64 = @as(f64, scale);

        c_cairo.cairo_set_operator(cr, c_cairo.CAIRO_OPERATOR_SOURCE);
        c_cairo.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c_cairo.cairo_paint(cr);
        c_cairo.cairo_set_operator(cr, c_cairo.CAIRO_OPERATOR_OVER);

        const card_frame = @import("card_frame.zig");
        card_frame.Registry.default.drawNamed(cr, style_, w_d, h_d);

        c_cairo.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c_cairo.CAIRO_FONT_SLANT_NORMAL, c_cairo.CAIRO_FONT_WEIGHT_NORMAL);


        const pad_x: f64 = 22.0 * scale_f;
        const pad_y: f64 = 18.0 * scale_f;
        const content_w = w_d - 2.0 * pad_x;
        const content_h = h_d - 2.0 * pad_y;
        _ = content_h;
        const mid_x = w_d * 0.5;
        const gap: f64 = 16.0 * scale_f;
        const panel_w = (content_w - gap) * 0.5;
        const left_x = pad_x;
        const right_x = mid_x + gap * 0.5;
        const top_y = pad_y;
        const bottom_y = h_d - pad_y;

        const title_size: f64 = @as(f64, style_.font_size_m) * 1.25 * scale_f;
        const body_size: f64 = @as(f64, style_.font_size_s) * 1.05 * scale_f;
        const tiny_size: f64 = @as(f64, style_.font_size_s) * 0.85 * scale_f;

        // Top pill: location name.
        var title_buf: [64:0]u8 = undefined;
        @memset(&title_buf, 0);
        const title_str = std.fmt.bufPrintZ(&title_buf, "{s}", .{std.mem.sliceTo(&state_.location_name, 0)}) catch "—";
        c_cairo.cairo_set_font_size(cr, title_size);
        c_cairo.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c_cairo.CAIRO_FONT_SLANT_NORMAL, c_cairo.CAIRO_FONT_WEIGHT_BOLD);
        var title_ext: c_cairo.cairo_text_extents_t = undefined;
        c_cairo.cairo_text_extents(cr, title_str, &title_ext);
        const pill_pad_x: f64 = 20.0 * scale_f;
        const pill_pad_y: f64 = 8.0 * scale_f;
        const pill_w_max = @min(content_w, title_ext.width + 2.0 * pill_pad_x);
        const pill_h = title_size + 2.0 * pill_pad_y;
        const pill_x = pad_x + (content_w - pill_w_max) * 0.5;
        const pill_y = top_y;

        roundedRect(cr, pill_x, pill_y, pill_w_max, pill_h, @min(10.0 * scale_f, pill_h * 0.25));
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.12);
        c_cairo.cairo_fill_preserve(cr);
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.45);
        c_cairo.cairo_set_line_width(cr, 1.0);
        c_cairo.cairo_stroke(cr);

        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
        c_cairo.cairo_move_to(cr, pill_x + (pill_w_max - title_ext.width) * 0.5, pill_y + (pill_h + title_ext.height) * 0.5 - 2.0 * scale_f);
        c_cairo.cairo_show_text(cr, title_str);

        // Divider under title.
        const header_bottom = pill_y + pill_h + 10.0 * scale_f;
        const divider_start = w_d - pad_x;
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.25);
        c_cairo.cairo_set_line_width(cr, 1.0);
        c_cairo.cairo_new_path(cr);
        c_cairo.cairo_move_to(cr, pad_x, header_bottom);
        c_cairo.cairo_line_to(cr, divider_start, header_bottom);
        c_cairo.cairo_stroke(cr);

        const panels_top = header_bottom + 10.0 * scale_f;
        const timeline_h = 32.0 * scale_f;
        const panels_bottom = bottom_y - timeline_h - 10.0 * scale_f;
        const panel_h = panels_bottom - panels_top;

        // Panel outlines.
        roundedRect(cr, left_x, panels_top, panel_w, panel_h, @min(10.0 * scale_f, panel_h * 0.1));
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.15);
        c_cairo.cairo_fill_preserve(cr);
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.35);
        c_cairo.cairo_set_line_width(cr, 1.0);
        c_cairo.cairo_stroke(cr);

        roundedRect(cr, right_x, panels_top, panel_w, panel_h, @min(10.0 * scale_f, panel_h * 0.1));
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.15);
        c_cairo.cairo_fill_preserve(cr);
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.35);
        c_cairo.cairo_set_line_width(cr, 1.0);
        c_cairo.cairo_stroke(cr);

        // Left panel: surf.
        var surf_y = panels_top + title_size + 8.0 * scale_f;
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
        c_cairo.cairo_set_font_size(cr, title_size);
        c_cairo.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c_cairo.CAIRO_FONT_SLANT_NORMAL, c_cairo.CAIRO_FONT_WEIGHT_BOLD);
        const surf_title = "SURF";
        var surf_title_ext: c_cairo.cairo_text_extents_t = undefined;
        c_cairo.cairo_text_extents(cr, surf_title, &surf_title_ext);
        c_cairo.cairo_move_to(cr, left_x + (panel_w - surf_title_ext.width) * 0.5, surf_y);
        c_cairo.cairo_show_text(cr, surf_title);
        surf_y += body_size * 1.7;

        c_cairo.cairo_set_font_size(cr, body_size);
        c_cairo.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c_cairo.CAIRO_FONT_SLANT_NORMAL, c_cairo.CAIRO_FONT_WEIGHT_NORMAL);

        const have_marine = state_.wave_height > 0.001 or state_.swell_height > 0.001;
        if (have_marine) {
            var surf_buf: [128:0]u8 = undefined;
            @memset(&surf_buf, 0);
            const wave_str = std.fmt.bufPrintZ(&surf_buf, "Wave {d:.1}m", .{state_.wave_height}) catch "Wave --";
            drawCardLine(cr, wave_str, left_x + 10.0 * scale_f, surf_y, panel_w - 20.0 * scale_f, gold);
            surf_y += body_size * 1.5;

            @memset(&surf_buf, 0);
            const swell_str = std.fmt.bufPrintZ(&surf_buf, "Swell {d:.1}m @ {d}°", .{ state_.swell_height, state_.swell_dir }) catch "Swell --";
            drawCardLine(cr, swell_str, left_x + 10.0 * scale_f, surf_y, panel_w - 20.0 * scale_f, gold);
            surf_y += body_size * 1.5;

            @memset(&surf_buf, 0);
            const period_str = std.fmt.bufPrintZ(&surf_buf, "Period {d:.1}s", .{state_.swell_period}) catch "Period --";
            drawCardLine(cr, period_str, left_x + 10.0 * scale_f, surf_y, panel_w - 20.0 * scale_f, gold);
        } else {
            c_cairo.cairo_set_font_size(cr, title_size * 0.9);
            const quip = self.card.nextNoSurfQuip();
            var quip_ext: c_cairo.cairo_text_extents_t = undefined;
            c_cairo.cairo_text_extents(cr, @ptrCast(quip.ptr), &quip_ext);
            var quip_title_size = title_size;
            while (quip_ext.width > panel_w - 14.0 * scale_f and quip_title_size > 7.0) {
                quip_title_size *= 0.92;
                c_cairo.cairo_set_font_size(cr, quip_title_size * 0.9);
                c_cairo.cairo_text_extents(cr, @ptrCast(quip.ptr), &quip_ext);
            }
            c_cairo.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
            c_cairo.cairo_move_to(cr, left_x + (panel_w - quip_ext.width) * 0.5, panels_top + panel_h * 0.5 + quip_ext.height * 0.35);
            c_cairo.cairo_show_text(cr, @ptrCast(quip.ptr));
        }
        // Always show wind under surf.
        surf_y = @max(surf_y, panels_top + panel_h - body_size * 1.6);
        var wind_buf: [64:0]u8 = undefined;
        @memset(&wind_buf, 0);
        const wind_str = std.fmt.bufPrintZ(&wind_buf, "Wind {d:.1} km/h @ {d}°", .{ state_.wind_speed, state_.wind_dir }) catch "Wind --";
        drawCardLine(cr, wind_str, left_x + 10.0 * scale_f, surf_y, panel_w - 20.0 * scale_f, gold);

        // Right panel: weather.
        var wx_y = panels_top + title_size + 8.0 * scale_f;
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
        c_cairo.cairo_set_font_size(cr, title_size);
        c_cairo.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c_cairo.CAIRO_FONT_SLANT_NORMAL, c_cairo.CAIRO_FONT_WEIGHT_BOLD);
        const wx_title = "WEATHER";
        var wx_title_ext: c_cairo.cairo_text_extents_t = undefined;
        c_cairo.cairo_text_extents(cr, wx_title, &wx_title_ext);
        c_cairo.cairo_move_to(cr, right_x + (panel_w - wx_title_ext.width) * 0.5, wx_y);
        c_cairo.cairo_show_text(cr, wx_title);
        wx_y += title_size * 1.6;

        var current_buf: [16:0]u8 = undefined;
        @memset(&current_buf, 0);
        const current_str = std.fmt.bufPrintZ(&current_buf, "{d:.0}°", .{state_.current_temp}) catch "--°";
        var big_size = title_size * 2.2;
        c_cairo.cairo_set_font_size(cr, big_size);
        c_cairo.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c_cairo.CAIRO_FONT_SLANT_NORMAL, c_cairo.CAIRO_FONT_WEIGHT_BOLD);
        var current_ext: c_cairo.cairo_text_extents_t = undefined;
        c_cairo.cairo_text_extents(cr, current_str, &current_ext);
        while (current_ext.width > panel_w - 14.0 * scale_f and big_size > 10.0) {
            big_size *= 0.92;
            c_cairo.cairo_set_font_size(cr, big_size);
            c_cairo.cairo_text_extents(cr, current_str, &current_ext);
        }
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
        c_cairo.cairo_move_to(cr, right_x + (panel_w - current_ext.width) * 0.5, wx_y + current_ext.height);
        c_cairo.cairo_show_text(cr, current_str);
        wx_y += current_ext.height + body_size * 0.9;

        c_cairo.cairo_set_font_size(cr, body_size);
        c_cairo.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c_cairo.CAIRO_FONT_SLANT_NORMAL, c_cairo.CAIRO_FONT_WEIGHT_NORMAL);
        var minmax_buf: [40:0]u8 = undefined;
        @memset(&minmax_buf, 0);
        const minmax_str = std.fmt.bufPrintZ(&minmax_buf, "{d:.0}° / {d:.0}°", .{ state_.temp_min, state_.temp_max }) catch "-- / --";
        drawCardLine(cr, minmax_str, right_x + 10.0 * scale_f, wx_y, panel_w - 20.0 * scale_f, muted);
        wx_y += body_size * 1.5;

        const condition_text = weatherCodeText(state_.weather_code);
        drawCardLine(cr, condition_text, right_x + 10.0 * scale_f, wx_y, panel_w - 20.0 * scale_f, muted);
        wx_y += body_size * 1.8;

        // Small condition icon centered in right panel.
        const icon_r = @min(panel_w * 0.22, (panels_bottom - wx_y - 4.0 * scale_f) * 0.35);
        if (icon_r >= 8.0 * scale_f) {
            renderConditionIcon(cr, right_x + panel_w * 0.5, wx_y + icon_r + 2.0 * scale_f, icon_r, state_.weather_code, state_.is_day != 0, state_.wind_speed, gold);
        }

        // Timeline scrubber placeholder below panels.
        const tl_y = panels_bottom + 12.0 * scale_f;
        const tl_h = 6.0 * scale_f;
        const tl_x = pad_x;
        const tl_w = content_w;
        roundedRect(cr, tl_x, tl_y, tl_w, tl_h, tl_h * 0.5);
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.18);
        c_cairo.cairo_fill_preserve(cr);
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.45);
        c_cairo.cairo_set_line_width(cr, 1.0);
        c_cairo.cairo_stroke(cr);

        const knob_r = 8.0 * scale_f;
        const hours = @max(1, self.card.timeline_hours);
        const t = @as(f64, @floatFromInt(@min(self.card.selected_hour, hours - 1))) / @as(f64, @floatFromInt(hours - 1));
        const knob_x = tl_x + tl_h * 0.5 + (tl_w - tl_h) * t;
        const knob_y = tl_y + tl_h * 0.5;
        c_cairo.cairo_new_path(cr);
        c_cairo.cairo_arc(cr, knob_x, knob_y, knob_r, 0, 2.0 * std.math.pi);
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
        c_cairo.cairo_fill_preserve(cr);
        c_cairo.cairo_set_source_rgba(cr, bg[0], bg[1], bg[2], bg[3]);
        c_cairo.cairo_set_line_width(cr, 1.5);
        c_cairo.cairo_stroke(cr);

        // Hour labels.
        c_cairo.cairo_set_font_size(cr, tiny_size);
        c_cairo.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c_cairo.CAIRO_FONT_SLANT_NORMAL, c_cairo.CAIRO_FONT_WEIGHT_NORMAL);
        c_cairo.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
        const start_label = "-24h";
        const end_label = "now";
        var lab_ext: c_cairo.cairo_text_extents_t = undefined;
        c_cairo.cairo_text_extents(cr, start_label, &lab_ext);
        c_cairo.cairo_move_to(cr, tl_x, tl_y + tl_h + tiny_size * 1.2);
        c_cairo.cairo_show_text(cr, start_label);
        c_cairo.cairo_text_extents(cr, end_label, &lab_ext);
        c_cairo.cairo_move_to(cr, tl_x + tl_w - lab_ext.width, tl_y + tl_h + tiny_size * 1.2);
        c_cairo.cairo_show_text(cr, end_label);
    }

    fn renderConditionIcon(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, code: i32, is_day: bool, wind_speed: f64, gold: [4]f64) void {
        c_cairo.cairo_set_line_cap(cr, c_cairo.CAIRO_LINE_CAP_ROUND);
        c_cairo.cairo_set_line_join(cr, c_cairo.CAIRO_LINE_JOIN_ROUND);
        c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);

        const wind_level: u2 = if (wind_speed >= 40.0) 2 else if (wind_speed >= 20.0) 1 else 0;
        const lean: f64 = if (wind_level > 0) 0.05 else 0.0;

        c_cairo.cairo_save(cr);
        if (lean != 0.0) {
            c_cairo.cairo_translate(cr, cx, cy);
            c_cairo.cairo_rotate(cr, lean);
            c_cairo.cairo_translate(cr, -cx, -cy);
        }

        switch (code) {
            0 => if (is_day) drawSun(cr, cx, cy, r, gold) else drawClearNight(cr, cx, cy, r, gold),
            1 => if (is_day) drawMostlyClearDay(cr, cx, cy, r, gold) else drawMostlyClearNight(cr, cx, cy, r, gold),
            2 => drawPartlyCloudy(cr, cx, cy, r, gold),
            3 => drawOvercast(cr, cx, cy, r, gold),
            45, 48 => drawFog(cr, cx, cy, r, gold),
            51, 53, 55 => drawDrizzle(cr, cx, cy, r, gold),
            56, 57 => drawFreezingDrizzle(cr, cx, cy, r, gold),
            61, 63, 65 => drawRain(cr, cx, cy, r, gold),
            66, 67 => drawFreezingRain(cr, cx, cy, r, gold),
            71, 73, 75, 77, 85, 86 => drawSnow(cr, cx, cy, r, gold),
            80, 81, 82 => drawHeavyRain(cr, cx, cy, r, gold),
            95, 96, 97, 99 => drawThunderstorm(cr, cx, cy, r, gold),
            else => drawOvercast(cr, cx, cy, r, gold),
        }

        c_cairo.cairo_restore(cr);
        drawWindStreaks(cr, cx, cy, r, wind_level, gold);
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
            self.cached_state.is_day = jsonI32(current.object.get("is_day"));
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

fn setStroke(cr: *c_cairo.cairo_t, gold: [4]f64, width: f64, alpha: f64) void {
    c_cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3] * alpha);
    c_cairo.cairo_set_line_width(cr, width);
}

fn drawCardLine(cr: *c_cairo.cairo_t, txt: []const u8, x: f64, y: f64, max_w: f64, color: [4]f64) void {
    c_cairo.cairo_set_source_rgba(cr, color[0], color[1], color[2], color[3]);
    var ext: c_cairo.cairo_text_extents_t = undefined;
    c_cairo.cairo_text_extents(cr, @ptrCast(txt.ptr), &ext);
    // No reliable font-size getter in the generated bindings; scale down from a reasonable base.
    var cur: f64 = 12.0;
    while (ext.width > max_w and cur > 6.0) {
        cur *= 0.92;
        c_cairo.cairo_set_font_size(cr, cur);
        c_cairo.cairo_text_extents(cr, @ptrCast(txt.ptr), &ext);
    }
    c_cairo.cairo_move_to(cr, x, y);
    c_cairo.cairo_show_text(cr, @ptrCast(txt.ptr));
}

fn weatherCodeText(code: i32) [:0]const u8 {
    return switch (code) {
        0 => "Clear sky",
        1 => "Mostly clear",
        2 => "Partly cloudy",
        3 => "Overcast",
        45, 48 => "Fog",
        51, 53, 55 => "Drizzle",
        56, 57 => "Freezing drizzle",
        61, 63, 65 => "Rain",
        66, 67 => "Freezing rain",
        71, 73, 75, 77, 85, 86 => "Snow",
        80, 81, 82 => "Heavy rain",
        95, 96, 97, 99 => "Thunderstorm",
        else => "Overcast",
    };
}

fn roundedRect(cr: *c_cairo.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
    const radius = @min(r, w / 2.0, h / 2.0);
    if (radius <= 0.0) {
        c_cairo.cairo_rectangle(cr, x, y, w, h);
        return;
    }
    c_cairo.cairo_new_sub_path(cr);
    c.cairo_arc(cr, x + w - radius, y + radius, radius, -std.math.pi / 2.0, 0);
    c.cairo_arc(cr, x + w - radius, y + h - radius, radius, 0, std.math.pi / 2.0);
    c.cairo_arc(cr, x + radius, y + h - radius, radius, std.math.pi / 2.0, std.math.pi);
    c.cairo_arc(cr, x + radius, y + radius, radius, std.math.pi, -std.math.pi / 2.0);
    c.cairo_close_path(cr);
}

fn cloudPath(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64) void {
    c_cairo.cairo_new_path(cr);
    const steps: usize = 56;
    const lobes: f64 = 7.0;
    const base_r: f64 = 0.68 * r;
    const amp: f64 = 0.14 * r;
    var i: usize = 0;
    while (i <= steps) : (i += 1) {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
        const a = t * 2.0 * std.math.pi;
        const rr = base_r + amp * std.math.cos(lobes * a);
        const px = cx + rr * std.math.cos(a);
        const py = cy + rr * std.math.sin(a);
        if (i == 0) {
            c_cairo.cairo_move_to(cr, px, py);
        } else {
            c_cairo.cairo_line_to(cr, px, py);
        }
    }
    c_cairo.cairo_close_path(cr);
}

fn drawCloudAt(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    cloudPath(cr, cx, cy, r);
    setStroke(cr, gold, 1.2, 1.0);
    c_cairo.cairo_stroke(cr);
}

fn sunRays(cr: *c_cairo.cairo_t, cx: f64, cy: f64, inner: f64, outer: f64, count: usize, start_angle: f64) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const a = start_angle + @as(f64, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f64, @floatFromInt(count));
        const ca = std.math.cos(a);
        const sa = std.math.sin(a);
        c_cairo.cairo_new_path(cr);
        c_cairo.cairo_move_to(cr, cx + ca * inner, cy + sa * inner);
        c_cairo.cairo_line_to(cr, cx + ca * outer, cy + sa * outer);
        c_cairo.cairo_stroke(cr);
    }
}

fn drawSun(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    setStroke(cr, gold, 1.2, 1.0);
    c_cairo.cairo_new_path(cr);
    c_cairo.cairo_arc(cr, cx, cy, r * 0.30, 0, 2 * std.math.pi);
    c_cairo.cairo_stroke(cr);
    sunRays(cr, cx, cy, r * 0.38, r * 0.72, 12, 0);
}

fn drawStar4(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    setStroke(cr, gold, 1.3, 1.0);
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const a = std.math.pi / 4.0 + @as(f64, @floatFromInt(i)) * std.math.pi / 2.0;
        const ca = std.math.cos(a);
        const sa = std.math.sin(a);
        c_cairo.cairo_new_path(cr);
        c_cairo.cairo_move_to(cr, cx - ca * r * 0.55, cy - sa * r * 0.55);
        c_cairo.cairo_line_to(cr, cx + ca * r * 0.55, cy + sa * r * 0.55);
        c_cairo.cairo_stroke(cr);
    }
    i = 0;
    while (i < 4) : (i += 1) {
        const a = @as(f64, @floatFromInt(i)) * std.math.pi / 2.0;
        const ca = std.math.cos(a);
        const sa = std.math.sin(a);
        c_cairo.cairo_new_path(cr);
        c_cairo.cairo_move_to(cr, cx - ca * r * 0.18, cy - sa * r * 0.18);
        c_cairo.cairo_line_to(cr, cx + ca * r * 0.18, cy + sa * r * 0.18);
        c_cairo.cairo_stroke(cr);
    }
}

fn drawSparkle(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    setStroke(cr, gold, 1.0, 1.0);
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const a = @as(f64, @floatFromInt(i)) * std.math.pi / 4.0;
        const ca = std.math.cos(a);
        const sa = std.math.sin(a);
        c_cairo.cairo_new_path(cr);
        c_cairo.cairo_move_to(cr, cx - ca * r, cy - sa * r);
        c_cairo.cairo_line_to(cr, cx + ca * r, cy + sa * r);
        c_cairo.cairo_stroke(cr);
    }
}

fn drawAsterisk(cr: *c_cairo.cairo_t, cx: f64, cy: f64, len: f64, gold: [4]f64) void {
    setStroke(cr, gold, 1.0, 1.0);
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const a = @as(f64, @floatFromInt(i)) * std.math.pi / 3.0;
        const ca = std.math.cos(a);
        const sa = std.math.sin(a);
        c_cairo.cairo_new_path(cr);
        c_cairo.cairo_move_to(cr, cx - ca * len, cy - sa * len);
        c_cairo.cairo_line_to(cr, cx + ca * len, cy + sa * len);
        c_cairo.cairo_stroke(cr);
    }
}

fn drawClearNight(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    drawStar4(cr, cx, cy, r, gold);
    drawSparkle(cr, cx + r * 0.55, cy - r * 0.18, r * 0.09, gold);
    drawSparkle(cr, cx + r * 0.76, cy + r * 0.06, r * 0.06, gold);
    drawSparkle(cr, cx + r * 0.90, cy + r * 0.30, r * 0.04, gold);
}

fn drawMostlyClearDay(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    drawSun(cr, cx - r * 0.20, cy - r * 0.18, r * 0.42, gold);
    cloudPath(cr, cx + r * 0.22, cy + r * 0.22, r * 0.34);
    setStroke(cr, gold, 1.1, 1.0);
    c_cairo.cairo_stroke(cr);
}

fn drawMostlyClearNight(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    drawStar4(cr, cx - r * 0.10, cy - r * 0.10, r * 0.40, gold);
    drawSparkle(cr, cx + r * 0.50, cy - r * 0.12, r * 0.07, gold);
    drawSparkle(cr, cx + r * 0.72, cy + r * 0.16, r * 0.04, gold);
    cloudPath(cr, cx + r * 0.24, cy + r * 0.24, r * 0.32);
    setStroke(cr, gold, 1.0, 1.0);
    c_cairo.cairo_stroke(cr);
}

fn drawPartlyCloudy(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    drawSun(cr, cx - r * 0.30, cy - r * 0.32, r * 0.44, gold);
    drawCloudAt(cr, cx + r * 0.04, cy + r * 0.06, r * 0.82, gold);
}

fn drawOvercast(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    drawCloudAt(cr, cx, cy, r * 0.85, gold);
}

fn drawFog(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    drawCloudAt(cr, cx, cy - r * 0.18, r * 0.70, gold);
    setStroke(cr, gold, 1.0, 1.0);
    const y_base = cy + r * 0.22;
    const spread = r * 0.90;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const y = y_base + @as(f64, @floatFromInt(i)) * 0.18 * r;
        const w = spread * (1.0 - @as(f64, @floatFromInt(i)) * 0.10);
        c_cairo.cairo_new_path(cr);
        c_cairo.cairo_move_to(cr, cx - w * 0.5, y);
        c_cairo.cairo_line_to(cr, cx + w * 0.5, y);
        c_cairo.cairo_stroke(cr);
    }
}

fn precipLines(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, count: usize, length: f64, angle: f64, width: f64, flake_end: bool, gold: [4]f64) void {
    setStroke(cr, gold, width, 1.0);
    const spread = r * 0.70;
    const y = cy + r * 0.08;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const t = if (count > 1) @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(count - 1)) else 0.5;
        const x = cx - spread * 0.5 + t * spread;
        const dx = length * std.math.sin(angle);
        const dy = length * std.math.cos(angle);
        const x0 = x - dx * 0.5;
        const y0 = y - dy * 0.5;
        const x1 = x + dx * 0.5;
        const y1 = y + dy * 0.5;
        c_cairo.cairo_new_path(cr);
        c_cairo.cairo_move_to(cr, x0, y0);
        c_cairo.cairo_line_to(cr, x1, y1);
        c_cairo.cairo_stroke(cr);
        if (flake_end) {
            drawSparkle(cr, x1, y1, r * 0.045, gold);
        }
    }
}

fn drawDrizzle(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    drawCloudAt(cr, cx, cy - r * 0.16, r * 0.66, gold);
    precipLines(cr, cx, cy + r * 0.04, r, 3, r * 0.30, 0.18, 1.0, false, gold);
}

fn drawFreezingDrizzle(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    drawCloudAt(cr, cx, cy - r * 0.16, r * 0.66, gold);
    precipLines(cr, cx, cy + r * 0.04, r, 3, r * 0.28, 0.25, 1.0, true, gold);
}

fn drawRain(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    drawCloudAt(cr, cx, cy - r * 0.16, r * 0.70, gold);
    precipLines(cr, cx, cy + r * 0.04, r, 4, r * 0.42, 0.45, 1.0, false, gold);
}

fn drawFreezingRain(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    drawCloudAt(cr, cx, cy - r * 0.16, r * 0.70, gold);
    precipLines(cr, cx, cy + r * 0.04, r, 4, r * 0.44, 0.40, 1.0, true, gold);
}

fn drawHeavyRain(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    drawCloudAt(cr, cx, cy - r * 0.14, r * 0.72, gold);
    precipLines(cr, cx, cy + r * 0.06, r, 5, r * 0.52, 0.40, 1.2, false, gold);
}

fn drawSnow(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    drawCloudAt(cr, cx, cy - r * 0.16, r * 0.70, gold);
    drawAsterisk(cr, cx - r * 0.22, cy + r * 0.32, r * 0.10, gold);
    drawAsterisk(cr, cx + r * 0.02, cy + r * 0.42, r * 0.09, gold);
    drawAsterisk(cr, cx + r * 0.24, cy + r * 0.30, r * 0.10, gold);
}

fn drawThunderstorm(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, gold: [4]f64) void {
    drawCloudAt(cr, cx, cy - r * 0.16, r * 0.68, gold);
    setStroke(cr, gold, 1.5, 1.0);
    const xs = [_]f64{ cx - 0.10 * r, cx + 0.10 * r, cx + 0.00 * r, cx + 0.18 * r, cx - 0.05 * r, cx + 0.14 * r };
    const ys = [_]f64{ cy + 0.20 * r, cy + 0.36 * r, cy + 0.36 * r, cy + 0.56 * r, cy + 0.56 * r, cy + 0.82 * r };
    c_cairo.cairo_new_path(cr);
    c_cairo.cairo_move_to(cr, xs[0], ys[0]);
    var i: usize = 1;
    while (i < xs.len) : (i += 1) {
        c_cairo.cairo_line_to(cr, xs[i], ys[i]);
    }
    c_cairo.cairo_stroke(cr);
}

fn drawWindStreaks(cr: *c_cairo.cairo_t, cx: f64, cy: f64, r: f64, level: u2, gold: [4]f64) void {
    if (level == 0) return;
    if (level == 1) {
        setStroke(cr, gold, 1.0, 0.9);
        const y0 = cy - 0.12 * r;
        const y1 = cy + 0.20 * r;
        c_cairo.cairo_new_path(cr);
        c_cairo.cairo_move_to(cr, cx + 0.55 * r, y0);
        c_cairo.cairo_line_to(cr, cx + 0.85 * r, y0 - 0.05 * r);
        c_cairo.cairo_line_to(cr, cx + 1.05 * r, y0 + 0.03 * r);
        c_cairo.cairo_stroke(cr);
        c_cairo.cairo_new_path(cr);
        c_cairo.cairo_move_to(cr, cx + 0.55 * r, y1);
        c_cairo.cairo_line_to(cr, cx + 0.85 * r, y1 + 0.05 * r);
        c_cairo.cairo_line_to(cr, cx + 1.05 * r, y1 - 0.03 * r);
        c_cairo.cairo_stroke(cr);
    } else {
        setStroke(cr, gold, 1.1, 0.95);
        const starts = [_]f64{ cy - 0.25 * r, cy - 0.06 * r, cy + 0.12 * r, cy + 0.30 * r };
        const ends = [_]f64{ cy - 0.34 * r, cy - 0.08 * r, cy + 0.18 * r, cy + 0.44 * r };
        var i: usize = 0;
        while (i < starts.len) : (i += 1) {
            c_cairo.cairo_new_path(cr);
            c_cairo.cairo_move_to(cr, cx + 0.55 * r, starts[i]);
            c_cairo.cairo_line_to(cr, cx + 1.00 * r, ends[i]);
            c_cairo.cairo_stroke(cr);
        }
    }
}
