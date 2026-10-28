// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const c = @import("dm").c;
const c_std = @import("c");
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

pub const FocusArea = enum { pills, files, preview };

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
    state_generation: usize = 0,
    focus: FocusArea = .files,
    selected_drive: usize = 0,
    search_buf: [32]u8 = @splat(0),
    search_len: usize = 0,

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

    pub fn handleKey(self: *FilesWidget, sym: @import("xkbcommon").Keysym) bool {
        switch (self.focus) {
            .pills => return self.handlePillsKey(sym),
            .files => return self.handleFilesKey(sym),
            .preview => return self.handlePreviewKey(sym),
        }
    }

    fn handlePillsKey(self: *FilesWidget, sym: @import("xkbcommon").Keysym) bool {
        switch (sym) {
            .Left => {
                if (self.drives.items.len > 0) {
                    if (self.selected_drive > 0) self.selected_drive -= 1 else self.selected_drive = self.drives.items.len - 1;
                }
                self.state_generation +|= 1;
                return true;
            },
            .Right => {
                if (self.drives.items.len > 0) {
                    self.selected_drive = (self.selected_drive + 1) % self.drives.items.len;
                }
                self.state_generation +|= 1;
                return true;
            },
            .Down, .Return, .KP_Enter => {
                self.focus = .files;
                self.state_generation +|= 1;
                if (sym == @import("xkbcommon").Keysym.Return or sym == @import("xkbcommon").Keysym.KP_Enter) {
                    if (self.selected_drive < self.drives.items.len) {
                        self.navigateTo(self.drives.items[self.selected_drive].mount);
                    }
                }
                return true;
            },
            .Escape => return false,
            else => return false,
        }
    }

    fn handleFilesKey(self: *FilesWidget, sym: @import("xkbcommon").Keysym) bool {
        switch (sym) {
            .Up => {
                if (self.selected_index > 0) {
                    self.moveSelection(-1);
                } else {
                    self.focus = .pills;
                    self.state_generation +|= 1;
                }
                return true;
            },
            .Down => {
                const count = self.entries.items.len;
                if (count > 0 and self.selected_index + 1 < count) {
                    self.moveSelection(1);
                } else {
                    self.focus = .preview;
                    self.state_generation +|= 1;
                }
                return true;
            },
            .Right, .Return, .KP_Enter => {
                self.activateSelected();
                return true;
            },
            .Left, .BackSpace => {
                if (self.search_len > 0 and sym == @import("xkbcommon").Keysym.BackSpace) {
                    self.search_len -= 1;
                    self.search_buf[self.search_len] = 0;
                    self.state_generation +|= 1;
                    return true;
                }
                const parent = std.fs.path.dirname(self.current_path);
                if (parent != null and !std.mem.eql(u8, self.current_path, "/home/kidul")) {
                    self.goUp();
                } else {
                    return false;
                }
                return true;
            },
            .Home => {
                if (self.entries.items.len > 0) {
                    self.selected_index = 0;
                    self.updatePreview();
                    self.state_generation +|= 1;
                }
                return true;
            },
            .End => {
                if (self.entries.items.len > 0) {
                    self.selected_index = self.entries.items.len - 1;
                    self.updatePreview();
                    self.state_generation +|= 1;
                }
                return true;
            },
            .Page_Up => {
                const visible: isize = @max(1, @as(isize, @intCast(self.visibleRowsEstimate())));
                self.moveSelection(-visible);
                return true;
            },
            .Page_Down => {
                const visible: isize = @max(1, @as(isize, @intCast(self.visibleRowsEstimate())));
                self.moveSelection(visible);
                return true;
            },
            .Escape => {
                if (self.search_len > 0) {
                    self.search_len = 0;
                    self.search_buf[0] = 0;
                    self.state_generation +|= 1;
                    return true;
                }
                return false;
            },
            else => {
                const ch = keySymToChar(sym);
                if (ch != 0) {
                    if (self.search_len < self.search_buf.len - 1) {
                        self.search_buf[self.search_len] = ch;
                        self.search_len += 1;
                        self.search_buf[self.search_len] = 0;
                        self.jumpToSearchPrefix();
                    }
                    return true;
                }
                return false;
            },
        }
    }

    fn handlePreviewKey(self: *FilesWidget, sym: @import("xkbcommon").Keysym) bool {
        switch (sym) {
            .Up, .Left, .BackSpace => {
                self.focus = .files;
                self.state_generation +|= 1;
                return true;
            },
            else => return false,
        }
    }

    fn keySymToChar(sym: @import("xkbcommon").Keysym) u8 {
        const v = @intFromEnum(sym);
        const xkb = @import("xkbcommon");
        if (v >= @intFromEnum(xkb.Keysym.a) and v <= @intFromEnum(xkb.Keysym.z)) {
            return @as(u8, @intCast(v - @intFromEnum(xkb.Keysym.a))) + 'a';
        }
        if (v >= @intFromEnum(xkb.Keysym.A) and v <= @intFromEnum(xkb.Keysym.Z)) {
            return @as(u8, @intCast(v - @intFromEnum(xkb.Keysym.A))) + 'A';
        }
        if (v >= @intFromEnum(xkb.Keysym.@"0") and v <= @intFromEnum(xkb.Keysym.@"9")) {
            return @as(u8, @intCast(v - @intFromEnum(xkb.Keysym.@"0"))) + '0';
        }
        return 0;
    }

    fn jumpToSearchPrefix(self: *FilesWidget) void {
        const needle = self.search_buf[0..self.search_len];
        for (self.entries.items, 0..) |entry, i| {
            if (entry.name.len >= needle.len and std.mem.startsWith(u8, entry.name, needle)) {
                self.selected_index = i;
                self.updatePreview();
                self.state_generation +|= 1;
                return;
            }
        }
        self.state_generation +|= 1;
    }

    fn visibleRowsEstimate(self: *FilesWidget) usize {
        _ = self;
        return 6;
    }

    pub fn handleClick(self: *FilesWidget, lx: f64, ly: f64, w_d: f64, h_d: f64, scale: f32) bool {
        _ = self;
        _ = lx; _ = ly; _ = w_d; _ = h_d; _ = scale;
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
        self.state_generation +|= 1;
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
        self.state_generation +|= 1;
    }

    pub fn goUp(self: *FilesWidget) void {
        const parent = std.fs.path.dirname(self.current_path) orelse return;
        self.navigateTo(parent);
        self.state_generation +|= 1;
    }

    pub fn navigateBack(self: *FilesWidget) void {
        if (self.history_index > 0) {
            self.history_index -= 1;
            self.setCurrentPath(self.path_history.items[self.history_index]);
        }
        self.state_generation +|= 1;
    }

    pub fn navigateForward(self: *FilesWidget) void {
        if (self.history_index + 1 < self.path_history.items.len) {
            self.history_index += 1;
            self.setCurrentPath(self.path_history.items[self.history_index]);
        }
        self.state_generation +|= 1;
    }

    fn navigateTo(self: *FilesWidget, path: []const u8) void {
        const path_copy = self.allocator.dupe(u8, path) catch return;
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
        self.state_generation +|= 1;
    }

    fn setCurrentPath(self: *FilesWidget, path: []const u8) void {
        if (self.current_path.ptr != "/home/kidul".ptr) {
            self.allocator.free(self.current_path);
        }
        self.current_path = path;
        self.selected_index = 0;
        self.scroll_offset = 0;
        self.search_len = 0;
        self.search_buf[0] = 0;
        self.loadDirectory(self.current_path) catch {};
        self.updatePreview();
        self.state_generation +|= 1;
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
        const nt = std.fmt.bufPrintSentinel(&path_z, "{s}", .{path}, 0) catch return;
        const dir = c_std.opendir(nt.ptr) orelse return;
        defer _ = c_std.closedir(dir);
        while (true) {
            const entry = c_std.readdir(dir) orelse break;
            const name_ptr: [*:0]u8 = @ptrCast(@as([*c]u8, @ptrCast(&entry.*.d_name)));
            const name = std.mem.span(name_ptr);
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            const full_path = std.fs.path.join(self.allocator, &.{ path, name }) catch continue;
            defer self.allocator.free(full_path);
            const is_dir = isDir(full_path);
            var stat_buf: c_std.struct_stat = undefined;
            var size: u64 = 0;
            var mtime: i64 = 0;
            if (c_std.stat(full_path.ptr, &stat_buf) == 0) {
                size = @intCast(stat_buf.st_size);
                mtime = stat_buf.st_mtim.tv_sec;
            }
            const name_copy = self.allocator.dupe(u8, name) catch continue;
            self.entries.append(self.allocator, .{ .name = name_copy, .is_dir = is_dir, .size = size, .mtime = mtime }) catch {
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

        // Full slide: fill background with card mat color.
        const bg4 = style_.color_card_mat.toF64();
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], 0.91);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);

        const pad: f64 = 18.0 * scale_f;
        const gap: f64 = 10.0 * scale_f;
        const pill_h: f64 = 34.0 * scale_f;
        const search_h: f64 = 34.0 * scale_f;
        const button_h: f64 = 44.0 * scale_f;
        const min_preview_h: f64 = 120.0 * scale_f;
        const max_preview_h: f64 = 260.0 * scale_f;
        const content_w: f64 = w_d - 2.0 * pad;

        // Focused pane spans the full card width.
        const files_w = content_w;
        const files_x = pad;
        const available_h: f64 = h_d - pad - pad;

        // Layout: pills -> search -> file buttons -> preview.
        const pills_y: f64 = pad;
        const search_y: f64 = pills_y + pill_h + gap;
        const files_y: f64 = search_y + search_h + gap;
        const files_available_h: f64 = available_h - (files_y - pad) - min_preview_h - gap;
        const desired_files_h = if (self.entries.items.len == 0)
            button_h
        else
            @as(f64, @floatFromInt(self.entries.items.len)) * (button_h + gap) - gap;
        var files_h: f64 = @min(desired_files_h, files_available_h);
        if (files_h < button_h) files_h = button_h;
        var preview_h: f64 = available_h - (files_y + files_h) - pad;
        if (preview_h < min_preview_h) {
            preview_h = min_preview_h;
            files_h = available_h - (files_y + files_h - files_h) - preview_h - pad;
        }
        if (preview_h > max_preview_h) preview_h = max_preview_h;
        const preview_y: f64 = h_d - pad - preview_h;
        files_h = preview_y - files_y - gap;

        self.drawPills(cr, files_x, pills_y, files_w, pill_h, scale_f, headerSizeFor(font_size), gold, muted, text);
        self.drawSearch(cr, files_x, search_y, files_w, search_h, scale_f, font_size, muted, text);

        // Card-like background + focused border for the file list.
        const border_color = gold;
        const fill_color = [_]f64{ 0.04, 0.04, 0.04, 0.90 };
        roundedRect(cr, files_x, files_y, files_w, files_h, 12.0);
        c.cairo_set_source_rgba(cr, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, border_color[0], border_color[1], border_color[2], if (self.focus == .files) 0.70 else 0.35);
        c.cairo_set_line_width(cr, 1.5);
        c.cairo_stroke(cr);

        self.drawFileButtons(cr, files_x, files_y, files_w, files_h, scale_f, font_size, gold, muted, text);
        self.drawPreview(cr, files_x, preview_y, files_w, preview_h, scale_f, font_size, muted, text);
    }

    fn drawPills(self: *FilesWidget, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, scale_f: f64, header_size: f64, gold: [4]f64, muted: [4]f64, text_color: [4]f64) void {
        c.cairo_set_font_size(cr, header_size);
        var total_w: f64 = 0.0;
        for (self.drives.items) |drive| {
            const ext = textExtents(cr, drive.label);
            total_w += ext.width + 24.0 * scale_f;
        }
        if (self.drives.items.len > 0) total_w += (@as(f64, @floatFromInt(self.drives.items.len)) - 1.0) * 10.0 * scale_f;
        var start_x = x + (w - total_w) * 0.5;
        if (start_x < x) start_x = x;
        var pill_x = start_x;
        for (self.drives.items, 0..) |drive, i| {
            const ext = textExtents(cr, drive.label);
            const pill_w = ext.width + 24.0 * scale_f;
            const is_focused = (self.focus == .pills and i == self.selected_drive);
            const is_current = std.mem.eql(u8, self.current_path, drive.mount);
            if (is_focused) {
                drawShadedButton(cr, pill_x, y, pill_w, h, h * 0.25, gold, 0.55);
            } else if (is_current) {
                drawShadedButton(cr, pill_x, y, pill_w, h, h * 0.25, gold, 0.35);
            } else {
                drawShadedButton(cr, pill_x, y, pill_w, h, h * 0.25, gold, 0.20);
            }
            c.cairo_set_source_rgba(cr, text_color[0], text_color[1], text_color[2], if (is_focused or is_current) text_color[3] else muted[3]);
            c.cairo_move_to(cr, pill_x + (pill_w - ext.width) * 0.5, y + (h + ext.height) * 0.5 - 4.0 * scale_f);
            showTextZ(cr, drive.label);
            pill_x += pill_w + 10.0 * scale_f;
        }
    }

    fn drawSearch(self: *FilesWidget, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, scale_f: f64, font_size: f64, muted: [4]f64, text_color: [4]f64) void {
        roundedRect(cr, x, y, w, h, 8.0);
        c.cairo_set_source_rgba(cr, 0.04, 0.04, 0.04, 0.60);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.25);
        c.cairo_set_line_width(cr, 1.0);
        c.cairo_stroke(cr);
        c.cairo_set_font_size(cr, font_size);
        const label = if (self.search_len > 0) self.search_buf[0..self.search_len] else "search";
        const ext = textExtents(cr, label);
        c.cairo_set_source_rgba(cr, if (self.search_len > 0) text_color[0] else muted[0], if (self.search_len > 0) text_color[1] else muted[1], if (self.search_len > 0) text_color[2] else muted[2], if (self.search_len > 0) text_color[3] else muted[3]);
        c.cairo_move_to(cr, x + 12.0 * scale_f, y + (h + ext.height) * 0.5 - 4.0 * scale_f);
        showTextZ(cr, label);
    }

    fn drawFileButtons(self: *FilesWidget, cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, scale_f: f64, font_size: f64, gold: [4]f64, muted: [4]f64, text_color: [4]f64) void {
        c.cairo_set_font_size(cr, font_size);
        const row_h = 44.0 * scale_f;
        const visible_rows = @as(usize, @intFromFloat(@max(1.0, @floor(h / row_h))));
        const count = self.entries.items.len;

        const target = @min(self.selected_index, if (count > 0) count - 1 else 0);
        var start = self.scroll_offset;
        if (count > visible_rows) {
            const half = visible_rows / 2;
            if (target >= half) start = target - half;
            if (start + visible_rows > count) start = count - visible_rows;
        }
        self.scroll_offset = start;

        if (count == 0) {
            c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
            const empty = "empty";
            const ext = textExtents(cr, empty);
            c.cairo_move_to(cr, x + (w - ext.width) * 0.5, y + h * 0.5);
            showTextZ(cr, empty);
            return;
        }

        const row_margin: f64 = 8.0 * scale_f;
        const selected_push: f64 = 18.0 * scale_f;
        const highlight_right_buffer: f64 = 10.0 * scale_f;
        const meta_inset_chars: f64 = 2.0 * font_size;

        var i: usize = 0;
        while (i < visible_rows and start + i < count) : (i += 1) {
            const idx = start + i;
            const entry = self.entries.items[idx];
            const row_y = y + @as(f64, @floatFromInt(i)) * row_h;
            const is_selected = (idx == self.selected_index and self.focus == .files);
            const highlight_left = x + row_margin + selected_push;
            const highlight_right = x + w - highlight_right_buffer;
            const highlight_w = highlight_right - highlight_left;

            if (is_selected) {
                roundedRect(cr, highlight_left, row_y + 4.0 * scale_f, highlight_w, row_h - 8.0 * scale_f, 8.0 * scale_f);
                c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.20);
                c.cairo_fill_preserve(cr);
                c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.60);
                c.cairo_set_line_width(cr, 1.0);
                c.cairo_stroke(cr);
            }

            const name_color = if (entry.name[0] == '.') muted else text_color;
            c.cairo_set_source_rgba(cr, name_color[0], name_color[1], name_color[2], name_color[3]);
            c.cairo_set_font_size(cr, font_size);
            const name_ext = textExtents(cr, entry.name);
            const text_x = x + (w - name_ext.width) * 0.5 + (if (is_selected) selected_push else 0.0);
            c.cairo_move_to(cr, text_x, row_y + row_h * 0.5 + font_size * 0.35);
            showTextZ(cr, entry.name);

            // Date on the left, extension badge on the right, only on the highlighted line.
            if (is_selected) {
                c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
                const date_str = formatDate(@intCast(entry.mtime));
                const date_x = highlight_left + meta_inset_chars;
                c.cairo_move_to(cr, date_x, row_y + row_h * 0.5 + font_size * 0.35);
                showTextZ(cr, date_str);

                if (!entry.is_dir) {
                    const ext = extensionOf(entry.name);
                    if (ext.len > 0) {
                        const ext_ext = textExtents(cr, ext);
                        const ext_x = highlight_right - meta_inset_chars - ext_ext.width;
                        c.cairo_move_to(cr, ext_x, row_y + row_h * 0.5 + font_size * 0.35);
                        showTextZ(cr, ext);
                    }
                }
            }
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
        _ = font_size;
        // If a folder is selected, show a large stylised folder icon.
        if (self.selected_index < self.entries.items.len and self.entries.items[self.selected_index].is_dir) {
            drawFolderIcon(cr, x, y, w, h, scale_f, text_color, muted);
            return;
        }

        // For files, the preview pane is intentionally left blank — files open in their assigned app.
        // Draw a very subtle hint only when focused.
        if (self.focus == .preview) {
            c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
            const hint = "press Enter to open";
            const ext = textExtents(cr, hint);
            c.cairo_move_to(cr, x + (w - ext.width) * 0.5, y + h * 0.5 + ext.height * 0.35);
            showTextZ(cr, hint);
        }
    }
    fn readPreviewText(self: *FilesWidget, path: []const u8, max_bytes: usize) !?[]u8 {
        var path_z: [1024]u8 = undefined;
        const nt = std.fmt.bufPrintSentinel(&path_z, "{s}", .{path}, 0) catch return null;
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

fn drawFolderIcon(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, scale_f: f64, text_color: [4]f64, muted: [4]f64) void {
    _ = text_color;
    // Manila folder icon: horizontal, thin-line, muted-gold, with inside border-color shading.
    const cx = x + w * 0.5;
    const cy = y + h * 0.5;
    const folder_h = h * 0.92;
    const folder_w = folder_h * 1.35;
    const tab_h = folder_h * 0.20;
    const round = 10.0 * scale_f;
    const line_w = 1.5 * scale_f;
    const shade = 0.10;

    const fx = cx - folder_w * 0.5;
    const fy = cy - folder_h * 0.5;

    folderIconPath(cr, fx, fy, folder_w, folder_h, round, tab_h);
    c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], shade);
    c.cairo_fill_preserve(cr);
    c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.70);
    c.cairo_set_line_width(cr, line_w);
    c.cairo_stroke(cr);
}

fn folderIconPath(cr: *c.cairo_t, fx: f64, fy: f64, fw: f64, fh: f64, r: f64, tab_h: f64) void {
    c.cairo_new_sub_path(cr);
    c.cairo_move_to(cr, fx + r, fy + tab_h);
    c.cairo_line_to(cr, fx + fw * 0.32, fy + tab_h);
    c.cairo_line_to(cr, fx + fw * 0.40, fy + tab_h * 0.60);
    c.cairo_line_to(cr, fx + fw * 0.60, fy + tab_h * 0.60);
    c.cairo_line_to(cr, fx + fw * 0.68, fy + tab_h);
    c.cairo_line_to(cr, fx + fw - r, fy + tab_h);
    c.cairo_arc(cr, fx + fw - r, fy + tab_h + r, r, -std.math.pi / 2.0, 0.0);
    c.cairo_line_to(cr, fx + fw, fy + fh - r);
    c.cairo_arc(cr, fx + fw - r, fy + fh - r, r, 0.0, std.math.pi / 2.0);
    c.cairo_line_to(cr, fx + r, fy + fh);
    c.cairo_arc(cr, fx + r, fy + fh - r, r, std.math.pi / 2.0, std.math.pi);
    c.cairo_line_to(cr, fx, fy + tab_h + r);
    c.cairo_arc(cr, fx + r, fy + tab_h + r, r, std.math.pi, 3.0 * std.math.pi / 2.0);
    c.cairo_close_path(cr);
}

fn drawFileIcon(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, scale_f: f64, text_color: [4]f64, muted: [4]f64) void {
    _ = text_color;
    // A4 file icon: vertical, thin-line, muted-gold, with inside border-color shading.
    const cx = x + w * 0.5;
    const cy = y + h * 0.5;
    const file_h = h * 0.85;
    const file_w = file_h * 0.75;
    const round = 8.0 * scale_f;
    const line_w = 1.5 * scale_f;
    const shade = 0.10;

    const fx = cx - file_w * 0.5;
    const fy = cy - file_h * 0.5;

    // Main body with folded corner.
    fileIconPath(cr, fx, fy, file_w, file_h, round);
    c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], shade);
    c.cairo_fill_preserve(cr);
    c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.75);
    c.cairo_set_line_width(cr, line_w);
    c.cairo_stroke(cr);

    // Folded corner line.
    c.cairo_move_to(cr, fx + file_w * 0.65, fy);
    c.cairo_line_to(cr, fx + file_w * 0.65, fy + file_h * 0.12);
    c.cairo_line_to(cr, fx + file_w, fy + file_h * 0.12);
    c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.55);
    c.cairo_set_line_width(cr, line_w);
    c.cairo_stroke(cr);
}

fn fileIconPath(cr: *c.cairo_t, fx: f64, fy: f64, fw: f64, fh: f64, r: f64) void {
    const fold_x = fx + fw * 0.65;
    const fold_y = fy + fh * 0.12;
    c.cairo_new_sub_path(cr);
    c.cairo_move_to(cr, fx, fy + r);
    c.cairo_line_to(cr, fx, fy + fh - r);
    c.cairo_arc(cr, fx + r, fy + fh - r, r, std.math.pi, std.math.pi / 2.0);
    c.cairo_line_to(cr, fx + fw - r, fy + fh);
    c.cairo_arc(cr, fx + fw - r, fy + fh - r, r, std.math.pi / 2.0, 0.0);
    c.cairo_line_to(cr, fx + fw, fy + fold_y + r);
    c.cairo_arc(cr, fx + fw - r, fy + fold_y + r, r, 0.0, -std.math.pi / 2.0);
    c.cairo_line_to(cr, fold_x + r, fy + fold_y);
    c.cairo_line_to(cr, fold_x, fy + fold_y);
    c.cairo_line_to(cr, fold_x, fy + r);
    c.cairo_arc(cr, fx + r, fy + r, r, -std.math.pi / 2.0, std.math.pi);
    c.cairo_close_path(cr);
}


fn headerSizeFor(font_size: f64) f64 {
    return font_size * 0.82;
}

var date_buf: [32]u8 = undefined;
var size_buf: [32]u8 = undefined;

fn extensionOf(name: []const u8) []const u8 {
    const idx = std.mem.lastIndexOfScalar(u8, name, '.') orelse return "";
    if (idx == 0 or idx + 1 >= name.len) return "";
    return name[idx + 1 ..];
}

fn formatDate(mtime: i64) []const u8 {
    const t: c_std.time_t = @intCast(mtime);
    const tm = c_std.localtime(&t) orelse return "-";
    const len = c_std.strftime(&date_buf, date_buf.len, "%b %d", tm);
    if (len == 0) return "-";
    return date_buf[0..len];
}

fn formatSize(size: u64) []const u8 {
    if (size < 1024) return std.fmt.bufPrint(&size_buf, "{d}B", .{size}) catch "?";
    if (size < 1024 * 1024) return std.fmt.bufPrint(&size_buf, "{d:.1}K", .{@as(f64, @floatFromInt(size)) / 1024.0}) catch "?";
    if (size < 1024 * 1024 * 1024) return std.fmt.bufPrint(&size_buf, "{d:.1}M", .{@as(f64, @floatFromInt(size)) / (1024.0 * 1024.0)}) catch "?";
    return std.fmt.bufPrint(&size_buf, "{d:.1}G", .{@as(f64, @floatFromInt(size)) / (1024.0 * 1024.0 * 1024.0)}) catch "?";
}

fn isDir(path: []const u8) bool {
    var path_z: [1024]u8 = undefined;
    const nt = std.fmt.bufPrintSentinel(&path_z, "{s}", .{path}, 0) catch return false;
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
    const nt = std.fmt.bufPrintSentinel(&buf, "{s}", .{text}, 0) catch blk: {
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
    const nt = std.fmt.bufPrintSentinel(&buf, "{s}", .{text}, 0) catch blk: {
        const len = @min(text.len, buf.len - 1);
        @memcpy(buf[0..len], text[0..len]);
        buf[len] = 0;
        break :blk buf[0..len :0];
    };
    c.cairo_show_text(cr, nt.ptr);
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
