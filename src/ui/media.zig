const std = @import("std");
const c = @import("dm").c;
const style = @import("../core/style.zig");

const unistd = @cImport({
    @cInclude("unistd.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("fcntl.h");
    @cInclude("time.h");
    @cInclude("stdio.h");
});

const c_posix = std.posix;
const c_linux = std.os.linux;

pub const MediaState = struct {
    available: bool = false,
    playing: bool = false,
    position: f64 = 0,
    duration: f64 = 0,
    title: [64:0]u8 = std.mem.zeroes([64:0]u8),
    artist: [64:0]u8 = std.mem.zeroes([64:0]u8),
    album: [64:0]u8 = std.mem.zeroes([64:0]u8),
};

pub const MediaCard = struct {
    open: bool = false,

    pub fn toggle(self: *MediaCard) void {
        self.open = !self.open;
    }
};

pub const MediaCategory = enum { movies, music, tv, pictures, shop };

pub const ControlFocus = enum { category, search, result, slider };

const LibraryEntry = struct {
    title: [:0]u8,
    artist: [:0]u8,
    path: [:0]u8,
};

const max_library_entries = 512;
const g_alloc = std.heap.page_allocator;

fn titleFromName(name: []const u8) ![:0]u8 {
    const stem = std.fs.path.stem(name);
    const title = try g_alloc.dupeZ(u8, stem);
    for (title) |*ch| {
        if (ch.* == '_' or ch.* == '-' or ch.* == '.') ch.* = ' ';
    }
    return title;
}

fn fileExtensionIndex(name: []const u8, category: MediaCategory) bool {
    var buf: [32]u8 = undefined;
    const ext = std.fs.path.extension(name);
    const ext_l = std.ascii.lowerString(&buf, ext);
    return switch (category) {
        .music => std.mem.eql(u8, ext_l, ".mp3") or
                  std.mem.eql(u8, ext_l, ".flac") or
                  std.mem.eql(u8, ext_l, ".m4a") or
                  std.mem.eql(u8, ext_l, ".ogg") or
                  std.mem.eql(u8, ext_l, ".opus") or
                  std.mem.eql(u8, ext_l, ".wav"),
        .movies => std.mem.eql(u8, ext_l, ".mp4") or
                   std.mem.eql(u8, ext_l, ".mkv") or
                   std.mem.eql(u8, ext_l, ".avi") or
                   std.mem.eql(u8, ext_l, ".mov") or
                   std.mem.eql(u8, ext_l, ".webm"),
        .tv => std.mem.eql(u8, ext_l, ".m3u") or std.mem.eql(u8, ext_l, ".m3u8"),
        .pictures => std.mem.eql(u8, ext_l, ".jpg") or
                     std.mem.eql(u8, ext_l, ".jpeg") or
                     std.mem.eql(u8, ext_l, ".png") or
                     std.mem.eql(u8, ext_l, ".webp") or
                     std.mem.eql(u8, ext_l, ".gif"),
        .shop => false,
    };
}

fn execFind(command: [*:0]const u8, entries: []LibraryEntry) usize {
    const fp = unistd.popen(command, "r") orelse return 0;
    defer _ = unistd.pclose(fp);
    var count: usize = 0;
    var line_buf: [4096:0]u8 = std.mem.zeroes([4096:0]u8);
    while (unistd.fgets(&line_buf, line_buf.len, fp) != null) {
        if (count >= entries.len) break;
        const slice = std.mem.sliceTo(&line_buf, 0);
        if (slice.len == 0) continue;
        var end = slice.len;
        while (end > 0 and (slice[end - 1] == '\n' or slice[end - 1] == '\r')) end -= 1;
        if (end == 0) continue;
        const path = slice[0..end];
        const name = std.fs.path.basename(path);
        const title = titleFromName(name) catch continue;
        const path_owned = g_alloc.dupeZ(u8, path) catch continue;
        const artist = g_alloc.dupeZ(u8, "") catch continue;
        entries[count] = .{ .title = title, .artist = artist, .path = path_owned };
        count += 1;
        @memset(&line_buf, 0);
    }
    return count;
}

fn scanCategory(category: MediaCategory, entries: []LibraryEntry) usize {
    const roots = switch (category) {
        .music => &[_][]const u8{ "/home/kidul/Music", "/mnt/sda_backup/Jelly/Music" },
        .movies => &[_][]const u8{ "/home/kidul/Movies", "/home/kidul/Videos", "/mnt/sda_backup/Jelly/Kids Movies", "/mnt/sda_backup/Jelly/Movies" },
        .tv => &[_][]const u8{},
        .pictures => &[_][]const u8{ "/home/kidul/Pictures", "/home/kidul/Images" },
        .shop => &[_][]const u8{},
    };
    const exts = switch (category) {
        .music => &[_][]const u8{ ".mp3", ".flac", ".m4a", ".ogg", ".opus", ".wav" },
        .movies => &[_][]const u8{ ".mp4", ".mkv", ".avi", ".mov", ".webm" },
        .tv => &[_][]const u8{ ".m3u", ".m3u8" },
        .pictures => &[_][]const u8{ ".jpg", ".jpeg", ".png", ".webp", ".gif" },
        .shop => &[_][]const u8{},
    };

    var count: usize = 0;
    for (roots) |root| {
        for (exts) |ext| {
            var cmd_buf: [1024:0]u8 = std.mem.zeroes([1024:0]u8);
            const cmd = std.fmt.bufPrintZ(&cmd_buf, "find \"{s}\" -type f -iname '*{s}' 2>/dev/null | sort -f | head -n 300", .{ root, ext }) catch continue;
            count += execFind(cmd, entries[count..]);
            if (count >= entries.len) break;
        }
        if (count >= entries.len) break;
    }
    std.log.info("KidulWM media scan {s}: {d} entries", .{ categoryLabel(category), count });
    if (count == 0) {
        count = fillSamples(category, entries);
        std.log.info("KidulWM media scan {s}: filled {d} samples", .{ categoryLabel(category), count });
    }
    std.mem.sort(LibraryEntry, entries[0..count], {}, compareLibraryEntryTitle);
    return count;
}
fn fillSamples(category: MediaCategory, entries: []LibraryEntry) usize {
    if (category == .tv or category == .shop) return 0;
    const titles = switch (category) {
        .music => &[_][]const u8{
            "Midnight City", "The Night We Met", "Weightless", "Clair de Lune", "Experience",
            "Instant Crush", "Hotline Bling", "Take Five", "Autumn Leaves", "Hotel California",
            "Bohemian Rhapsody", "Go Your Own Way", "Dreams", "Under Pressure", "Come Together",
            "God Only Knows", "Good Vibrations", "Cecilia", "Mrs. Robinson", "Bridge Over Troubled Water",
        },
        .movies => &[_][]const u8{
            "Encanto", "Turning Red", "Toy Story 2", "Kung Fu Panda 3", "Ice Age",
            "Coco", "Moana", "Frozen", "Zootopia", "Bolt",
            "Ratatouille", "WALL·E", "Up", "Finding Nemo", "The Incredibles",
            "Shrek", "How to Train Your Dragon", "Trolls", "Sing", "The Croods",
        },
        .pictures => &[_][]const u8{
            "Vacation 01", "Family 2025", "Puppy", "Sunset", "Wallpaper",
            "Portrait", "Concert Night", "Baptism", "Halloween", "Christmas 24",
            "Beach Day", "Mountain Hike", "Brunch", "Graduation", "Pool Party",
            "Road Trip", "Camping", "New Puppy", "Garden", "Selfie",
        },
        .tv, .shop => &[_][]const u8{},
    };
    const artists = switch (category) {
        .music => &[_][]const u8{
            "M83", "Lord Huron", "Marconi Union", "Debussy", "Ludovico Einaudi",
            "Daft Punk", "Drake", "Dave Brubeck", "Nat King Cole", "Eagles",
            "Queen", "Fleetwood Mac", "Fleetwood Mac", "Queen", "The Beatles",
            "Beach Boys", "Beach Boys", "Simon & Garfunkel", "Simon & Garfunkel", "Simon & Garfunkel",
        },
        .movies => &[_][]const u8{
            "Disney", "Pixar", "Pixar", "DreamWorks", "Blue Sky",
            "Pixar", "Disney", "Disney", "Disney", "Disney",
            "Pixar", "Pixar", "Pixar", "Pixar", "Pixar",
            "DreamWorks", "DreamWorks", "DreamWorks", "Illumination", "DreamWorks",
        },
        .pictures => &[_][]const u8{
            "Album", "Album", "Album", "Album", "Album",
            "Album", "Album", "Album", "Album", "Album",
            "Album", "Album", "Album", "Album", "Album",
            "Album", "Album", "Album", "Album", "Album",
        },
        .tv, .shop => &[_][]const u8{},
    };
    const count = @min(titles.len, entries.len);
    for (0..count) |i| {
        entries[i] = .{
            .title = g_alloc.dupeZ(u8, titles[i]) catch continue,
            .artist = g_alloc.dupeZ(u8, artists[i]) catch continue,
            .path = g_alloc.dupeZ(u8, "/nonexistent") catch continue,
        };
    }
    return count;
}

fn compareLibraryEntryTitle(_: void, a: LibraryEntry, b: LibraryEntry) bool {
    var la: [512]u8 = undefined;
    var lb: [512]u8 = undefined;
    const lower_a = std.ascii.lowerString(&la, a.title);
    const lower_b = std.ascii.lowerString(&lb, b.title);
    return std.mem.lessThan(u8, lower_a, lower_b);
}

fn categoryLabel(cat: MediaCategory) [:0]const u8 {
    return switch (cat) {
        .movies => "Movies",
        .music => "Music",
        .tv => "TV",
        .pictures => "Pics",
        .shop => "Shop",
    };
}

var g_music: [max_library_entries]LibraryEntry = undefined;
var g_music_count: usize = 0;
var g_music_ready = false;
var g_movies: [max_library_entries]LibraryEntry = undefined;
var g_movies_count: usize = 0;
var g_movies_ready = false;
var g_pictures: [max_library_entries]LibraryEntry = undefined;
var g_pictures_count: usize = 0;
var g_pictures_ready = false;

fn getLibrary(category: MediaCategory) []const LibraryEntry {
    switch (category) {
        .music => {
            if (!g_music_ready) {
                g_music_count = scanCategory(.music, &g_music);
                g_music_ready = true;
            }
            return g_music[0..g_music_count];
        },
        .movies => {
            if (!g_movies_ready) {
                g_movies_count = scanCategory(.movies, &g_movies);
                g_movies_ready = true;
            }
            return g_movies[0..g_movies_count];
        },
        .tv => {
            return &[_]LibraryEntry{};
        },
        .pictures => {
            if (!g_pictures_ready) {
                g_pictures_count = scanCategory(.pictures, &g_pictures);
                g_pictures_ready = true;
            }
            return g_pictures[0..g_pictures_count];
        },
        .shop => {
            return &[_]LibraryEntry{};
        },
    }
}

fn displayIndex(cat: MediaCategory) usize {
    return switch (cat) {
        .shop => 0,
        .movies => 1,
        .music => 2,
        .pictures => 3,
        .tv => 4,
    };
}

fn mediaCategoryFromIndex(i: usize) MediaCategory {
    return switch (i) {
        0 => .shop,
        1 => .movies,
        2 => .music,
        3 => .pictures,
        4 => .tv,
        else => .music,
    };
}

pub const MediaWidget = struct {
    allocator: std.mem.Allocator,
    card: MediaCard = .{},
    ipc_path: [128:0]u8 = std.mem.zeroes([128:0]u8),
    mpv_pid: ?i32 = null,
    last_poll_us: u64 = 0,
    poll_fail_count: u32 = 0,
    cached: MediaState = .{},
    helix_phase: f64 = 0,
    last_energy: f64 = 0,
    last_helix_us: u64 = 0,

    focus: ControlFocus = .category,
    category: MediaCategory = .music,
    search_buf: [128:0]u8 = std.mem.zeroes([128:0]u8),
    search_len: usize = 0,
    search_focused: bool = false,
    search_caret: usize = 0,
    last_caret_blink_us: u64 = 0,
    show_caret: bool = true,
    grid_cols: usize = 5,

    state_generation: u32 = 0,
    slider_reveal: f64 = 0.0,
    slider_reveal_target: f64 = 0.0,

    selected_result: usize = 0,
    visible_result_count: usize = 0,
    list_scroll_offset: usize = 0,
    max_scroll_offset: usize = 0,
    slider_hover: bool = false,

    pub fn init(allocator: std.mem.Allocator) MediaWidget {
        const ipc = "/run/user/1000/kidulwm-mpv.sock";
        var self = MediaWidget{ .allocator = allocator };
        @memcpy(self.ipc_path[0..ipc.len], ipc);
        self.ipc_path[ipc.len] = 0;
        return self;
    }

    pub fn deinit(self: *MediaWidget) void {
        self.ensureStopped();
    }

    pub fn toggleCard(self: *MediaWidget) void {
        self.card.toggle();
        if (self.card.open) {
            self.focus = .search;
            self.search_focused = true;
            self.slider_hover = false;
            self.selected_result = 0;
            self.list_scroll_offset = 0;
            self.clearSearch();
        }
        self.bumpGeneration();
    }

    pub fn setCardOpen(self: *MediaWidget, open: bool) void {
        self.card.open = open;
        if (open) {
            self.focus = .search;
            self.search_focused = true;
            self.slider_hover = false;
            self.selected_result = 0;
            self.list_scroll_offset = 0;
            self.clearSearch();
        }
        self.bumpGeneration();
    }

    pub fn isCardOpen(self: *const MediaWidget) bool {
        return self.card.open;
    }

    pub fn focusControl(self: *MediaWidget, ctl: ControlFocus) void {
        self.focus = ctl;
        self.search_focused = ctl == .search;
        self.slider_reveal_target = if (ctl == .slider) 1.0 else 0.0;
        if (ctl != .slider) self.slider_hover = false;
        if (self.search_focused) {
            self.search_caret = self.search_len;
        }
        self.bumpGeneration();
    }

    pub fn focusSlider(self: *MediaWidget) void {
        self.focusControl(.slider);
        self.slider_hover = true;
    }

    pub fn stepSliderReveal(self: *MediaWidget, dt: f64) void {
        const prev_reveal = self.slider_reveal;
        if (self.slider_reveal < self.slider_reveal_target) {
            self.slider_reveal = @min(self.slider_reveal_target, self.slider_reveal + dt * 24.0);
        } else if (self.slider_reveal > self.slider_reveal_target) {
            self.slider_reveal = @max(self.slider_reveal_target, self.slider_reveal - dt * 24.0);
        }
        if (self.slider_reveal != prev_reveal) self.bumpGeneration();
    }

    fn bumpGeneration(self: *MediaWidget) void {
        self.state_generation +%= 1;
    }

    pub fn moveCategory(self: *MediaWidget, delta: i32) void {
        const idx: i32 = @intCast(displayIndex(self.category));
        const new_idx = @mod(idx + delta, 5);
        self.category = mediaCategoryFromIndex(@intCast(new_idx));
        self.selected_result = 0;
        self.list_scroll_offset = 0;
        self.bumpGeneration();
    }

    pub fn moveResultSelection(self: *MediaWidget, delta: i32) void {
        const library = getLibrary(self.category);
        if (library.len == 0) return;
        var idx: i32 = @intCast(self.selected_result);
        idx = @mod(idx + delta, @as(i32, @intCast(library.len)));
        self.selected_result = @intCast(idx);
        std.log.info("KidulWM media move horizontal: selected={} len={}", .{self.selected_result, library.len});
        self.adjustScrollToSelection();
    }

    pub fn moveResultVertical(self: *MediaWidget, rows: i32) void {
        const cols: i32 = @intCast(self.grid_cols);
        const library = getLibrary(self.category);
        if (library.len == 0) return;
        const total_rows: i32 = @intCast((library.len + @as(usize, @intCast(cols)) - 1) / @as(usize, @intCast(cols)));
        var row: i32 = @intCast(self.selected_result / @as(usize, @intCast(cols)));
        var col: i32 = @intCast(self.selected_result % @as(usize, @intCast(cols)));
        const new_row_uncapped: i32 = row + rows;
        if (new_row_uncapped < 0) {
            // Wrapping up from top row: land on same column, last row (clamp to last item if row is partial).
            row = total_rows - 1;
            const last_row_items: i32 = @intCast(library.len - @as(usize, @intCast(row)) * @as(usize, @intCast(cols)));
            if (col >= last_row_items) col = last_row_items - 1;
        } else if (new_row_uncapped >= total_rows) {
            // Wrapping down from bottom row: land on same column, first row.
            row = 0;
        } else {
            row = new_row_uncapped;
            const row_items: i32 = if (row == total_rows - 1)
                @intCast(library.len - @as(usize, @intCast(row)) * @as(usize, @intCast(cols)))
            else
                cols;
            if (col >= row_items) col = row_items - 1;
        }
        self.selected_result = @intCast(row * cols + col);
        self.adjustScrollToSelection();
    }

    pub fn pageList(self: *MediaWidget, pages: i32) void {
        const rows_per_page: i32 = @max(1, @as(i32, @intCast(self.visible_result_count / 2)));
        var off: i32 = @intCast(self.list_scroll_offset);
        off += rows_per_page * pages;
        off = @max(0, @min(off, @as(i32, @intCast(self.max_scroll_offset))));
        self.list_scroll_offset = @intCast(off);
        self.bumpGeneration();
    }

    pub fn adjustScrollToSelection(self: *MediaWidget) void {
        const cols: usize = self.grid_cols;
        const selected_row = self.selected_result / cols;
        const visible_rows = self.visible_result_count / cols;
        if (selected_row < self.list_scroll_offset) {
            self.list_scroll_offset = selected_row;
        } else if (visible_rows > 0 and selected_row >= self.list_scroll_offset + visible_rows) {
            var off = selected_row + 1 - visible_rows;
            if (off > self.max_scroll_offset) off = self.max_scroll_offset;
            self.list_scroll_offset = off;
        }
        self.bumpGeneration();
    }

    pub fn jumpToLetter(self: *MediaWidget, letter: u8) void {
        const library = getLibrary(self.category);
        if (library.len == 0) return;
        const needle = std.ascii.toLower(letter);
        var idx: usize = 0;
        // Binary-ish scan to first title starting with letter.
        for (library, 0..) |entry, i| {
            const title = std.mem.sliceTo(entry.title, 0);
            if (title.len == 0) continue;
            const first = std.ascii.toLower(title[0]);
            if (first >= needle) {
                idx = i;
                break;
            }
        }
        self.selected_result = idx;
        self.adjustScrollToSelection();
    }

    pub fn jumpToSliderPosition(self: *MediaWidget, ratio: f64) void {
        const library = getLibrary(self.category);
        if (library.len == 0) return;
        const clamped = @max(0.0, @min(1.0, ratio));
        const letters: []const u8 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        const idx = @min(letters.len - 1, @as(usize, @intFromFloat(@floor(clamped * @as(f64, @floatFromInt(letters.len))))));
        self.jumpToLetter(letters[idx]);
    }

    pub fn moveSliderVertical(self: *MediaWidget, letters_delta: i32) void {
        const letters: []const u8 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        const letter_idx: i32 = @intCast(self.currentSliderLetterIndex());
        const new_letter_idx = @mod(letter_idx + letters_delta, @as(i32, @intCast(letters.len)));
        self.jumpToLetter(letters[@intCast(new_letter_idx)]);
    }

    pub fn currentSliderLetterIndex(self: *const MediaWidget) usize {
        const library = getLibrary(self.category);
        if (library.len == 0) return 0;
        if (self.selected_result >= library.len) return 0;
        const title = std.mem.sliceTo(library[self.selected_result].title, 0);
        if (title.len == 0) return 0;
        const first = std.ascii.toUpper(title[0]);
        if (first >= 'A' and first <= 'Z') return @intCast(first - 'A');
        return 0;
    }

    pub fn resultGridGeometry(self: *const MediaWidget) struct { cols: usize, total_rows: usize, selected_row: usize, selected_col: usize } {
        const cols = self.grid_cols;
        const library = getLibrary(self.category);
        const total_rows = if (library.len == 0) 0 else (library.len + cols - 1) / cols;
        const selected_row = self.selected_result / cols;
        const selected_col = self.selected_result % cols;
        return .{ .cols = cols, .total_rows = total_rows, .selected_row = selected_row, .selected_col = selected_col };
    }

    pub fn atResultTopRow(self: *const MediaWidget) bool {
        const g = self.resultGridGeometry();
        return g.total_rows == 0 or g.selected_row == 0;
    }

    pub fn isResultLastColumn(self: *const MediaWidget) bool {
        const g = self.resultGridGeometry();
        if (g.total_rows == 0) return false;
        const library = getLibrary(self.category);
        const row = g.selected_row;
        const row_items = if (row == g.total_rows - 1)
            library.len - row * g.cols
        else
            g.cols;
        if (row_items == 0) return false;
        return g.selected_col == row_items - 1;
    }

    pub fn focusSearch(self: *MediaWidget) void {
        self.focusControl(.search);
    }

    pub fn clearSearch(self: *MediaWidget) void {
        @memset(&self.search_buf, 0);
        self.search_len = 0;
        self.search_caret = 0;
        self.bumpGeneration();
    }

    pub fn appendSearch(self: *MediaWidget, ch: u8) void {
        if (self.search_len >= self.search_buf.len - 1) return;
        self.bumpGeneration();
        if (self.search_caret < self.search_len) {
            var i: usize = self.search_len;
            while (i > self.search_caret) : (i -= 1) {
                self.search_buf[i] = self.search_buf[i - 1];
            }
        }
        self.search_buf[self.search_caret] = ch;
        self.search_caret += 1;
        self.search_len += 1;
        self.search_buf[self.search_len] = 0;
    }

    pub fn backspaceSearch(self: *MediaWidget) void {
        if (self.search_caret == 0) return;
        self.bumpGeneration();
        var i = self.search_caret - 1;
        while (i < self.search_len - 1) : (i += 1) {
            self.search_buf[i] = self.search_buf[i + 1];
        }
        self.search_caret -= 1;
        self.search_len -= 1;
        self.search_buf[self.search_len] = 0;
    }

    pub fn deleteSearch(self: *MediaWidget) void {
        if (self.search_caret >= self.search_len) return;
        self.bumpGeneration();
        var i = self.search_caret;
        while (i < self.search_len - 1) : (i += 1) {
            self.search_buf[i] = self.search_buf[i + 1];
        }
        self.search_len -= 1;
        self.search_buf[self.search_len] = 0;
    }

    pub fn moveSearchCaret(self: *MediaWidget, delta: i32) void {
        const new = @as(i32, @intCast(self.search_caret)) + delta;
        self.search_caret = @intCast(@max(0, @min(new, @as(i32, @intCast(self.search_len)))));
        self.bumpGeneration();
    }

    pub fn searchText(self: *const MediaWidget) []const u8 {
        return if (self.search_len > 0) self.search_buf[0..self.search_len] else "";
    }

    pub fn selectedResultPath(self: *const MediaWidget) [:0]const u8 {
        const library = getLibrary(self.category);
        if (self.selected_result >= library.len) return "";
        return library[self.selected_result].path;
    }

    pub fn acceptSearch(self: *MediaWidget) []const u8 {
        const text = self.searchText();
        self.focusControl(.result);
        return text;
    }

    pub fn cancelSearch(self: *MediaWidget) void {
        self.clearSearch();
        self.focusControl(.category);
    }

    fn ensureStopped(self: *MediaWidget) void {
        if (self.mpv_pid) |pid| {
            _ = c_linux.kill(pid, c_linux.SIG.TERM);
            var status: u32 = 0;
            _ = c_linux.waitpid(@intCast(pid), &status, c_linux.W.NOHANG);
            self.mpv_pid = null;
        }
    }

    pub fn play(self: *MediaWidget, path: []const u8) void {
        self.ensureStopped();
        _ = unistd.unlink(@ptrCast(&self.ipc_path[0]));

        var path_z: [4096:0]u8 = std.mem.zeroes([4096:0]u8);
        const copy_len = @min(path.len, path_z.len - 1);
        @memcpy(path_z[0..copy_len], path[0..copy_len]);
        path_z[copy_len] = 0;

        const pid = unistd.fork();
        if (pid < 0) {
            std.log.err("media: fork failed for mpv", .{});
            return;
        }
        if (pid == 0) {
            _ = unistd.setsid();
            const devnull = unistd.open("/dev/null", unistd.O_RDWR);
            if (devnull >= 0) {
                _ = unistd.dup2(devnull, 0);
                _ = unistd.dup2(devnull, 1);
                _ = unistd.dup2(devnull, 2);
                if (devnull > 2) _ = unistd.close(devnull);
            }
            const argv = [_:null]?[*:0]const u8{
                "mpv".ptr,
                "--no-video".ptr,
                "--really-quiet".ptr,
                "--idle=no".ptr,
                "--force-window=no".ptr,
                "--ao=alsa,pulse,null".ptr,
                "--input-ipc-server=/run/user/1000/kidulwm-mpv.sock".ptr,
                "--".ptr,
                @ptrCast(&path_z[0]),
                null,
            };
            _ = unistd.execvp("mpv", @ptrCast(argv[0..].ptr));
            unistd._exit(127);
        }
        self.mpv_pid = pid;
        self.cached = .{};
        self.cached.available = true;
        self.last_poll_us = 0;
        self.poll_fail_count = 0;
    }

    pub fn playPause(self: *MediaWidget) void {
        self.sendSimpleCommand("cycle", &.{"pause"});
    }

    pub fn next(self: *MediaWidget) void {
        self.sendSimpleCommand("playlist-next", &.{});
    }

    pub fn prev(self: *MediaWidget) void {
        self.sendSimpleCommand("playlist-prev", &.{});
    }

    pub fn seek(self: *MediaWidget, seconds: f64) void {
        var sbuf: [64:0]u8 = std.mem.zeroes([64:0]u8);
        const s = std.fmt.bufPrintZ(&sbuf, "{d:.3}", .{seconds}) catch return;
        self.sendSimpleCommand("seek", &.{s});
    }

    fn sendSimpleCommand(self: *MediaWidget, name: []const u8, args: []const []const u8) void {
        if (self.mpv_pid == null) return;
        const fd = self.connectIpc() orelse return;
        defer _ = c_linux.close(fd);

        var json: [512]u8 = undefined;
        var j: usize = 0;
        const parts = [_][]const u8{
            "{\"command\":[\"",
            "\"",
            ",\"",
            "\"]}\n",
        };
        @memcpy(json[j..j + parts[0].len], parts[0]); j += parts[0].len;
        @memcpy(json[j..j + name.len], name); j += name.len;
        @memcpy(json[j..j + parts[1].len], parts[1]); j += parts[1].len;
        for (args) |a| {
            @memcpy(json[j..j + a.len], a); j += a.len;
            @memcpy(json[j..j + parts[2].len], parts[2]); j += parts[2].len;
        }
        if (args.len == 0) {
            @memcpy(json[j..j + parts[3].len], parts[3]); j += parts[3].len;
        } else {
            const tail = "]}\n";
            @memcpy(json[j..j + tail.len], tail); j += tail.len;
        }
        _ = c_linux.write(fd, &json, j);
    }

    fn connectIpc(self: *MediaWidget) ?i32 {
        const fd_i: i32 = @intCast(c_linux.socket(c_linux.AF.UNIX, c_linux.SOCK.STREAM, 0));
        if (fd_i < 0) return null;

        var addr: c_posix.sockaddr.un = std.mem.zeroes(c_posix.sockaddr.un);
        addr.family = c_linux.AF.UNIX;
        var path_buf: [128:0]u8 = std.mem.zeroes([128:0]u8);
        var path_slice = std.mem.sliceTo(&self.ipc_path, 0);
        if (path_slice.len == 0) {
            const default_path = "/run/user/1000/kidulwm-mpv.sock";
            @memcpy(path_buf[0..default_path.len], default_path);
            path_buf[default_path.len] = 0;
            path_slice = std.mem.sliceTo(&path_buf, 0);
        }
        const path_len = @min(path_slice.len, addr.path.len - 1);
        @memcpy(addr.path[0..path_len], path_slice[0..path_len]);
        addr.path[path_len] = 0;
        const addr_len: u32 = @intCast(@offsetOf(c_posix.sockaddr.un, "path") + path_len + 1);
        if (c_linux.connect(fd_i, @ptrCast(&addr), addr_len) != 0) {
            _ = c_linux.close(fd_i);
            return null;
        }
        return fd_i;
    }

    fn sendAndRead(self: *MediaWidget, command_json: []const u8, out: []u8) ?usize {
        if (self.mpv_pid == null) return null;
        const fd = self.connectIpc() orelse return null;
        defer _ = c_linux.close(fd);
        _ = c_linux.write(fd, command_json.ptr, command_json.len);

        const flags = unistd.fcntl(fd, unistd.F_GETFL, @as(c_int, 0));
        if (flags >= 0) {
            _ = unistd.fcntl(fd, unistd.F_SETFL, @as(c_int, @intCast(flags)) | unistd.O_NONBLOCK);
        }

        var total: usize = 0;
        var attempts: u8 = 0;
        while (attempts < 20 and total < out.len) {
            const rc = c_linux.read(fd, out.ptr + total, out.len - total);
            if (rc == 0) break;
            if (@as(i64, @bitCast(rc)) < 0) {
                if (c_linux.errno(rc) == .AGAIN) {
                    _ = unistd.usleep(10_000);
                    attempts += 1;
                    continue;
                }
                break;
            }
            total += rc;
            attempts = 0;
        }
        return if (total > 0) total else null;
    }

    fn parseBoolField(haystack: []const u8, key: []const u8) ?bool {
        var kbuf: [128]u8 = undefined;
        const K = std.fmt.bufPrint(&kbuf, "\"{s}\":", .{key}) catch return null;
        const idx = std.mem.indexOf(u8, haystack, K) orelse return null;
        const rest = haystack[idx + K.len..];
        if (std.mem.startsWith(u8, rest, "true")) return true;
        if (std.mem.startsWith(u8, rest, "false")) return false;
        return null;
    }

    fn parseStringField(haystack: []const u8, key: []const u8, out: []u8) void {
        var kbuf: [128]u8 = undefined;
        const K = std.fmt.bufPrint(&kbuf, "\"{s}\":\"", .{key}) catch return;
        const start = std.mem.indexOf(u8, haystack, K) orelse return;
        const rest = haystack[start + K.len..];
        const end = std.mem.indexOfScalar(u8, rest, '"') orelse return;
        const len = @min(end, out.len - 1);
        @memcpy(out[0..len], rest[0..len]);
        out[len] = 0;
    }

    fn parseFloatField(_: *MediaWidget, haystack: []const u8, key: []const u8) ?f64 {
        var kbuf: [128]u8 = undefined;
        const K = std.fmt.bufPrint(&kbuf, "\"{s}\":", .{key}) catch return null;
        const start = std.mem.indexOf(u8, haystack, K) orelse return null;
        const rest = haystack[start + K.len..];
        const end = for (rest, 0..) |ch, i| {
            if (ch == ',' or ch == '}' or ch == ']' or std.ascii.isWhitespace(ch)) break i;
        } else rest.len;
        return std.fmt.parseFloat(f64, rest[0..end]) catch null;
    }

    pub fn update(self: *MediaWidget) void {
        if (self.mpv_pid == null) {
            self.cached.playing = false;
            return;
        }
        const now = animationNowUs();
        if (now -% self.last_poll_us < 1_000_000) return;
        self.last_poll_us = now;

        var buf: [8192]u8 = std.mem.zeroes([8192]u8);
        const cmd = "{\"command\":[\"get_property\",\"playback-time\"]}\n" ++
                    "{\"command\":[\"get_property\",\"duration\"]}\n" ++
                    "{\"command\":[\"get_property\",\"pause\"]}\n" ++
                    "{\"command\":[\"get_property\",\"metadata\"]}\n";
        const n = self.sendAndRead(cmd, &buf) orelse {
            self.poll_fail_count += 1;
            if (self.poll_fail_count > 10) {
                self.cached.playing = false;
                self.cached.available = false;
            }
            return;
        };
        self.poll_fail_count = 0;
        const resp = buf[0..n];

        const pos = parseFloatField(self, resp, "playback-time");
        self.cached.position = pos orelse self.cached.position;
        const dur = parseFloatField(self, resp, "duration");
        self.cached.duration = dur orelse self.cached.duration;
        if (parseBoolField(resp, "pause")) |paused| {
            self.cached.playing = !paused;
        }
        parseStringField(resp, "title", &self.cached.title);
        if (self.cached.title[0] == 0) parseStringField(resp, "TITLE", &self.cached.title);
        if (self.cached.title[0] == 0) parseStringField(resp, "icy-title", &self.cached.title);
        parseStringField(resp, "artist", &self.cached.artist);
        parseStringField(resp, "album", &self.cached.album);
    }

    pub fn needsRedraw(self: *const MediaWidget) bool {
        _ = self;
        return true;
    }

    pub const PeekBox = struct { x: i32, y: i32, width: i32, height: i32 };

    pub fn renderPeek(self: *MediaWidget, cr: *c.cairo_t, box: PeekBox, style_: style.Style, scale: f32) void {
        const w_d: f64 = @floatFromInt(box.width);
        const h_d: f64 = @floatFromInt(box.height);
        if (w_d < 8.0 or h_d < 8.0) return;

        const border = style_.color_border_focused.toF64();
        const muted = style_.color_text_muted.toF64();
        const scale_f: f64 = @as(f64, scale);
        const playing = self.cached.playing;

        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        const margin: f64 = 6.0 * scale_f;
        const band_w = w_d - margin * 2.0;
        const lane_h = h_d - margin * 2.0;
        const cx = margin + band_w * 0.5;
        const cy = margin + lane_h * 0.5;

        const now = animationNowUs();
        const dt = if (self.last_helix_us == 0) 0.0 else @as(f64, @floatFromInt(now -% self.last_helix_us)) / 1_000_000.0;
        self.last_helix_us = now;
        const helix_speed: f64 = if (playing) 1.8 else 0.35;
        self.helix_phase += dt * helix_speed;
        const energy = if (playing) 0.6 + 0.4 * @sin(self.helix_phase * 2.0) else 0.12;
        self.last_energy = self.last_energy * 0.92 + energy * 0.08;

        const amp = @max(2.0 * scale_f, lane_h * 0.28 * self.last_energy);
        const marker_count: usize = 5;

        c.cairo_set_line_width(cr, @max(1.0, 1.4 * scale_f));

        for (0..2) |strand| {
            const strand_offset: f64 = @as(f64, @floatFromInt(strand)) * std.math.pi;
            c.cairo_new_path(cr);
            var t: f64 = 0;
            const steps: usize = 60;
            var first = true;
            while (t <= 1.0001) : (t += 1.0 / @as(f64, @floatFromInt(steps))) {
                const y = cy - lane_h * 0.5 + t * lane_h;
                const wave = @sin(t * std.math.pi * 4.0 - self.helix_phase + strand_offset);
                const x = cx + wave * amp;
                if (first) {
                    c.cairo_move_to(cr, x, y);
                    first = false;
                } else {
                    c.cairo_line_to(cr, x, y);
                }
            }
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], if (playing) 0.85 else 0.55);
            c.cairo_stroke(cr);
        }

        const alpha_pulse = 0.45 + 0.55 * self.last_energy;
        const marker_r = @max(3.0 * scale_f, lane_h * 0.09);
        var mi: usize = 0;
        while (mi <= marker_count) : (mi += 1) {
            const t = @as(f64, @floatFromInt(mi)) / @as(f64, @floatFromInt(marker_count));
            const y = margin + t * lane_h;
            const wave = @sin(t * std.math.pi * 4.0 - self.helix_phase);
            const x = cx + wave * amp;
            c.cairo_new_path(cr);
            c.cairo_arc(cr, x, y, marker_r, 0, std.math.pi * 2.0);
            if (playing) {
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], alpha_pulse);
            } else {
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.22);
            }
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.55);
            c.cairo_set_line_width(cr, @max(0.5, 0.7 * scale_f));
            c.cairo_stroke(cr);
        }

        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
        const txt = if (self.cached.title[0] != 0) std.mem.sliceTo(&self.cached.title, 0) else "No media";
        const font_h: f64 = @as(f64, style_.font_size_s) * 0.7 * scale_f;
        c.cairo_set_font_size(cr, font_h);
        var ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, txt.ptr, &ext);
        if (ext.width < band_w - 4.0 * scale_f) {
            c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.75);
            c.cairo_move_to(cr, margin, h_d - margin);
            c.cairo_show_text(cr, txt.ptr);
        }

        if (self.cached.available) {
            const dot_r = @max(2.5 * scale_f, 4.0 * scale_f);
            c.cairo_new_path(cr);
            c.cairo_arc(cr, w_d - margin - dot_r, margin + dot_r, dot_r, 0, std.math.pi * 2.0);
            if (playing) {
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.9);
            } else {
                c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.45);
            }
            c.cairo_fill(cr);
        }
    }

    pub const CardClick = struct {
        search_x: i32 = 0,
        search_y: i32 = 0,
        search_w: i32 = 0,
        search_h: i32 = 0,
        cat_y: [5]i32 = .{ 0, 0, 0, 0, 0 },
        cat_h: [5]i32 = .{ 0, 0, 0, 0, 0 },
        cat_for_index: [5]MediaCategory = .{ .music, .music, .music, .music, .music },
        cat_x: [5]i32 = .{ 0, 0, 0, 0, 0 },
        cat_w: [5]i32 = .{ 0, 0, 0, 0, 0 },
        list_x: i32 = 0,
        list_y: i32 = 0,
        list_w: i32 = 0,
        list_h: i32 = 0,
        scroll_x: i32 = 0,
        scroll_y: i32 = 0,
        scroll_w: i32 = 0,
        scroll_h: i32 = 0,
        letters_x: i32 = 0,
        letters_y: i32 = 0,
        letters_w: i32 = 0,
        letters_h: i32 = 0,
        cols: i32 = 2,
        tile_w: i32 = 0,
        tile_h: i32 = 0,
        tile_gap: i32 = 0,
        scroll_offset_at_render: usize = 0,
    };

    fn renderArtPlaceholder(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, seed: u64, border: [4]f64) void {
        const corner = @min(8.0, w * 0.06);
        const h1: f64 = @floatFromInt(((seed >> 16) & 0xFF) % 32 + 20);
        const h2: f64 = @floatFromInt(((seed >> 8) & 0xFF) % 24 + 40);
        const h3: f64 = @floatFromInt(((seed) & 0xFF) % 28 + 30);

        const shadow_grad = c.cairo_pattern_create_linear(x, y, x + w * 1.05, y + h * 1.1).?;
        c.cairo_pattern_add_color_stop_rgba(shadow_grad, 0.0, 0.0, 0.0, 0.0, 0.0);
        c.cairo_pattern_add_color_stop_rgba(shadow_grad, 1.0, 0.0, 0.0, 0.0, 0.55);
        c.cairo_save(cr);
        roundedRect(cr, x + 2.0, y + 2.0, w, h, corner);
        c.cairo_clip(cr);
        c.cairo_set_source(cr, shadow_grad);
        c.cairo_paint(cr);
        c.cairo_restore(cr);
        c.cairo_pattern_destroy(shadow_grad);

        roundedRect(cr, x, y, w, h, corner);
        const front_grad = c.cairo_pattern_create_linear(x, y, x + w, y + h).?;
        c.cairo_pattern_add_color_stop_rgba(front_grad, 0.0, h1 / 90.0, h2 / 120.0, h3 / 150.0, 0.50);
        c.cairo_pattern_add_color_stop_rgba(front_grad, 1.0, h2 / 150.0, h1 / 150.0, h3 / 110.0, 0.28);
        c.cairo_set_source(cr, front_grad);
        c.cairo_fill_preserve(cr);
        c.cairo_pattern_destroy(front_grad);

        const sheen_h = h * 0.22;
        const sheen = c.cairo_pattern_create_linear(x, y, x, y + sheen_h).?;
        c.cairo_pattern_add_color_stop_rgba(sheen, 0.0, 1.0, 1.0, 1.0, 0.18);
        c.cairo_pattern_add_color_stop_rgba(sheen, 1.0, 1.0, 1.0, 1.0, 0.0);
        c.cairo_set_source(cr, sheen);
        c.cairo_fill_preserve(cr);
        c.cairo_pattern_destroy(sheen);

        const spine_w = w * 0.08;
        c.cairo_save(cr);
        roundedRect(cr, x, y, w, h, corner);
        c.cairo_clip(cr);
        const spine_grad = c.cairo_pattern_create_linear(x, y, x + spine_w, y).?;
        c.cairo_pattern_add_color_stop_rgba(spine_grad, 0.0, 1.0, 1.0, 1.0, 0.14);
        c.cairo_pattern_add_color_stop_rgba(spine_grad, 1.0, 1.0, 1.0, 1.0, 0.0);
        c.cairo_set_source(cr, spine_grad);
        c.cairo_fill_preserve(cr);
        c.cairo_pattern_destroy(spine_grad);
        c.cairo_restore(cr);

        c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.30);
        c.cairo_set_line_width(cr, 1.0);
        c.cairo_stroke(cr);

        const cx = x + w * 0.5;
        const cy = y + h * 0.5;
        const r = @min(w, h) * 0.18;
        c.cairo_new_path(cr);
        c.cairo_arc(cr, cx, cy, r, 0, 2.0 * std.math.pi);
        c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.10);
        c.cairo_fill(cr);
        c.cairo_new_path(cr);
        c.cairo_arc(cr, cx, cy, r * 0.35, 0, 2.0 * std.math.pi);
        c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.12);
        c.cairo_fill(cr);
    }

    fn renderTileArt(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, entry: LibraryEntry, border: [4]f64) void {
        const dir = std.fs.path.dirname(entry.path) orelse "/home/dad/Music";
        const stem = std.fs.path.stem(entry.path);

        const candidates = [_][]const u8{
            "-landscape.jpg",
            "-landscape.png",
            "-backdrop.jpg",
            "-backdrop.png",
            "-poster.jpg",
            "-poster.png",
            "-logo.png",
            ".png",
            "cover.png",
            "folder.png",
            "art.png",
        };
        for (candidates) |suffix| {
            var buf: [4096:0]u8 = std.mem.zeroes([4096:0]u8);
            const slash = if (dir.len > 0 and dir[dir.len - 1] == '/') "" else "/";
            const full = std.fmt.bufPrintZ(&buf, "{s}{s}{s}{s}", .{ dir, slash, stem, suffix }) catch continue;
            const surf = c.cairo_image_surface_create_from_png(full.ptr);
            if (surf != null) {
                const sw: f64 = @floatFromInt(c.cairo_image_surface_get_width(surf));
                const sh: f64 = @floatFromInt(c.cairo_image_surface_get_height(surf));
                if (sw > 0 and sh > 0) {
                    const sx = w / sw;
                    const sy = h / sh;
                    const s = @max(sx, sy);
                    const dx = x + (w - sw * s) * 0.5;
                    const dy = y + (h - sh * s) * 0.5;
                    c.cairo_save(cr);
                    roundedRect(cr, x, y, w, h, @min(8.0, w * 0.06));
                    c.cairo_clip(cr);
                    c.cairo_translate(cr, dx, dy);
                    c.cairo_scale(cr, s, s);
                    c.cairo_set_source_surface(cr, surf, 0, 0);
                    c.cairo_paint(cr);
                    c.cairo_restore(cr);
                    c.cairo_surface_destroy(surf);
                    roundedRect(cr, x, y, w, h, @min(8.0, w * 0.06));
                    c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.25);
                    c.cairo_set_line_width(cr, 1.0);
                    c.cairo_stroke(cr);
                    return;
                }
                c.cairo_surface_destroy(surf);
            }
        }
        const seed = std.hash.Crc32.hash(entry.title) ^ std.hash.Crc32.hash(entry.artist);
        renderArtPlaceholder(cr, x, y, w, h, seed, border);
    }

    pub fn renderCard(self: *MediaWidget, cr: *c.cairo_t, w_d: f64, h_d: f64, style_: style.Style, scale: f32, out_click: ?*CardClick) void {
        const border = style_.color_border_focused.toF64();
        const muted = style_.color_text_muted.toF64();
        const scale_f: f64 = @as(f64, scale);

        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        const card_frame_mod = @import("card_frame.zig");
        card_frame_mod.Registry.default.drawNamed(cr, style_, w_d, h_d);

        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);

        const pad_x: f64 = 22.0 * scale_f;
        const pad_y: f64 = 14.0 * scale_f;
        const content_w = w_d - 2.0 * pad_x;

        // ---- Category pills ----
        const search_h = @max(34.0 * scale_f, 28.0 * scale_f);
        const pill_h_max = search_h;
        const pill_h_min = @max(26.0 * scale_f, 22.0 * scale_f);
        const pill_gap = 12.0 * scale_f;
        const pill_w = (content_w - 4.0 * pill_gap) / 5.0;
        const cat_y = pad_y;
        const total_pill_w = pill_w * 5.0 + pill_gap * 4.0;
        const pill_start_x = pad_x + (content_w - total_pill_w) * 0.5;
        const search_y = cat_y + pill_h_max + 10.0 * scale_f;
        const pill_r = 6.0 * scale_f;

        const active_display = displayIndex(self.category);
        for (0..5) |i| {
            const offset: i32 = @as(i32, @intCast(i)) - 2;
            const idx_i32 = @mod(@as(i32, @intCast(active_display)) + offset, 5);
            const idx: usize = @intCast(idx_i32);
            const cat = mediaCategoryFromIndex(idx);
            const px = pill_start_x + @as(f64, @floatFromInt(i)) * (pill_w + pill_gap);
            const is_selected = self.category == cat;
            const is_focused = self.focus == .category and is_selected;
            const dist = @abs(offset);
            const dimmer = @as(f64, @floatFromInt(dist));
            const this_h = if (is_selected) pill_h_max else pill_h_min - @min(dimmer * 3.0 * scale_f, pill_h_min - 22.0 * scale_f);
            const py = cat_y + (pill_h_max - this_h) * 0.5;
            const alpha = 0.95 - @as(f64, @floatFromInt(dist)) * 0.06;

            if (out_click) |click| {
                click.cat_for_index[i] = cat;
                click.cat_y[i] = @intFromFloat(py);
                click.cat_h[i] = @intFromFloat(this_h);
                click.cat_x[i] = @intFromFloat(px);
                click.cat_w[i] = @intFromFloat(pill_w);
            }

            roundedRect(cr, px, py, pill_w, this_h, pill_r);
            if (is_focused) {
                // bright focused border
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.14);
                c.cairo_fill_preserve(cr);
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.85);
                c.cairo_set_line_width(cr, 2.5);
                c.cairo_stroke(cr);
            } else if (is_selected) {
                // dimmer unfocused selected border
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.10);
                c.cairo_fill_preserve(cr);
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.45);
                c.cairo_set_line_width(cr, 2.0);
                c.cairo_stroke(cr);
            } else {
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.06);
                c.cairo_fill_preserve(cr);
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.40);
                c.cairo_set_line_width(cr, 1.0);
                c.cairo_stroke(cr);
            }

            const label = categoryLabel(cat);
            const pill_font = @as(f64, style_.font_size_s) * scale_f;
            c.cairo_set_font_size(cr, pill_font);
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, label.ptr, &ext);
            c.cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, if (is_selected) 1.0 else alpha);
            c.cairo_move_to(cr, px + (pill_w - ext.width) * 0.5, py + this_h * 0.5 + pill_font * 0.30);
            c.cairo_show_text(cr, label.ptr);
        }

        // ---- Search bar (shortened) ----
        const search_w = pill_w * 3.0 + pill_gap * 2.0;
        const search_x = pill_start_x + pill_w + pill_gap;
        const search_r = 6.0 * scale_f;

        if (out_click) |click| {
            click.search_x = @intFromFloat(search_x);
            click.search_y = @intFromFloat(search_y);
            click.search_w = @intFromFloat(search_w);
            click.search_h = @intFromFloat(search_h);
        }

        roundedRect(cr, search_x, search_y, search_w, search_h, search_r);
        if (self.focus == .search) {
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.18);
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 1.0);
            c.cairo_set_line_width(cr, 2.0);
            c.cairo_stroke(cr);
        } else {
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.06);
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.25);
            c.cairo_set_line_width(cr, 1.0);
            c.cairo_stroke(cr);
        }

        const search_margin: f64 = 12.0 * scale_f;
        const search_text_x = search_x + search_margin;
        const search_text_w = search_w - 2.0 * search_margin;
        const search_font = @as(f64, style_.font_size_m) * scale_f;
        c.cairo_set_font_size(cr, search_font);

        const display_text: []const u8 = if (self.search_len > 0) std.mem.sliceTo(&self.search_buf, 0) else "search media...";
        if (self.focus == .search or self.search_len > 0) {
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.95);
        } else {
            c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.55);
        }
        self.drawEllipsizedText(cr, display_text, search_text_x, search_y + search_h * 0.5 + search_font * 0.35, search_text_w);

        if (self.focus == .search) {
            const now = animationNowUs();
            if (now -% self.last_caret_blink_us > 500_000) {
                self.show_caret = !self.show_caret;
                self.last_caret_blink_us = now;
            }
            if (self.show_caret) {
                var caret_buf: [128:0]u8 = std.mem.zeroes([128:0]u8);
                const caret_copy = @min(self.search_caret, self.search_len);
                if (caret_copy > 0) {
                    @memcpy(caret_buf[0..caret_copy], self.search_buf[0..caret_copy]);
                }
                caret_buf[caret_copy] = 0;
                var caret_ext: c.cairo_text_extents_t = undefined;
                c.cairo_text_extents(cr, caret_buf[0..caret_copy :0].ptr, &caret_ext);
                const caret_x = search_text_x + caret_ext.width;
                const caret_y0 = search_y + 8.0 * scale_f;
                const caret_y1 = search_y + search_h - 8.0 * scale_f;
                c.cairo_new_path(cr);
                c.cairo_move_to(cr, caret_x, caret_y0);
                c.cairo_line_to(cr, caret_x, caret_y1);
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.95);
                c.cairo_set_line_width(cr, @max(1.0, 1.3 * scale_f));
                c.cairo_stroke(cr);
            }
        } else {
            self.show_caret = true;
        }

        // ---- Result grid + scroller ----
        const list_y = search_y + search_h + 10.0 * scale_f;
        const bar_w: f64 = 5.0 * scale_f;
        const scroller_track: f64 = 30.0 * scale_f; // fixed right-side channel for the scroller and letters
        const cols = self.grid_cols;
        const base_gap: f64 = 36.0 * scale_f;
        const min_gap: f64 = 8.0 * scale_f;
        const tile_gap: f64 = @max(min_gap, base_gap - (scroller_track * self.slider_reveal) / @as(f64, @floatFromInt(cols + 1)));
        const tile_w = (w_d - @as(f64, @floatFromInt(cols + 1)) * base_gap) / @as(f64, @floatFromInt(cols));
        const list_x = tile_gap;
        const list_w = w_d - 2.0 * tile_gap;
        const list_h = h_d - list_y - pad_y;
        const right_gap_center = w_d - tile_gap * 0.5;
        const channel_cx_open = right_gap_center;
        const channel_cx = channel_cx_open + (1.0 - self.slider_reveal) * (tile_gap * 0.5 + scroller_track * 0.5);
        const channel_x = channel_cx - scroller_track * 0.5;

        if (out_click) |click| {
            click.list_x = @intFromFloat(list_x);
            click.list_y = @intFromFloat(list_y);
            click.list_w = @intFromFloat(list_w);
            click.list_h = @intFromFloat(list_h);
            click.scroll_x = @intFromFloat(channel_x);
            click.scroll_y = @intFromFloat(list_y);
            click.scroll_w = @intFromFloat(scroller_track);
            click.scroll_h = @intFromFloat(list_h);
            click.scroll_offset_at_render = self.list_scroll_offset;
            click.letters_x = click.scroll_x;
            click.letters_w = click.scroll_w;
        }


        const label_h = 34.0 * scale_f;
        
        
        const label_font = @as(f64, style_.font_size_s) * scale_f;

        const art_h = tile_w * 1.25;
        const tile_h = art_h + label_h;
        const row_h = tile_h + tile_gap;
        const rows_visible: usize = if (row_h <= 0.0 or list_h <= 0.0) 0 else @max(2, @as(usize, @intFromFloat(@floor(list_h / row_h))));
        const library = getLibrary(self.category);
        const total_rows = (library.len + cols - 1) / cols;
        if (library.len == 0) {
            const msg = switch (self.category) {
                .tv => "Live TV — Coming Soon",
                .shop => "Artist Shop — Coming Soon",
                else => "No items found",
            };
            c.cairo_set_font_size(cr, label_font * 1.3);
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, msg.ptr, &ext);
            const mx = list_x + (list_w - ext.width) * 0.5;
            const my = list_y + list_h * 0.5;
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.65);
            c.cairo_move_to(cr, mx, my);
            c.cairo_show_text(cr, msg.ptr);
            c.cairo_set_font_size(cr, label_font);
            const sub = switch (self.category) {
                .tv => "Tuner + aerial support on the way",
                .shop => "Buy & sell media directly in your player",
                else => "",
            };
            c.cairo_text_extents(cr, sub.ptr, &ext);
            c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.55);
            c.cairo_move_to(cr, list_x + (list_w - ext.width) * 0.5, my + label_font * 1.6);
            c.cairo_show_text(cr, sub.ptr);
        }
        self.visible_result_count = rows_visible * cols;
        self.max_scroll_offset = if (total_rows > rows_visible) total_rows - rows_visible else 0;
        if (self.list_scroll_offset > self.max_scroll_offset) self.list_scroll_offset = self.max_scroll_offset;
        if (self.selected_result >= library.len) self.selected_result = if (library.len > 0) library.len - 1 else 0;

        if (out_click) |click| {
            click.cols = @intCast(cols);
            click.tile_w = @intFromFloat(tile_w);
            click.tile_h = @intFromFloat(tile_h);
            click.tile_gap = @intFromFloat(tile_gap);
        }

        var focus_tx: f64 = 0;
        var focus_ty: f64 = 0;
        var focus_drawn = false;

        var row_i: usize = 0;
        while (row_i < rows_visible and self.list_scroll_offset + row_i < total_rows) : (row_i += 1) {
            const grid_row = self.list_scroll_offset + row_i;
            const ty = list_y + @as(f64, @floatFromInt(row_i)) * row_h;
            const first_idx = grid_row * cols;
            const last_idx = @min(first_idx + cols, library.len);
            const tiles_in_row = last_idx - first_idx;
            _ = tiles_in_row;
            const row_start_x = list_x;
            var col_i: usize = 0;
            while (col_i < cols) : (col_i += 1) {
                const idx = grid_row * cols + col_i;
                if (idx >= library.len) break;
                const entry = library[idx];
                const tx = row_start_x + @as(f64, @floatFromInt(col_i)) * (tile_w + tile_gap);

                if (self.focus == .result and self.selected_result == idx) {
                    focus_tx = tx;
                    focus_ty = ty;
                    focus_drawn = true;
                }

                if (self.focus == .result and self.selected_result == idx) {
                    const sel_pad = 4.0 * scale_f;
                    c.cairo_new_path(cr);
                    roundedRect(cr, tx - sel_pad, ty - sel_pad, tile_w + 2.0 * sel_pad, tile_h + 2.0 * sel_pad, 10.0 * scale_f);
                    c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.35);
                    c.cairo_fill_preserve(cr);
                    c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 1.0);
                    c.cairo_set_line_width(cr, 3.0);
                    c.cairo_stroke(cr);
                }

                renderTileArt(cr, tx, ty, tile_w, art_h, entry, border);

                c.cairo_set_font_size(cr, label_font);
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.95);
                const title_y = ty + art_h + label_font * 1.15;
                self.drawEllipsizedText(cr, std.mem.sliceTo(entry.title, 0), tx, title_y, tile_w);

                c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.75);
                self.drawEllipsizedText(cr, std.mem.sliceTo(entry.artist, 0), tx, title_y + label_font * 1.25, tile_w);
            }
        }

        if (self.focus == .result and focus_drawn) {
            const over_w = tile_w + 20.0 * scale_f;
            const over_h = tile_h + 18.0 * scale_f;
            const ox = focus_tx + tile_w * 0.5 - over_w * 0.5;
            const oy = focus_ty + tile_h * 0.5 - over_h * 0.5;
            const corner = 10.0 * scale_f;

            c.cairo_save(cr);
            roundedRect(cr, ox - 3.0 * scale_f, oy - 3.0 * scale_f, over_w + 6.0 * scale_f, over_h + 6.0 * scale_f, corner + 3.0 * scale_f);
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.28);
            c.cairo_fill(cr);

            roundedRect(cr, ox, oy, over_w, over_h, corner);
            c.cairo_clip(cr);
            c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 1.0);
            c.cairo_paint(cr);

            const over_art_h = over_h - label_h;
            renderTileArt(cr, ox, oy, over_w, over_art_h, library[self.selected_result], border);

            c.cairo_set_font_size(cr, label_font);
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.95);
            const over_title_y = oy + over_art_h + label_font * 1.15;
            self.drawEllipsizedText(cr, std.mem.sliceTo(library[self.selected_result].title, 0), ox, over_title_y, over_w);

            c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.75);
            self.drawEllipsizedText(cr, std.mem.sliceTo(library[self.selected_result].artist, 0), ox, over_title_y + label_font * 1.25, over_w);

            c.cairo_restore(cr);
        }

        // ---- Vertical slider scroller (weather-card style) ----
        const track_h = list_h;
        const track_r = bar_w * 0.5;

        roundedRect(cr, channel_cx - bar_w * 0.5, list_y, bar_w, track_h, track_r);
        c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.12);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.35);
        c.cairo_set_line_width(cr, 1.0);
        c.cairo_stroke(cr);

        const ratio = if (self.max_scroll_offset == 0) 0.0 else @as(f64, @floatFromInt(self.list_scroll_offset)) / @as(f64, @floatFromInt(self.max_scroll_offset));
        const knob_r = @max(bar_w * 1.5, 10.0 * scale_f);
        const usable_h = track_h - bar_w;
        const knob_cx = channel_cx;
        const knob_cy = list_y + bar_w * 0.5 + usable_h * ratio;
        c.cairo_new_path(cr);
        c.cairo_arc(cr, knob_cx, knob_cy, knob_r, 0, 2.0 * std.math.pi);
        c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.9);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.35);
        c.cairo_set_line_width(cr, 1.0);
        c.cairo_stroke(cr);

        // ---- A-Z 5-letter scrolling selector on the vertical slider ----
        const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        const alpha_font_base = @as(f64, style_.font_size_s) * scale_f;
        const strip_w = scroller_track - 4.0 * scale_f;
        const strip_x = channel_cx - strip_w * 0.5;
        const strip_y = list_y;
        const strip_h = list_h;

        if (out_click) |click| {
            click.letters_y = @intFromFloat(strip_y);
            click.letters_h = @intFromFloat(strip_h);
        }

        const show_all = self.slider_hover or self.focus == .slider;
        const center_idx = self.currentSliderLetterIndex();

        const window_size: usize = 5;
        const half_window = window_size / 2;
        var window_start: usize = if (center_idx <= half_window) 0 else center_idx - half_window;
        if (center_idx + half_window >= letters.len) {
            window_start = letters.len - window_size;
        }

        const slot_h = strip_h / @as(f64, @floatFromInt(window_size));
        const current_slot: usize = if (center_idx <= half_window) center_idx else if (center_idx + half_window >= letters.len) window_size - (letters.len - center_idx) else half_window;
        _ = current_slot;

        // Keep the highlight small enough to fit inside the strip without overflowing the card.
        const highlight_r = @min(@as(f64, 8.0) * scale_f, strip_w * 0.36);

        if (show_all) {
            for (letters, 0..) |ch, i| {
                const slot_i = @as(i32, @intCast(i)) - @as(i32, @intCast(window_start));
                if (slot_i < 0 or slot_i >= window_size) continue;

                const distance: usize = if (i > center_idx) i - center_idx else center_idx - i;
                const multiplier: f64 = if (distance == 0) 1.7 else if (distance == 1) 1.25 else 0.88;
                const alpha_font = alpha_font_base * multiplier;

                const slot_y = strip_y + @as(f64, @floatFromInt(slot_i)) * slot_h + slot_h * 0.5 + alpha_font * 0.35;
                const cx = strip_x + strip_w * 0.5;

                const lbuf = [1:0]u8{ch};
                c.cairo_set_font_size(cr, alpha_font);
                var lex: c.cairo_text_extents_t = undefined;
                c.cairo_text_extents(cr, &lbuf, &lex);
                const lx = cx - lex.width * 0.5;

                if (distance == 0) {
                    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.5);
                    c.cairo_new_path(cr);
                    c.cairo_arc(cr, cx, slot_y - alpha_font * 0.25, highlight_r, 0, 2.0 * std.math.pi);
                    c.cairo_fill_preserve(cr);
                    c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.9);
                    c.cairo_set_line_width(cr, 1.0);
                    c.cairo_stroke(cr);
                    c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 1.0);
                } else {
                    c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], 0.65);
                }

                c.cairo_move_to(cr, lx, slot_y);
                c.cairo_show_text(cr, &lbuf);
            }
        }
    }

    fn drawEllipsizedText(_: *MediaWidget, cr: *c.cairo_t, text: []const u8, x: f64, y: f64, max_w: f64) void {
        var ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, text.ptr, &ext);
        if (ext.width <= max_w) {
            c.cairo_move_to(cr, x, y);
            c.cairo_show_text(cr, text.ptr);
            return;
        }
        var clipped: [256:0]u8 = std.mem.zeroes([256:0]u8);
        const copy = @min(text.len, clipped.len - 4);
        if (copy > 0) {
            @memcpy(clipped[0..copy], text[0..copy]);
        }
        clipped[copy] = 0;
        var attempt_len = copy;
        while (attempt_len > 3) {
            attempt_len -= 1;
            clipped[attempt_len] = 0;
            if (attempt_len >= 3) {
                clipped[attempt_len - 3] = '.';
                clipped[attempt_len - 2] = '.';
                clipped[attempt_len - 1] = '.';
                clipped[attempt_len] = 0;
            }
            c.cairo_text_extents(cr, &clipped, &ext);
            if (ext.width <= max_w) break;
            if (attempt_len <= 3) break;
        }
        c.cairo_move_to(cr, x, y);
        c.cairo_show_text(cr, &clipped);
    }

    fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
        const rr = @min(r, w * 0.5, h * 0.5);
        c.cairo_new_path(cr);
        c.cairo_move_to(cr, x + rr, y);
        c.cairo_line_to(cr, x + w - rr, y);
        c.cairo_arc(cr, x + w - rr, y + rr, rr, -std.math.pi * 0.5, 0);
        c.cairo_line_to(cr, x + w, y + h - rr);
        c.cairo_arc(cr, x + w - rr, y + h - rr, rr, 0, std.math.pi * 0.5);
        c.cairo_line_to(cr, x + rr, y + h);
        c.cairo_arc(cr, x + rr, y + h - rr, rr, std.math.pi * 0.5, std.math.pi);
        c.cairo_line_to(cr, x, y + rr);
        c.cairo_arc(cr, x + rr, y + rr, rr, std.math.pi, std.math.pi * 1.5);
        c.cairo_close_path(cr);
    }
};

fn animationNowUs() u64 {
    var ts: unistd.timespec = std.mem.zeroes(unistd.timespec);
    if (unistd.clock_gettime(unistd.CLOCK_MONOTONIC, &ts) != 0) return 0;
    return @as(u64, @intCast(ts.tv_sec)) * 1_000_000 + @as(u64, @intCast(ts.tv_nsec)) / 1000;
}
