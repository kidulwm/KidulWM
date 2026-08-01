const std = @import("std");
const c = @import("dm").c;
const style = @import("../core/style.zig");
const gauge_data = @import("../core/gauge_data.zig");

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

        // GPU / CPU mercury gauges at top.
        self.renderMercuryGauges(cr, w_d, s, focused, unfocused, burnt_orange);

        // RAM circular ampoule in the middle.
        self.renderRamAmpouleInternal(cr, w_d, h_d, s, focused, unfocused, burnt_orange);
    }

    fn renderMercuryGauges(self: *GaugeWidget, cr: *c.cairo_t, w_d: f64, s: f64, focused: [4]f64, unfocused: [4]f64, burnt_orange: [4]f64) void {
        _ = self;
        const metrics = [_]gauge_data.Metric{ .gpu_temp, .cpu_temp };
        const labels = [_][]const u8{ "GPU", "CPU" };

        const bar_w: f64 = 12.0 * s;
        const bar_h: f64 = 55.0 * s;
        const bulb_r: f64 = bar_w * 0.85;

        const group_top = 50.0 * s;
        const gauge_gap = 104.0 * s;

        var i: usize = 0;
        while (i < metrics.len) : (i += 1) {
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
        _ = h_d;
        const value = sampleMetric(.ram_usage) catch 0.45;
        const warn_level = warnLevel(value);
        const fg = if (warn_level >= 1) burnt_orange else focused;
        const fill_color = if (warn_level >= 3) burnt_orange else unfocused;
        const outline_color = if (warn_level >= 2) burnt_orange else unfocused;

        const cx = w_d * 0.5;
        const cy = 258.0 * s;
        const body_w: f64 = 58.0 * s;
        const body_h: f64 = 42.0 * s;
        const rim_w: f64 = 46.0 * s;
        const rim_h: f64 = 8.0 * s;

        // Cauldron body path: rim, left belly, bottom, right belly.
        const left_rim = [2]f64{ cx - rim_w * 0.5, cy - body_h * 0.5 };
        const right_rim = [2]f64{ cx + rim_w * 0.5, cy - body_h * 0.5 };
        const left_belly = [2]f64{ cx - body_w * 0.5, cy + rim_h };
        const right_belly = [2]f64{ cx + body_w * 0.5, cy + rim_h };
        const bottom = [2]f64{ cx, cy + body_h * 0.5 };

        c.cairo_save(cr);

        // Feet.
        c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], 0.85);
        c.cairo_set_line_width(cr, 2.0 * s);
        c.cairo_move_to(cr, cx - body_w * 0.35, cy + body_h * 0.45);
        c.cairo_line_to(cr, cx - body_w * 0.35, cy + body_h * 0.6);
        c.cairo_stroke(cr);
        c.cairo_move_to(cr, cx + body_w * 0.35, cy + body_h * 0.45);
        c.cairo_line_to(cr, cx + body_w * 0.35, cy + body_h * 0.6);
        c.cairo_stroke(cr);

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
        c.cairo_set_source_rgba(cr, unfocused[0], unfocused[1], unfocused[2], 0.06);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], 0.85);
        c.cairo_set_line_width(cr, 2.5 * s);
        c.cairo_stroke(cr);

        // Rim.
        c.cairo_save(cr);
        c.cairo_move_to(cr, left_rim[0], left_rim[1]);
        c.cairo_curve_to(cr, left_rim[0], left_rim[1] - rim_h,
                              right_rim[0], right_rim[1] - rim_h,
                              right_rim[0], right_rim[1]);
        c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], 0.85);
        c.cairo_set_line_width(cr, 2.5 * s);
        c.cairo_stroke(cr);
        c.cairo_restore(cr);

        // Liquid fill clipped to body.
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
        c.cairo_set_source_rgba(cr, fill_color[0], fill_color[1], fill_color[2], 0.55);
        c.cairo_fill(cr);

        // Bubbles.
        c.cairo_set_source_rgba(cr, focused[0], focused[1], focused[2], 0.5);
        const bubbles = [_][3]f64{
            .{ cx - body_w * 0.18, fill_top - 2.0 * s, 1.8 * s },
            .{ cx + body_w * 0.10, fill_top - 6.0 * s, 1.2 * s },
            .{ cx + body_w * 0.25, fill_top - 1.0 * s, 1.5 * s },
        };
        for (bubbles) |b| {
            c.cairo_arc(cr, b[0], b[1], b[2], 0, 2.0 * std.math.pi);
            c.cairo_fill(cr);
        }
        c.cairo_restore(cr);

        // Smoke puffs above the rim.
        const smoke_alpha: f64 = if (value > 0.50) 0.18 else 0.08;
        const puff_base_y = left_rim[1] - rim_h - 3.0 * s;
        const puffs = [_][3]f64{
            .{ cx - rim_w * 0.22, puff_base_y - 4.0 * s, 2.2 * s },
            .{ cx + rim_w * 0.05, puff_base_y - 9.0 * s, 1.8 * s },
            .{ cx + rim_w * 0.28, puff_base_y - 3.0 * s, 2.0 * s },
            .{ cx - rim_w * 0.05, puff_base_y - 14.0 * s, 1.5 * s },
        };
        c.cairo_set_source_rgba(cr, focused[0], focused[1], focused[2], smoke_alpha);
        for (puffs) |p| {
            c.cairo_arc(cr, p[0], p[1], p[2], 0, 2.0 * std.math.pi);
            c.cairo_fill(cr);
        }

        // Percentage label inside the liquid.
        var percent_buf: [16]u8 = undefined;
        const percent_text = std.fmt.bufPrintZ(&percent_buf, "{d}%", .{@as(u32, @intFromFloat(value * 100.0))}) catch "RAM";
        c.cairo_set_source_rgba(cr, focused[0], focused[1], focused[2], 0.9);
        c.cairo_set_font_size(cr, 11.0 * s);
        var percent_ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, @ptrCast(percent_text), &percent_ext);
        c.cairo_move_to(cr, cx - percent_ext.width * 0.5, cy + body_h * 0.25 + 4.0 * s);
        c.cairo_show_text(cr, @ptrCast(percent_text));

        // Label.
        c.cairo_set_source_rgba(cr, fg[0], fg[1], fg[2], fg[3]);
        c.cairo_set_font_size(cr, 14.0 * s);
        const label = "RAM";
        var ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, @ptrCast(label), &ext);
        c.cairo_move_to(cr, cx - ext.width * 0.5, bottom[1] + 18.0 * s);
        c.cairo_show_text(cr, @ptrCast(label));

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
};
