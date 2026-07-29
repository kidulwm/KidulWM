const std = @import("std");
const c = @import("dm").c;
const style = @import("../core/style.zig");
const animation = @import("../core/animation.zig");

pub const Notification = struct {
    title: []const u8,
    body: []const u8,
    source_id: []const u8,
    received_us: u64,
    dismissed: bool = false,
};

pub const NotificationQueue = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Notification),
    max_items: usize,

    pub fn init(allocator: std.mem.Allocator, max_items: usize) NotificationQueue {
        return .{
            .allocator = allocator,
            .items = .empty,
            .max_items = max_items,
        };
    }

    pub fn deinit(self: *NotificationQueue) void {
        for (self.items.items) |*item| {
            self.allocator.free(item.title);
            self.allocator.free(item.body);
            self.allocator.free(item.source_id);
        }
        self.items.deinit(self.allocator);
    }

    fn allocCopy(self: *const NotificationQueue, src: []const u8) ![]u8 {
        return self.allocator.dupe(u8, src);
    }

    pub fn push(self: *NotificationQueue, title: []const u8, body: []const u8, source_id: []const u8, now_us: u64) !void {
        const n = Notification{
            .title = try self.allocCopy(title),
            .body = try self.allocCopy(body),
            .source_id = try self.allocCopy(source_id),
            .received_us = now_us,
        };
        if (self.items.items.len >= self.max_items) {
            const old = self.items.orderedRemove(0);
            self.allocator.free(old.title);
            self.allocator.free(old.body);
            self.allocator.free(old.source_id);
        }
        try self.items.append(self.allocator, n);
    }

    pub fn dismiss(self: *NotificationQueue, index: usize) void {
        if (index >= self.items.items.len) return;
        self.items.items[index].dismissed = true;
    }

    pub fn activeCount(self: *const NotificationQueue) usize {
        var count: usize = 0;
        for (self.items.items) |item| {
            if (!item.dismissed) count += 1;
        }
        return count;
    }
};

pub const TypewriterState = struct {
    /// Which notification in the queue is currently being revealed.
    queue_index: usize = 0,
    /// Characters already revealed for the current notification.
    chars_revealed: usize = 0,
    last_char_us: u64 = 0,
    /// Time between typed characters.
    char_interval_us: u64 = 70_000,
    /// Cycle the cursor blink every N microseconds.
    cursor_blink_us: u64 = 530_000,
    is_idle: bool = false,
    idle_since_us: u64 = 0,

    pub fn reset(self: *TypewriterState, now_us: u64) void {
        self.queue_index = 0;
        self.chars_revealed = 0;
        self.last_char_us = now_us;
        self.is_idle = false;
        self.idle_since_us = 0;
    }

    pub fn isCursorVisible(self: *const TypewriterState, now_us: u64) bool {
        _ = self;
        _ = now_us;
        return true;
    }

    pub fn update(self: *TypewriterState, queue: *const NotificationQueue, now_us: u64) bool {
        const active = queue.activeCount();
        if (active == 0) {
            self.reset(now_us);
            return false;
        }
        if (self.queue_index >= active) {
            self.queue_index = 0;
            self.chars_revealed = 0;
            self.last_char_us = now_us;
        }
        const item = &queue.items.items[self.queue_index];
        if (item.dismissed) {
            self.queue_index += 1;
            self.chars_revealed = 0;
            self.last_char_us = now_us;
            return true;
        }
        const text = item.body;
        if (self.chars_revealed >= text.len) {
            self.is_idle = true;
            self.idle_since_us = if (self.idle_since_us == 0) now_us else self.idle_since_us;
            return false;
        }
        if (now_us - self.last_char_us >= self.char_interval_us) {
            const advance = @max(1, (now_us - self.last_char_us) / self.char_interval_us);
            self.chars_revealed = @min(text.len, self.chars_revealed + @as(usize, @intCast(advance)));
            self.last_char_us = now_us;
            self.is_idle = false;
            self.idle_since_us = 0;
            return true;
        }
        return false;
    }

    pub fn advanceQueue(self: *TypewriterState, queue: *const NotificationQueue) void {
        const active = queue.activeCount();
        if (active == 0) return;
        self.queue_index = (self.queue_index + 1) % active;
        self.chars_revealed = 0;
        self.last_char_us = animation.nowUs();
        self.is_idle = false;
        self.idle_since_us = 0;
    }
};

pub const SoundConfig = struct {
    enabled: bool = false,
    volume: f32 = 0.35,
};

pub const NotificationConfig = struct {
    /// Time in us between characters.
    char_interval_us: u64 = 70_000,
    /// How long to idle on a fully-typed notification before advancing.
    idle_timeout_us: u64 = 6_000_000,
    /// Line height multiplier for body text.
    line_gap: f64 = 1.35,
    /// Vertical space between consecutive notifications.
    notification_gap: i32 = 12,
    /// Horizontal margin inside the notification column.
    hmargin: i32 = 10,
    /// Breathing room below the clock widget.
    top_breathing_room: i32 = 12,
    sound: SoundConfig = .{},
};

pub const NotificationWidget = struct {
    queue: NotificationQueue,
    tw: TypewriterState,
    config: NotificationConfig,

    pub fn init(allocator: std.mem.Allocator) NotificationWidget {
        return .{
            .queue = NotificationQueue.init(allocator, 32),
            .tw = .{},
            .config = .{},
        };
    }

    pub fn deinit(self: *NotificationWidget) void {
        self.queue.deinit();
    }

    pub fn push(self: *NotificationWidget, title: []const u8, body: []const u8, source_id: []const u8) !void {
        const now = animation.nowUs();
        try self.queue.push(title, body, source_id, now);
        if (self.tw.is_idle) {
            self.tw.advanceQueue(&self.queue);
        }
    }

    pub fn update(self: *NotificationWidget, now_us: u64) bool {
        const alive = self.tw.update(&self.queue, now_us);
        if (self.tw.is_idle and self.queue.activeCount() > 0) {
            if (now_us - self.tw.idle_since_us >= self.config.idle_timeout_us) {
                self.tw.advanceQueue(&self.queue);
                return true;
            }
        }
        return alive or self.tw.is_idle;
    }
};

pub const PeekBox = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

/// Render the notification stream into the provided Cairo surface.
/// The surface is assumed to be device-pixel sized; text is rendered
/// naturally and the caller scales if needed for the output scale.
pub fn renderNotifications(
    cr: *c.cairo_t,
    box: PeekBox,
    style_: style.Style,
    widget: *NotificationWidget,
    now_us: u64,
) void {
    if (widget.queue.activeCount() == 0) return;
    const w_d: f64 = @floatFromInt(box.width);
    const h_d: f64 = @floatFromInt(box.height);
    if (w_d < 20.0 or h_d < 20.0) return;

    const bg = style_.tray_bg_color.toF64();
    const gold = style_.color_border_focused.toF64();
    const text = style_.tray_text_color.toF64();

    c.cairo_save(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    // Notifications are intentionally chrome-free: centered text on the
    // cinematic wallpaper with only a faint, single-rule top accent.
    _ = bg;
    c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.18);
    c.cairo_set_line_width(cr, 1.0);
    c.cairo_move_to(cr, 0.0, 0.0);
    c.cairo_line_to(cr, w_d, 0.0);
    c.cairo_stroke(cr);

    const pad_x: f64 = @floatFromInt(widget.config.hmargin);
    const content_w = w_d - 2.0 * pad_x;
    if (content_w <= 0.0) {
        c.cairo_restore(cr);
        return;
    }

    const title_font = "Fantasque Sans Mono";
    const body_font = "Fantasque Sans Mono";
    const title_size: f64 = @as(f64, style_.font_size_m) * 1.15;
    const body_size: f64 = @as(f64, style_.font_size_s) * 1.05;
    const line_gap: f64 = body_size * widget.config.line_gap;

    var y: f64 = pad_x + title_size;

    // Draw all queued notifications; currently-typing one is last if there is space.
    var i: usize = 0;
    while (i < widget.queue.items.items.len) : (i += 1) {
        const item = &widget.queue.items.items[i];
        if (item.dismissed) continue;
        if (y + title_size >= h_d) break;

        c.cairo_select_font_face(cr, title_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
        c.cairo_set_font_size(cr, title_size);
        c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.95);
        centerText(cr, item.title, content_w, pad_x, y);
        y += title_size * 1.25;

        const is_typing = (i == widget.tw.queue_index);
        const full_body = item.body;
        const visible = if (is_typing) blk: {
            const len = @min(widget.tw.chars_revealed, full_body.len);
            break :blk full_body[0..len];
        } else full_body;

        c.cairo_select_font_face(cr, body_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
        c.cairo_set_font_size(cr, body_size);
        c.cairo_set_source_rgba(cr, text[0], text[1], text[2], 0.92);

        // Wrap body into centered lines.
        var body_y = y;
        var offset: usize = 0;
        while (offset < visible.len) {
            const line = nextLine(cr, visible[offset..], content_w);
            if (body_y + body_size > h_d) {
                offset = visible.len;
                break;
            }
            centerText(cr, line, content_w, pad_x, body_y);
            body_y += line_gap;
            offset += line.len;
            // Skip the single spaces we wrapped on.
            if (offset < visible.len and visible[offset] == ' ') offset += 1;
        }

        if (is_typing) {
            // Add a blinking caret after the last visible line.
            if (widget.tw.isCursorVisible(now_us)) {
                drawCaret(cr, body_size, text);
            }
        }

        y = body_y + @as(f64, @floatFromInt(widget.config.notification_gap));
    }

    c.cairo_restore(cr);
}

fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
    const radius = @min(r, @min(w, h) * 0.5);
    const degrees = std.math.pi / 180.0;
    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, x + w - radius, y + radius, radius, -90.0 * degrees, 0.0 * degrees);
    c.cairo_arc(cr, x + w - radius, y + h - radius, radius, 0.0 * degrees, 90.0 * degrees);
    c.cairo_arc(cr, x + radius, y + h - radius, radius, 90.0 * degrees, 180.0 * degrees);
    c.cairo_arc(cr, x + radius, y + radius, radius, 180.0 * degrees, 270.0 * degrees);
    c.cairo_close_path(cr);
}

fn centerText(cr: *c.cairo_t, txt: []const u8, content_w: f64, x_offset: f64, y_baseline: f64) void {
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, @ptrCast(txt.ptr), &ext);
    const x = x_offset + (content_w - ext.width) * 0.5;
    c.cairo_move_to(cr, x, y_baseline);
    c.cairo_show_text(cr, @ptrCast(txt.ptr));
}

/// Return the longest prefix of `text` that fits in `max_w`.
fn nextLine(cr: *c.cairo_t, text: []const u8, max_w: f64) []const u8 {
    if (text.len == 0) return text;
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, @ptrCast(text.ptr), &ext);
    if (ext.width <= max_w) return text;

    // Binary search for the break point.
    var lo: usize = 1;
    var hi: usize = text.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        c.cairo_text_extents(cr, @ptrCast(text[0..mid].ptr), &ext);
        if (ext.width <= max_w) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    var cut = lo - 1;
    // Prefer breaking at a space.
    if (cut < text.len and text[cut] != ' ') {
        var j = cut;
        while (j > 0) : (j -= 1) {
            if (text[j] == ' ') {
                cut = j;
                break;
            }
        }
    }
    return text[0..cut];
}

fn drawCaret(cr: *c.cairo_t, body_size: f64, color: [4]f64) void {
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, @ptrCast("M"), &ext);
    const w = @max(ext.width * 0.35, body_size * 0.12);
    const h = body_size * 0.95;
    var cur_x: f64 = undefined;
    var cur_y: f64 = undefined;
    c.cairo_get_current_point(cr, &cur_x, &cur_y);
    c.cairo_set_source_rgba(cr, color[0], color[1], color[2], 1.0);
    c.cairo_rectangle(cr, cur_x + 1.0, cur_y - h * 0.75, w, h);
    c.cairo_fill(cr);
}
