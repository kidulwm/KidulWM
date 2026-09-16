const std = @import("std");
const weather = @import("ui/weather.zig");
const style = @import("core/style.zig");
const c = @import("dm").c;

// Render the peek pill at the LIVE geometry: 111 logical wide x 320 tall,
// scale 1 and scale 2, into PNGs for eyeball comparison.
pub fn main() !void {
    const st = style.Style{};
    var widget = weather.WeatherWidget.init(std.heap.page_allocator);
    defer widget.deinit();
    widget.update();

    const cases = [_]struct { name: [:0]const u8, w: i32, h: i32, scale: f32 }{
        .{ .name = "/tmp/peek_weather_s1.png", .w = 111, .h = 320, .scale = 1.0 },
        .{ .name = "/tmp/peek_weather_s2.png", .w = 111, .h = 320, .scale = 2.0 },
    };
    for (cases) |cs| {
        const dev_w: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(cs.w)) * cs.scale));
        const dev_h: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(cs.h)) * cs.scale));
        const surf = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, dev_w, dev_h);
        defer c.cairo_surface_destroy(surf);
        const cr = c.cairo_create(surf).?;
        defer c.cairo_destroy(cr);
        // Opaque bg so we see what the pill actually paints.
        c.cairo_set_source_rgba(cr, 0.10, 0.10, 0.11, 1.0);
        c.cairo_paint(cr);
        widget.renderPeek(cr, .{ .x = 0, .y = 0, .width = dev_w, .height = dev_h }, st, cs.scale);
        _ = c.cairo_surface_write_to_png(surf, cs.name.ptr);
        std.debug.print("wrote {s} ({d}x{d} dev)\n", .{ cs.name, dev_w, dev_h });
    }
}
