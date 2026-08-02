const std = @import("std");
const c = @import("dm").c;
const style = @import("../core/style.zig");
const gauge_data = @import("../core/gauge_data.zig");

pub const DrivesWidget = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DrivesWidget {
        return .{ .allocator = allocator };
    }

    pub fn deinit(_: *DrivesWidget) void {}

    pub const PeekBox = struct { x: i32, y: i32, width: i32, height: i32 };

    pub fn renderPeek(self: *DrivesWidget, cr: *c.cairo_t, box: PeekBox, style_: style.Style, scale: f32) void {
        const w_d: f64 = @floatFromInt(box.width);
        const h_d: f64 = @floatFromInt(box.height);
        if (w_d < 8.0 or h_d < 8.0) return;

        const focused = style_.color_border_focused.toF64();
        const unfocused = style_.color_border.toF64();
        const burnt_orange = [4]f64{ 0.85, 0.42, 0.10, 1.0 };

        const s = @as(f64, scale);
        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);

        self.renderChestGauges(cr, w_d, s, focused, unfocused, burnt_orange);
    }

    fn renderChestGauges(self: *DrivesWidget, cr: *c.cairo_t, w_d: f64, s: f64, focused: [4]f64, unfocused: [4]f64, burnt_orange: [4]f64) void {
        _ = self;
        const metrics = [_]gauge_data.Metric{ .disk1_size, .disk2_size };
        const labels = [_][]const u8{ "d1", "d2" };

        const chest_w: f64 = 48.6 * s;
        const chest_h: f64 = 34.2 * s;
        const lid_h: f64 = 10.8 * s;
        const gap: f64 = 67.0 * s;

        var i: usize = 0;
        while (i < metrics.len) : (i += 1) {
            const top_y = 473.0 * s + @as(f64, @floatFromInt(i)) * (chest_h + gap);
            const value = sampleMetric(metrics[i]) catch 0.30 + 0.15 * @as(f64, @floatFromInt(i));
            const warn_level = warnLevel(value);
            const fg = if (warn_level >= 1) burnt_orange else focused;
            const fill_color = if (warn_level >= 3) burnt_orange else unfocused;
            const outline_color = if (warn_level >= 2) burnt_orange else unfocused;

            const cx = w_d * 0.5;
            const cy = top_y + chest_h * 0.5;
            const left = cx - chest_w * 0.5;
            const right = cx + chest_w * 0.5;
            const bottom_y = cy + chest_h * 0.5;
            const top = cy - chest_h * 0.5;

            c.cairo_save(cr);

            // Empty chest body.
            c.cairo_move_to(cr, left, top + lid_h);
            c.cairo_line_to(cr, right, top + lid_h);
            c.cairo_line_to(cr, right, bottom_y);
            c.cairo_line_to(cr, left, bottom_y);
            c.cairo_close_path(cr);
            c.cairo_set_source_rgba(cr, unfocused[0], unfocused[1], unfocused[2], 0.10);
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], 0.75);
            c.cairo_set_line_width(cr, 3.0 * s);
            c.cairo_stroke(cr);

            // Thin top edge where lid meets body.
            c.cairo_move_to(cr, left + 1.0 * s, top + lid_h);
            c.cairo_line_to(cr, right - 1.0 * s, top + lid_h);
            c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], 0.75);
            c.cairo_set_line_width(cr, 1.5 * s);
            c.cairo_stroke(cr);

            // Liquid fill inside chest.
            const fill_h = (chest_h - lid_h) * value;
            if (fill_h > 0) {
                c.cairo_save(cr);
                c.cairo_move_to(cr, left + 1.0 * s, top + lid_h);
                c.cairo_line_to(cr, right - 1.0 * s, top + lid_h);
                c.cairo_line_to(cr, right - 1.0 * s, bottom_y);
                c.cairo_line_to(cr, left + 1.0 * s, bottom_y);
                c.cairo_close_path(cr);
                c.cairo_clip(cr);
                c.cairo_rectangle(cr, left, bottom_y - fill_h, chest_w, fill_h);
                c.cairo_set_source_rgba(cr, fill_color[0], fill_color[1], fill_color[2], 0.55);
                c.cairo_fill(cr);
                c.cairo_restore(cr);
            }

            // Lid curve.
            c.cairo_move_to(cr, left, top + lid_h);
            c.cairo_curve_to(cr, left + chest_w * 0.25, top - lid_h * 0.3,
                                  right - chest_w * 0.25, top - lid_h * 0.3,
                                  right, top + lid_h);
            c.cairo_set_source_rgba(cr, unfocused[0], unfocused[1], unfocused[2], 0.08);
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], 0.75);
            c.cairo_set_line_width(cr, 3.0 * s);
            c.cairo_stroke(cr);

            // Lock plate with thicker border.
            c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], 0.75);
            c.cairo_set_line_width(cr, 3.0 * s);
            c.cairo_arc(cr, cx, top + lid_h, 3.5 * s, 0, 2.0 * std.math.pi);
            c.cairo_stroke(cr);

            // Label inside chest, at bottom.
            c.cairo_set_source_rgba(cr, fg[0], fg[1], fg[2], fg[3]);
            c.cairo_set_font_size(cr, 11.0 * s);
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, @ptrCast(labels[i]), &ext);
            const label_x = cx - ext.width * 0.5;
            const label_y = bottom_y - 4.0 * s;

            // Clear a small zone behind the label so it stands out.
            c.cairo_set_source_rgba(cr, unfocused[0], unfocused[1], unfocused[2], 0.12);
            c.cairo_rectangle(cr, label_x - 2.0 * s, label_y - ext.height - 2.0 * s, ext.width + 4.0 * s, ext.height + 4.0 * s);
            c.cairo_fill(cr);

            // Draw label.
            c.cairo_move_to(cr, label_x, label_y);
            c.cairo_show_text(cr, @ptrCast(labels[i]));

            c.cairo_restore(cr);
        }
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
