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

    // Layout: true = label/value on the right of the tube; false = on the left.
    const label_on_right = true;

    pub fn renderPeek(self: *GaugeWidget, cr: *c.cairo_t, box: PeekBox, style_: style.Style, scale: f32) void {
        const w_d: f64 = @floatFromInt(box.width);
        const h_d: f64 = @floatFromInt(box.height);
        if (w_d < 8.0 or h_d < 8.0) return;

        const data = gauge_data.GaugeData.init(self.allocator);
        const metrics = [_]gauge_data.Metric{ .gpu_temp, .cpu_temp, .ram_usage, .disk1_size, .disk2_size };
        const labels = [_][]const u8{ "GPU", "CPU", "RAM", "D1", "D2" };

        const focused = style_.color_border_focused.toF64();
        const unfocused = style_.color_border.toF64();
        const burnt_orange = [4]f64{ 0.8, 0.35, 0.08, 1.0 };

        const margin: f64 = 4.0 * @as(f64, scale);
        const row_h = h_d / @as(f64, @floatFromInt(metrics.len));

        // Tube geometry.
        const tube_w: f64 = 10.0 * @as(f64, scale);
        const tube_h: f64 = row_h * 0.55;
        const bulb_r: f64 = tube_w * 0.85;
        const stem_w: f64 = tube_w * 0.45;

        // Font setup (used for layout measurement).
        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);

        var i: usize = 0;
        while (i < metrics.len) : (i += 1) {
            var pct_buf: [8]u8 = undefined;
            const y_center = @as(f64, @floatFromInt(i)) * row_h + row_h * 0.5;
            const value = sampleMetric(&data, metrics[i]) catch 0.35 + 0.1 * @as(f64, @floatFromInt(i % 5));

            const warn_level = warnLevel(value);
            const fg = if (warn_level >= 1) burnt_orange else focused;
            const liquid_color = if (warn_level >= 3) burnt_orange else unfocused;
            const outline_color = if (warn_level >= 2) burnt_orange else unfocused;

            const gauge_left: f64 = if (label_on_right)
                margin
            else
                w_d - margin - tube_w;
            const tube_x = gauge_left + tube_w * 0.5;
            const tube_top = y_center - tube_h * 0.5;
            const tube_bottom = y_center + tube_h * 0.5;

            // Draw glass tube outline.
            c.cairo_save(cr);
            c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], outline_color[3]);
            c.cairo_set_line_width(cr, 1.0 * @as(f64, scale));

            // Stem.
            c.cairo_move_to(cr, tube_x - stem_w * 0.5, tube_top);
            c.cairo_line_to(cr, tube_x - stem_w * 0.5, tube_bottom - bulb_r);
            c.cairo_arc(cr, tube_x, tube_bottom - bulb_r, bulb_r, std.math.pi, 0);
            c.cairo_line_to(cr, tube_x + stem_w * 0.5, tube_top);
            c.cairo_close_path(cr);
            c.cairo_stroke(cr);

            // Rounded cap on stem top.
            c.cairo_arc(cr, tube_x, tube_top, stem_w * 0.5, std.math.pi, 0);
            c.cairo_stroke(cr);

            // Liquid fill.
            const fill_h = tube_h * value;
            const fill_top = tube_bottom - fill_h;
            c.cairo_set_source_rgba(cr, liquid_color[0], liquid_color[1], liquid_color[2], liquid_color[3]);
            if (fill_h > bulb_r) {
                // Fill bulb + stem.
                c.cairo_arc(cr, tube_x, tube_bottom - bulb_r, bulb_r * 0.78, std.math.pi, 0);
                c.cairo_rectangle(cr, tube_x - stem_w * 0.38, fill_top, stem_w * 0.76, fill_h - bulb_r);
                c.cairo_fill(cr);
                // Round top of liquid.
                c.cairo_arc(cr, tube_x, fill_top, stem_w * 0.38, 0, std.math.pi);
                c.cairo_fill(cr);
            } else {
                // Fill only part of bulb.
                const angle = std.math.acos((bulb_r - fill_h) / (bulb_r * 0.78));
                c.cairo_arc(cr, tube_x, tube_bottom - bulb_r, bulb_r * 0.78, -angle, angle);
                c.cairo_fill(cr);
            }

            // Subtle highlight on left edge of tube.
            c.cairo_set_source_rgba(cr, fg[0], fg[1], fg[2], 0.25);
            c.cairo_set_line_width(cr, 0.5 * @as(f64, scale));
            c.cairo_move_to(cr, tube_x - stem_w * 0.25, tube_top + stem_w * 0.25);
            c.cairo_line_to(cr, tube_x - stem_w * 0.25, tube_bottom - bulb_r * 1.2);
            c.cairo_stroke(cr);
            c.cairo_restore(cr);

            // Label + value to the right or left of the tube.
            c.cairo_set_source_rgba(cr, fg[0], fg[1], fg[2], fg[3]);
            c.cairo_set_font_size(cr, 9.0 * @as(f64, scale));
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, @ptrCast(labels[i]), &ext);

            const text_x: f64 = if (label_on_right)
                gauge_left + tube_w + margin
            else
                gauge_left - margin - ext.width;
            const label_y = y_center - margin * 0.2;
            c.cairo_move_to(cr, text_x, label_y);
            c.cairo_show_text(cr, @ptrCast(labels[i]));

            const pct_text = formatPercent(value, &pct_buf);
            c.cairo_set_font_size(cr, 7.0 * @as(f64, scale));
            var ext2: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, @ptrCast(pct_text), &ext2);
            const value_x: f64 = if (label_on_right)
                gauge_left + tube_w + margin
            else
                gauge_left - margin - ext2.width;
            const value_y = y_center + ext2.height + margin * 0.2;
            c.cairo_move_to(cr, value_x, value_y);
            c.cairo_show_text(cr, @ptrCast(pct_text));

            // 95%+ flash indicator.
            if (warn_level >= 3 and @mod(@as(i32, @intFromFloat(std.math.floor(value * 100.0))), 2) == 0) {
                c.cairo_set_source_rgba(cr, burnt_orange[0], burnt_orange[1], burnt_orange[2], 0.6);
                c.cairo_arc(cr, tube_x, tube_bottom - bulb_r, bulb_r * 1.3, 0, 2.0 * std.math.pi);
                c.cairo_fill(cr);
            }
        }
    }

    fn warnLevel(value: f64) u32 {
        if (value >= 0.95) return 3;
        if (value >= 0.90) return 2;
        if (value >= 0.85) return 1;
        return 0;
    }

    fn formatPercent(value: f64, buf: []u8) []const u8 {
        const pct: i32 = @intFromFloat(@round(value * 100.0));
        const clamped = @min(pct, 100);
        const res = std.fmt.bufPrint(buf, "{d}%", .{clamped}) catch "100%";
        return res;
    }

    fn sampleMetric(data: *const gauge_data.GaugeData, metric: gauge_data.Metric) !f64 {
        const v = try data.sample(metric);
        return @max(0.0, @min(1.0, v.value));
    }
};
