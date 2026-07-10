const std = @import("std");
const wlr = @import("wlroots");

/// A CPU-backed wlr.Buffer implementation with read-only pointer access.
/// The pixel data is DRM_FORMAT_ARGB8888 (Cairo native).
pub const DataBuffer = struct {
    base: wlr.Buffer,
    pixels: []u8,
    stride: usize,

    const Self = @This();

    // DRM_FORMAT_ARGB8888 fourcc
    const DRM_FORMAT_ARGB8888: u32 = 0x34325241;

    pub fn destroy(buffer: *wlr.Buffer) callconv(.c) void {
        const self: *Self = @alignCast(@fieldParentPtr("base", buffer));
        const allocator = std.heap.page_allocator;
        allocator.free(self.pixels);
        allocator.destroy(self);
    }

    pub fn getDmabuf(_: *wlr.Buffer, _: *wlr.DmabufAttributes) callconv(.c) bool {
        return false;
    }

    pub fn getShm(_: *wlr.Buffer, _: *wlr.ShmAttributes) callconv(.c) bool {
        return false;
    }

    pub fn beginDataPtrAccess(buffer: *wlr.Buffer, flags: u32, data: **anyopaque, format: *u32, stride: *usize) callconv(.c) bool {
        _ = flags;
        const self: *Self = @alignCast(@fieldParentPtr("base", buffer));
        data.* = self.pixels.ptr;
        format.* = DRM_FORMAT_ARGB8888;
        stride.* = self.stride;
        return true;
    }

    pub fn endDataPtrAccess(_: *wlr.Buffer) callconv(.c) void {}

    pub fn impl() *const wlr.Buffer.Impl {
        return &.{
            .destroy = destroy,
            .get_dmabuf = getDmabuf,
            .get_shm = getShm,
            .begin_data_ptr_access = beginDataPtrAccess,
            .end_data_ptr_access = endDataPtrAccess,
        };
    }

    pub fn create(pixels: []const u8, width: i32, height: i32, stride: i32) !*wlr.Buffer {
        const allocator = std.heap.page_allocator;
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const owned = try allocator.dupe(u8, pixels);
        errdefer allocator.free(owned);

        self.* = .{
            .base = undefined,
            .pixels = owned,
            .stride = @intCast(stride),
        };
        wlr.Buffer.init(&self.base, impl(), width, height);
        return &self.base;
    }
};
