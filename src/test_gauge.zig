// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const c_cairo = @import("dm").c;
const gauge = @import("ui/gauge.zig");
const style = @import("core/style.zig");
const theme = @import("core/theme.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const width: i32 = 240;
    const height: i32 = 400;
    const surface = c_cairo.cairo_image_surface_create(c_cairo.CAIRO_FORMAT_ARGB32, width, height) orelse return error.SurfaceFail;
    defer c_cairo.cairo_surface_destroy(surface);
    const cr = c_cairo.cairo_create(surface) orelse return error.ContextFail;
    defer c_cairo.cairo_destroy(cr);

    c_cairo.cairo_set_operator(cr, c_cairo.CAIRO_OPERATOR_SOURCE);
    c_cairo.cairo_set_source_rgba(cr, 0.05, 0.05, 0.05, 1.0);
    c_cairo.cairo_paint(cr);
    c_cairo.cairo_set_operator(cr, c_cairo.CAIRO_OPERATOR_OVER);

    const style_ = style.default();
    var gw = gauge.GaugeWidget.init(allocator);
    gw.renderRamAmpoule(cr, width, height, 1.0, style_);

    _ = c_cairo.cairo_surface_write_to_png(surface, "/tmp/gauge.png");
}
