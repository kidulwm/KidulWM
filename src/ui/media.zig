const std = @import("std");
const c = @import("dm").c;
const style = @import("../core/style.zig");

const unistd = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0");
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

pub const ControlFocus = enum { category, subcategory, search, result, slider };

const LibraryEntry = struct {
    title: [:0]u8,
    artist: [:0]u8,
    path: [:0]u8,
};

const max_library_entries = 512;
const g_alloc = std.heap.page_allocator;

// ---------------------------------------------------------------------------
// ArtPipeline — widget-owned art state. Surfaces keyed by crc32(resolved
// art path); requests ride a pipe to the worker, results come back on the
// same pipe. The render thread polls the read end non-blocking each frame.
// ---------------------------------------------------------------------------
const kimg = @import("../core/kimg.zig");

const ART_DWELL_US: u64 = 500_000; // 500ms focused before hi-res upgrade
// Speed limit on simultaneous network decodes: one worker drains serially,
// and the queue never holds more than this. Visible wall is ~8 tiles.
const MAX_ART_IN_FLIGHT: u32 = 12;

fn lockArtMutex(m: *std.atomic.Mutex) void {
    while (!m.tryLock()) std.atomic.spinLoopHint();
}

// GLOBAL art cache — one map set for the compositor's lifetime. The
// prewarm thread populates these from the on-disk thumb cache at boot;
// the MediaWidget reads them per tile. Keys are crc32(resolved art path).
// All writes take g_art_mutex (same as queue/results). Reads on the
// render thread are safe because HashMap reads never rehash.
var g_surfaces: std.AutoHashMap(u32, ?*c.cairo_surface_t) = undefined;
var g_no_art: std.AutoHashMap(u32, void) = undefined;
var g_path_by_key: std.AutoHashMap(u32, [:0]u8) = undefined;
var g_in_flight: std.AutoHashMap(u32, void) = undefined;
var g_maps_ready = false;

// Dwell state — render thread only, no cross-thread traffic.
const DwellState = struct {
    key: u32 = 0,
    since_us: u64 = 0,
    hires_done_key: u32 = 0,
};

const ArtPipeline = struct {
    dwell: DwellState = .{},
    ready: bool = false,

    fn init(self: *ArtPipeline, alloc: std.mem.Allocator) void {
        _ = alloc;
        // One-time global map init. idempotent.
        if (!g_maps_ready) {
            g_surfaces = std.AutoHashMap(u32, ?*c.cairo_surface_t).init(g_alloc);
            g_no_art = std.AutoHashMap(u32, void).init(g_alloc);
            g_path_by_key = std.AutoHashMap(u32, [:0]u8).init(g_alloc);
            g_in_flight = std.AutoHashMap(u32, void).init(g_alloc);
            g_maps_ready = true;
        }
        self.ready = true;
        ensureArtWorker();
    }

    fn deinit(self: *ArtPipeline) void {
        // Global maps survive for the compositor's lifetime — no deinit
        // of shared data, just mark this widget's thread-local state.
        self.* = .{};
    }
};

// Request queue lives behind the GLOBAL art mutex; ONE global worker drains
// it. The queue/results are file-globals, so the worker must be too —
// per-widget workers raced on the shared queue and tripped the 0.16
// atomic.Mutex unlock assert (the Movies crash, thread panic at unlock).
var art_req_queue: std.ArrayListUnmanaged(kimg.Request) = .empty;
var art_results: std.ArrayListUnmanaged(kimg.Result) = .empty;
var g_art_mutex: std.atomic.Mutex = .unlocked;
// Two ONE-WAY pipes. The crashed design shared one pipe both directions:
// worker poll() and render-thread read() raced to steal wake bytes from
// each other, and every queued request + every result wrote a byte, so the
// pipe stayed readable forever -> compositor re-rendered at 100% CPU (the
// lag) and the byte race was the lurking crash vector.
var g_work_r: i32 = -1; // worker reads requests-wake from this
var g_work_w: i32 = -1; // render thread writes to this
var g_done_r: i32 = -1; // render thread reads results-wake from this
var g_done_w: i32 = -1; // worker writes to this
var g_worker_started = false;
var g_worker_quit: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

fn ensureArtWorker() void {
    if (g_worker_started) return;
    g_worker_started = true;
    var work_fds: [2]i32 = .{ -1, -1 };
    var done_fds: [2]i32 = .{ -1, -1 };
    if (c_linux.pipe2(&work_fds, .{ .NONBLOCK = true, .CLOEXEC = true }) == 0) {
        g_work_r = work_fds[0];
        g_work_w = work_fds[1];
    }
    if (c_linux.pipe2(&done_fds, .{ .NONBLOCK = true, .CLOEXEC = true }) == 0) {
        g_done_r = done_fds[0];
        g_done_w = done_fds[1];
    }
    _ = std.Thread.spawn(.{}, artWorkerMain, .{}) catch {
        std.log.info("kimg: worker spawn failed", .{});
    };
}

fn wakeFdDrain(fd: i32) void {
    if (fd < 0) return;
    var sink: [64]u8 = undefined;
    while (true) {
        const rc = c_linux.read(fd, &sink, sink.len);
        const signed: i64 = @bitCast(rc);
        if (signed <= 0) break;
        if (signed < sink.len) break;
    }
}

fn pokeArtWorker() void {
    if (g_work_w >= 0) {
        var b: [1]u8 = .{1};
        _ = c_linux.write(g_work_w, &b, 1);
    }
}

fn artWorkerMain() void {
    std.log.info("kimg trace: worker thread entered, work_r={d}", .{g_work_r});
    while (!g_worker_quit.load(.acquire)) {
        // Wait for work on OUR pipe only.
        var pfd = [_]c_linux.pollfd{.{ .fd = g_work_r, .events = c_linux.POLL.IN, .revents = 0 }};
        _ = c_linux.poll(&pfd, 1, 500);
        if (g_worker_quit.load(.acquire)) break;
        wakeFdDrain(g_work_r); // consume ALL pending bytes before draining

        var batch: u32 = 0;
        while (true) {
            var req_opt: ?kimg.Request = null;
            {
                lockArtMutex(&g_art_mutex);
                defer g_art_mutex.unlock();
                if (art_req_queue.items.len > 0) {
                    req_opt = art_req_queue.orderedRemove(0);
                }
            }
            const req = req_opt orelse break;
            const res = kimg.processRequest(g_alloc, req);
            {
                lockArtMutex(&g_art_mutex);
                defer g_art_mutex.unlock();
                art_results.append(g_alloc, res) catch {};
            }
            batch += 1;
        }
        // ONE wake per batch, not one per result — kills the re-render storm.
        if (batch > 0 and g_done_w >= 0) {
            std.log.info("kimg trace: worker batch done, {d} results", .{batch});
            var b: [1]u8 = .{1};
            _ = c_linux.write(g_done_w, &b, 1);
        }
    }
}

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
        .music => &[_][]const u8{ "/home/kidul/Music", "/mnt/hostmedia/music", "/mnt/sda_backup/Jelly/Music" },
        .movies => &[_][]const u8{ "/home/kidul/Movies", "/home/kidul/Videos", "/mnt/hostmedia/jelly/Kids Movies", "/mnt/hostmedia/jelly/Movies", "/mnt/sda_backup/Jelly/Kids Movies", "/mnt/sda_backup/Jelly/Movies" },
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

/// Boot-time pre-warm: scan every category and resolve art paths on a
/// background thread so the render thread never blocks on first open.
///
/// SAFETY: g_* atomics are the ONLY cross-thread state. The prewarm writes
/// through intermediate locals, then publishes with a release-store of the
/// ready flag. The render thread sees either (ready=false) and falls through
/// to the lazy scan as before, or (ready=true, entries fully written).
/// No torn reads, no mutexes on the hot path.
pub fn prewarmThread() void {
    std.log.info("kmedia: prewarm started", .{});

    // Scan into local arrays first, then publish with release semantics.
    // The g_*_count/ready atomics are the ONLY things the render thread
    // ever reads from another thread's writes.
    var music_tmp: [max_library_entries]LibraryEntry = undefined;
    const music_n = scanCategory(.music, &music_tmp);
    @memcpy(&g_music, &music_tmp);
    g_music_count = music_n;
    // Release-store: everything above is visible before the flag goes true.
    @atomicStore(bool, &g_music_ready, true, .release);

    var movies_tmp: [max_library_entries]LibraryEntry = undefined;
    const movies_n = scanCategory(.movies, &movies_tmp);
    @memcpy(&g_movies, &movies_tmp);
    g_movies_count = movies_n;
    @atomicStore(bool, &g_movies_ready, true, .release);

    var pics_tmp: [max_library_entries]LibraryEntry = undefined;
    const pics_n = scanCategory(.pictures, &pics_tmp);
    @memcpy(&g_pictures, &pics_tmp);
    g_pictures_count = pics_n;
    @atomicStore(bool, &g_pictures_ready, true, .release);

    std.log.info("kmedia: prewarm scan done: music={d} movies={d} pics={d}", .{ music_n, movies_n, pics_n });

    // Pre-decode thumbs from the on-disk cache into the GLOBAL surface map.
    // Any tile with a cached 256px PNG on disk gets its surface NOW, on the
    // prewarm thread, so the first render hits RAM, not SSHFS. Tiles with no
    // disk cache get queued for the art worker (which decodes from the
    // network and writes to disk for next boot).
    if (!g_maps_ready) {
        g_surfaces = std.AutoHashMap(u32, ?*c.cairo_surface_t).init(g_alloc);
        g_no_art = std.AutoHashMap(u32, void).init(g_alloc);
        g_path_by_key = std.AutoHashMap(u32, [:0]u8).init(g_alloc);
        g_in_flight = std.AutoHashMap(u32, void).init(g_alloc);
        g_maps_ready = true;
    }

    const cats = [_]struct { entries: []const LibraryEntry, is_music: bool, is_pic: bool }{
        .{ .entries = g_music[0..g_music_count], .is_music = true, .is_pic = false },
        .{ .entries = g_movies[0..g_movies_count], .is_music = false, .is_pic = false },
        .{ .entries = g_pictures[0..g_pictures_count], .is_music = false, .is_pic = true },
    };

    var cached_n: u32 = 0;
    var queued_n: u32 = 0;
    var noart_n: u32 = 0;
    for (cats) |cat| {
        for (cat.entries) |entry| {
            const art_path = kimg.resolveArtPath(std.heap.page_allocator, entry.path, cat.is_music, cat.is_pic) orelse {
                g_no_art.put(std.hash.Crc32.hash(entry.path), {}) catch {};
                noart_n += 1;
                continue;
            };
            const key = kimg.thumbKey(art_path);
            if (g_surfaces.contains(key)) {
                std.heap.page_allocator.free(art_path);
                continue;
            }
            // Store resolved path for the widget's dwell lookups.
            if (!g_path_by_key.contains(key)) {
                g_path_by_key.put(key, art_path) catch {
                    std.heap.page_allocator.free(art_path);
                    continue;
                };
            }
            // Try the disk cache first — instant, no network.
            if (kimg.thumbCachePath(std.heap.page_allocator, art_path)) |cache_path| {
                if (kimg.fileExists(cache_path)) {
                    const surf = c.cairo_image_surface_create_from_png(cache_path.ptr);
                    if (surf != null and c.cairo_surface_status(surf) == c.CAIRO_STATUS_SUCCESS) {
                        g_surfaces.put(key, surf) catch {};
                        cached_n += 1;
                        std.heap.page_allocator.free(cache_path);
                        continue;
                    }
                    if (surf != null) c.cairo_surface_destroy(surf);
                }
                std.heap.page_allocator.free(cache_path);
            }
            // Not on disk — queue for the art worker.
            const owned_art = g_alloc.dupeZ(u8, art_path) catch continue;
            const owned_cache = kimg.thumbCachePath(g_alloc, art_path) orelse {
                g_alloc.free(owned_art);
                continue;
            };
            if (!g_in_flight.contains(key)) {
                g_in_flight.put(key, {}) catch {};
                lockArtMutex(&g_art_mutex);
                art_req_queue.append(g_alloc, .{ .key = key, .kind = .thumb, .art_path = owned_art, .cache_path = owned_cache }) catch {};
                g_art_mutex.unlock();
                queued_n += 1;
            } else {
                g_alloc.free(owned_art);
                g_alloc.free(owned_cache);
            }
            std.heap.page_allocator.free(art_path);
        }
    }
    std.log.info("kmedia: prewarm cache={d} queued={d} noart={d}", .{ cached_n, queued_n, noart_n });
    pokeArtWorker();
}

/// Spawn the prewarm on a background thread. Called from Server.init.
/// Thread completes quickly, self-contained, no shared state to race.
pub fn spawnPrewarm() void {
    _ = std.Thread.spawn(.{}, prewarmThread, .{}) catch |err| {
        std.log.warn("kmedia: prewarm spawn failed: {}", .{err});
    };
}

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

// ---------------------------------------------------------------------------
// THE PILL — brand-locked house spec (kbrowser slider lineage).
// These constants are OURS, not the theme's: user theme changes must not
// touch pill geometry or colors. Recognisable up close and from afar.
// Geometry per segment matches the original 3-pill kbrowser slider:
//   track h=56, inner pill inset 5 (h=46), full stadium radius, 280px segs.
// ---------------------------------------------------------------------------
const PILL_SEG_W: f64 = 280.0; // same segment width the original 3 had
const PILL_TRACK_H: f64 = 56.0;
const PILL_INSET: f64 = 5.0;
const PILL_COUNT: usize = 5;

const PillColor = struct { r: f64, g: f64, b: f64 };

fn pc(hex: u24) PillColor {
    return .{
        .r = @as(f64, @floatFromInt((hex >> 16) & 0xFF)) / 255.0,
        .g = @as(f64, @floatFromInt((hex >> 8) & 0xFF)) / 255.0,
        .b = @as(f64, @floatFromInt(hex & 0xFF)) / 255.0,
    };
}

const PILL_TRACK_FILL = pc(0x0a0a0a);
const PILL_TRACK_BORDER = pc(0x4d4a40);
const PILL_GOLD = pc(0x948e7b);
const PILL_TEXT_ACTIVE = pc(0xe8e6df);
const PILL_TEXT_DIM = pc(0x6a6354);

fn pillModeColor(cat: MediaCategory) PillColor {
    // House set — sits beside the browser trio. Fine-tune hex at polish pass.
    return switch (cat) {
        .music => pc(0x9e7e52), // amber (retired Isolate)
        .movies => pc(0x6a8fc4), // blue
        .tv => pc(0x6b9e75), // green
        .pictures => pc(0x948e7b), // gold-grey
        .shop => pc(0xc45c5c), // muted red
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
    subcategory_open: bool = false,
    subcategory_index: usize = 0,
    subcategory_for: MediaCategory = .music,
    search_buf: [128:0]u8 = std.mem.zeroes([128:0]u8),
    search_len: usize = 0,
    search_focused: bool = false,
    search_caret: usize = 0,
    last_caret_blink_us: u64 = 0,
    show_caret: bool = true,
    grid_cols: usize = 5,
    art_cache: std.StringHashMap(?*c.cairo_surface_t),

    // ---- kimg art pipeline (law: local art is sacred, wall = 256px ----
    // ---- thumbs, focused card dwells into hi-res, decode off-thread) ----
    art: ArtPipeline = .{},

    state_generation: u32 = 0,
    slider_reveal: f64 = 0.0,
    slider_reveal_target: f64 = 0.0,
    /// UP+1 state: pills centered, row0 below, nothing else.
    up_plus_one: bool = false,

    selected_result: usize = 0,
    visible_result_count: usize = 0,
    list_scroll_offset: usize = 0,
    max_scroll_offset: usize = 0,
    slider_hover: bool = false,

    pub fn init(allocator: std.mem.Allocator) MediaWidget {
        const ipc = "/run/user/1000/kidulwm-mpv.sock";
        var self = MediaWidget{
            .allocator = allocator,
            .art_cache = std.StringHashMap(?*c.cairo_surface_t).init(allocator),
        };
        @memcpy(self.ipc_path[0..ipc.len], ipc);
        self.ipc_path[ipc.len] = 0;
        self.art.init(allocator);
        return self;
    }

    pub fn deinit(self: *MediaWidget) void {
        self.art.deinit();
        self.clearArtCache();
        self.art_cache.deinit();
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
            self.slider_reveal = 0.0;
            self.slider_reveal_target = 0.0;
            self.clearSearch();
        } else {
            self.slider_reveal = 0.0;
            self.slider_reveal_target = 0.0;
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
        if (ctl == .result or ctl == .slider) {
            self.subcategory_open = false;
            self.subcategory_index = 0;
            self.up_plus_one = false; // entering cards kills UP+1
        }
        if (ctl == .category) {
            // Landing or UP+1: decided by up_plus_one flag
        }
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
        const speed = 80.0; // near-instant slide
        if (self.slider_reveal < self.slider_reveal_target) {
            self.slider_reveal = @min(self.slider_reveal_target, self.slider_reveal + dt * speed);
        } else if (self.slider_reveal > self.slider_reveal_target) {
            self.slider_reveal = @max(self.slider_reveal_target, self.slider_reveal - dt * speed);
        }
        if (self.slider_reveal != prev_reveal) self.bumpGeneration();
    }

    /// Drain finished art results (called each render). Returns true when
    /// at least one tile's surface landed, so the caller can re-render.
    pub fn pollArtResults(self: *MediaWidget) bool {
        if (!self.art.ready) return false;
        var landed = false;
        // Drain OUR pipe (done direction) so wake bytes don't accumulate.
        wakeFdDrain(g_done_r);
        while (true) {
            var res_opt: ?kimg.Result = null;
            {
                lockArtMutex(&g_art_mutex);
                defer g_art_mutex.unlock();
                if (art_results.items.len > 0) res_opt = art_results.orderedRemove(0);
            }
            const res = res_opt orelse break;
            const flight_key = res.key ^ (if (res.kind == .hires) @as(u32, 0x8000_0000) else 0);
            _ = g_in_flight.remove(flight_key);
            // Only the latest dwell target may own the hi-res slot.
            if (res.kind == .hires) {
                if (res.key != self.art.dwell.key) {
                    if (res.surface) |s| c.cairo_surface_destroy(s);
                    continue;
                }
                if (self.art.dwell.hires_done_key != 0 and self.art.dwell.hires_done_key != res.key) {
                    if (g_surfaces.get(self.art.dwell.hires_done_key)) |old| {
                        if (old) |s| c.cairo_surface_destroy(s);
                        _ = g_surfaces.remove(self.art.dwell.hires_done_key);
                    }
                }
                self.art.dwell.hires_done_key = if (res.surface != null) res.key else 0;
            }
            const gop = g_surfaces.getOrPut(res.key) catch continue;
            if (gop.found_existing) {
                if (gop.value_ptr.*) |old| c.cairo_surface_destroy(old);
            }
            gop.value_ptr.* = res.surface;
            landed = true;
        }
        if (landed) self.bumpGeneration();
        return landed;
    }

    /// Ensure a thumb request is queued for this entry. Render-thread cheap:
    /// path resolve + hash + map lookup; decode rides the worker.
    fn requestThumb(self: *MediaWidget, entry: LibraryEntry, is_music: bool, is_picture: bool) ?u32 {
        _ = self; // global maps now, but keep the signature
        // Fast path: memoized "no art" — zero syscalls, zero allocs.
        const entry_key = std.hash.Crc32.hash(entry.path);
        if (g_no_art.contains(entry_key)) return null;
        const art_path = kimg.resolveArtPath(g_alloc, entry.path, is_music, is_picture) orelse {
            g_no_art.put(entry_key, {}) catch {};
            return null;
        };
        std.log.info("kimg trace: resolved '{s}' -> {s}", .{ entry.title, art_path });
        const key = kimg.thumbKey(art_path);
        if (g_surfaces.contains(key)) {
            g_alloc.free(art_path);
            return key;
        }
        // Remember the resolved path for the dwell hi-res request.
        if (!g_path_by_key.contains(key)) {
            const dup = g_alloc.dupeZ(u8, art_path) catch art_path;
            g_path_by_key.put(key, dup) catch {};
            if (dup.ptr != art_path.ptr) g_alloc.free(art_path);
        } else {
            g_alloc.free(art_path);
        }
        if (!g_in_flight.contains(key)) {
            // Throttle: never more than MAX_IN_FLIGHT requests queued. The wall
            // shows ~8 tiles; 148 at once is what burst the mount and starved
            // the render thread (the Movies crash). Over the limit the tile
            // keeps its placeholder this frame — next render retries.
            if (g_in_flight.count() >= MAX_ART_IN_FLIGHT) return key;
            const cached = kimg.thumbCachePath(g_alloc, g_path_by_key.get(key).?) orelse return key;
            const owned_art = g_alloc.dupeZ(u8, g_path_by_key.get(key).?) catch {
                g_alloc.free(cached);
                return key;
            };
            g_in_flight.put(key, {}) catch {
                g_alloc.free(owned_art);
                g_alloc.free(cached);
                return key;
            };
            {
                lockArtMutex(&g_art_mutex);
                defer g_art_mutex.unlock();
                art_req_queue.append(g_alloc, .{ .key = key, .kind = .thumb, .art_path = owned_art, .cache_path = cached }) catch |e| {
                    std.log.info("kimg trace: queue append FAILED key={x} err={s}", .{ key, @errorName(e) });
                };
                std.log.info("kimg trace: queued key={x} qlen={d}", .{ key, art_req_queue.items.len });
            }
            pokeArtWorker();
        }
        return key;
    }

    /// Focused-card dwell: after ART_DWELL_US on the same tile, queue the
    /// hi-res upgrade exactly once per focus target.
    fn tickDwell(self: *MediaWidget, focused_key: ?u32) void {
        const now = animationNowUs();
        if (focused_key) |k| {
            if (k != self.art.dwell.key) {
                self.art.dwell.key = k;
                self.art.dwell.since_us = now;
            }
        } else {
            self.art.dwell.key = 0;
            self.art.dwell.since_us = 0;
            return;
        }
        const k = focused_key.?;
        if (self.art.dwell.hires_done_key == k) return;
        if (now -% self.art.dwell.since_us < ART_DWELL_US) return;
        const art_path = g_path_by_key.get(k) orelse return;
        const flight_key = k ^ 0x8000_0000;
        if (g_in_flight.contains(flight_key)) return;
        const owned = g_alloc.dupeZ(u8, art_path) catch return;
        const cached = g_alloc.dupeZ(u8, "") catch {
            g_alloc.free(owned);
            return;
        };
        g_in_flight.put(flight_key, {}) catch {
            g_alloc.free(owned);
            g_alloc.free(cached);
            return;
        };
        {
            lockArtMutex(&g_art_mutex);
            defer g_art_mutex.unlock();
            art_req_queue.append(g_alloc, .{ .key = k, .kind = .hires, .art_path = owned, .cache_path = cached }) catch {};
        }
        pokeArtWorker();
    }

    fn bumpGeneration(self: *MediaWidget) void {
        self.state_generation +%= 1;
    }

    pub fn subcategoryNames(self: *const MediaWidget, cat: MediaCategory) []const []const u8 {
        _ = self;
        return switch (cat) {
            .movies => &[_][]const u8{ "Action", "Comedy", "Drama", "Horror", "Sci-Fi" },
            .music => &[_][]const u8{ "Rock", "Pop", "Jazz", "Classical", "Electronic" },
            .tv => &[_][]const u8{ "Series", "Live", "Docs", "Kids", "Sport" },
            .pictures => &[_][]const u8{ "Photos", "Wallpapers", "Screenshots", "Art" },
            .shop => &[_][]const u8{},
        };
    }

    pub fn canOpenSubcategory(self: *const MediaWidget) bool {
        return self.subcategoryNames(self.category).len > 0 and !self.subcategory_open;
    }

    pub fn openSubcategory(self: *MediaWidget) void {
        const names = self.subcategoryNames(self.category);
        if (names.len == 0) return;
        self.subcategory_for = self.category;
        self.subcategory_open = true;
        self.subcategory_index = 0;
        self.focus = .subcategory;
        self.bumpGeneration();
    }

    pub fn closeSubcategory(self: *MediaWidget) void {
        self.subcategory_open = false;
        self.subcategory_index = 0;
        self.focus = .category;
        self.bumpGeneration();
    }

    pub fn moveSubcategory(self: *MediaWidget, delta: i32) void {
        const names = self.subcategoryNames(self.category);
        if (names.len == 0) return;
        var idx: i32 = @intCast(self.subcategory_index);
        idx += delta;
        idx = @max(0, @min(idx, @as(i32, @intCast(names.len - 1))));
        self.subcategory_index = @intCast(idx);
        self.bumpGeneration();
    }

    pub fn moveCategory(self: *MediaWidget, delta: i32) void {
        const idx: i32 = @intCast(displayIndex(self.category));
        const raw = idx + delta;
        const new_idx = @max(0, @min(4, raw));
        self.setCategory(mediaCategoryFromIndex(@intCast(new_idx)));
    }

    pub fn setCategory(self: *MediaWidget, cat: MediaCategory) void {
        self.category = cat;
        self.subcategory_open = false;
        self.subcategory_index = 0;
        self.search_len = 0;
        self.search_caret = 0;
        self.selected_result = 0;
        self.list_scroll_offset = 0;
        self.bumpGeneration();
    }

    pub fn moveResultSelection(self: *MediaWidget, delta: i32) void {
        const library = getLibrary(self.category);
        if (library.len == 0) return;
        // HARD STOPS: no wrap on horizontal. ←→ walk the row, edges stick.
        var idx: i32 = @intCast(self.selected_result);
        idx += delta;
        idx = @max(0, @min(idx, @as(i32, @intCast(library.len - 1))));
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
            // HARD STOP at top: row0 is the ceiling. No wrap.
            row = 0;
        } else if (new_row_uncapped >= total_rows) {
            // HARD STOP at bottom: last row is the floor. No wrap.
            row = total_rows - 1;
            const last_row_items: i32 = @intCast(library.len - @as(usize, @intCast(row)) * @as(usize, @intCast(cols)));
            if (col >= last_row_items) col = last_row_items - 1;
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
        // CFC: the row you're moving TO becomes center.
        // scroll_offset = selected_row, clamped to [0, max_scroll_offset].
        // The render centers (grid_row - scroll_offset) at h_d/2, so
        // offset = selected_row puts the selected row dead center.
        // Row above = top peek, row below = bottom peek.
        const cols: usize = self.grid_cols;
        const selected_row = self.selected_result / cols;
        var off: i32 = @as(i32, @intCast(selected_row));
        off = @max(0, @min(off, @as(i32, @intCast(self.max_scroll_offset))));
        self.list_scroll_offset = @intCast(off);
        self.bumpGeneration();
    }

    pub fn jumpToLetter(self: *MediaWidget, letter: u8) void {
        self.jumpToSearchPrefix(&.{letter});
    }

    pub fn jumpToSearchPrefix(self: *MediaWidget, needle: []const u8) void {
        const library = getLibrary(self.category);
        if (library.len == 0) return;
        if (needle.len == 0) return;
        const lower_needle = std.ascii.lowerString(&self.search_buf, needle);
        var idx: usize = 0;
        // Find first title starting with prefix.
        for (library, 0..) |entry, i| {
            const title = std.mem.sliceTo(entry.title, 0);
            if (title.len == 0) continue;
            if (title.len < lower_needle.len) continue;
            if (std.ascii.eqlIgnoreCase(title[0..lower_needle.len], lower_needle)) {
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

    pub fn moveSliderVertical(self: *MediaWidget, rows_delta: i32) void {
        const rows_per_letter: i32 = 1;
        var off: i32 = @intCast(self.list_scroll_offset);
        off += rows_delta * rows_per_letter;
        off = @max(0, @min(off, @as(i32, @intCast(self.max_scroll_offset))));
        self.list_scroll_offset = @intCast(off);
        self.bumpGeneration();
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

    pub fn hasResults(self: *const MediaWidget) bool {
        return getLibrary(self.category).len > 0;
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
                "--ao=pipewire,pulse,alsa,null".ptr,
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

        // kmedia band data: 7 octave bands on the 432 Hz ladder (A2..A8).
        const kmedia = @import("../core/kmedia.zig");
        const kb = kmedia.bands();
        const audio_level = kmedia.level();
        const audio_live = audio_level > 0.03;

        // Vertical infinity symbol: a Lissajous figure-8 (x=sin θ, y=sin 2θ)
        // traced as two interleaved dot chains — one continuous line that
        // reads as two snakes. The whole 8 precesses slowly about its
        // vertical axis: one full turn per 60s, always moving, never loud.
        const turn_speed: f64 = 2.0 * std.math.pi / 60.0; // rad/s
        self.helix_phase += dt * turn_speed;
        const precess = @cos(self.helix_phase);

        const rung_count = 7;
        const half_h = lane_h * 0.5;
        const half_w = @min(band_w * 0.5, half_h * 0.55);

        // --- Whispy octave rungs -------------------------------------------
        // Each rung sits inside BOTH loops of the 8. At a given height the
        // loop wall crosses at x = ±x_inner (pinch side) and x = ±x_outer,
        // so we draw two segments per loop [x_inner, x_outer] and
        // [-x_outer, -x_inner] — never across the empty center gap.
        for (0..rung_count) |r| {
            // Original even spread across the full figure-8, bottom to top,
            // now clipped to the loop walls at each height.
            const frac = (@as(f64, @floatFromInt(r)) + 0.75) / (@as(f64, rung_count) + 0.5);
            const ry = cy + half_h - frac * lane_h;
            const e: f64 = @floatCast(@min(1.2, kb[r] * 1.4));
            const base_alpha: f64 = if (audio_live) 0.18 + 0.45 * e else 0.10;
            const lw = @max(1.0, 1.0 + 2.0 * e) * scale_f;

            const ny = std.math.clamp(@abs(ry - cy) / half_h, 0.0, 0.99);
            const half_asin = std.math.asin(ny) * 0.5;
            const x_inner = @sin(half_asin) * half_w * @abs(precess);
            const x_outer = @cos(half_asin) * half_w * @abs(precess);
            if (x_outer - x_inner < 1.5) continue;

            for ([2]f64{ -1.0, 1.0 }) |seg_side| {
                const xa = cx + seg_side * x_inner;
                const xb = cx + seg_side * x_outer;
                c.cairo_set_line_width(cr, lw);
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], base_alpha);
                c.cairo_move_to(cr, @min(xa, xb), ry);
                c.cairo_line_to(cr, @max(xa, xb), ry);
                c.cairo_stroke(cr);

                // Ghost whisp when the octave is loud.
                if (audio_live and e > 0.45) {
                    const ghost_off = 1.8 * scale_f;
                    c.cairo_set_line_width(cr, 1.0 * scale_f);
                    c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.35 * e);
                    const gx0 = @min(xa, xb) + (xb - xa) * 0.07 * seg_side;
                    const gx1 = @max(xa, xb) - (xb - xa) * 0.07 * seg_side;
                    c.cairo_move_to(cr, gx0, ry + ghost_off);
                    c.cairo_line_to(cr, gx1, ry + ghost_off);
                    c.cairo_stroke(cr);
                }
            }
        }

        // --- Figure-8 outline as two interleaved dot chains -----------------
        const dot_count: usize = 56;
        const chain_dot_r: f64 = @max(1.0, 1.3 * scale_f);
        for (0..2) |chain| {
            const chain_off = @as(f64, @floatFromInt(chain)) * std.math.pi / @as(f64, @floatFromInt(dot_count));
            for (0..dot_count) |i| {
                const theta = @as(f64, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f64, @floatFromInt(dot_count)) + chain_off;
                const px = cx + @sin(theta) * half_w * precess;
                const py = cy + @sin(2.0 * theta) * half_h;
                // Fade dots near the "back" of the precession for depth.
                const depth = 0.55 + 0.45 * @cos(theta + self.helix_phase);
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.30 + 0.30 * depth);
                c.cairo_arc(cr, px, py, chain_dot_r, 0, 2.0 * std.math.pi);
                c.cairo_fill(cr);
            }
        }

        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
        const txt = if (self.cached.title[0] != 0) std.mem.sliceTo(&self.cached.title, 0) else "";
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
        sub_x: [5]i32 = .{ 0, 0, 0, 0, 0 },
        sub_y: i32 = 0,
        sub_w: [5]i32 = .{ 0, 0, 0, 0, 0 },
        sub_h: i32 = 0,
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

    fn renderTileArt(
        self: *MediaWidget,
        cr: *c.cairo_t,
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        entry: LibraryEntry,
        border: [4]f64,
        is_music: bool,
        is_picture: bool,
        is_focused: bool,
    ) ?u32 {
        const seed = std.hash.Crc32.hash(entry.title);
        const key = self.requestThumb(entry, is_music, is_picture);
        // Dwell target tracking happens in the render loop caller.
        _ = is_focused;

        var surf: ?*c.cairo_surface_t = null;
        if (key) |k| {
            if (g_surfaces.get(k)) |v| surf = v;
        }
        // Hi-res upgrade replaces the thumb surface for that key wholesale —
        // same key, bigger pixels, so no special draw path needed here.

        if (surf) |s| {
            const sw: f64 = @floatFromInt(c.cairo_image_surface_get_width(s));
            const sh: f64 = @floatFromInt(c.cairo_image_surface_get_height(s));
            if (sw > 0 and sh > 0) {
                const sx = w / sw;
                const sy = h / sh;
                const scale_factor = @max(sx, sy);
                const dx = x + (w - sw * scale_factor) * 0.5;
                const dy = y + (h - sh * scale_factor) * 0.5;
                c.cairo_save(cr);
                roundedRect(cr, x, y, w, h, @min(8.0, w * 0.06));
                c.cairo_clip(cr);
                c.cairo_translate(cr, dx, dy);
                c.cairo_scale(cr, scale_factor, scale_factor);
                c.cairo_set_source_surface(cr, s, 0, 0);
                c.cairo_paint(cr);
                c.cairo_restore(cr);
                roundedRect(cr, x, y, w, h, @min(8.0, w * 0.06));
                c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.25);
                c.cairo_set_line_width(cr, 1.0);
                c.cairo_stroke(cr);
                return key;
            }
        }
        renderArtPlaceholder(cr, x, y, w, h, seed, border);
        return key;
    }

    pub fn clearArtCache(self: *MediaWidget) void {
        var it = self.art_cache.valueIterator();
        while (it.next()) |ptr| {
            if (ptr.*) |surf| c.cairo_surface_destroy(surf);
        }
        self.art_cache.clearRetainingCapacity();
    }

    pub fn renderCard(self: *MediaWidget, cr: *c.cairo_t, w_d: f64, h_d: f64, style_: style.Style, scale: f32, out_click: ?*CardClick) void {
        // Art worker drain: pop-in thumbnails land here, one gen per batch.
        _ = self.pollArtResults();
        const border = style_.color_border_focused.toF64();
        const muted = style_.color_text_muted.toF64();
        const card_bg = style_.color_background.toF64();
        const scale_f: f64 = @as(f64, scale);

        // Slide mode (out_click == null): wear the system chrome — corners
        // + 2px focused ring, same tokens every other slide gets. Card
        // callers keep their full-bleed fill.
        const as_slide = (out_click == null);
        const corner_r = @as(f64, style_.corner_depth) * scale_f;
        if (as_slide) {
            // Transparent outside the corner path.
            c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
            c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
            c.cairo_paint(cr);
            c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);
            // Clip everything to the slide's corner shape.
            c.cairo_save(cr);
            mediaSlidePath(cr, 0, 0, w_d, h_d, corner_r, style_.corner_style);
            c.cairo_clip(cr);
        }

        // Full slide: fill background, no card frame.
        const bg4 = style_.color_card_mat.toF64();
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], 0.91);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);

        const pad_x: f64 = 22.0 * scale_f;
        const pad_y: f64 = 14.0 * scale_f;
        const content_w = w_d - 2.0 * pad_x;

        // ---- CFC layout: results ride the TOP band, the interaction ----
        // ---- stack sits at screen CENTER. The stack is ONE slot with ----
        // ---- two states: pill track, or searchbar when she types.    ----
        const pb_seg_w = PILL_SEG_W * scale_f;
        const pb_track_h = PILL_TRACK_H * scale_f;
        const pb_track_w = pb_seg_w * @as(f64, @floatFromInt(PILL_COUNT));
        const pb_track_x = pad_x + @max(0.0, (content_w - pb_track_w) * 0.5);
        const pb_track_r = pb_track_h * 0.5;
        const pb_inset = PILL_INSET * scale_f;
        const pb_pill_h = pb_track_h - 2.0 * pb_inset;
        const pb_pill_r = pb_pill_h * 0.5;
        const pill_w = pb_seg_w - 2.0 * pb_inset;
        const active_display = displayIndex(self.category);
        const mcol = pillModeColor(self.category);

        // ---- CFC LAW: the row you're moving TO becomes center. ----
        // ---- Direction determines destination. Destination becomes center. ----
        const search_active = self.search_focused or self.search_len > 0;
        const in_wall = (self.focus == .result or self.focus == .slider) and !search_active;

        const sub_names = self.subcategoryNames(self.category);
        const sub_rows: f64 = if (self.subcategory_open and sub_names.len > 0) 1.0 else 0.0;
        const stack_gap = 8.0 * scale_f;
        const stack_h = pb_track_h + sub_rows * (pb_track_h + stack_gap);

        // ---- TILE DIMS: constant 2:3 fan art; only focus inflates.   ----
        const gap: f64 = 56.0 * scale_f; // ONE Goldilocks gap everywhere
        const grid_top = pad_y + gap;
        const cols = self.grid_cols;
        const tile_gap: f64 = gap;
        const tile_w = (w_d - @as(f64, @floatFromInt(cols + 1)) * gap) / @as(f64, @floatFromInt(cols));
        const art_h = tile_w * 1.5;
        const tile_h = art_h;
        const row_h = tile_h + tile_gap;

        // ---- THE CFC LAW — one sentence: -------------------------------
        // ---- "The row you're moving TO becomes center." -----------------
        //
        // LANDING (focus in chrome, up_plus_one = false):
        //   Pills bar centered. Row0 above, row1 below. Even gaps.
        //   stack_y = (h_d - stack_h) / 2
        //   row0_top = stack_y - gap - tile_h
        //   row1_top = stack_y + stack_h + gap
        //
        // THE UP (↑ from landing, or scrolled back to row0):
        //   Row0 centered at h_d/2. Top peek EMPTY. Row1 half below.
        //   Pills gone.
        //
        // THE DOWN (↓ from landing):
        //   Row1 centered at h_d/2. Row0 half above. Row2 half below.
        //   Pills gone.
        //
        // STANDARD VIEW (moving ↓ in the wall):
        //   The row you're moving TO centers. Half-rows bleed.
        //
        // THE UP + 1 (↑ from THE UP, up_plus_one = true):
        //   Pills bar centered. Row0 in full below. NOTHING else.
        //   No peek, no additional rows. Nothing above the pills.
        //
        // SEARCH: letter key from ANY state — the bar takes the stack
        //   rect exactly; tiles keep their state's geometry behind it.

        const centered_stack_y = (h_d - stack_h) * 0.5;
        const landing_stack_y = @min(centered_stack_y, grid_top + tile_h + gap);
        const stack_y = landing_stack_y; // pills always centered
        const cat_y = stack_y; // pill track top (sub/search hang below)
        const stack_bottom = stack_y + stack_h;

        // ---- Category pill bar: ONE stadium track, 5 segments, floating ----
        // ---- tricolor inner pill. THE PILL spec — brand-locked,        ----
        // ---- theme-immune, same 280px segments the original 3 had.     ----
        // ---- WALL state: the stack is GONE — nothing draws, no token. ----
        if (!search_active and !in_wall) {
        // Track fill + border (house colors, never theme-fed).
        roundedRect(cr, pb_track_x, cat_y, pb_track_w, pb_track_h, pb_track_r);
        c.cairo_set_source_rgba(cr, PILL_TRACK_FILL.r, PILL_TRACK_FILL.g, PILL_TRACK_FILL.b, 1.0);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, PILL_TRACK_BORDER.r, PILL_TRACK_BORDER.g, PILL_TRACK_BORDER.b, 1.0);
        c.cairo_set_line_width(cr, 1.5);
        c.cairo_stroke(cr);

        // Segment separators (soft, 10px end margin — browser pattern).
        c.cairo_set_source_rgba(cr, PILL_TRACK_BORDER.r, PILL_TRACK_BORDER.g, PILL_TRACK_BORDER.b, 90.0 / 255.0);
        c.cairo_set_line_width(cr, 1.0);
        var sep_i: usize = 1;
        while (sep_i < PILL_COUNT) : (sep_i += 1) {
            const sx = pb_track_x + @as(f64, @floatFromInt(sep_i)) * pb_seg_w;
            c.cairo_move_to(cr, sx, cat_y + 10.0 * scale_f);
            c.cairo_line_to(cr, sx, cat_y + pb_track_h - 10.0 * scale_f);
            c.cairo_stroke(cr);
        }

        // Floating inner pill on the selected segment.
        const pill_x = pb_track_x + @as(f64, @floatFromInt(active_display)) * pb_seg_w + pb_inset;
        const pill_y = cat_y + pb_inset;

        roundedRect(cr, pill_x, pill_y, pill_w, pb_pill_h, pb_pill_r);
        c.cairo_set_source_rgba(cr, mcol.r, mcol.g, mcol.b, 90.0 / 255.0);
        c.cairo_fill_preserve(cr);
        // Gold ring: bright when the bar itself has focus, dim otherwise.
        const ring_a: f64 = if (self.focus == .category) 200.0 / 255.0 else 120.0 / 255.0;
        c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, ring_a);
        c.cairo_set_line_width(cr, 1.5);
        c.cairo_stroke(cr);

        // Segment labels + uniform hit rects.
        const pill_font = @as(f64, style_.font_size_s) * scale_f;
        c.cairo_set_font_size(cr, pill_font);
        for (0..PILL_COUNT) |i| {
            const cat = mediaCategoryFromIndex(i);
            const seg_x = pb_track_x + @as(f64, @floatFromInt(i)) * pb_seg_w;
            if (out_click) |click| {
                click.cat_for_index[i] = cat;
                click.cat_x[i] = @intFromFloat(seg_x);
                click.cat_y[i] = @intFromFloat(cat_y);
                click.cat_w[i] = @intFromFloat(pb_seg_w);
                click.cat_h[i] = @intFromFloat(pb_track_h);
            }
            const label = categoryLabel(cat);
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, label.ptr, &ext);
            const tcol = if (i == active_display) PILL_TEXT_ACTIVE else PILL_TEXT_DIM;
            c.cairo_set_source_rgba(cr, tcol.r, tcol.g, tcol.b, 1.0);
            c.cairo_move_to(cr, seg_x + (pb_seg_w - ext.width) * 0.5, cat_y + pb_track_h * 0.5 + pill_font * 0.30);
            c.cairo_show_text(cr, label.ptr);
        }
        } // end if (!search_active) pill track

        // ---- Subcategory track: SAME spec as the main track, one row ----
        // ---- under it. Floating inner pill wears the parent's color. ----
        if (!search_active and !in_wall and self.subcategory_open and sub_names.len > 0) {
            const sub_y = cat_y + pb_track_h + stack_gap;
            const sub_n = sub_names.len;
            const sub_track_w = pb_seg_w * @as(f64, @floatFromInt(sub_n));
            const sub_track_x = pad_x + @max(0.0, (content_w - sub_track_w) * 0.5);

            roundedRect(cr, sub_track_x, sub_y, sub_track_w, pb_track_h, pb_track_r);
            c.cairo_set_source_rgba(cr, PILL_TRACK_FILL.r, PILL_TRACK_FILL.g, PILL_TRACK_FILL.b, 1.0);
            c.cairo_fill_preserve(cr);
            c.cairo_set_source_rgba(cr, PILL_TRACK_BORDER.r, PILL_TRACK_BORDER.g, PILL_TRACK_BORDER.b, 1.0);
            c.cairo_set_line_width(cr, 1.5);
            c.cairo_stroke(cr);

            c.cairo_set_source_rgba(cr, PILL_TRACK_BORDER.r, PILL_TRACK_BORDER.g, PILL_TRACK_BORDER.b, 90.0 / 255.0);
            c.cairo_set_line_width(cr, 1.0);
            var ssep: usize = 1;
            while (ssep < sub_n) : (ssep += 1) {
                const sx = sub_track_x + @as(f64, @floatFromInt(ssep)) * pb_seg_w;
                c.cairo_move_to(cr, sx, sub_y + 10.0 * scale_f);
                c.cairo_line_to(cr, sx, sub_y + pb_track_h - 10.0 * scale_f);
                c.cairo_stroke(cr);
            }

            // Floating inner pill on the selected sub (parent's mode color).
            const sub_pill_x = sub_track_x + @as(f64, @floatFromInt(self.subcategory_index)) * pb_seg_w + pb_inset;
            const sub_pill_y = sub_y + pb_inset;
            roundedRect(cr, sub_pill_x, sub_pill_y, pill_w, pb_pill_h, pb_pill_r);
            c.cairo_set_source_rgba(cr, mcol.r, mcol.g, mcol.b, 90.0 / 255.0);
            c.cairo_fill_preserve(cr);
            const sub_ring_a: f64 = if (self.focus == .subcategory) 200.0 / 255.0 else 120.0 / 255.0;
            c.cairo_set_source_rgba(cr, PILL_GOLD.r, PILL_GOLD.g, PILL_GOLD.b, sub_ring_a);
            c.cairo_set_line_width(cr, 1.5);
            c.cairo_stroke(cr);

            const sub_font = @as(f64, style_.font_size_s) * scale_f;
            c.cairo_set_font_size(cr, sub_font);
            for (sub_names, 0..) |name, si| {
                const seg_x = sub_track_x + @as(f64, @floatFromInt(si)) * pb_seg_w;
                if (out_click) |click| {
                    if (si < 5) {
                        click.sub_x[si] = @intFromFloat(seg_x);
                        click.sub_y = @intFromFloat(sub_y);
                        click.sub_w[si] = @intFromFloat(pb_seg_w);
                        click.sub_h = @intFromFloat(pb_track_h);
                    }
                }
                var ext: c.cairo_text_extents_t = undefined;
                c.cairo_text_extents(cr, name.ptr, &ext);
                const tcol = if (si == self.subcategory_index) PILL_TEXT_ACTIVE else PILL_TEXT_DIM;
                c.cairo_set_source_rgba(cr, tcol.r, tcol.g, tcol.b, 1.0);
                c.cairo_move_to(cr, seg_x + (pb_seg_w - ext.width) * 0.5, sub_y + pb_track_h * 0.5 + sub_font * 0.30);
                c.cairo_show_text(cr, name.ptr);
            }
        }

        // ---- Search bar: takes the pill track's rect when active; ----
        // ---- otherwise sits just under the stack, same stadium.     ----
        const search_h = pb_track_h;
        const search_w = pb_track_w;
        const search_x = pb_track_x;
        const search_y = if (search_active) cat_y else cat_y + stack_h + stack_gap;
        const search_r = search_h * 0.5;

        if (out_click) |click| {
            click.search_x = @intFromFloat(search_x);
            click.search_y = @intFromFloat(search_y);
            click.search_w = @intFromFloat(search_w);
            click.search_h = @intFromFloat(search_h);
        }

        // Search only draws when it owns center.
        if (search_active) {
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
        } // end if (search_active) search draw

        // ---- Result grid + scroller: CFC — the row you're moving TO ----
        // ---- becomes center. Direction determines destination.       ----
        const grid_bottom = h_d - pad_y;

        // Row placement: pure function of (state, row index).
        // LANDING: row0 above the stack, skip, row1+ below.
        // WALL: the row you're moving TO is centered at h_d/2.
        // UP+1: row0 in full below the centered pills, nothing else.
        const wall = in_wall;
        const up1 = self.up_plus_one and !wall;
        const row0_top = if (up1) stack_bottom + gap else stack_y - gap - tile_h;
        const row1_top = if (up1) row0_top + row_h else stack_bottom + gap;

        // Clip = the slide body. Tiles never overlap the stack because
        // their Y never lands in it.
        c.cairo_save(cr);
        c.cairo_rectangle(cr, 0, pad_y, w_d, grid_bottom - pad_y);
        c.cairo_clip(cr);

        const bar_w: f64 = 5.0 * scale_f;
        const scroller_track: f64 = 30.0 * scale_f;
        const list_x = tile_gap;
        const list_w = w_d - 2.0 * tile_gap;
        const right_gap_center = w_d - tile_gap * 0.5;
        const channel_cx_open = right_gap_center;
        const channel_cx = channel_cx_open + (1.0 - self.slider_reveal) * (tile_gap * 0.5 + scroller_track * 0.5);
        const channel_x = channel_cx - scroller_track * 0.5;

        // ---- FAN ART: 2:3 portrait posters, constant size. Focused   ----
        // ---- tile only: slight inflate + double border + title.     ----
        const label_font = @as(f64, style_.font_size_s) * scale_f;

        // Field span: WALL from grid_top; LANDING from row0_top; UP+1 from row0_top.
        const field_top = if (wall) grid_top else row0_top;
        const rows_visible: usize = if (up1) 1 else @intFromFloat(@max(0.0, @ceil((grid_bottom - field_top) / row_h)));
        const list_y = field_top; // scroller/track anchor
        const list_h = grid_bottom - field_top;

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
        // rows_visible is how many row-slots fit on screen; the scroller
        // range is total_rows - 1 (any row may be selected, CFC centers it).
        self.visible_result_count = rows_visible * cols;
        self.max_scroll_offset = if (total_rows > 0) total_rows - 1 else 0;
        // Keep SELECTION in range; never clamp list_scroll_offset here — in
        // the wall the offset IS the selected row and clamping it amputates
        // the CFC center on the next render (the "DOWN shows no top peek"
        // and "highlight drifts off screen" bugs both traced to that clamp).
        if (self.selected_result >= library.len) self.selected_result = if (library.len > 0) library.len - 1 else 0;
        if (total_rows > 0 and self.selected_result / cols > self.max_scroll_offset) {
            self.selected_result = self.max_scroll_offset * cols + (self.selected_result % cols);
            if (self.selected_result >= library.len) self.selected_result = library.len - 1;
        }
        if (self.list_scroll_offset > self.max_scroll_offset) self.list_scroll_offset = self.max_scroll_offset;

        if (out_click) |click| {
            click.cols = @intCast(cols);
            click.tile_w = @intFromFloat(tile_w);
            click.tile_h = @intFromFloat(tile_h);
            click.tile_gap = @intFromFloat(tile_gap);
        }

        var focus_tx: f64 = 0;
        var focus_ty: f64 = 0;
        var focus_drawn = false;
        var focus_tile_key: ?u32 = null;

        // Render window. WALL: anchored on the SELECTED row (CFC), bleeding
        // half a screen up and down so top/bottom peeks always arrive.
        // LANDING/UP+1: anchored on list_scroll_offset from field_top.
        const wall_rows_span: usize = rows_visible + 2;
        const anchor_row: usize = if (wall) blk: {
            const sel_row = self.selected_result / cols;
            const half_screen = rows_visible / 2;
            break :blk if (sel_row > half_screen) sel_row - half_screen else 0;
        } else self.list_scroll_offset;

        var row_i: usize = 0;
        while (row_i < wall_rows_span and anchor_row + row_i < total_rows) : (row_i += 1) {
            const grid_row = anchor_row + row_i;
            // PLACEMENT:
            //   WALL:   the row you're moving TO is centered at h_d/2
            //   LANDING: row0 above stack, skip, row1+ below
            //   UP+1:   row0 in full below the centered pills, nothing else
            const ty = if (wall)
                h_d * 0.5 - tile_h * 0.5 + (@as(f64, @floatFromInt(grid_row)) - @as(f64, @floatFromInt(self.selected_result / cols))) * row_h
            else if (up1)
                row0_top + @as(f64, @floatFromInt(grid_row)) * row_h
            else if (grid_row == 0)
                row0_top
            else
                row1_top + @as(f64, @floatFromInt(grid_row - 1)) * row_h;
            const first_idx = grid_row * cols;
            var col_i: usize = 0;
            while (col_i < cols) : (col_i += 1) {
                const idx = first_idx + col_i;
                if (idx >= library.len) break;
                const entry = library[idx];
                const tx = list_x + @as(f64, @floatFromInt(col_i)) * (tile_w + tile_gap);

                const is_focused_tile = self.focus == .result and self.selected_result == idx;

                // THE 3 SUBTLETIES on the focused tile: slight enlarge,
                // double border (inner ring wider), trimmed title on top.
                // Everyone else is a cleanskin.
                const inflate: f64 = if (is_focused_tile) tile_w * 0.06 else 0.0;
                const dx = tx - inflate * 0.5;
                const dy = ty - inflate * 0.5;
                const dw = tile_w + inflate;
                const dh = art_h + inflate;

                if (is_focused_tile) {
                    focus_tx = tx;
                    focus_ty = ty;
                    focus_drawn = true;
                    const depth = 3.0 * scale_f;
                    const fr = 10.0 * scale_f;
                    // 3D shadow: offset dark bottom-right edge
                    roundedRect(cr, dx + depth, dy + depth, dw, dh, fr);
                    c.cairo_set_source_rgba(cr, card_bg[0], card_bg[1], card_bg[2], 0.85);
                    c.cairo_fill(cr);
                    // Outer ring (the double border's outer half)
                    roundedRect(cr, dx, dy, dw, dh, fr);
                    c.cairo_set_source_rgba(cr, card_bg[0], card_bg[1], card_bg[2], 0.55);
                    c.cairo_fill_preserve(cr);
                    c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.95);
                    c.cairo_set_line_width(cr, 3.0);
                    c.cairo_stroke(cr);
                }

                const tile_key = self.renderTileArt(cr, dx, dy, dw, dh, entry, border, self.category == .music, self.category == .pictures, is_focused_tile);
                if (is_focused_tile) focus_tile_key = tile_key;

                if (is_focused_tile) {
                    // Inner ring — the double border's inside half.
                    const ir = 10.0 * scale_f;
                    roundedRect(cr, dx + 2.0 * scale_f, dy + 2.0 * scale_f, dw - 4.0 * scale_f, dh - 4.0 * scale_f, ir);
                    c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.8);
                    c.cairo_set_line_width(cr, 2.0);
                    c.cairo_stroke(cr);
                }
                // No per-tile labels — TRIMMED TITLE for the focused tile only.
            }
        }

        // Focused-card dwell → hi-res upgrade (500ms on the same tile).
        self.tickDwell(if (focus_drawn) focus_tile_key else null);

        // Trimmed title: the focused tile's name, centered above ITS row.
        // Sits in the real gap above that row (stack gap, row gap, or
        // the strip margin) — there is always one by construction.
        if (self.focus == .result and focus_drawn and library.len > 0) {
            const title = std.mem.sliceTo(library[self.selected_result].title, 0);
            c.cairo_set_font_size(cr, label_font);
            var ext: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, title.ptr, &ext);
            const title_x = focus_tx + tile_w * 0.5 - ext.width * 0.5;
            const title_y = focus_ty - 14.0 * scale_f;
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.95);
            c.cairo_move_to(cr, title_x, title_y);
            c.cairo_show_text(cr, title.ptr);
        }

        // ---- Plain scrollbar track ----
        const track_h = list_h;
        const track_r = bar_w * 0.5;

        roundedRect(cr, channel_cx - bar_w * 0.5, list_y, bar_w, track_h, track_r);
        c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.10);
        c.cairo_fill_preserve(cr);
        c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 0.25);
        c.cairo_set_line_width(cr, 1.0);
        c.cairo_stroke(cr);

        const ratio = if (self.max_scroll_offset == 0) 0.0 else @as(f64, @floatFromInt(self.list_scroll_offset)) / @as(f64, @floatFromInt(self.max_scroll_offset));
        const knob_r = @max(bar_w * 1.5, 9.0 * scale_f);
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

        // Pop the slide-body clip.
        c.cairo_restore(cr);

        // (No title strip — the cards own every pixel. The pills bar
        // is the only chrome, and it's either centered or gone.)

        // Slide chrome LAST: pop the corner clip, then the 2px focused ring
        // at the buffer edge (same tokens as window chrome).
        if (as_slide) {
            c.cairo_restore(cr);
            const bw = @as(f64, style_.border_width) * scale_f;
            const half = bw * 0.5;
            mediaSlidePath(cr, half, half, w_d - bw, h_d - bw, @max(0.0, corner_r - half), style_.corner_style);
            c.cairo_set_source_rgba(cr, border[0], border[1], border[2], 1.0);
            c.cairo_set_line_width(cr, bw);
            c.cairo_stroke(cr);
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

/// Slide chrome path: the system's corner treatment for a focused slide.
/// Round = roundedRect at corner_depth, chamfer = clipped corners, square.
fn mediaSlidePath(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64, corner_style: style.Style.CornerStyle) void {
    switch (corner_style) {
        .round => roundedRectPath(cr, x, y, w, h, r),
        .chamfer => chamferPath(cr, x, y, w, h, r),
        .square => c.cairo_rectangle(cr, x, y, w, h),
    }
}

fn roundedRectPath(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
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

fn chamferPath(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, d: f64) void {
    const dd = @min(d, w * 0.5, h * 0.5);
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + dd, y);
    c.cairo_line_to(cr, x + w - dd, y);
    c.cairo_line_to(cr, x + w, y + dd);
    c.cairo_line_to(cr, x + w, y + h - dd);
    c.cairo_line_to(cr, x + w - dd, y + h);
    c.cairo_line_to(cr, x + dd, y + h);
    c.cairo_line_to(cr, x, y + h - dd);
    c.cairo_line_to(cr, x, y + dd);
    c.cairo_close_path(cr);
}

fn animationNowUs() u64 {
    var ts: unistd.timespec = std.mem.zeroes(unistd.timespec);
    if (unistd.clock_gettime(unistd.CLOCK_MONOTONIC, &ts) != 0) return 0;
    return @as(u64, @intCast(ts.tv_sec)) * 1_000_000 + @as(u64, @intCast(ts.tv_nsec)) / 1000;
}
