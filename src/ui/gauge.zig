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
        self.renderRamAmpoule(cr, w_d, h_d, s, focused, unfocused, burnt_orange);
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

    fn renderRamAmpoule(self: *GaugeWidget, cr: *c.cairo_t, w_d: f64, h_d: f64, s: f64, focused: [4]f64, unfocused: [4]f64, burnt_orange: [4]f64) void {
        _ = self;
        _ = h_d;
        const value = sampleMetric(.ram_usage) catch 0.45;
        const warn_level = warnLevel(value);
        const fg = if (warn_level >= 1) burnt_orange else focused;
        const fill_color = if (warn_level >= 3) burnt_orange else unfocused;

        const cx = w_d * 0.5;
        const cy = 220.0 * s;
        const radius = 38.0 * s;
        const neck_w = 16.0 * s;
        const neck_h = 18.0 * s;

        c.cairo_save(cr);

        // Build ampoule path: round bottom + straight neck.
        c.cairo_move_to(cr, cx - neck_w * 0.5, cy - radius);
        c.cairo_line_to(cr, cx - neck_w * 0.5, cy);
        c.cairo_arc(cr, cx, cy, radius, std.math.pi, 0);
        c.cairo_line_to(cr, cx + neck_w * 0.5, cy - radius);
        c.cairo_close_path(cr);

        // Empty vessel with 5% tint.
        c.cairo_set_source_rgba(cr, unfocused[0], unfocused[1], unfocused[2], 0.05);
        c.cairo_fill_preserve(cr);

        // Liquid fill in bottom half of ampoule.
        c.cairo_save(cr);
        c.cairo_clip(cr);
        const fill_h = radius * 2.0 * value;
        c.cairo_rectangle(cr, cx - radius, cy + radius - fill_h, radius * 2.0, fill_h);
        c.cairo_set_source_rgba(cr, fill_color[0], fill_color[1], fill_color[2], 0.55);
        c.cairo_fill(cr);
        c.cairo_restore(cr);

        // Outline.
        c.cairo_set_source_rgba(cr, unfocused[0], unfocused[1], unfocused[2], 0.85);
        c.cairo_set_line_width(cr, 3.0 * s);
        c.cairo_stroke(cr);

        // Label.
        c.cairo_set_source_rgba(cr, fg[0], fg[1], fg[2], fg[3]);
        c.cairo_set_font_size(cr, 14.0 * s);
        const label = "RAM";
        var ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, @ptrCast(label), &ext);
        c.cairo_move_to(cr, cx - ext.width * 0.5, cy + radius + neck_h + 18.0 * s);
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
