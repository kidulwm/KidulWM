// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const c_std = @import("c");
const c = @import("dm").c;
const style = @import("../core/style.zig");
const gauge_data = @import("../core/gauge_data.zig");
const gauge_config = @import("../core/gauge_config.zig");

pub const GaugeWidget = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GaugeWidget {
        return .{ .allocator = allocator };
    }

    pub fn deinit(_: *GaugeWidget) void {}

    pub const PeekBox = struct { x: i32, y: i32, width: i32, height: i32 };

    pub fn renderPeek(self: *GaugeWidget, cr: *c.cairo_t, box: PeekBox, style_: style.Style, scale: f32) void {
        const w_d: f64 = @floatFromInt(box.width);
        const h_d: f64 = @floatFromInt(box.height);
        if (w_d < 8.0 or h_d < 8.0) return;

        const focused = style_.color_border_focused.toF64();
        const unfocused = style_.color_border.toF64();
        const burnt_orange = [4]f64{ 0.85, 0.42, 0.10, 1.0 };

        const s = @as(f64, scale);

        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);

        // GPU / CPU mercury gauges at top, hidden when below temperature threshold.
        self.renderMercuryGauges(cr, w_d, h_d, s, focused, unfocused, burnt_orange);
    }

    fn renderMercuryGauges(self: *GaugeWidget, cr: *c.cairo_t, w_d: f64, h_d: f64, s: f64, focused: [4]f64, unfocused: [4]f64, burnt_orange: [4]f64) void {
        _ = self;
        _ = h_d;
        const metrics = [_]gauge_data.Metric{ .gpu_temp, .cpu_temp };
        const labels = [_][]const u8{ "gpu", "cpu" };

        const bar_w: f64 = 12.0 * s;
        const bar_h: f64 = 55.0 * s;
        const bulb_r: f64 = bar_w * 0.85;

        const group_top = 97.0 * s;
        const gauge_gap = 130.0 * s;

        var i: usize = 0;
        while (i < metrics.len) : (i += 1) {
            const visible = metricVisible(metrics[i]) catch false;
            if (!visible) continue;

            const y_center = group_top + @as(f64, @floatFromInt(i)) * gauge_gap;
            const value = sampleMetric(metrics[i]) catch 0.30 + 0.12 * @as(f64, @floatFromInt(i % 5));

            const warn_level = warnLevel(value);
            const fg = if (warn_level >= 1) burnt_orange else focused;
            const fill_color = if (warn_level >= 3) burnt_orange else unfocused;
            const outline_color = if (warn_level >= 2) burnt_orange else unfocused;

            const bar_x = w_d * 0.5;
            const bar_top = y_center - bar_h * 0.5;
            const bar_bottom = y_center + bar_h * 0.5;
            const bulb_center_y = bar_bottom - bulb_r;

            c.cairo_save(cr);

            // 5% tint in empty parts.
            c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], 0.05);
            c.cairo_arc(cr, bar_x, bulb_center_y, bulb_r - 1.5 * s, 0, 2.0 * std.math.pi);
            c.cairo_fill(cr);
            const empty_top = bar_top + bar_w * 0.5;
            c.cairo_rectangle(cr, bar_x - bar_w * 0.5 + 1.5 * s, empty_top, bar_w - 3.0 * s, bulb_center_y - bulb_r - empty_top);
            c.cairo_fill(cr);

            // Liquid fill at 55% alpha.
            c.cairo_set_source_rgba(cr, fill_color[0], fill_color[1], fill_color[2], 0.55);
            const fill_top = bar_bottom - bar_h * value;
            if (fill_top <= bulb_center_y + bulb_r) {
                c.cairo_arc(cr, bar_x, bulb_center_y, bulb_r - 1.5 * s, 0, 2.0 * std.math.pi);
                c.cairo_fill(cr);
            }
            if (bar_bottom - fill_top > bulb_r * 2.0) {
                c.cairo_rectangle(cr, bar_x - bar_w * 0.5 + 2.0 * s, fill_top, bar_w - 4.0 * s, bulb_center_y - fill_top);
                c.cairo_fill(cr);
            }

            // Outline in unfocused border color, 3 px.
            c.cairo_set_source_rgba(cr, unfocused[0], unfocused[1], unfocused[2], 0.85);
            c.cairo_set_line_width(cr, 3.0 * s);

            c.cairo_move_to(cr, bar_x - bar_w * 0.5, bulb_center_y - bulb_r);
            c.cairo_line_to(cr, bar_x - bar_w * 0.5, bar_top + bar_w * 0.5);
            c.cairo_arc(cr, bar_x, bar_top + bar_w * 0.5, bar_w * 0.5, std.math.pi, 0);
            c.cairo_line_to(cr, bar_x + bar_w * 0.5, bulb_center_y - bulb_r);
            c.cairo_arc(cr, bar_x, bulb_center_y, bulb_r, 0, 2.0 * std.math.pi);
            c.cairo_stroke(cr);

            // Label.
            c.cairo_set_source_rgba(cr, fg[0], fg[1], fg[2], fg[3]);
            c.cairo_set_font_size(cr, 14.0 * s);
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, @ptrCast(labels[i]), &ext);
            c.cairo_move_to(cr, bar_x - ext.width * 0.5, bar_bottom + 22.0 * s);
            c.cairo_show_text(cr, @ptrCast(labels[i]));

            c.cairo_restore(cr);
        }
    }

    pub fn renderRamAmpoule(self: *GaugeWidget, cr: *c.cairo_t, box_w: i32, box_h: i32, scale: f32, style_: style.Style) void {
        const w_d: f64 = @floatFromInt(box_w);
        const h_d: f64 = @floatFromInt(box_h);
        const focused = style_.color_border_focused.toF64();
        const unfocused = style_.color_border.toF64();
        const burnt_orange = [4]f64{ 0.85, 0.42, 0.10, 1.0 };
        const s = @as(f64, scale);
        self.renderRamAmpouleInternal(cr, w_d, h_d, s, focused, unfocused, burnt_orange);
    }

    fn renderRamAmpouleInternal(self: *GaugeWidget, cr: *c.cairo_t, w_d: f64, h_d: f64, s: f64, focused: [4]f64, unfocused: [4]f64, burnt_orange: [4]f64) void {
        _ = self;
        const value = sampleMetric(.ram_usage) catch 0.45;
        const warn_level = warnLevel(value);
        const fg = if (warn_level >= 1) burnt_orange else focused;
        const outline_color = if (warn_level >= 2) burnt_orange else unfocused;
        _ = fg;

        const cx = w_d * 0.5;
        const cy = h_d * 0.5;
        const cauldron_scale: f64 = 1.8;
        const body_w: f64 = 52.0 * s * cauldron_scale;
        const body_h: f64 = 38.0 * s * cauldron_scale;
        const rim_w: f64 = 41.0 * s * cauldron_scale;
        const rim_h: f64 = 7.0 * s * cauldron_scale;

        // Cauldron body path: rim, left belly, bottom, right belly.
        const left_rim = [2]f64{ cx - rim_w * 0.5, cy - body_h * 0.5 };
        const right_rim = [2]f64{ cx + rim_w * 0.5, cy - body_h * 0.5 };
        const left_belly = [2]f64{ cx - body_w * 0.5, cy + rim_h };
        const right_belly = [2]f64{ cx + body_w * 0.5, cy + rim_h };
        const bottom = [2]f64{ cx, cy + body_h * 0.5 };

        c.cairo_save(cr);

        // Feet: outlined curved legs with shaded interior and solid ball tips.
        // Left leg.
        c.cairo_move_to(cr, cx - body_w * 0.32, cy + body_h * 0.42);
        c.cairo_curve_to(cr, cx - body_w * 0.36, cy + body_h * 0.45,
                              cx - body_w * 0.40, cy + body_h * 0.48,
                              cx - body_w * 0.42, cy + body_h * 0.50);
        c.cairo_set_source_rgba(cr, unfocused[0], unfocused[1], unfocused[2], 0.10);
        c.cairo_set_line_width(cr, 4.0 * s);
        c.cairo_stroke_preserve(cr);
        c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], 0.75);
        c.cairo_set_line_width(cr, 1.5 * s);
        c.cairo_stroke(cr);

        // Right leg.
        c.cairo_move_to(cr, cx + body_w * 0.32, cy + body_h * 0.42);
        c.cairo_curve_to(cr, cx + body_w * 0.36, cy + body_h * 0.45,
                              cx + body_w * 0.40, cy + body_h * 0.48,
                              cx + body_w * 0.42, cy + body_h * 0.50);
        c.cairo_set_source_rgba(cr, unfocused[0], unfocused[1], unfocused[2], 0.10);
        c.cairo_set_line_width(cr, 4.0 * s);
        c.cairo_stroke_preserve(cr);
        c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], 0.75);
        c.cairo_set_line_width(cr, 1.5 * s);
        c.cairo_stroke(cr);

        // Ball tips.
        c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], 0.75);
        c.cairo_arc(cr, cx - body_w * 0.44, cy + body_h * 0.54, 4.8 * s, 0, 2.0 * std.math.pi);
        c.cairo_fill(cr);
        c.cairo_arc(cr, cx + body_w * 0.44, cy + body_h * 0.54, 4.8 * s, 0, 2.0 * std.math.pi);
        c.cairo_fill(cr);

        // Empty vessel.
        c.cairo_move_to(cr, left_rim[0], left_rim[1]);
        c.cairo_curve_to(cr, left_rim[0] - body_w * 0.12, left_rim[1] + body_h * 0.35,
                              left_belly[0], left_belly[1] - body_h * 0.15,
                              left_belly[0], left_belly[1]);
        c.cairo_curve_to(cr, left_belly[0], bottom[1] - body_h * 0.1,
                              bottom[0] - body_w * 0.15, bottom[1],
                              bottom[0], bottom[1]);
        c.cairo_curve_to(cr, bottom[0] + body_w * 0.15, bottom[1],
                              right_belly[0], bottom[1] - body_h * 0.1,
                              right_belly[0], right_belly[1]);
        c.cairo_curve_to(cr, right_belly[0], right_belly[1] - body_h * 0.15,
                              right_rim[0] + body_w * 0.12, right_rim[1] + body_h * 0.35,
                              right_rim[0], right_rim[1]);
        c.cairo_close_path(cr);
        c.cairo_set_source_rgba(cr, unfocused[0], unfocused[1], unfocused[2], 0.12);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], 0.75);
        c.cairo_set_line_width(cr, 3.0 * s);
        c.cairo_stroke_preserve(cr);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.35);
        c.cairo_set_line_width(cr, 1.0 * s);
        c.cairo_stroke(cr);

        // Side shading to give a rounded 3D look.
        c.cairo_save(cr);
        c.cairo_move_to(cr, left_rim[0], left_rim[1]);
        c.cairo_curve_to(cr, left_rim[0] - body_w * 0.12, left_rim[1] + body_h * 0.35,
                              left_belly[0], left_belly[1] - body_h * 0.15,
                              left_belly[0], left_belly[1]);
        c.cairo_curve_to(cr, left_belly[0], bottom[1] - body_h * 0.1,
                              bottom[0] - body_w * 0.15, bottom[1],
                              bottom[0], bottom[1]);
        c.cairo_curve_to(cr, bottom[0] + body_w * 0.15, bottom[1],
                              right_belly[0], bottom[1] - body_h * 0.1,
                              right_belly[0], right_belly[1]);
        c.cairo_curve_to(cr, right_belly[0], right_belly[1] - body_h * 0.15,
                              right_rim[0] + body_w * 0.12, right_rim[1] + body_h * 0.35,
                              right_rim[0], right_rim[1]);
        c.cairo_close_path(cr);
        c.cairo_clip(cr);

        // Left shadow.
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.18);
        c.cairo_rectangle(cr, left_belly[0] - body_w * 0.05, left_rim[1] - body_h * 0.2, body_w * 0.28, body_h * 1.4);
        c.cairo_fill(cr);

        // Right highlight.
        c.cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.03);
        c.cairo_rectangle(cr, right_belly[0] - body_w * 0.23, left_rim[1] - body_h * 0.2, body_w * 0.28, body_h * 1.4);
        c.cairo_fill(cr);

        // Bottom darker shading.
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.22);
        c.cairo_rectangle(cr, left_belly[0], bottom[1] - body_h * 0.35, right_belly[0] - left_belly[0], body_h * 0.35);
        c.cairo_fill(cr);
        c.cairo_restore(cr);

        // Rim.
        c.cairo_save(cr);
        c.cairo_move_to(cr, left_rim[0], left_rim[1]);
        c.cairo_curve_to(cr, left_rim[0], left_rim[1] - rim_h,
                              right_rim[0], right_rim[1] - rim_h,
                              right_rim[0], right_rim[1]);
        c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], 0.75);
        c.cairo_set_line_width(cr, 3.0 * s);
        c.cairo_stroke_preserve(cr);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.35);
        c.cairo_set_line_width(cr, 1.0 * s);
        c.cairo_stroke(cr);
        c.cairo_restore(cr);

        // Liquid fill clipped to body — bright bubbling turquoise under black glass.
        const fill_h = body_h * value;
        const fill_top = bottom[1] - fill_h;
        c.cairo_save(cr);
        c.cairo_move_to(cr, left_rim[0], left_rim[1]);
        c.cairo_curve_to(cr, left_rim[0] - body_w * 0.12, left_rim[1] + body_h * 0.35,
                              left_belly[0], left_belly[1] - body_h * 0.15,
                              left_belly[0], left_belly[1]);
        c.cairo_curve_to(cr, left_belly[0], bottom[1] - body_h * 0.1,
                              bottom[0] - body_w * 0.15, bottom[1],
                              bottom[0], bottom[1]);
        c.cairo_curve_to(cr, bottom[0] + body_w * 0.15, bottom[1],
                              right_belly[0], bottom[1] - body_h * 0.1,
                              right_belly[0], right_belly[1]);
        c.cairo_curve_to(cr, right_belly[0], right_belly[1] - body_h * 0.15,
                              right_rim[0] + body_w * 0.12, right_rim[1] + body_h * 0.35,
                              right_rim[0], right_rim[1]);
        c.cairo_close_path(cr);
        c.cairo_clip(cr);
        c.cairo_rectangle(cr, left_belly[0], fill_top, right_belly[0] - left_belly[0], fill_h);
        c.cairo_set_source_rgba(cr, 0.10, 0.85, 0.75, 0.55);
        c.cairo_fill(cr);

        // Animated bubbles.
        const t: f64 = @as(f64, @floatFromInt(c_std.time(null))) / 1.0;
        c.cairo_set_source_rgba(cr, 0.45, 1.0, 0.9, 0.65);
        const bubbles = [_][3]f64{
            .{ cx - body_w * 0.18, fill_top - 2.0 * s - std.math.sin(t * 3.0 + 0.0) * 3.0 * s, 1.8 * s },
            .{ cx + body_w * 0.10, fill_top - 6.0 * s - std.math.sin(t * 2.5 + 2.0) * 2.5 * s, 1.2 * s },
            .{ cx + body_w * 0.25, fill_top - 1.0 * s - std.math.sin(t * 4.0 + 4.0) * 3.5 * s, 1.5 * s },
            .{ cx - body_w * 0.05, fill_top - 10.0 * s - std.math.sin(t * 3.5 + 1.5) * 2.0 * s, 1.0 * s },
            .{ cx + body_w * 0.30, fill_top - 4.0 * s - std.math.sin(t * 2.0 + 3.5) * 2.8 * s, 1.3 * s },
        };
        for (bubbles) |b| {
            c.cairo_arc(cr, b[0], b[1], b[2], 0, 2.0 * std.math.pi);
            c.cairo_fill(cr);
        }
        c.cairo_restore(cr);

        // Smoke puffs above the rim.
        const smoke_alpha: f64 = if (value > 0.50) 0.45 else 0.22;
        const puff_base_y = left_rim[1] - rim_h - 3.0 * s;
        const puffs = [_][3]f64{
            .{ cx - rim_w * 0.32, puff_base_y - 6.0 * s, 3.2 * s },
            .{ cx + rim_w * 0.08, puff_base_y - 14.0 * s, 2.6 * s },
            .{ cx + rim_w * 0.38, puff_base_y - 5.0 * s, 2.9 * s },
            .{ cx - rim_w * 0.08, puff_base_y - 20.0 * s, 2.2 * s },
            .{ cx + rim_w * 0.18, puff_base_y - 26.0 * s, 1.8 * s },
        };
        for (puffs) |p| {
            // Outer glow ring.
            c.cairo_set_source_rgba(cr, focused[0], focused[1], focused[2], smoke_alpha * 0.35);
            c.cairo_arc(cr, p[0], p[1], p[2] * 1.6, 0, 2.0 * std.math.pi);
            c.cairo_fill(cr);
            // Solid core puff.
            c.cairo_set_source_rgba(cr, focused[0], focused[1], focused[2], smoke_alpha);
            c.cairo_arc(cr, p[0], p[1], p[2], 0, 2.0 * std.math.pi);
            c.cairo_fill(cr);
        }

        c.cairo_restore(cr);
    }

    fn warnLevel(value: f64) u32 {
        if (value >= 0.95) return 3;
        if (value >= 0.90) return 2;
        if (value >= 0.85) return 1;
        return 0;
    }

    fn sampleMetric(metric: gauge_data.Metric) !f64 {
        var data = gauge_data.GaugeData.init(std.heap.page_allocator);
        const v = try data.sample(metric);
        return @max(0.0, @min(1.0, v.value));
    }

    fn metricVisible(metric: gauge_data.Metric) !bool {
        // Master switch: the temp gauge group stays hidden until the user
        // enables it (set-show-temp / gauges.toml). RAM rejoins the group later.
        const cfg = gauge_config.load(std.heap.page_allocator);
        return switch (metric) {
            .gpu_temp, .cpu_temp => blk: {
                if (!cfg.show_temp) break :blk false;
                const f = try metricFahrenheit(metric);
                break :blk f >= cfg.temp_threshold_f;
            },
            .ram_usage => cfg.show_ram,
            else => true,
        };
    }

    fn metricFahrenheit(metric: gauge_data.Metric) !f64 {
        const celsius = try metricCelsius(metric);
        return celsius * 9.0 / 5.0 + 32.0;
    }

    fn metricCelsius(metric: gauge_data.Metric) !f64 {
        var data = gauge_data.GaugeData.init(std.heap.page_allocator);
        const v = try data.sample(metric);
        return v.raw;
    }
};
