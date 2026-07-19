const std = @import("std");
const c = @import("dm").c;

/// Image utilities for loading client assets (wallpapers, etc.) into buffers
/// that can be consumed by the wlr scene graph.
pub const Image = struct {
    /// A loaded PNG image whose pixel data is owned by a Cairo surface.
    /// Call `deinit` to release the underlying surface.
    pub const Owned = struct {
        surface: ?*c.cairo_surface_t,
        data: []u8,
        width: i32,
        height: i32,
        stride: i32,

        pub fn deinit(self: Owned) void {
            c.cairo_surface_destroy(self.surface);
        }
    };

    /// Load a PNG file from `path` using Cairo's built-in PNG reader.
    /// Returns a Cairo surface-backed wrapper. The pixel slice is valid until
    /// `deinit` is called; it is suitable for copying into a `wlr.Buffer`.
    pub fn loadPng(path: []const u8) !Owned {
        const path_z = try std.heap.page_allocator.dupeZ(u8, path);
        defer std.heap.page_allocator.free(path_z);
        const source = c.cairo_image_surface_create_from_png(path_z.ptr);
        if (source == null) return error.OutOfMemory;

        const status = c.cairo_surface_status(source);
        if (status != c.CAIRO_STATUS_SUCCESS) {
            c.cairo_surface_destroy(source);
            return error.CairoError;
        }

        const format = c.cairo_image_surface_get_format(source);
        const width = c.cairo_image_surface_get_width(source);
        const height = c.cairo_image_surface_get_height(source);

        if (width <= 0 or height <= 0) {
            c.cairo_surface_destroy(source);
            return error.InvalidImage;
        }

        // The wlr scene graph needs an ARGB8888 buffer. Convert any other
        // Cairo format (e.g. RGB24 from an opaque PNG) on the fly.
        const surface = if (format == c.CAIRO_FORMAT_ARGB32) source else blk: {
            const argb = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, width, height) orelse {
                c.cairo_surface_destroy(source);
                return error.OutOfMemory;
            };
            const cr = c.cairo_create(argb);
            c.cairo_set_source_surface(cr, source, 0, 0);
            c.cairo_paint(cr);
            c.cairo_destroy(cr);
            c.cairo_surface_destroy(source);
            break :blk argb;
        };

        c.cairo_surface_flush(surface);

        const stride = c.cairo_image_surface_get_stride(surface);
        const data_ptr = c.cairo_image_surface_get_data(surface);
        if (data_ptr == null) {
            c.cairo_surface_destroy(surface);
            return error.InvalidImage;
        }

        const data = @as([*]u8, @ptrCast(data_ptr))[0..@intCast(stride * height)];

        return .{
            .surface = surface,
            .data = data,
            .width = width,
            .height = height,
            .stride = stride,
        };
    }
};
