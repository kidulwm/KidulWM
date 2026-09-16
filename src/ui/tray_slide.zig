const std = @import("std");
const wlr = @import("wlroots");
const cairo = @import("dm").c;
const style_mod = @import("../core/style.zig");
const Style = style_mod.Style;
const chrome_renderer = @import("../render/chrome.zig");
const DataBuffer = @import("../render/buffer.zig").DataBuffer;

/// Minimal notification feed store (stage 2 demolition): the overlay tray's
/// NotificationWidget died with tray.zig, but the ingress (kidulwm-control
/// notification_test/clear, WM-reset notices) must not crash or silently
/// lose data. Owned by the Server; rendered as the NOTIFICATIONS CFC
/// section of the home slide (last N entries, gold CFC text).
pub const NotificationStore = struct {
    pub const max_entries = 8;
    pub const entry_len = 128;

    pub const Entry = struct {
        title: [entry_len]u8 = undefined,
        title_len: usize = 0,
        body: [entry_len]u8 = undefined,
        body_len: usize = 0,
        source: [entry_len]u8 = undefined,
        source_len: usize = 0,

        pub fn titleSlice(self: *const Entry) []const u8 {
            return self.title[0..self.title_len];
        }
        pub fn bodySlice(self: *const Entry) []const u8 {
            return self.body[0..self.body_len];
        }
    };

    entries: [max_entries]Entry = undefined,
    count: usize = 0,
    /// Total pushes ever seen, so `clear` and overflow behave sanely.
    seen: u64 = 0,
    /// Bumped on every mutation so the home slide can re-render.
    generation: u64 = 0,

    fn copySpan(dst: *[entry_len]u8, dst_len: *usize, src: []const u8) void {
        const n = @min(src.len, entry_len - 1);
        @memcpy(dst[0..n], src[0..n]);
        dst_len.* = n;
    }

    pub fn add(self: *NotificationStore, title: []const u8, body: []const u8, source: []const u8) void {
        var e: *Entry = undefined;
        if (self.count < max_entries) {
            e = &self.entries[self.count];
            self.count += 1;
        } else {
            // Ring full: drop the oldest, shift left.
            std.mem.copyForwards(Entry, self.entries[0 .. max_entries - 1], self.entries[1..max_entries]);
            e = &self.entries[max_entries - 1];
        }
        e.* = .{};
        copySpan(&e.title, &e.title_len, title);
        copySpan(&e.body, &e.body_len, body);
        copySpan(&e.source, &e.source_len, source);
        self.seen += 1;
        self.generation +%= 1;
    }

    pub fn clear(self: *NotificationStore) void {
        self.count = 0;
        self.generation +%= 1;
    }

    /// Most-recent-last slice of live entries.
    pub fn items(self: *const NotificationStore) []const Entry {
        return self.entries[0..self.count];
    }
};

/// Compositor-owned HOME slide content painter (TASKCARD-3 stage 2): one
/// scene tree per output holding the home card. The home slide is a REAL
/// deck.slides entry at index 0 (kind .home, ephemeral) — it walks, peeks,
/// parks and quits through the stock paths; this struct only carries the
/// render state (tree + buffers + repaint guards), painted at the slide's
/// layout rect like any slide.
///
/// A1 PROPER SLIDE: real border + background via the STOCK chrome renderer —
/// the same border/background every focused slide gets. Specialness is the
/// content only: CFC'd cairo text, centered both axes, sections stacked with
/// the house gap. v1 = static section lines; real feeds wire in later stages.
pub const TraySlide = struct {
    tree: ?*wlr.SceneTree = null,
    /// Background + gold section lines (content of the slide).
    card_buffer: ?*wlr.SceneBuffer = null,
    /// Stock chrome border ring (render/chrome.zig — A1).
    chrome_buffer: ?*wlr.SceneBuffer = null,
    /// Repaint guard: re-render only when the target rect changed.
    card_last_w: i32 = 0,
    card_last_h: i32 = 0,
    /// Feed guard: re-render when the notification store mutates.
    card_last_notif_gen: u64 = 0,

    pub fn isOpen(self: *const TraySlide) bool {
        return self.tree != null;
    }

    pub const Section = struct {
        label: []const u8,
        line: []const u8,
    };

    /// v1 content: placeholder section lines (spec stage 1 — no real feeds).
    /// NOTIFICATIONS is wired to the NotificationStore at render time
    /// (stage 2); the placeholder is its empty state.
    pub const sections = [_]Section{
        .{ .label = "MEDIA", .line = "nothing playing" },
        .{ .label = "WEATHER", .line = "no data" },
        .{ .label = "SIGNALS", .line = "no data" },
        .{ .label = "NOTIFICATIONS", .line = "none" },
    };
};

/// Render the home card (near-black bg + CFC gold text, centered both axes,
/// sections stacked with the house gap) into a wlroots buffer. Rendered at
/// physical pixels (logical size × scale), like the media slide card.
/// `store` feeds the NOTIFICATIONS section (stage 2): up to the last 3
/// entries as gold CFC lines, or the "none" placeholder when empty.
pub fn renderToBuffer(
    style: Style,
    width: i32,
    height: i32,
    scale: u32,
    store: ?*const NotificationStore,
) ?*wlr.Buffer {
    if (width <= 0 or height <= 0) return null;
    const s: i32 = @max(1, @as(i32, @intCast(scale)));
    const pw: i32 = width * s;
    const ph: i32 = height * s;
    const surface = cairo.cairo_image_surface_create(cairo.CAIRO_FORMAT_ARGB32, pw, ph) orelse return null;
    if (cairo.cairo_surface_status(surface) != cairo.CAIRO_STATUS_SUCCESS) {
        cairo.cairo_surface_destroy(surface);
        return null;
    }
    const cr = cairo.cairo_create(surface) orelse {
        cairo.cairo_surface_destroy(surface);
        return null;
    };
    defer cairo.cairo_destroy(cr);

    const w: f64 = @floatFromInt(pw);
    const h: f64 = @floatFromInt(ph);
    const fs: f64 = @floatFromInt(s);

    // Background: kfiles near-black token, fully opaque (A1 — the stock
    // chrome background ring sits on top; transparency is a future alpha
    // constant, not this stage).
    const bg = style.tray_bg_color.toF64();
    cairo.cairo_set_source_rgba(cr, bg[0], bg[1], bg[2], 1.0);
    cairo.cairo_paint(cr);

    // CFC: sections stacked, centered both axes, house gap between blocks.
    const label_size: f64 = @as(f64, style.font_size_m) * fs;
    const line_size: f64 = @as(f64, style.font_size_l) * fs;
    const house_gap: f64 = @as(f64, @floatFromInt(style_mod.layout.gap)) * fs * 3.0;
    const block_gap: f64 = house_gap / 3.0;

    // NOTIFICATIONS feed (stage 2): last N entries, most recent last.
    // Fixed-size line buffers keep the whole render allocation-free.
    const max_notif_lines = 3;
    var notif_bufs: [max_notif_lines][NotificationStore.entry_len * 2 + 4]u8 = undefined;
    var notif_lens: [max_notif_lines]usize = .{0} ** max_notif_lines;
    var notif_count: usize = 0;
    if (store) |st| {
        const live = st.items();
        const start = if (live.len > max_notif_lines) live.len - max_notif_lines else 0;
        for (live[start..]) |*e| {
            var buf = &notif_bufs[notif_count];
            const t = e.titleSlice();
            const b = e.bodySlice();
            var n: usize = 0;
            const tn = @min(t.len, NotificationStore.entry_len);
            @memcpy(buf[0..tn], t[0..tn]);
            n += tn;
            if (b.len > 0) {
                buf[n] = ' ';
                buf[n + 1] = '-';
                buf[n + 2] = ' ';
                n += 3;
                const bn = @min(b.len, buf.len - n);
                @memcpy(buf[n .. n + bn], b[0..bn]);
                n += bn;
            }
            notif_lens[notif_count] = n;
            notif_count += 1;
        }
    }
    const notif_line_count: f64 = @floatFromInt(@max(notif_count, 1));

    const n: f64 = @floatFromInt(TraySlide.sections.len);
    const block_h = label_size + block_gap + line_size;
    // The NOTIFICATIONS block grows by one line per extra feed entry.
    const total_h = n * block_h + (n - 1.0) * house_gap +
        (notif_line_count - 1.0) * (line_size + block_gap);
    var y = (h - total_h) / 2.0;

    const gold = style.color_gold.toF64();
    const gold_dim = style.color_gold_dim.toF64();

    var ext: cairo.cairo_text_extents_t = undefined;
    for (TraySlide.sections) |section| {
        // Section label (dim gold, small, centered).
        cairo.cairo_select_font_face(cr, "JetBrains Mono", cairo.CAIRO_FONT_SLANT_NORMAL, cairo.CAIRO_FONT_WEIGHT_NORMAL);
        cairo.cairo_set_font_size(cr, label_size);
        cairo.cairo_text_extents(cr, section.label.ptr, &ext);
        cairo.cairo_set_source_rgba(cr, gold_dim[0], gold_dim[1], gold_dim[2], gold_dim[3]);
        cairo.cairo_move_to(cr, (w - ext.width) / 2.0 - ext.x_bearing, y + label_size);
        cairo.cairo_show_text(cr, section.label.ptr);
        y += label_size + block_gap;

        // Section line(s) (gold, large, centered).
        cairo.cairo_select_font_face(cr, "JetBrains Mono", cairo.CAIRO_FONT_SLANT_NORMAL, cairo.CAIRO_FONT_WEIGHT_BOLD);
        cairo.cairo_set_font_size(cr, line_size);
        cairo.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
        if (std.mem.eql(u8, section.label, "NOTIFICATIONS") and notif_count > 0) {
            var li: usize = 0;
            while (li < notif_count) : (li += 1) {
                const text = notif_bufs[li][0..notif_lens[li]];
                var zbuf: [NotificationStore.entry_len * 2 + 4]u8 = undefined;
                @memcpy(zbuf[0..text.len], text);
                zbuf[text.len] = 0;
                const z: [*:0]const u8 = @ptrCast(&zbuf);
                cairo.cairo_text_extents(cr, z, &ext);
                cairo.cairo_move_to(cr, (w - ext.width) / 2.0 - ext.x_bearing, y + line_size);
                cairo.cairo_show_text(cr, z);
                y += line_size + block_gap;
            }
            y += house_gap - block_gap;
        } else {
            cairo.cairo_text_extents(cr, section.line.ptr, &ext);
            cairo.cairo_move_to(cr, (w - ext.width) / 2.0 - ext.x_bearing, y + line_size);
            cairo.cairo_show_text(cr, section.line.ptr);
            y += line_size + house_gap;
        }
    }

    cairo.cairo_surface_flush(surface);
    const data = cairo.cairo_image_surface_get_data(surface) orelse {
        cairo.cairo_surface_destroy(surface);
        return null;
    };
    const stride = cairo.cairo_image_surface_get_stride(surface);
    const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(ph));
    const buf = DataBuffer.create(data[0..buf_size], pw, ph, stride) catch {
        cairo.cairo_surface_destroy(surface);
        return null;
    };
    cairo.cairo_surface_destroy(surface);
    return buf;
}

/// Render the STOCK chrome border ring (A1) into a wlroots buffer, same
/// render the per-window chrome path uses.
pub fn renderChromeToBuffer(
    style: Style,
    width: i32,
    height: i32,
    scale: u32,
) ?*wlr.Buffer {
    const surface = chrome_renderer.renderChrome(style, width, height, true, scale, chrome_renderer.EdgeMode.all, null) orelse return null;
    defer cairo.cairo_surface_destroy(surface);
    const pixels = chrome_renderer.surfacePixels(surface);
    return DataBuffer.create(pixels.pixels, pixels.width, pixels.height, pixels.stride) catch null;
}
