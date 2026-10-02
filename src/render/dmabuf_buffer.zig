// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const wlr = @import("wlroots");

/// A dmabuf-backed wlr.Buffer wrapping an externally imported VA surface
/// (kmedia zero-copy slide path). Implements get_dmabuf so the gles2
/// renderer imports the fds directly via EGLImage (wlr_texture_from_buffer
/// → gles2_texture_from_dmabuf). Immutable from wlroots' point of view.
///
/// FD ownership: we dup the VA-exported fds up front and OWN the dups —
/// destroy() closes them. The VA descriptor fds are closed by the caller
/// right after create(), so wlroots' EGL import never sees an fd we might
/// close under it (wlr never takes ownership of fds handed through
/// wlr_dmabuf_attributes; it dups again internally for the EGLImage).
pub const DmabufBuffer = struct {
    base: wlr.Buffer,
    attribs: wlr.DmabufAttributes,

    const Self = @This();

    pub fn destroy(buffer: *wlr.Buffer) callconv(.c) void {
        const self: *Self = @alignCast(@fieldParentPtr("base", buffer));
        self.attribs.finish(); // closes the dup'd fds
        std.heap.page_allocator.destroy(self);
    }

    pub fn getDmabuf(buffer: *wlr.Buffer, attribs: *wlr.DmabufAttributes) callconv(.c) bool {
        const self: *Self = @alignCast(@fieldParentPtr("base", buffer));
        return attribs.copy(&self.attribs); // dup's fds for the consumer
    }

    pub fn getShm(_: *wlr.Buffer, _: *wlr.ShmAttributes) callconv(.c) bool {
        return false;
    }

    pub fn beginDataPtrAccess(_: *wlr.Buffer, _: u32, _: **anyopaque, _: *u32, _: *usize) callconv(.c) bool {
        return false;
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

    /// Takes ownership of attribs (fails → attribs.finish() here).
    pub fn create(attribs: *wlr.DmabufAttributes) !*wlr.Buffer {
        const allocator = std.heap.page_allocator;
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        self.* = .{ .base = undefined, .attribs = attribs.* };
        wlr.Buffer.init(&self.base, impl(), attribs.width, attribs.height);
        return &self.base;
    }
};
