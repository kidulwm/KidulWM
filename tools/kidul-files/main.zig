const std = @import("std");

// Kidul Files TUI — first-cut Zig file manager.
// Arrow-key navigation, drive pills, friendly path labels, sudo-gated root.

const c = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("dirent.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/ioctl.h");
    @cInclude("termios.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("signal.h");
    @cInclude("sys/wait.h");
});

const Drive = struct {
    name: []const u8,
    path: []const u8,
};

const Entry = struct {
    name: []const u8,
    path: []const u8,
    is_dir: bool,
    size: u64,
};

const App = struct {
    allocator: std.mem.Allocator,
    drives: std.ArrayList(Drive),
    entries: std.ArrayList(Entry),
    current_path: []const u8,
    selected_drive: usize,
    selected_index: usize,
    scroll_offset: usize,
    preview_text: std.ArrayList(u8),
    running: bool,
    term_w: usize,
    term_h: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, start_path: ?[]const u8) !Self {
        var drives = std.ArrayList(Drive).empty;
        try discoverDrives(allocator, &drives);

        const home_env = c.getenv("HOME");
        const home_path: []const u8 = if (home_env != null and home_env[0] != 0)
            std.mem.sliceTo(home_env, 0)
        else
            "/home";
        const current_path = if (start_path) |sp|
            try allocator.dupe(u8, sp)
        else
            try allocator.dupe(u8, home_path);

        var entries = std.ArrayList(Entry).empty;
        try loadEntries(allocator, current_path, &entries);

        return .{
            .allocator = allocator,
            .drives = drives,
            .entries = entries,
            .current_path = current_path,
            .selected_drive = 0,
            .selected_index = 0,
            .scroll_offset = 0,
            .preview_text = std.ArrayList(u8).empty,
            .running = true,
            .term_w = 80,
            .term_h = 24,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.drives.items) |d| {
            self.allocator.free(d.name);
            self.allocator.free(d.path);
        }
        self.drives.deinit(self.allocator);
        clearEntries(&self.entries, self.allocator);
        self.allocator.free(self.current_path);
        self.preview_text.deinit(self.allocator);
    }

    fn discoverDrives(allocator: std.mem.Allocator, drives: *std.ArrayList(Drive)) !void {
        const mounts = readFileAlloc(allocator, "/proc/self/mounts") catch return;
        defer allocator.free(mounts);

        const home_env = c.getenv("HOME");
        const home_path: []const u8 = if (home_env != null and home_env[0] != 0)
            std.mem.sliceTo(home_env, 0)
        else
            "/home";

        var lines = std.mem.splitAny(u8, mounts, "\n");
        var drive_idx: usize = 1;

        while (lines.next()) |line| {
            if (line.len == 0) continue;
            var it = std.mem.splitAny(u8, line, " ");
            _ = it.next(); // device
            const mount_point = it.next() orelse continue;
            const fs_type = it.next() orelse continue;

            if (isPseudoFs(fs_type)) continue;

            const name = if (std.mem.eql(u8, mount_point, "/"))
                try allocator.dupe(u8, "root")
            else if (std.mem.eql(u8, mount_point, home_path))
                try driveNameForHome(allocator, home_path)
            else if (std.mem.startsWith(u8, mount_point, home_path) and mount_point.len > home_path.len and mount_point[home_path.len] == '/')
                try driveNameForPath(allocator, mount_point)
            else if (isHomePath(mount_point))
                try allocator.dupe(u8, "home")
            else blk: {
                const n = try std.fmt.allocPrint(allocator, "drive{d}", .{drive_idx});
                drive_idx += 1;
                break :blk n;
            };

            try drives.append(allocator, .{ .name = name, .path = try allocator.dupe(u8, mount_point) });
        }

        if (drives.items.len == 0) {
            try drives.append(allocator, .{ .name = try allocator.dupe(u8, "home"), .path = try allocator.dupe(u8, "/home") });
        }
    }

    fn driveNameForHome(allocator: std.mem.Allocator, home_path: []const u8) ![]const u8 {
        const basename = std.fs.path.basename(home_path);
        if (basename.len > 0 and !std.mem.eql(u8, basename, "/")) {
            return toLower(allocator, basename);
        }
        return allocator.dupe(u8, "home");
    }

    fn driveNameForPath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
        const basename = std.fs.path.basename(path);
        if (basename.len > 0 and !std.mem.eql(u8, basename, "/")) {
            return toLower(allocator, basename);
        }
        return allocator.dupe(u8, "drive");
    }

    fn toLower(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
        const out = try allocator.alloc(u8, s.len);
        for (s, 0..) |ch, i| {
            out[i] = std.ascii.toLower(ch);
        }
        return out;
    }

    fn isPseudoFs(fs_type: []const u8) bool {
        const pseudo = [_][]const u8{ "tmpfs", "devtmpfs", "proc", "sysfs", "cgroup", "cgroup2" };
        for (pseudo) |p| {
            if (std.mem.eql(u8, fs_type, p)) return true;
        }
        return std.mem.startsWith(u8, fs_type, "cgroup");
    }

    fn isHomePath(path: []const u8) bool {
        return std.mem.eql(u8, path, "/home") or std.mem.eql(u8, path, "/home/kidul") or std.mem.startsWith(u8, path, "/home/");
    }

    fn isInHomeScope(path: []const u8) bool {
        return std.mem.eql(u8, path, "/home") or std.mem.startsWith(u8, path, "/home/");
    }

    fn isElevated(self: *Self) bool {
        _ = self;
        return c.geteuid() == 0;
    }

    fn loadEntries(allocator: std.mem.Allocator, path: []const u8, entries: *std.ArrayList(Entry)) !void {
        entries.clearRetainingCapacity();
        const dir = c.opendir(path.ptr) orelse return;
        defer _ = c.closedir(dir);

        var result: ?*c.struct_dirent = undefined;
        while (true) {
            result = c.readdir(dir);
            if (result == null) break;
            const entry = result.?;
            const name = entry.d_name[0..std.mem.len(@as([*c]const u8, &entry.d_name))];
            if (name[0] == '.') continue;

            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, name });
            var stat: c.struct_stat = undefined;
            const is_dir = if (c.stat(full_path.ptr, &stat) == 0) c.S_ISDIR(stat.st_mode) else false;
            const size: u64 = if (is_dir) 0 else @intCast(stat.st_size);

            const name_copy = try allocator.dupe(u8, name);
            try entries.append(allocator, .{
                .name = name_copy,
                .path = full_path,
                .is_dir = is_dir,
                .size = size,
            });
        }

        std.mem.sort(Entry, entries.items, {}, entryLessThan);
    }

    fn entryLessThan(_: void, a: Entry, b: Entry) bool {
        if (a.is_dir != b.is_dir) return a.is_dir;
        return std.mem.lessThan(u8, a.name, b.name);
    }

    fn clearEntries(entries: *std.ArrayList(Entry), allocator: std.mem.Allocator) void {
        for (entries.items) |*e| {
            allocator.free(e.name);
            allocator.free(e.path);
        }
        entries.clearAndFree(allocator);
    }

    var g_app: ?*App = null;

fn handleSigWinch(signo: c_int) callconv(.c) void {
    _ = signo;
    if (g_app) |app| {
        app.updateTermSize();
        app.draw() catch {};
    }
}

pub fn run(self: *Self) !void {
        enableRawMode();
        defer disableRawMode();
        g_app = self;
        defer g_app = null;

        // Retry a few times to let Ghostty resize the pty before first draw.
        var startup_delay: usize = 0;
        while (startup_delay < 10) : (startup_delay += 1) {
            self.updateTermSize();
            if (self.term_h >= 30) break;
            _ = c.usleep(50_000);
        }

        const debug = c.fopen("/tmp/kidul-files-debug.log", "w");
        if (debug) |d| {
            _ = c.fprintf(d, "term_w=%zu term_h=%zu path=%s\n", self.term_w, self.term_h, self.current_path.ptr);
            _ = c.fclose(d);
        }

        // Handle terminal resize.
        _ = c.signal(c.SIGWINCH, handleSigWinch);

        while (self.running) {
            self.updateTermSize();
            try self.draw();

            var buf: [8]u8 = undefined;
            const n = c.read(0, &buf, buf.len);
            if (n == 0) continue;

            if (buf[0] == 'q' or buf[0] == 'Q') {
                self.running = false;
            } else if (buf[0] == '\x1b' and n >= 3 and buf[1] == '[') {
                switch (buf[2]) {
                    'A' => self.moveSelection(-1),
                    'B' => self.moveSelection(1),
                    'C' => self.openSelected(),
                    'D' => self.goUp(),
                    else => {},
                }
            } else if (buf[0] == 'j' or buf[0] == 'J') {
                self.moveSelection(1);
            } else if (buf[0] == 'k' or buf[0] == 'K') {
                self.moveSelection(-1);
            } else if (buf[0] == 'l' or buf[0] == 'L') {
                self.openSelected();
            } else if (buf[0] == 'h' or buf[0] == 'H') {
                self.goUp();
            }
        }
    }

    fn updateTermSize(self: *Self) void {
        var ws: c.winsize = undefined;
        if (c.ioctl(0, c.TIOCGWINSZ, &ws) != -1 and ws.ws_col >= 40 and ws.ws_row >= 10) {
            self.term_w = @intCast(ws.ws_col);
            self.term_h = @intCast(ws.ws_row);
        }
    }

    fn moveSelection(self: *Self, delta: i32) void {
        if (self.entries.items.len == 0) return;
        const new: i32 = @as(i32, @intCast(self.selected_index)) + delta;
        if (new < 0 or new >= self.entries.items.len) return;
        self.selected_index = @intCast(new);
        self.updatePreview() catch {};
    }

    fn openSelected(self: *Self) void {
        if (self.entries.items.len == 0) return;
        const entry = self.entries.items[self.selected_index];
        if (entry.is_dir) {
            self.changeDir(entry.path);
        } else {
            self.openFile(entry.path) catch {};
        }
    }

    fn goUp(self: *Self) void {
        const parent = std.fs.path.dirname(self.current_path) orelse return;
        if (!self.isElevated() and !App.isInHomeScope(parent)) {
            self.setRestrictedMessage();
            return;
        }
        self.changeDir(parent);
    }

    fn changeDir(self: *Self, path: []const u8) void {
        if (!self.isElevated() and !App.isInHomeScope(path)) {
            self.setRestrictedMessage();
            return;
        }
        var new_entries = std.ArrayList(Entry).empty;
        loadEntries(self.allocator, path, &new_entries) catch {
            new_entries.deinit(self.allocator);
            return;
        };
        clearEntries(&self.entries, self.allocator);
        self.entries = new_entries;
        self.allocator.free(self.current_path);
        self.current_path = std.fs.path.resolve(self.allocator, &[_][]const u8{path}) catch return;
        self.selected_index = 0;
        self.scroll_offset = 0;
        self.updatePreview() catch {};
    }

    fn setRestrictedMessage(self: *Self) void {
        self.preview_text.clearRetainingCapacity();
        self.preview_text.appendSlice(self.allocator, "Restricted\nEnter sudo passwd to view system files.\n") catch {};
    }

    fn openFile(self: *Self, path: []const u8) !void {
        _ = self;
        const pid = c.fork();
        if (pid == 0) {
            _ = c.execlp("xdg-open", "xdg-open", path.ptr, @as(?*const anyopaque, null));
            c._exit(1);
        } else if (pid > 0) {
            var status: c_int = 0;
            _ = c.waitpid(pid, &status, 0);
        }
    }

    fn updatePreview(self: *Self) !void {
        self.preview_text.clearRetainingCapacity();
        if (self.entries.items.len == 0) return;
        const entry = self.entries.items[self.selected_index];

        if (entry.is_dir) {
            try self.preview_text.appendSlice(self.allocator, "<directory>\n");
            return;
        }

        const file = c.fopen(entry.path.ptr, "r") orelse {
            try self.preview_text.appendSlice(self.allocator, "<cannot open file>\n");
            return;
        };
        defer _ = c.fclose(file);
        var buf: [4096]u8 = undefined;
        const read = c.fread(&buf, 1, buf.len, file);
        try self.preview_text.appendSlice(self.allocator, buf[0..read]);
    }

    fn friendlyLabelFor(path: []const u8) []const u8 {
        if (std.mem.eql(u8, path, "/")) return "root";
        if (std.mem.eql(u8, path, "/home")) return "home";
        if (std.mem.startsWith(u8, path, "/home/")) {
            // /home/dad  ->  dad, /home/dad/MyFolders -> dad/MyFolders
            const rest = path[6..];
            return rest;
        }
        return path;
    }

    fn draw(self: *Self) !void {
        const stdout = c.stdout.?;
        const w = self.term_w;
        const h = self.term_h;

        _ = c.fputs("\x1b[2J\x1b[H", stdout);

        const gap = 1;
        const card_y = 1;
        const card_h = if (h > 0) h else 1;

        // 20/60/20 split.
        const inner_w = if (w > 2 * gap + 2) w - 2 * gap - 2 else 40;
        const side_w = @max(10, inner_w / 5);
        const mid_w = if (inner_w > 2 * side_w + 2 * gap) inner_w - 2 * side_w - 2 * gap else 20;

        const left_x = 2;
        const mid_x = left_x + side_w + gap;
        const right_x = mid_x + mid_w + gap;

        self.drawPanel(stdout, left_x, card_y, side_w, card_h);
        self.drawLeftPeek(stdout, left_x, card_y, side_w, card_h);

        self.drawPanel(stdout, mid_x, card_y, mid_w, card_h);
        self.drawMiddle(stdout, mid_x, card_y, mid_w, card_h);

        self.drawPanel(stdout, right_x, card_y, side_w, card_h);
        self.drawRightPeek(stdout, right_x, card_y, side_w, card_h);

        _ = c.fflush(stdout);
    }

    fn fillRow(stdout: *c.struct__IO_FILE, x: usize, y: usize, width: usize) void {
        _ = c.fprintf(stdout, "\x1b[%d;%dH\x1b[48;2;34;36;37m", y, x);
        const space_buf = "                                                                        ";
        var remaining = width;
        while (remaining > 0) : (remaining -= if (remaining > space_buf.len) space_buf.len else remaining) {
            const n = if (remaining > space_buf.len) space_buf.len else remaining;
            _ = c.fwrite(space_buf.ptr, 1, n, stdout);
        }
        _ = c.fputs("\x1b[0m", stdout);
    }

    fn drawPanel(self: *Self, stdout: *c.struct__IO_FILE, x: usize, y: usize, width: usize, height: usize) void {
        _ = self;
        var row: usize = 0;
        while (row < height) : (row += 1) {
            fillRow(stdout, x, y + row, width);
        }
    }

    fn drawLeftPeek(self: *Self, stdout: *c.struct__IO_FILE, x: usize, y: usize, w: usize, h: usize) void {
        const label = friendlyLabelFor(self.current_path);
        const name = if (label.len > w - 2) label[0 .. w - 2] else label;
        const pad_left = if (name.len + 2 >= w) 0 else (w - name.len) / 2;
        const label_y = y + (h / 2);
        fillRow(stdout, x, label_y, w);
        _ = c.fprintf(stdout, "\x1b[%d;%dH\x1b[48;2;34;36;37m\x1b[38;5;250m", label_y, x + 1);
        if (pad_left > 0) {
            var p: usize = 0;
            while (p < pad_left) : (p += 1) _ = c.fputc(' ', stdout);
        }
        _ = c.fwrite(name.ptr, 1, name.len, stdout);
        _ = c.fputs("\x1b[0m", stdout);
    }

    fn drawMiddle(self: *Self, stdout: *c.struct__IO_FILE, x: usize, y: usize, w: usize, h: usize) void {
        const visible_rows = if (h > 2) h - 2 else 1;
        const count = self.entries.items.len;
        const start_y = if (count < visible_rows) y + 1 + (visible_rows - count) / 2 else y + 1;
        var row: usize = 0;
        while (row < visible_rows) : (row += 1) {
            const screen_row = start_y + row;
            if (screen_row >= y + h) break;
            const idx = self.scroll_offset + row;
            fillRow(stdout, x, screen_row, w);
            if (idx >= self.entries.items.len) continue;
            const entry = self.entries.items[idx];
            _ = c.fprintf(stdout, "\x1b[%d;%dH", screen_row, x + 1);
            if (idx == self.selected_index) {
                _ = c.fputs("\x1b[38;5;222m", stdout);
            } else {
                _ = c.fputs("\x1b[0m\x1b[38;5;252m", stdout);
            }
            const name = if (entry.name.len > w - 2) entry.name[0 .. w - 2] else entry.name;
            _ = c.fwrite(name.ptr, 1, name.len, stdout);
            _ = c.fputs("\x1b[0m", stdout);
        }
    }

    fn drawRightPeek(self: *Self, stdout: *c.struct__IO_FILE, x: usize, y: usize, w: usize, h: usize) void {
        const label = "preview";
        const label_y = y + (h / 2);
        const label_x = if (label.len + 2 >= w) x + 1 else x + (w - label.len) / 2;
        fillRow(stdout, x, label_y, w);
        _ = c.fprintf(stdout, "\x1b[%d;%dH\x1b[48;2;34;36;37m\x1b[38;5;240m%s\x1b[0m", label_y, label_x, label);
        var row: usize = 1;
        const lines = std.mem.splitAny(u8, self.preview_text.items, "\n");
        var it = lines;
        while (it.next()) |line| {
            if (row >= h - 1) break;
            const trimmed = if (line.len > w - 2) line[0 .. w - 2] else line;
            fillRow(stdout, x, y + row, w);
            _ = c.fprintf(stdout, "\x1b[%d;%dH\x1b[48;2;34;36;37m\x1b[38;5;252m", y + row, x + 1);
            _ = c.fwrite(trimmed.ptr, 1, trimmed.len, stdout);
            _ = c.fputs("\x1b[0m", stdout);
            row += 1;
        }
        while (row < h - 1) : (row += 1) {
            fillRow(stdout, x, y + row, w);
        }
    }
};
fn isImage(path_: []const u8) bool {
    const ext = std.fs.path.extension(path_);
    return std.mem.eql(u8, ext, ".png") or
        std.mem.eql(u8, ext, ".jpg") or
        std.mem.eql(u8, ext, ".jpeg") or
        std.mem.eql(u8, ext, ".gif") or
        std.mem.eql(u8, ext, ".bmp") or
        std.mem.eql(u8, ext, ".webp");
}

var orig_termios: c.struct_termios = undefined;

fn enableRawMode() void {
    _ = c.tcgetattr(0, &orig_termios);
    var raw = orig_termios;
    raw.c_lflag &= ~(@as(c_uint, c.ECHO | c.ICANON));
    _ = c.tcsetattr(0, c.TCSAFLUSH, &raw);
    _ = c.fputs("\x1b[?25l", c.stdout);
}

fn disableRawMode() void {
    _ = c.tcsetattr(0, c.TCSAFLUSH, &orig_termios);
    _ = c.fputs("\x1b[?25h", c.stdout);
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = c.fopen(path.ptr, "r") orelse return error.FileNotFound;
    defer _ = c.fclose(file);
    _ = c.fseek(file, 0, c.SEEK_END);
    const size = c.ftell(file);
    _ = c.fseek(file, 0, c.SEEK_SET);
    const buf = try allocator.alloc(u8, @intCast(size));
    _ = c.fread(buf.ptr, 1, @intCast(size), file);
    return buf;
}

pub fn main(init: std.process.Init.Minimal) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var it = std.process.Args.Iterator.init(init.args);
    _ = it.next(); // skip program name
    const start_path = it.next();

    var app = try App.init(allocator, start_path);
    defer app.deinit();

    try app.run();
}
