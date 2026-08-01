const std = @import("std");
const c = @import("dm").c;
const style = @import("../core/style.zig");
const gauge_data = @import("../core/gauge_data.zig");

const wave_sheet_png = @embedFile("assets/gauge_waves_20.png");
const stage_count = 20;
const cols: u32 = 5;
const rows: u32 = 4;
const cell_w: u32 = 100;
const cell_h: u32 = 100;
const pad: u32 = 2;

const PngStream = struct {
    data: []const u8,
    offset: usize = 0,
};

fn readPngStream(closure: *anyopaque, out: [*c]u8, len: c_uint) callconv(.c) c.cairo_status_t {
    const ctx: *PngStream = @ptrCast(@alignCast(closure));
    const l: usize = len;
    const remaining = if (ctx.offset >= ctx.data.len) 0 else ctx.data.len - ctx.offset;
    const copy = @min(remaining, l);
    if (copy > 0) {
        @memcpy(out[0..copy], ctx.data[ctx.offset .. ctx.offset + copy]);
        ctx.offset += copy;
    }
    if (copy < l) {
        @memset(out[copy..l], 0);
    }
    return c.CAIRO_STATUS_SUCCESS;
}

fn loadPngFromBytes(bytes: []const u8) !*c.cairo_surface_t {
    var ctx = PngStream{ .data = bytes };
    const surf = c.cairo_image_surface_create_from_png_stream(
        @ptrCast(&readPngStream),
        @ptrCast(&ctx),
    ) orelse return error.OutOfMemory;
    if (c.cairo_surface_status(surf) != c.CAIRO_STATUS_SUCCESS) {
        c.cairo_surface_destroy(surf);
        return error.InvalidPng;
    }
    const format = c.cairo_image_surface_get_format(surf);
    if (format == c.CAIRO_FORMAT_ARGB32) return surf;

    const w = c.cairo_image_surface_get_width(surf);
    const h = c.cairo_image_surface_get_height(surf);
    const argb = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, w, h) orelse {
        c.cairo_surface_destroy(surf);
        return error.OutOfMemory;
    };
    const cr = c.cairo_create(argb) orelse {
        c.cairo_surface_destroy(argb);
        c.cairo_surface_destroy(surf);
        return error.OutOfMemory;
    };
    c.cairo_set_source_surface(cr, surf, 0, 0);
    c.cairo_paint(cr);
    c.cairo_destroy(cr);
    c.cairo_surface_destroy(surf);
    return argb;
}

pub const GaugeWidget = struct {
    allocator: std.mem.Allocator,
    wave_surface: ?*c.cairo_surface_t = null,
    cell_surfaces: [stage_count]?*c.cairo_surface_t = .{null} ** stage_count,

    pub fn init(allocator: std.mem.Allocator) GaugeWidget {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *GaugeWidget) void {
        for (&self.cell_surfaces) |*opt| {
            if (opt.*) |surf| c.cairo_surface_destroy(surf);
            opt.* = null;
        }
        if (self.wave_surface) |surf| c.cairo_surface_destroy(surf);
    }

    fn ensureCells(self: *GaugeWidget) void {
        if (self.wave_surface != null) return;
        self.wave_surface = loadPngFromBytes(wave_sheet_png) catch |err| {
            std.log.err("KidulWM: failed to load gauge wave sheet: {}", .{err});
            return;
        };
        const sheet = self.wave_surface.?;
        const sheet_w = @as(f64, @floatFromInt(c.cairo_image_surface_get_width(sheet)));
        const sheet_h = @as(f64, @floatFromInt(c.cairo_image_surface_get_height(sheet)));
        const src_cell_w = (sheet_w - @as(f64, @floatFromInt(cols + 1)) * @as(f64, @floatFromInt(pad))) / @as(f64, @floatFromInt(cols));
        const src_cell_h = (sheet_h - @as(f64, @floatFromInt(rows + 1)) * @as(f64, @floatFromInt(pad))) / @as(f64, @floatFromInt(rows));

        for (0..stage_count) |stage| {
            const col = stage % cols;
            const row = stage / cols;
            const src_x = @as(f64, @floatFromInt(pad)) + @as(f64, @floatFromInt(col)) * (src_cell_w + @as(f64, @floatFromInt(pad)));
            const src_y = @as(f64, @floatFromInt(pad)) + @as(f64, @floatFromInt(row)) * (src_cell_h + @as(f64, @floatFromInt(pad)));

            const cell = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, cell_w, cell_h) orelse continue;
            const cr = c.cairo_create(cell) orelse {
                c.cairo_surface_destroy(cell);
                continue;
            };
            c.cairo_set_source_surface(cr, sheet, -src_x, -src_y);
            c.cairo_pattern_set_filter(c.cairo_get_source(cr), c.CAIRO_FILTER_BILINEAR);
            c.cairo_paint(cr);
            c.cairo_destroy(cr);
            self.cell_surfaces[stage] = cell;
        }
    }

    pub const PeekBox = struct { x: i32, y: i32, width: i32, height: i32 };

    pub fn renderPeek(self: *GaugeWidget, cr: *c.cairo_t, box: PeekBox, style_: style.Style, scale: f32) void {
        self.ensureCells();
        const w_d: f64 = @floatFromInt(box.width);
        const h_d: f64 = @floatFromInt(box.height);
        if (w_d < 8.0 or h_d < 8.0) return;

        const gold = style_.color_border_focused.toF64();
        const muted = style_.color_text_muted.toF64();
        const metrics = [_]gauge_data.Metric{ .gpu_temp, .cpu_temp, .ram_usage, .disk1_size, .disk2_size };
        const labels = [_][]const u8{ "GPU", "CPU", "RAM", "D1", "D2" };

        const gauge_h = h_d / @as(f64, @floatFromInt(metrics.len));
        const margin: f64 = 2.0 * @as(f64, scale);

        var i: usize = 0;
        while (i < metrics.len) : (i += 1) {
            const y = @as(f64, @floatFromInt(i)) * gauge_h;

            // wave spans full width, leaving a little margin
            const icon_size = @min(gauge_h - margin * 2.0, w_d - margin * 2.0);
            const icon_x = (w_d - icon_size) * 0.5;
            const icon_y = y + margin;

            // Preview value (random-ish per index)
            const t = 0.05 + 0.90 * @abs(@sin(@as(f64, @floatFromInt(i)) * 1.7 + 0.5));
            const stage = @min(stage_count - 1, @as(usize, @intFromFloat(@floor(t * @as(f64, @floatFromInt(stage_count))))));
            const cell = self.cell_surfaces[stage] orelse continue;

            // Draw wave full-width, colorized with theme gold.
            c.cairo_save(cr);
            c.cairo_translate(cr, icon_x, icon_y);
            c.cairo_scale(cr, icon_size / @as(f64, @floatFromInt(cell_w)), icon_size / @as(f64, @floatFromInt(cell_h)));
            c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
            c.cairo_mask_surface(cr, cell, 0, 0);
            c.cairo_restore(cr);

            // label centered underneath the wave
            c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
            c.cairo_set_font_size(cr, 7.0 * @as(f64, scale));
            c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, @ptrCast(labels[i]), &ext);
            const label_x = (w_d - ext.width) * 0.5;
            const label_y = y + gauge_h - margin - ext.height * 0.5;
            c.cairo_move_to(cr, label_x, label_y);
            c.cairo_show_text(cr, @ptrCast(labels[i]));
        }
    }
};
