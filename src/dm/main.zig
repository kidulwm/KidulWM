const std = @import("std");
const c = @import("c.zig").c;
const render = @import("render.zig");
const Style = @import("style.zig").Style;

fn writeFrame(name: []const u8, alpha: f64, splash: bool) !void {
    const w: i32 = 1280;
    const h: i32 = 720;
    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, w, h) orelse return error.CairoSurfaceFailed;
    defer c.cairo_surface_destroy(surface);
    const cr = c.cairo_create(surface) orelse return error.CairoContextFailed;
    defer c.cairo_destroy(cr);

    if (splash) {
        render.drawSplash(cr, Style{}, w, h, alpha);
    } else {
        render.drawFrame(cr, Style{}, w, h, alpha);
    }

    const path = try std.fmt.allocPrint(std.heap.page_allocator, "/tmp/kiduldm-{s}.png", .{name});
    defer std.heap.page_allocator.free(path);

    const status = c.cairo_surface_write_to_png(surface, path.ptr);
    if (status != c.CAIRO_STATUS_SUCCESS) {
        std.log.err("failed to write PNG: {s}", .{c.cairo_status_to_string(status)});
        return error.PngWriteFailed;
    }
    std.log.info("frame written to {s}", .{path});
}

pub fn main() !void {
    try writeFrame("splash", 1.0, true);
    try writeFrame("frame0", 1.0, false);
}
