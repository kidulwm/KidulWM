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
    size: u64 = 0,
    mtime: i64 = 0,
};

pub const Drive = struct {
    label: []const u8,
    mount: []const u8,
};

pub const FilesWidget = struct {
    allocator: std.mem.Allocator,
    card: FilesCard = .{},
    current_path: []const u8 = "/home/kidul",
    path_history: std.ArrayList([]const u8),
    history_index: usize = 0,
    entries: std.ArrayList(Entry),
    drives: std.ArrayList(Drive),
    selected_index: usize = 0,
    scroll_offset: usize = 0,
    preview_path: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) FilesWidget {
        const current_path = allocator.dupe(u8, "/home/kidul") catch "/home/kidul";
        var path_history = std.ArrayList([]const u8).empty;
        path_history.append(allocator, current_path) catch {};
        return .{
            .allocator = allocator,
            .current_path = current_path,
            .path_history = path_history,
            .entries = .empty,
            .drives = .empty,
        };
    }

    pub fn deinit(self: *FilesWidget) void {
        self.clearEntries();
        self.clearDrives();
        self.entries.deinit(self.allocator);
        self.drives.deinit(self.allocator);
        for (self.path_history.items) |p| {
            if (p.ptr != self.current_path.ptr) self.allocator.free(p);
        }
        self.path_history.deinit(self.allocator);
        if (self.preview_path) |pp| self.allocator.free(pp);
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

    pub fn handleClick(self: *FilesWidget, lx: f64, ly: f64, w_d: f64, h_d: f64, scale: f32) bool {
        const scale_f: f64 = @floatCast(scale);
        const pad: f64 = 18.0 * scale_f;
        const gap: f64 = 10.0 * scale_f;
        const header_h: f64 = 34.0 * scale_f;
        const pill_h: f64 = header_h;
        const content_top: f64 = pad + pill_h + gap;
        const content_h: f64 = h_d - content_top - pad;
        const content_w: f64 = w_d - 2.0 * pad;
        const list_w = content_w * 0.55;
        const list_x = pad;
        const preview_x = list_x + list_w + gap;
        const preview_w = content_w * 0.45 - gap;
        const list_body_y = content_top + header_h + gap;
        const list_body_h = content_h - header_h - gap;

        // Click on the preview pane is consumed but does nothing else.
        if (lx >= preview_x and lx < preview_x + preview_w and ly >= content_top and ly < content_top + content_h) {
            return true;
        }

        if (lx < list_x or ly < list_body_y or lx > list_x + list_w or ly > list_body_y + list_body_h) return false;

        const row_h = 34.0 * scale_f;
        const row = @as(usize, @intFromFloat(@floor((ly - list_body_y) / row_h)));
        const visible_rows = @as(usize, @intFromFloat(@floor(list_body_h / row_h)));
        if (row >= visible_rows) return false;

        const start = self.scroll_offset;
        const idx = start + row;
        if (idx >= self.entries.items.len) return false;

        self.selected_index = idx;
        self.updatePreview();
        const entry = self.entries.items[idx];
        if (entry.is_dir) {
            const new_path = std.fs.path.join(self.allocator, &.{ self.current_path, entry.name }) catch return true;
            self.navigateTo(new_path);
        }
        return true;
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
        self.updatePreview();
    }

    pub fn activateSelected(self: *FilesWidget) void {
        if (self.selected_index >= self.entries.items.len) return;
        const entry = self.entries.items[self.selected_index];
        if (entry.is_dir) {
            const new_path = std.fs.path.join(self.allocator, &.{ self.current_path, entry.name }) catch return;
            self.navigateTo(new_path);
        } else {
            self.updatePreview();
        }
    }

    pub fn goUp(self: *FilesWidget) void {
        const parent = std.fs.path.dirname(self.current_path) orelse return;
        self.navigateTo(parent);
    }

    pub fn navigateBack(self: *FilesWidget) void {
        if (self.history_index > 0) {
            self.history_index -= 1;
            self.setCurrentPath(self.path_history.items[self.history_index]);
        }
    }

    pub fn navigateForward(self: *FilesWidget) void {
        if (self.history_index + 1 < self.path_history.items.len) {
            self.history_index += 1;
            self.setCurrentPath(self.path_history.items[self.history_index]);
        }
    }

    fn navigateTo(self: *FilesWidget, path: []const u8) void {
        const path_copy = self.allocator.dupe(u8, path) catch return;
        // Truncate forward history if we branched.
        while (self.path_history.items.len > self.history_index + 1) {
            const old = self.path_history.pop() orelse break;
            self.allocator.free(old);
        }
        self.path_history.append(self.allocator, path_copy) catch {
            self.allocator.free(path_copy);
            return;
        };
        self.history_index = self.path_history.items.len - 1;
        self.setCurrentPath(path_copy);
    }

    fn setCurrentPath(self: *FilesWidget, path: []const u8) void {
        if (self.current_path.ptr != "/home/kidul".ptr) {
            self.allocator.free(self.current_path);
        }
        self.current_path = path;
        self.selected_index = 0;
        self.scroll_offset = 0;
        self.loadDirectory(self.current_path) catch {};
        self.updatePreview();
    }

    fn updatePreview(self: *FilesWidget) void {
        if (self.preview_path) |pp| {
            self.allocator.free(pp);
            self.preview_path = null;
        }
        if (self.selected_index >= self.entries.items.len) return;
        const entry = self.entries.items[self.selected_index];
        if (entry.is_dir) return;
        const full = std.fs.path.join(self.allocator, &.{ self.current_path, entry.name }) catch return;
        self.preview_path = full;
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
    }

    pub fn renderCard(self: *FilesWidget, cr: *c.cairo_t, w_d: f64, h_d: f64, style_: style.Style, scale: f32) void {
        const scale_f: f64 = @floatCast(scale);
        const gold = style_.color_border_focused.toF64();
        const muted = style_.color_text_muted.toF64();
        const text = style_.tray_text_focused_color.toF64();
        const font_size = 22.0 * scale_f;
        const header_size = 18.0 * scale_f;

        // The shared card mat already painted the background/border with system corners.
        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);

        const pad: f64 = 18.0 * scale_f;
        const gap: f64 = 10.0 * scale_f;
        const header_h: f64 = 34.0 * scale_f;

        // Drive pills at top.
        const pill_h: f64 = header_h;
        var pill_x: f64 = pad;
        for (self.drives.items) |drive| {
            c.cairo_set_font_size(cr, header_size);
            const extents = textExtents(cr, drive.label);
            const pill_w = extents.width + 24.0 * scale_f;
            if (pill_x + pill_w > w_d - pad) break;
            drawShadedButton(cr, pill_x, pad, pill_w, pill_h, pill_h * 0.25, gold, 0.30);
            c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
            c.cairo_move_to(cr, pill_x + (pill_w - extents.width) * 0.5, pad + (pill_h + extents.height) * 0.5 - 4.0 * scale_f);
            showTextZ(cr, drive.label);
            pill_x += pill_w + gap;
        }

        const content_top: f64 = pad + pill_h + gap;
        const content_h: f64 = h_d - content_top - pad;
        const content_w: f64 = w_d - 2.0 * pad;

        // Two panes: left file list ~55%, right preview ~45%.
        const list_w = content_w * 0.55;
        const preview_w = content_w * 0.45 - gap;
        const list_x = pad;
        const preview_x = list_x + list_w + gap;

        // Left file list panel.
        drawPanel(cr, list_x, content_top, list_w, content_h, style_, gold);
        self.drawBreadcrumbs(cr, list_x, content_top, list_w, header_h, scale_f, gold, muted);
        const list_body_y = content_top + header_h + gap;
        const list_body_h = content_h - header_h - gap;
        self.drawFileList(cr, list_x, list_body_y, list_w, list_body_h, scale_f, font_size, gold, muted, text);

        // Right preview panel.
        drawPanel(cr, preview_x, content_top, preview_w, content_h, style_, gold);
        self.drawPreview(cr, preview_x, content_top, preview_w, content_h, scale_f, font_size, muted, text);
    }

    fn drawPanel(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, tstyle: style.Style, border: [4]f64) void {
        switch (tstyle.corner_style) {
            .round => roundedRect(cr, x, y, w, h, 12.0),
            .chamfer => chamferedRect(cr, x, y, w, h, 12.0),
            .square => c.cairo_rectangle(cr, x, y, w, h),
        }
        c.cairo_set_source_rgba(cr, 0.04, 0.04, 0.04, 0.70);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.35);
        c.cairo_set_line_width(cr, 1.0);
        c.cairo_stroke(cr);
    }

    fn drawBreadcrumbs(self: *FilesWidget, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, scale_f: f64, gold: [4]f64, muted: [4]f64) void {
        _ = w;
        var parts_buf: [16][]const u8 = undefined;
        const parts = breadcrumbParts(self.current_path, &parts_buf);
        var bx: f64 = x + 8.0 * scale_f;
        const by = y + h * 0.5;
        c.cairo_set_font_size(cr, 14.0 * scale_f);
        for (parts, 0..) |part, i| {
            const extents = textExtents(cr, part);
            const is_last = i == parts.len - 1;
            c.cairo_set_source_rgba(cr, if (is_last) gold[0] else muted[0], if (is_last) gold[1] else muted[1], if (is_last) gold[2] else muted[2], if (is_last) gold[3] else muted[3]);
            c.cairo_move_to(cr, bx, by + extents.height * 0.35);
            showTextZ(cr, part);
            bx += extents.width + 8.0 * scale_f;
            if (!is_last) {
                c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
                c.cairo_move_to(cr, bx, by + extents.height * 0.35);
                showTextZ(cr, "/");
                bx += extents.width + 8.0 * scale_f;
            }
        }
    }

    fn drawFileList(self: *FilesWidget, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, scale_f: f64, font_size: f64, gold: [4]f64, muted: [4]f64, text_color: [4]f64) void {
        c.cairo_set_font_size(cr, font_size);
        const row_h = 34.0 * scale_f;
        const visible_rows = @as(usize, @intFromFloat(@floor(h / row_h)));
        if (visible_rows == 0) return;

        const count = self.entries.items.len;
        if (count == 0) {
            c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
            const empty = "empty";
            const ext = textExtents(cr, empty);
            c.cairo_move_to(cr, x + (w - ext.width) * 0.5, y + h * 0.5);
            showTextZ(cr, empty);
            return;
        }

        const target = @min(self.selected_index, count - 1);
        var start: usize = 0;
        if (count > visible_rows) {
            const half = visible_rows / 2;
            if (target >= half) start = target - half;
            if (start + visible_rows > count) start = count - visible_rows;
        }
        self.scroll_offset = start;

        const margin = 8.0 * scale_f;
        const text_inset = 28.0 * scale_f;

        var i: usize = 0;
        while (i < visible_rows and start + i < count) : (i += 1) {
            const idx = start + i;
            const entry = self.entries.items[idx];
            const row_y = y + @as(f64, @floatFromInt(i)) * row_h;
            const is_selected = idx == self.selected_index;

            // Row background only on selected/hovered lines.
            if (is_selected) {
                roundedRect(cr, x + margin, row_y + 2.0 * scale_f, w - margin * 2.0, row_h - 4.0 * scale_f, 8.0 * scale_f);
                c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.15);
                c.cairo_fill_preserve(cr);
                c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.55);
                c.cairo_set_line_width(cr, 1.0);
                c.cairo_stroke(cr);
            }

            // Glyph: folder or file.
            const glyph = if (entry.is_dir) ">" else "-";
            c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], if (is_selected) gold[3] else muted[3]);
            c.cairo_move_to(cr, x + margin + 8.0 * scale_f, row_y + row_h * 0.5 + font_size * 0.35);
            showTextZ(cr, glyph);

            // Name, left-aligned.
            const name_color = if (entry.name[0] == '.') muted else text_color;
            c.cairo_set_source_rgba(cr, name_color[0], name_color[1], name_color[2], if (is_selected) text_color[3] else name_color[3]);
            c.cairo_move_to(cr, x + text_inset, row_y + row_h * 0.5 + font_size * 0.35);
            showTextZ(cr, entry.name);
        }

        // Scrollbar.
        if (count > visible_rows) {
            const track_h = h - 8.0 * scale_f;
            const thumb_h = track_h * (@as(f64, @floatFromInt(visible_rows)) / @as(f64, @floatFromInt(count)));
            const max_start = count - visible_rows;
            const thumb_y = y + 4.0 * scale_f + track_h * (@as(f64, @floatFromInt(start)) / @as(f64, @floatFromInt(max_start)));
            roundedRect(cr, x + w - 8.0 * scale_f, thumb_y, 4.0 * scale_f, thumb_h, 2.0 * scale_f);
            c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.45);
            c.cairo_fill(cr);
        }
    }

    fn drawPreview(self: *FilesWidget, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, scale_f: f64, font_size: f64, muted: [4]f64, text_color: [4]f64) void {
        const margin: f64 = 16.0 * scale_f;
        c.cairo_set_font_size(cr, font_size);
        if (self.preview_path) |pp| {
            const name = std.fs.path.basename(pp);
            const title = if (name.len > 0) name else "...";
            const ext = textExtents(cr, title);
            c.cairo_set_source_rgba(cr, text_color[0], text_color[1], text_color[2], text_color[3]);
            c.cairo_move_to(cr, x + margin, y + margin + ext.height);
            showTextZ(cr, title);

            // Preview content for text files.
            const preview = self.readPreviewText(pp, 1024) catch null;
            if (preview) |p| {
                defer self.allocator.free(p);
                c.cairo_set_font_size(cr, 13.0 * scale_f);
                const wrap_w = w - margin * 2.0;
                var lines = std.mem.splitAny(u8, p, "\n");
                var ly: f64 = y + margin + ext.height + 16.0 * scale_f;
                var line_count: usize = 0;
                while (lines.next()) |line| {
                    if (line_count >= 20) break;
                    const truncated = if (line.len > 80) line[0..80] else line;
                    const line_extent = textExtents(cr, truncated);
                    if (line_extent.width > wrap_w) {
                        // Simple truncation by character count estimate.
                        const chars = truncated.len;
                        const avg_w = line_extent.width / @as(f64, @floatFromInt(chars));
                        const max_chars: usize = @intFromFloat(wrap_w / avg_w);
                        const safe_len = if (max_chars > 3) max_chars - 3 else 0;
                        const safe_text = if (safe_len < truncated.len) truncated[0..safe_len] else truncated;
                        c.cairo_move_to(cr, x + margin, ly + 13.0 * scale_f);
                        showTextZ(cr, safe_text);
                        c.cairo_move_to(cr, x + margin + textExtents(cr, safe_text).width, ly + 13.0 * scale_f);
                        showTextZ(cr, "...");
                    } else {
                        c.cairo_move_to(cr, x + margin, ly + 13.0 * scale_f);
                        showTextZ(cr, truncated);
                    }
                    ly += 16.0 * scale_f;
                    line_count += 1;
                }
            } else {
                c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
                const nope = "no preview";
                const ne = textExtents(cr, nope);
                c.cairo_move_to(cr, x + margin, y + h * 0.5 + ne.height * 0.35);
                showTextZ(cr, nope);
            }
        } else {
            c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
            const hint = "select a file";
            const ext = textExtents(cr, hint);
            c.cairo_move_to(cr, x + (w - ext.width) * 0.5, y + h * 0.5 + ext.height * 0.35);
            showTextZ(cr, hint);
        }
    }

    fn readPreviewText(self: *FilesWidget, path: []const u8, max_bytes: usize) !?[]u8 {
        var path_z: [1024]u8 = undefined;
        const nt = std.fmt.bufPrintZ(&path_z, "{s}", .{path}) catch return null;
        const file = c_std.fopen(nt.ptr, "r") orelse return null;
        defer _ = c_std.fclose(file);
        var buf = std.ArrayList(u8).empty;
        var tmp: [1024]u8 = undefined;
        var total: usize = 0;
        while (c_std.fgets(&tmp, tmp.len, file) != null) {
            const len = std.mem.indexOfScalar(u8, &tmp, 0) orelse tmp.len;
            const line = tmp[0..len];
            try buf.appendSlice(self.allocator, line);
            total += len;
            if (total >= max_bytes) break;
        }
        return try buf.toOwnedSlice(self.allocator);
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
    roundedRect(cr, x, y, w, h, r);
    c.cairo_set_source_rgba(cr, 0.06, 0.06, 0.06, fill_alpha);
    c.cairo_fill_preserve(cr);
    c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.55);
    c.cairo_set_line_width(cr, 1.0);
    c.cairo_stroke(cr);
    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, x + w - r, y + r, r, -std.math.pi / 2.0, 0.0);
    c.cairo_arc(cr, x + r, y + r, r, -std.math.pi, -std.math.pi / 2.0);
    c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.25);
    c.cairo_set_line_width(cr, 1.0);
    c.cairo_stroke(cr);
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

fn chamferedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, ch: f64) void {
    const chamfer = @min(ch, w / 2.0, h / 2.0);
    c.cairo_new_sub_path(cr);
    c.cairo_move_to(cr, x + chamfer, y);
    c.cairo_line_to(cr, x + w - chamfer, y);
    c.cairo_line_to(cr, x + w, y + chamfer);
    c.cairo_line_to(cr, x + w, y + h - chamfer);
    c.cairo_line_to(cr, x + w - chamfer, y + h);
    c.cairo_line_to(cr, x + chamfer, y + h);
    c.cairo_line_to(cr, x, y + h - chamfer);
    c.cairo_line_to(cr, x, y + chamfer);
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

fn breadcrumbParts(path: []const u8, buf: *[16][]const u8) []const []const u8 {
    var it = std.mem.splitAny(u8, path, "/");
    if (path.len == 0 or std.mem.eql(u8, path, "/")) {
        buf[0] = "root";
        return buf[0..1];
    }
    var i: usize = 0;
    if (std.mem.eql(u8, path[0..1], "/") and i == 0) {
        buf[i] = "root";
        i += 1;
    }
    while (it.next()) |seg| {
        if (seg.len == 0) continue;
        if (i >= buf.len) break;
        buf[i] = seg;
        i += 1;
    }
    return buf[0..i];
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
