const std = @import("std");

// ---------------------------------------------------------------------------
// kimg — media art pipeline. THE LAW:
//
//   1. A file on disk beats everything, forever. Local art is sacred: the
//      scanner reads it, never writes it, and no future network fetch may
//      ever replace it (fill-only, opt-in, and not built today).
//   2. Resolution order, per category:
//        movie in own folder : <stem>-poster.* → poster.* → folder.*
//        flat movie/series   : parent folder's folder.* → poster.*
//        music track         : embedded art (ffprobe) → folder.* → cover.*
//                              → any image in folder
//        pictures            : the file itself IS the art
//      All failures land on the placeholder gradient. No exceptions.
//   3. The wall shows 256px thumbs, decoded once, cached on disk at
//      ~/.cache/kidulwm/thumbs/<crc32 of resolved art path>.png.
//      RAM stays flat no matter how big the library gets.
//   4. The focused card, after a dwell, gets a hi-res decode of the
//      original art. Only the focused card. Only after the dwell.
//   5. Decode happens on the worker thread. The render thread never
//      stats, never opens, never blocks.
// ---------------------------------------------------------------------------

const cairo = @import("dm").c;

extern fn access(path: [*:0]const u8, mode: c_int) c_int;
extern fn system(cmd: [*:0]const u8) c_int;
extern fn getenv(name: [*:0]const u8) ?[*:0]u8;
const F_OK: c_int = 0;

extern fn kidul_img_decode(path: [*:0]const u8, out_rgba: *[*]u8, out_w: *c_int, out_h: *c_int) c_int;
extern fn kidul_img_free(px: [*]u8) void;

pub const THUMB_W: usize = 256;

pub const Kind = enum { thumb, hires };

pub const Request = struct {
    /// Key for the in-flight/result maps: crc32 of resolved art path.
    key: u32,
    kind: Kind,
    /// Owned copies (g_alloc) — worker frees after use.
    art_path: [:0]u8,
    cache_path: [:0]u8,
};

pub const Result = struct {
    key: u32,
    kind: Kind,
    surface: ?*cairo.cairo_surface_t, // null = decode failed, use placeholder
};

fn fileExists(path: []const u8) bool {
    var buf: [4096:0]u8 = undefined;
    if (path.len >= buf.len) return false;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return access(buf[0..path.len :0].ptr, F_OK) == 0;
}

fn isImageName(name: []const u8) bool {
    const ext = std.fs.path.extension(name);
    var b: [16]u8 = undefined;
    if (ext.len > b.len) return false;
    const l = std.ascii.lowerString(&b, ext);
    return std.mem.eql(u8, l, ".jpg") or std.mem.eql(u8, l, ".jpeg") or
        std.mem.eql(u8, l, ".png") or std.mem.eql(u8, l, ".webp") or
        std.mem.eql(u8, l, ".gif") or std.mem.eql(u8, l, ".bmp");
}

fn tryNames(alloc: std.mem.Allocator, dir: []const u8, stem: []const u8, suffixes: []const []const u8) ?[:0]u8 {
    for (suffixes) |suffix| {
        const full = std.fmt.allocPrintSentinel(alloc, "{s}/{s}{s}", .{ dir, stem, suffix }, 0) catch return null;
        if (fileExists(full)) return full;
        alloc.free(full);
    }
    return null;
}

/// Extract embedded art from an audio file via ffprobe+ffmpeg into a temp
/// png. Returns the temp path (caller frees) or null. Only called on the
/// worker thread, only for music with no folder art, and only once per
/// album ever (the disk thumb cache sits in front of it).
fn extractEmbedded(alloc: std.mem.Allocator, media_path: []const u8) ?[:0]u8 {
    const key = std.hash.Crc32.hash(media_path);
    const tmp = std.fmt.allocPrintSentinel(alloc, "/tmp/kidul-art-{x}.png", .{key}, 0) catch return null;
    if (fileExists(tmp)) return tmp;
    var cmd_buf: [4608:0]u8 = undefined;
    const cmd = std.fmt.bufPrintZ(&cmd_buf,
        "ffmpeg -y -loglevel error -i \"{s}\" -an -vcodec png -frames:v 1 \"{s}\" 2>/dev/null",
        .{ media_path, tmp }) catch return null;
    const rc = system(cmd.ptr);
    if (rc != 0 or !fileExists(tmp)) {
        alloc.free(tmp);
        return null;
    }
    return tmp;
}

fn firstImageInDir(alloc: std.mem.Allocator, dir: []const u8) ?[:0]u8 {
    var threaded = std.Io.Threaded.init(alloc, .{});
    const io = threaded.io();
    var d = std.Io.Dir.openDirAbsolute(io, dir, .{ .iterate = true }) catch return null;
    defer d.close(io);
    var it = d.iterate();
    var best: ?[:0]u8 = null;
    while (it.next(io) catch null) |ent| {
        if (ent.kind != .file) continue;
        if (!isImageName(ent.name)) continue;
        const full = std.fmt.allocPrintSentinel(alloc, "{s}/{s}", .{ dir, ent.name }, 0) catch continue;
        if (best) |b| {
            if (std.mem.lessThan(u8, ent.name, std.fs.path.basename(b))) {
                alloc.free(b);
                best = full;
            } else alloc.free(full);
        } else best = full;
    }
    return best;
}

const poster_suffixes = [_][]const u8{ "-poster.jpg", "-poster.png", "-poster.jpeg" };
const plain_poster_names = [_][]const u8{ "poster.jpg", "poster.png", "poster.jpeg" };
const folder_names = [_][]const u8{ "folder.jpg", "folder.png", "folder.jpeg" };
const cover_names = [_][]const u8{ "cover.jpg", "cover.png", "cover.jpeg" };

/// Resolve the canonical LOCAL art path for a media entry. Returns null when
/// nothing local exists (placeholder). Caller owns the returned slice.
/// Pure path work — cheap stats, no decode. Safe to call on render thread.
pub fn resolveArtPath(
    alloc: std.mem.Allocator,
    media_path: []const u8,
    is_music: bool,
    is_picture: bool,
) ?[:0]u8 {
    if (is_picture) {
        // The file is its own art.
        if (fileExists(media_path)) {
            return alloc.dupeZ(u8, media_path) catch null;
        }
        return null;
    }

    const dir = std.fs.path.dirname(media_path) orelse return null;
    const stem = std.fs.path.stem(media_path);
    const base = std.fs.path.basename(dir);

    // Movie in own folder / any media: <stem>-poster.* first.
    if (tryNames(alloc, dir, stem, &poster_suffixes)) |p| return p;

    // If the folder looks like a title folder (folder name == stem, or the
    // folder contains a folder/poster file), use folder-level art.
    if (tryNames(alloc, dir, "", &folder_names)) |p| return p;
    if (tryNames(alloc, dir, "", &plain_poster_names)) |p| return p;
    _ = base;

    if (is_music) {
        // Embedded art travels with the file — second only to an explicit
        // folder image the user placed herself.
        if (extractEmbedded(alloc, media_path)) |p| return p;
        if (tryNames(alloc, dir, "", &cover_names)) |p| return p;
        if (firstImageInDir(alloc, dir)) |p| return p;
    } else {
        // Flat movie/series dump: parent folder art.
        const parent = std.fs.path.dirname(dir) orelse return null;
        if (tryNames(alloc, parent, "", &folder_names)) |p| return p;
        if (tryNames(alloc, parent, "", &plain_poster_names)) |p| return p;
    }
    return null;
}

/// Cache path for a resolved art path: ~/.cache/kidulwm/thumbs/<crc>.png
pub fn thumbCachePath(alloc: std.mem.Allocator, art_path: []const u8) ?[:0]u8 {
    const home_c = getenv("HOME");
    const home: []const u8 = if (home_c) |h| std.mem.span(h) else "/home/kidul";
    const key = std.hash.Crc32.hash(art_path);
    return std.fmt.allocPrintSentinel(alloc, "{s}/.cache/kidulwm/thumbs/{x}.png", .{ home, key }, 0) catch null;
}

pub fn thumbKey(art_path: []const u8) u32 {
    return std.hash.Crc32.hash(art_path);
}

/// Bilinear-resize RGBA src to dst dims. Cairo handles final paint scaling;
/// we bake the 256px thumb here so decode RAM stays flat.
fn resizeRgba(
    src: [*]const u8,
    sw: usize,
    sh: usize,
    dst: [*]u8,
    dw: usize,
    dh: usize,
) void {
    var y: usize = 0;
    while (y < dh) : (y += 1) {
        const fy = (@as(f64, @floatFromInt(y)) + 0.5) * @as(f64, @floatFromInt(sh)) / @as(f64, @floatFromInt(dh)) - 0.5;
        const y0: usize = if (fy < 0) 0 else @intFromFloat(@floor(fy));
        const y1: usize = @min(y0 + 1, sh - 1);
        const wy = fy - @floor(@max(0.0, fy));
        var x: usize = 0;
        while (x < dw) : (x += 1) {
            const fx = (@as(f64, @floatFromInt(x)) + 0.5) * @as(f64, @floatFromInt(sw)) / @as(f64, @floatFromInt(dw)) - 0.5;
            const x0: usize = if (fx < 0) 0 else @intFromFloat(@floor(fx));
            const x1: usize = @min(x0 + 1, sw - 1);
            const wx = fx - @floor(@max(0.0, fx));
            const p00 = (y0 * sw + x0) * 4;
            const p01 = (y0 * sw + x1) * 4;
            const p10 = (y1 * sw + x0) * 4;
            const p11 = (y1 * sw + x1) * 4;
            const di = (y * dw + x) * 4;
            var chn: usize = 0;
            while (chn < 4) : (chn += 1) {
                const v00 = @as(f64, @floatFromInt(src[p00 + chn]));
                const v01 = @as(f64, @floatFromInt(src[p01 + chn]));
                const v10 = @as(f64, @floatFromInt(src[p10 + chn]));
                const v11 = @as(f64, @floatFromInt(src[p11 + chn]));
                const top = v00 + (v01 - v00) * wx;
                const bot = v10 + (v11 - v10) * wx;
                dst[di + chn] = @intFromFloat(@max(0, @min(255, top + (bot - top) * wy)));
            }
        }
    }
}

/// Decode an image (jpeg/png/gif/bmp via stb) into a premultiplied ARGB32
/// cairo surface scaled so width == target_w (aspect preserved). Returns
/// null on failure. Runs on the worker thread only.
pub fn decodeToSurface(alloc: std.mem.Allocator, path: [:0]const u8, target_w: usize) ?*cairo.cairo_surface_t {
    var rgba: [*]u8 = undefined;
    var w: c_int = 0;
    var h: c_int = 0;
    if (kidul_img_decode(path.ptr, &rgba, &w, &h) != 0) return null;
    defer kidul_img_free(rgba);
    if (w <= 0 or h <= 0) return null;

    const sw: usize = @intCast(w);
    const sh: usize = @intCast(h);
    const dw = target_w;
    const dh = @max(1, sh * dw / sw);

    const scaled = alloc.alloc(u8, dw * dh * 4) catch return null;
    if (sw == dw and sh == dh) {
        @memcpy(scaled, rgba[0 .. dw * dh * 4]);
    } else {
        resizeRgba(rgba, sw, sh, scaled.ptr, dw, dh);
    }

    // stb gives RGBA straight alpha; cairo ARGB32 wants premultiplied BGRA
    // (native little-endian). Convert in place.
    var i: usize = 0;
    while (i < dw * dh) : (i += 1) {
        const p = scaled[i * 4 .. i * 4 + 4];
        const r = p[0];
        const g = p[1];
        const b = p[2];
        const a = p[3];
        p[0] = @intCast(@min(255, @as(u32, b) * a / 255));
        p[1] = @intCast(@min(255, @as(u32, g) * a / 255));
        p[2] = @intCast(@min(255, @as(u32, r) * a / 255));
        p[3] = a;
    }

    const surf = cairo.cairo_image_surface_create_for_data(
        scaled.ptr,
        cairo.CAIRO_FORMAT_ARGB32,
        @intCast(dw),
        @intCast(dh),
        @intCast(dw * 4),
    ) orelse {
        alloc.free(scaled);
        return null;
    };
    if (cairo.cairo_surface_status(surf) != cairo.CAIRO_STATUS_SUCCESS) {
        cairo.cairo_surface_destroy(surf);
        alloc.free(scaled);
        return null;
    }
    // The pixel buffer must outlive us: hand it to the surface via user
    // data with a destructor, so cairo_surface_destroy frees both.
    const DataBox = struct { buf: []u8, alloc: std.mem.Allocator };
    const box = alloc.create(DataBox) catch {
        cairo.cairo_surface_destroy(surf);
        alloc.free(scaled);
        return null;
    };
    box.* = .{ .buf = scaled, .alloc = alloc };
    const key = struct {
        var k: cairo.cairo_user_data_key_t = undefined;
    };
    _ = cairo.cairo_surface_set_user_data(surf, @ptrCast(&key.k), box, struct {
        fn dtor(p: ?*anyopaque) callconv(.c) void {
            const b2: *DataBox = @ptrCast(@alignCast(p orelse return));
            b2.alloc.free(b2.buf);
            b2.alloc.destroy(b2);
        }
    }.dtor);
    return surf;
}

/// Worker-thread entry for one request: decode original (or use cached
/// thumb file), scale, write thumb png to disk, return the surface.
pub fn processRequest(alloc: std.mem.Allocator, req: Request) Result {
    var surface: ?*cairo.cairo_surface_t = null;
    switch (req.kind) {
        .thumb => {
            // Disk cache hit?
            if (fileExists(req.cache_path)) {
                const s = cairo.cairo_image_surface_create_from_png(req.cache_path.ptr);
                if (s != null and cairo.cairo_surface_status(s) == cairo.CAIRO_STATUS_SUCCESS) {
                    surface = s;
                } else if (s != null) cairo.cairo_surface_destroy(s);
            }
            if (surface == null) {
                if (decodeToSurface(alloc, req.art_path, THUMB_W)) |s| {
                    // Write-through to disk cache (best effort).
                    if (std.fs.path.dirname(req.cache_path)) |d| {
                        var threaded = std.Io.Threaded.init(alloc, .{});
                        const io = threaded.io();
                        std.Io.Dir.createDirPath(std.Io.Dir.cwd(), io, d) catch {};
                    }
                    _ = cairo.cairo_surface_write_to_png(s, req.cache_path.ptr);
                    surface = s;
                }
            }
        },
        .hires => {
            // Focused-card upgrade: decode at 2x thumb width, no disk write
            // (the dwell card is transient; the wall thumb is the artifact).
            surface = decodeToSurface(alloc, req.art_path, THUMB_W * 2);
        },
    }
    alloc.free(req.art_path);
    alloc.free(req.cache_path);
    return .{ .key = req.key, .kind = req.kind, .surface = surface };
}
