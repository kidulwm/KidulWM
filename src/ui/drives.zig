const std = @import("std");
const c_std = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("time.h");
    @cInclude("sys/statvfs.h");
});
const c = @import("dm").c;
const style = @import("../core/style.zig");

pub const DrivesWidget = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DrivesWidget {
        return .{ .allocator = allocator };
    }

    pub fn deinit(_: *DrivesWidget) void {}

    pub const PeekBox = struct { x: i32, y: i32, width: i32, height: i32 };

    pub fn renderPeek(self: *DrivesWidget, cr: *c.cairo_t, box: PeekBox, style_: style.Style, scale: f32, kfiles_open: bool) void {
        const w_d: f64 = @floatFromInt(box.width);
        const h_d: f64 = @floatFromInt(box.height);
        if (w_d < 8.0 or h_d < 8.0) return;

        const focused = style_.color_border_focused.toF64();
        const unfocused = style_.color_border.toF64();

        const s = @as(f64, scale);

        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);

        self.renderDriveList(cr, w_d, h_d, s, focused, unfocused, kfiles_open);
    }

    fn renderDriveList(self: *DrivesWidget, cr: *c.cairo_t, w_d: f64, h_d: f64, s: f64, focused: [4]f64, unfocused: [4]f64, kfiles_open: bool) void {
        _ = self;
        _ = h_d;

        var drives_buf: [16]DriveInfo = undefined;
        const count = discoverDrives(&drives_buf);
        if (count == 0) return;

        if (!kfiles_open) {
            // LAW: no text in the peek. The EXIT dot-matrix owns peek
            // signage; the drive list appears only while kfiles is open.
            return;
        }

        const pad: f64 = 6.0 * s;
        const item_h: f64 = 28.0 * s;
        const gap: f64 = 4.0 * s;
        const top: f64 = 10.0 * s;
        const max_w: f64 = w_d - 2.0 * pad;

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const drive = &drives_buf[i];
            const usable = !drive.hidden;
            const fg = if (usable) focused else unfocused;
            const alpha: f64 = if (usable) 0.85 else 0.35;

            const y = top + @as(f64, @floatFromInt(i)) * (item_h + gap);

            // Pill background.
            c.cairo_set_source_rgba(cr, unfocused[0], unfocused[1], unfocused[2], 0.10);
            roundedRect(cr, pad, y, max_w, item_h, 4.0 * s);
            c.cairo_fill(cr);

            // Outline.
            c.cairo_set_source_rgba(cr, fg[0], fg[1], fg[2], alpha * 0.75);
            c.cairo_set_line_width(cr, 1.5 * s);
            roundedRect(cr, pad, y, max_w, item_h, 4.0 * s);
            c.cairo_stroke(cr);

            // Usage bar.
            if (usable) {
                const usage = driveUsage(drive);
                c.cairo_set_source_rgba(cr, focused[0], focused[1], focused[2], 0.35);
                roundedRect(cr, pad + 2.0 * s, y + item_h * 0.55, (max_w - 4.0 * s) * usage, item_h * 0.25, 2.0 * s);
                c.cairo_fill(cr);
            }

            // Label.
            c.cairo_set_source_rgba(cr, fg[0], fg[1], fg[2], alpha);
            c.cairo_set_font_size(cr, 10.0 * s);
            var ext: c.cairo_text_extents_t = undefined;
            const label = if (drive.name_len > 0) drive.name[0..drive.name_len] else "?";
            c.cairo_text_extents(cr, @ptrCast(label), &ext);
            c.cairo_move_to(cr, pad + 4.0 * s, y + item_h * 0.45);
            c.cairo_show_text(cr, @ptrCast(label));
        }
    }
};

pub const DriveInfo = struct {
    path: [128]u8 = .{0} ** 128,
    path_len: usize = 0,
    name: [64]u8 = .{0} ** 64,
    name_len: usize = 0,
    hidden: bool = false,
};

pub fn discoverDrives(out: []DriveInfo) usize {
    var count: usize = 0;
    const max = out.len;

    var mounted: [32]MountEntry = undefined;
    var mounted_count: usize = 0;

    const file = c_std.fopen("/proc/self/mounts", "r");
    if (file != null) {
        defer _ = c_std.fclose(file.?);
        var line_buf: [1024]u8 = .{0} ** 1024;
        while (c_std.fgets(&line_buf, line_buf.len, file.?) != null) {
            const line_len = std.mem.indexOfScalar(u8, &line_buf, 0) orelse line_buf.len;
            var end = line_len;
            while (end > 0 and (line_buf[end - 1] == '\r' or line_buf[end - 1] == '\n')) end -= 1;
            const line = line_buf[0..end];
            var it = std.mem.splitAny(u8, line, " ");
            const dev = it.next() orelse continue;
            const mount = it.next() orelse continue;
            const fs_type = it.next() orelse continue;
            if (!std.mem.startsWith(u8, dev, "/dev/")) continue;
            if (!isWantedFs(fs_type)) continue;
            if (mounted_count >= mounted.len) continue;
            mounted[mounted_count] = .{
                .dev = dev,
                .mount = mount,
            };
            mounted_count += 1;
        }
    }

    const parts = c_std.fopen("/proc/partitions", "r");
    if (parts != null) {
        defer _ = c_std.fclose(parts.?);
        var part_buf: [512]u8 = .{0} ** 512;
        var line_no: usize = 0;
        while (c_std.fgets(&part_buf, part_buf.len, parts.?) != null) {
            line_no += 1;
            if (line_no <= 2) continue;
            const line_len = std.mem.indexOfScalar(u8, &part_buf, 0) orelse part_buf.len;
            var end = line_len;
            while (end > 0 and (part_buf[end - 1] == '\r' or part_buf[end - 1] == '\n')) end -= 1;
            const line = part_buf[0..end];
            var it = std.mem.splitAny(u8, line, " \t");
            _ = it.next(); _ = it.next(); _ = it.next();
            const name = std.mem.trim(u8, it.next() orelse continue, " \t");
            if (name.len == 0) continue;
            if (std.mem.startsWith(u8, name, "loop") or std.mem.startsWith(u8, name, "ram")) continue;
            var dev_buf: [128]u8 = undefined;
            const dev_path = std.fmt.bufPrint(&dev_buf, "/dev/{s}", .{name}) catch continue;

            var found_mount: ?[]const u8 = null;
            var mi: usize = 0;
            while (mi < mounted_count) : (mi += 1) {
                if (std.mem.eql(u8, mounted[mi].dev, dev_path)) {
                    found_mount = mounted[mi].mount;
                    break;
                }
            }

            if (count >= max) break;
            var drive = &out[count];
            drive.* = .{};
            drive.hidden = found_mount == null;
            const mount = found_mount orelse dev_path;
            const label = driveLabelFor(mount);
            drive.path_len = @min(drive.path.len, mount.len);
            @memcpy(drive.path[0..drive.path_len], mount[0..drive.path_len]);
            drive.name_len = @min(drive.name.len, label.len);
            @memcpy(drive.name[0..drive.name_len], label[0..drive.name_len]);
            count += 1;
        }
    }

    return count;
}

const MountEntry = struct {
    dev: []const u8,
    mount: []const u8,
};

fn isWantedFs(fs_type: []const u8) bool {
    return std.mem.eql(u8, fs_type, "vfat") or
        std.mem.eql(u8, fs_type, "ext4") or
        std.mem.eql(u8, fs_type, "btrfs") or
        std.mem.eql(u8, fs_type, "xfs") or
        std.mem.eql(u8, fs_type, "ntfs") or
        std.mem.eql(u8, fs_type, "exfat");
}

fn driveLabelFor(mount: []const u8) []const u8 {
    if (std.mem.eql(u8, mount, "/")) return "root";
    if (std.mem.lastIndexOfScalar(u8, mount, '/')) |idx| {
        if (idx + 1 < mount.len) return mount[idx + 1 ..];
    }
    return mount;
}

fn driveUsage(drive: *const DriveInfo) f64 {
    var buf: c_std.struct_statvfs = undefined;
    const path = if (drive.path_len > 0) drive.path[0..drive.path_len] else return 0.0;
    var path_z: [256:0]u8 = undefined;
    if (path.len >= path_z.len) return 0.0;
    @memcpy(path_z[0..path.len], path);
    path_z[path.len] = 0;
    if (c_std.statvfs(&path_z, &buf) != 0) return 0.0;
    if (buf.f_blocks == 0) return 0.0;
    const used = @as(f64, @floatFromInt(buf.f_blocks - buf.f_bavail));
    const total = @as(f64, @floatFromInt(buf.f_blocks));
    return @max(0.0, @min(1.0, used / total));
}

fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
    const radius = @min(r, w * 0.5, h * 0.5);
    c.cairo_move_to(cr, x + radius, y);
    c.cairo_line_to(cr, x + w - radius, y);
    c.cairo_arc(cr, x + w - radius, y + radius, radius, -std.math.pi * 0.5, 0.0);
    c.cairo_line_to(cr, x + w, y + h - radius);
    c.cairo_arc(cr, x + w - radius, y + h - radius, radius, 0.0, std.math.pi * 0.5);
    c.cairo_line_to(cr, x + radius, y + h);
    c.cairo_arc(cr, x + radius, y + h - radius, radius, std.math.pi * 0.5, std.math.pi);
    c.cairo_line_to(cr, x, y + radius);
    c.cairo_arc(cr, x + radius, y + radius, radius, std.math.pi, -std.math.pi * 0.5);
    c.cairo_close_path(cr);
}
