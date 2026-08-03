const std = @import("std");
const c = @import("dm").c;
const style = @import("../core/style.zig");

pub const FilesCard = struct {
    open: bool = false,

    pub fn toggle(self: *FilesCard) void {
        self.open = !self.open;
    }
};

pub const Entry = struct {
    name: []const u8,
    is_dir: bool,
};

pub const Drive = struct {
    label: []const u8,
    mount: []const u8,
};

pub const FilesWidget = struct {
    allocator: std.mem.Allocator,
    card: FilesCard = .{},
    current_path: []const u8 = "/home/dad",
    entries: std.ArrayList(Entry),
    drives: std.ArrayList(Drive),
    selected_index: usize = 0,
    scroll_offset: usize = 0,

    pub fn init(allocator: std.mem.Allocator) FilesWidget {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList(Entry).init(allocator),
            .drives = std.ArrayList(Drive).init(allocator),
        };
    }

    pub fn deinit(self: *FilesWidget) void {
        self.clearEntries();
        self.clearDrives();
        self.entries.deinit();
        self.drives.deinit();
    }

    pub fn toggleCard(self: *FilesWidget) void {
        self.card.toggle();
        if (self.card.open) {
            self.refresh();
        }
    }

    pub fn isCardOpen(self: *const FilesWidget) bool {
        return self.card.open;
    }

    pub fn refresh(self: *FilesWidget) void {
        self.discoverDrives();
        self.loadDirectory(self.current_path) catch {};
    }

    pub fn moveSelection(self: *FilesWidget, delta: isize) void {
        const count = self.entries.items.len;
        if (count == 0) return;
        const current = @as(isize, @intCast(self.selected_index));
        var next = current + delta;
        if (next < 0) next = 0;
        if (next >= @as(isize, @intCast(count))) next = @as(isize, @intCast(count)) - 1;
        self.selected_index = @intCast(next);
    }

    fn clearEntries(self: *FilesWidget) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.entries.clearRetainingCapacity();
    }

    fn clearDrives(self: *FilesWidget) void {
        for (self.drives.items) |drive| {
            self.allocator.free(drive.label);
            self.allocator.free(drive.mount);
        }
        self.drives.clearRetainingCapacity();
    }

    pub fn discoverDrives(self: *FilesWidget) void {
        self.clearDrives();
        const file = std.fs.openFileAbsolute("/proc/self/mounts", .{}) catch return;
        defer file.close();
        const reader = file.reader();
        var buf: [1024]u8 = undefined;
        while (reader.readUntilDelimiterOrEof(&buf, '\n') catch break) |line| {
            var it = std.mem.splitAny(u8, line, " ");
            const dev = it.next() orelse continue;
            const mount = it.next() orelse continue;
            const fs_type = it.next() orelse continue;
            if (!std.mem.startsWith(u8, dev, "/dev/")) continue;
            if (std.mem.eql(u8, fs_type, "vfat") or
                std.mem.eql(u8, fs_type, "ext4") or
                std.mem.eql(u8, fs_type, "btrfs") or
                std.mem.eql(u8, fs_type, "xfs"))
            {
                const label = driveLabelFor(mount);
                const mount_copy = self.allocator.dupe(u8, mount) catch continue;
                const label_copy = self.allocator.dupe(u8, label) catch {
                    self.allocator.free(mount_copy);
                    continue;
                };
                self.drives.append(.{ .label = label_copy, .mount = mount_copy }) catch {
                    self.allocator.free(mount_copy);
                    self.allocator.free(label_copy);
                };
            }
        }
    }

    pub fn loadDirectory(self: *FilesWidget, path: []const u8) !void {
        self.clearEntries();
        var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch return;
        defer dir.close();
        var it = dir.iterate();
        while (try it.next()) |entry| {
            const name = try self.allocator.dupe(u8, entry.name);
            self.entries.append(.{ .name = name, .is_dir = entry.kind == .directory }) catch {
                self.allocator.free(name);
            };
        }
        // Simple alphabetical sort, directories first.
        std.mem.sort(Entry, self.entries.items, {}, cmpEntry);
        self.selected_index = 0;
        self.scroll_offset = 0;
    }

    pub fn activateSelected(self: *FilesWidget) void {
        if (self.selected_index >= self.entries.items.len) return;
        const entry = self.entries.items[self.selected_index];
        if (!entry.is_dir) return;
        const new_path = std.fs.path.join(self.allocator, &.{ self.current_path, entry.name }) catch return;
        self.allocator.free(self.current_path);
        self.current_path = new_path;
        self.loadDirectory(self.current_path) catch {};
    }

    pub fn goUp(self: *FilesWidget) void {
        const parent = std.fs.path.dirname(self.current_path) orelse return;
        const new_path = self.allocator.dupe(u8, parent) catch return;
        self.allocator.free(self.current_path);
        self.current_path = new_path;
        self.loadDirectory(self.current_path) catch {};
    }

    pub fn renderCard(self: *FilesWidget, cr: *c.cairo_t, w_d: f64, h_d: f64, style_: style.Style, scale: f32) void {
        const scale_f: f64 = @floatFromInt(scale);
        const bg = style_.color_background.toF64();
        const gold = style_.color_border_focused.toF64();
        const muted = style_.color_text_muted.toF64();
        const text = style_.color_text.toF64();
        const font_size = 27.0 * scale_f;

        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
        c.cairo_set_font_size(cr, font_size);

        const pad: f64 = 16.0 * scale_f;
        const gap: f64 = 12.0 * scale_f;
        const pill_h: f64 = font_size * 1.6;
        const pills_y: f64 = pad;
        const content_top: f64 = pills_y + pill_h + gap;
        const content_h: f64 = h_d - content_top - pad;
        const content_w: f64 = w_d - 2.0 * pad;

        // Drive pills.
        var pill_x: f64 = pad;
        for (self.drives.items) |drive| {
            const extents = textExtents(cr, drive.label);
            const pill_w = extents.width + 24.0 * scale_f;
            if (pill_x + pill_w > w_d - pad) break;
            roundedRect(cr, pill_x, pills_y, pill_w, pill_h, pill_h * 0.25);
            c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.12);
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.45);
            c.cairo_set_line_width(cr, 1.0);
            c.cairo_stroke(cr);
            c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
            c.cairo_move_to(cr, pill_x + (pill_w - extents.width) * 0.5, pills_y + (pill_h + extents.height) * 0.5 - 4.0 * scale_f);
            c.cairo_show_text(cr, drive.label.ptr);
            pill_x += pill_w + gap;
        }

        // Three panes: 20/60/20.
        const side_w = content_w * 0.2;
        const mid_w = content_w * 0.6;
        const left_x = pad;
        const mid_x = left_x + side_w + gap;
        const right_x = mid_x + mid_w + gap;
        const corner = 10.0 * scale_f;

        // Left pane.
        drawPane(cr, bg, left_x, content_top, side_w, content_h, corner);
        const left_label = friendlyLabelFor(self.current_path);
        const left_extents = textExtents(cr, left_label);
        c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
        c.cairo_move_to(cr, left_x + (side_w - left_extents.width) * 0.5, content_top + 32.0 * scale_f);
        c.cairo_show_text(cr, left_label.ptr);

        // Middle pane.
        drawPane(cr, bg, mid_x, content_top, mid_w, content_h, corner);
        self.drawMiddle(cr, mid_x, content_top, mid_w, content_h, scale_f, text, muted);

        // Right pane.
        drawPane(cr, bg, right_x, content_top, side_w, content_h, corner);
        const preview_label = "preview";
        const preview_extents = textExtents(cr, preview_label);
        c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
        c.cairo_move_to(cr, right_x + (side_w - preview_extents.width) * 0.5, content_top + content_h * 0.5 + preview_extents.height * 0.5);
        c.cairo_show_text(cr, preview_label.ptr);
    }

    fn drawMiddle(self: *FilesWidget, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, scale_f: f64, text_color: [4]f64, muted_color: [4]f64) void {
        const row_h = 32.0 * scale_f;
        const visible_rows = @as(usize, @intFromFloat(@floor(h / row_h)));
        if (visible_rows == 0) return;

        const count = self.entries.items.len;
        if (count == 0) return;

        // Keep selected item centered when possible.
        const target = @min(self.selected_index, count - 1);
        var start: usize = 0;
        if (count > visible_rows) {
            const half = visible_rows / 2;
            if (target >= half) {
                start = target - half;
            }
            if (start + visible_rows > count) {
                start = count - visible_rows;
            }
        }
        self.scroll_offset = start;

        var i: usize = 0;
        while (i < visible_rows and start + i < count) : (i += 1) {
            const idx = start + i;
            const entry = self.entries.items[idx];
            const row_y = y + @as(f64, @floatFromInt(i)) * row_h + row_h * 0.5;
            const extents = textExtents(cr, entry.name);
            const text_x = x + (w - extents.width) * 0.5;
            if (idx == self.selected_index) {
                c.cairo_set_source_rgba(cr, text_color[0], text_color[1], text_color[2], text_color[3]);
            } else {
                c.cairo_set_source_rgba(cr, muted_color[0], muted_color[1], muted_color[2], muted_color[3]);
            }
            c.cairo_move_to(cr, text_x, row_y + extents.height * 0.25);
            c.cairo_show_text(cr, entry.name.ptr);
        }
    }
};

fn drawPane(cr: *c.cairo_t, bg: [4]f64, x: f64, y: f64, w: f64, h: f64, r: f64) void {
    roundedRect(cr, x, y, w, h, r);
    c.cairo_set_source_rgba(cr, bg[0], bg[1], bg[2], 0.95);
    c.cairo_fill(cr);
}

fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
    const radius = @min(r, w / 2.0, h / 2.0);
    if (radius <= 0.0) {
        c.cairo_rectangle(cr, x, y, w, h);
        return;
    }
    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, x + w - radius, y + radius, radius, -std.math.pi / 2.0, 0.0);
    c.cairo_arc(cr, x + w - radius, y + h - radius, radius, 0.0, std.math.pi / 2.0);
    c.cairo_arc(cr, x + radius, y + h - radius, radius, std.math.pi / 2.0, std.math.pi);
    c.cairo_arc(cr, x + radius, y + radius, radius, std.math.pi, 3.0 * std.math.pi / 2.0);
    c.cairo_close_path(cr);
}

fn textExtents(cr: *c.cairo_t, text_: []const u8) c.cairo_text_extents_t {
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, text_.ptr, &ext);
    return ext;
}

fn friendlyLabelFor(path: []const u8) []const u8 {
    if (std.mem.eql(u8, path, "/")) return "root";
    if (std.mem.startsWith(u8, path, "/home/")) {
        return path[6..];
    }
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| {
        if (idx + 1 < path.len) return path[idx + 1 ..];
    }
    return path;
}

fn driveLabelFor(mount: []const u8) []const u8 {
    if (std.mem.eql(u8, mount, "/")) return "root";
    if (std.mem.lastIndexOfScalar(u8, mount, '/')) |idx| {
        if (idx + 1 < mount.len) return mount[idx + 1 ..];
    }
    return mount;
}

fn cmpEntry(_: void, a: Entry, b: Entry) bool {
    if (a.is_dir != b.is_dir) return a.is_dir;
    return std.mem.lessThan(u8, a.name, b.name);
}
