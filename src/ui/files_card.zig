const std = @import("std");
const c = @import("dm").c;
const c_std = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("stdio.h");
    @cInclude("dirent.h");
    @cInclude("sys/stat.h");
});
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
    current_path: []const u8 = "/home/kidul",
    entries: std.ArrayList(Entry),
    drives: std.ArrayList(Drive),
    selected_index: usize = 0,
    scroll_offset: usize = 0,

    pub fn init(allocator: std.mem.Allocator) FilesWidget {
        const current_path = allocator.dupe(u8, "/home/kidul") catch "/home/kidul";
        return .{
            .allocator = allocator,
            .current_path = current_path,
            .entries = .empty,
            .drives = .empty,
        };
    }

    pub fn deinit(self: *FilesWidget) void {
        self.clearEntries();
        self.clearDrives();
        self.entries.deinit(self.allocator);
        self.drives.deinit(self.allocator);
        if (self.current_path.ptr != "/home/kidul".ptr) {
            self.allocator.free(self.current_path);
        }
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
        const file = c_std.fopen("/proc/self/mounts", "r") orelse return;
        defer _ = c_std.fclose(file);
        var line_buf: [1024]u8 = undefined;
        while (c_std.fgets(&line_buf, line_buf.len, file) != null) {
            const line_len = std.mem.indexOfScalar(u8, &line_buf, 0) orelse line_buf.len;
            const line = std.mem.trimEnd(u8, line_buf[0..line_len], "\r\n");
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
                self.drives.append(self.allocator, .{ .label = label_copy, .mount = mount_copy }) catch {
                    self.allocator.free(mount_copy);
                    self.allocator.free(label_copy);
                };
            }
        }
    }

    pub fn loadDirectory(self: *FilesWidget, path: []const u8) !void {
        self.clearEntries();
        var path_z: [1024]u8 = undefined;
        const nt = std.fmt.bufPrintZ(&path_z, "{s}", .{path}) catch return;
        const dir = c_std.opendir(nt.ptr) orelse return;
        defer _ = c_std.closedir(dir);
        while (true) {
            const entry = c_std.readdir(dir) orelse break;
            const name_ptr: [*:0]u8 = @ptrCast(&entry.*.d_name[0]);
            const name = std.mem.span(name_ptr);
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            const full_path = std.fs.path.join(self.allocator, &.{ path, name }) catch continue;
            defer self.allocator.free(full_path);
            const is_dir = isDir(full_path);
            const name_copy = self.allocator.dupe(u8, name) catch continue;
            self.entries.append(self.allocator, .{ .name = name_copy, .is_dir = is_dir }) catch {
                self.allocator.free(name_copy);
            };
        }
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
        const scale_f: f64 = @floatCast(scale);
        _ = style_.color_background.toF64();
        const gold = style_.color_border_focused.toF64();
        const muted = style_.color_text_muted.toF64();
        const text = style_.tray_text_focused_color.toF64();
        const font_size = 33.0 * scale_f;

        // Fully transparent card background — files live in space.
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

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
            drawShadedButton(cr, pill_x, pills_y, pill_w, pill_h, pill_h * 0.25, gold, 0.35);
            c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
            c.cairo_move_to(cr, pill_x + (pill_w - extents.width) * 0.5, pills_y + (pill_h + extents.height) * 0.5 - 4.0 * scale_f);
            showTextZ(cr, drive.label);
            pill_x += pill_w + gap;
        }

        // Three panes: 20/60/20.
        const side_w = content_w * 0.2;
        const mid_w = content_w * 0.6;
        const left_x = pad;
        const mid_x = left_x + side_w + gap;
        const right_x = mid_x + mid_w + gap;
        // Left pane label.
        const left_label = friendlyLabelFor(self.current_path);
        const left_extents = textExtents(cr, left_label);
        const left_label_x = left_x + (side_w - left_extents.width) * 0.5;
        const left_button_h = left_extents.height + 14.0 * scale_f;
        const left_button_y = content_top + left_extents.height * 0.5 + 8.0 * scale_f;
        drawShadedButton(cr, left_label_x - 8.0 * scale_f, left_button_y, left_extents.width + 16.0 * scale_f, left_button_h, 8.0 * scale_f, gold, 0.20);
        c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
        c.cairo_move_to(cr, left_label_x, left_button_y + left_button_h * 0.5 + left_extents.height * 0.35);
        showTextZ(cr, left_label);

        // Middle pane.
        self.drawMiddle(cr, mid_x, content_top, mid_w, content_h, scale_f, text, muted);

        // Right pane label.
        const preview_label = "preview";
        const preview_extents = textExtents(cr, preview_label);
        const preview_label_x = right_x + (side_w - preview_extents.width) * 0.5;
        drawShadedButton(cr, preview_label_x - 8.0 * scale_f, content_top + content_h * 0.5 - preview_extents.height * 0.5, preview_extents.width + 16.0 * scale_f, preview_extents.height + 16.0 * scale_f, 8.0 * scale_f, gold, 0.20);
        c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
        c.cairo_move_to(cr, preview_label_x, content_top + content_h * 0.5 + preview_extents.height * 0.5);
        showTextZ(cr, preview_label);
    }

    fn drawMiddle(self: *FilesWidget, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, scale_f: f64, text_color: [4]f64, muted_color: [4]f64) void {
        const row_h = 46.0 * scale_f;
        const visible_rows = @as(usize, @intFromFloat(@floor(h / row_h)));
        if (visible_rows == 0) return;

        const count = self.entries.items.len;
        if (count == 0) return;

        // Find the longest entry width to make all buttons the same size.
        var max_text_w: f64 = 0.0;
        for (self.entries.items) |entry| {
            const e = textExtents(cr, entry.name);
            if (e.width > max_text_w) max_text_w = e.width;
        }
        const button_w = max_text_w + 48.0 * scale_f;

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
            const button_x = x + (w - button_w) * 0.5;
            const is_selected = idx == self.selected_index;
            const button_h = row_h * 0.95;
            const button_y = row_y - button_h * 0.5;
            drawShadedButton(cr, button_x, button_y, button_w, button_h, 10.0 * scale_f, muted_color, if (is_selected) 0.40 else 0.20);
            if (is_selected) {
                c.cairo_set_source_rgba(cr, text_color[0], text_color[1], text_color[2], text_color[3]);
            } else {
                c.cairo_set_source_rgba(cr, muted_color[0], muted_color[1], muted_color[2], muted_color[3]);
            }
            c.cairo_move_to(cr, text_x, button_y + button_h * 0.5 + extents.height * 0.35);
            showTextZ(cr, entry.name);
        }
    }
};

fn isDir(path: []const u8) bool {
    var path_z: [1024]u8 = undefined;
    const nt = std.fmt.bufPrintZ(&path_z, "{s}", .{path}) catch return false;
    var stat_buf: c_std.struct_stat = undefined;
    if (c_std.stat(nt.ptr, &stat_buf) != 0) return false;
    return (stat_buf.st_mode & c_std.S_IFMT) == c_std.S_IFDIR;
}

fn drawShadedButton(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64, border: [4]f64, fill_alpha: f64) void {
    // 90% dark grey / near-black button background.
    roundedRect(cr, x, y, w, h, r);
    c.cairo_set_source_rgba(cr, 0.06, 0.06, 0.06, 0.90);
    c.cairo_fill_preserve(cr);
    // Inner shading gradient for depth.
    const grad = c.cairo_pattern_create_linear(x, y, x, y + h);
    defer c.cairo_pattern_destroy(grad);
    c.cairo_pattern_add_color_stop_rgba(grad, 0.0, 0.10, 0.10, 0.10, 0.55);
    c.cairo_pattern_add_color_stop_rgba(grad, 0.5, 0.06, 0.06, 0.06, 0.20);
    c.cairo_pattern_add_color_stop_rgba(grad, 1.0, 0.02, 0.02, 0.02, 0.55);
    c.cairo_set_source(cr, grad);
    c.cairo_fill_preserve(cr);
    // Goldy border.
    c.cairo_set_source_rgba(cr, border[0], border[1], border[2], border[3]);
    c.cairo_set_line_width(cr, 1.0);
    c.cairo_stroke(cr);
    // Subtle top highlight rim.
    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, x + w - r, y + r, r, -std.math.pi / 2.0, 0.0);
    c.cairo_arc(cr, x + r, y + r, r, -std.math.pi, -std.math.pi / 2.0);
    c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.25);
    c.cairo_set_line_width(cr, 1.0);
    c.cairo_stroke(cr);
    _ = fill_alpha;
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

fn textExtents(cr: *c.cairo_t, text: []const u8) c.cairo_text_extents_t {
    var ext: c.cairo_text_extents_t = undefined;
    var buf: [1024]u8 = undefined;
    const nt = std.fmt.bufPrintZ(&buf, "{s}", .{text}) catch blk: {
        const len = @min(text.len, buf.len - 1);
        @memcpy(buf[0..len], text[0..len]);
        buf[len] = 0;
        break :blk buf[0..len :0];
    };
    c.cairo_text_extents(cr, nt.ptr, &ext);
    return ext;
}

fn showTextZ(cr: *c.cairo_t, text: []const u8) void {
    var buf: [1024]u8 = undefined;
    const nt = std.fmt.bufPrintZ(&buf, "{s}", .{text}) catch blk: {
        const len = @min(text.len, buf.len - 1);
        @memcpy(buf[0..len], text[0..len]);
        buf[len] = 0;
        break :blk buf[0..len :0];
    };
    c.cairo_show_text(cr, nt.ptr);
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
