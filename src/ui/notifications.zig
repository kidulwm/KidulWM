const std = @import("std");
const c = @import("dm").c;
const style = @import("../core/style.zig");
const animation = @import("../core/animation.zig");

/// Urgency level of a notification card.
pub const Priority = enum {
    /// Interrupts immediately, pauses the stream, shown all-at-once in bursts if needed.
    critical,
    /// Interrupts after the current card finishes, but ahead of normal/low.
    high,
    /// Scheduled one-at-a-time rotation.
    normal,
    /// Only shown when nothing higher is waiting.
    low,

    pub fn fromString(s: []const u8) ?Priority {
        if (std.mem.eql(u8, s, "critical")) return .critical;
        if (std.mem.eql(u8, s, "high")) return .high;
        if (std.mem.eql(u8, s, "normal")) return .normal;
        if (std.mem.eql(u8, s, "low")) return .low;
        return null;
    }

    pub fn label(self: Priority) []const u8 {
        return switch (self) {
            .critical => "CRITICAL",
            .high => "HIGH",
            .normal => "NOTICE",
            .low => "UPDATE",
        };
    }

    pub fn labelColor(self: Priority) [4]f64 {
        return switch (self) {
            // Warning orange borrowed from rkt-dashboard's urgency dial.
            // Soft enough to sit in the cinematic black-gold palette, urgent enough to act.
            .critical => .{ 0.847, 0.451, 0.180, 0.85 },
            // Gold/tan for everything else.
            .high => .{ 0.580, 0.557, 0.482, 0.95 },
            .normal => .{ 0.580, 0.557, 0.482, 0.75 },
            .low => .{ 0.580, 0.557, 0.482, 0.55 },
        };
    }
};

/// Visual skin for a notification card. The queue/priority logic does not care
/// which skin is active; this just gives us a hook to swap presentation later.
pub const DisplayMode = enum {
    /// The current under-clock typewriter stream.
    typewriter,
    /// Future: a rolled parchment / scroll card.
    scroll,
    /// Future: a top-of-screen urgent banner.
    banner,
    /// Future: the full notification river peek card.
    river,

    pub fn fromString(s: []const u8) ?DisplayMode {
        if (std.mem.eql(u8, s, "typewriter")) return .typewriter;
        if (std.mem.eql(u8, s, "scroll")) return .scroll;
        if (std.mem.eql(u8, s, "banner")) return .banner;
        if (std.mem.eql(u8, s, "river")) return .river;
        return null;
    }
};

/// One notification title/body unit. Title and panel are one card; the skin
/// that draws the card is selected by `display_mode` independently of priority.
pub const NotificationCard = struct {
    title: []const u8,
    body: []const u8,
    source_id: []const u8,
    priority: Priority,
    display_mode: DisplayMode,
    /// If non-null, clicking this card opens an action card (Block/Allow/Details).
    /// The action_id names the kind of action card to open (e.g. "security", "usb").
    action_id: ?[]const u8,
    received_us: u64,
    dismissed: bool = false,
    /// For burst grouping: how many same-source critical events collapsed into this card.
    group_count: usize = 1,

    pub fn priorityRank(self: *const NotificationCard) u8 {
        return switch (self.priority) {
            .critical => 0,
            .high => 1,
            .normal => 2,
            .low => 3,
        };
    }
};

/// Optional hints passed in from the bridge/CLI. Unset fields fall back to source rules.
pub const PushOptions = struct {
    priority: ?Priority = null,
    display_mode: ?DisplayMode = null,
    action_id: ?[]const u8 = null,
};

/// A small rule table for source → presentation. This will later move into a
/// parsed config file; for now it gives us day-one source-specific behaviour.
pub const SourceRule = struct {
    priority: Priority,
    display_mode: DisplayMode,
    action_id: ?[]const u8,
    label: []const u8,
    /// Color for the source label only; body text keeps the neutral color.
    label_color: [4]f64,
};

/// Default rules matching config/notifications.yaml. Used when a source_id has
/// no explicit override and no caller-supplied options.
fn defaultRule(source_id: []const u8) SourceRule {
    if (std.mem.eql(u8, source_id, "security")) {
        return .{ .priority = .critical, .display_mode = .typewriter, .action_id = "security", .label = "Security", .label_color = .{ 0.847, 0.451, 0.180, 0.85 } };
    }
    if (std.mem.eql(u8, source_id, "usb")) {
        return .{ .priority = .critical, .display_mode = .typewriter, .action_id = "usb", .label = "USB", .label_color = .{ 0.847, 0.451, 0.180, 0.85 } };
    }
    if (std.mem.eql(u8, source_id, "download")) {
        return .{ .priority = .critical, .display_mode = .typewriter, .action_id = "download", .label = "Download", .label_color = .{ 0.847, 0.451, 0.180, 0.85 } };
    }
    if (std.mem.eql(u8, source_id, "system")) {
        return .{ .priority = .high, .display_mode = .typewriter, .action_id = null, .label = "System", .label_color = .{ 0.580, 0.557, 0.482, 0.75 } };
    }
    if (std.mem.eql(u8, source_id, "files")) {
        return .{ .priority = .normal, .display_mode = .typewriter, .action_id = null, .label = "Files", .label_color = .{ 0.760, 0.670, 0.380, 0.92 } };
    }
    if (std.mem.eql(u8, source_id, "media")) {
        return .{ .priority = .low, .display_mode = .typewriter, .action_id = null, .label = "Media", .label_color = .{ 0.650, 0.580, 0.700, 0.85 } };
    }
    if (std.mem.eql(u8, source_id, "email")) {
        return .{ .priority = .normal, .display_mode = .typewriter, .action_id = null, .label = "Email", .label_color = .{ 0.380, 0.650, 0.720, 0.90 } };
    }
    if (std.mem.eql(u8, source_id, "assistant")) {
        return .{ .priority = .low, .display_mode = .typewriter, .action_id = null, .label = "Bob's", .label_color = .{ 0.580, 0.557, 0.482, 0.95 } };
    }
    return .{ .priority = .normal, .display_mode = .typewriter, .action_id = null, .label = "Snippet", .label_color = .{ 0.580, 0.557, 0.482, 0.95 } };
}

pub const NotificationQueue = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(NotificationCard),
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
            if (item.action_id) |a| self.allocator.free(a);
        }
        self.items.deinit(self.allocator);
    }

    fn allocCopy(self: *const NotificationQueue, src: []const u8) ![]u8 {
        return self.allocator.dupe(u8, src);
    }

    /// Push a new card. If a critical card of the same source arrived within
    /// `burst_window_us`, collapse into that card's group instead of appending.
    pub fn push(
        self: *NotificationQueue,
        title: []const u8,
        body: []const u8,
        source_id: []const u8,
        opts: PushOptions,
        now_us: u64,
        burst_window_us: u64,
    ) !bool {
        const rule = defaultRule(source_id);
        const priority = opts.priority orelse rule.priority;
        const display_mode = opts.display_mode orelse rule.display_mode;
        const action_id: ?[]const u8 = if (opts.action_id) |a|
            try self.allocCopy(a)
        else if (rule.action_id) |a|
            try self.allocCopy(a)
        else
            null;

        // Burst grouping for critical events of the same source.
        if (priority == .critical) {
            var i: usize = self.items.items.len;
            while (i > 0) : (i -= 1) {
                const item = &self.items.items[i - 1];
                if (item.dismissed) continue;
                if (item.priority == .critical and std.mem.eql(u8, item.source_id, source_id)) {
                    if (now_us - item.received_us <= burst_window_us) {
                        item.group_count += 1;
                        // Keep the newest title/body as the lead message.
                        self.allocator.free(item.title);
                        self.allocator.free(item.body);
                        item.title = try self.allocCopy(title);
                        item.body = try self.allocCopy(body);
                        item.received_us = now_us;
                        return true;
                    }
                    break;
                }
            }
        }

        const n = NotificationCard{
            .title = try self.allocCopy(title),
            .body = try self.allocCopy(body),
            .source_id = try self.allocCopy(source_id),
            .priority = priority,
            .display_mode = display_mode,
            .action_id = action_id,
            .received_us = now_us,
        };
        if (self.items.items.len >= self.max_items) {
            const old = self.items.orderedRemove(0);
            self.allocator.free(old.title);
            self.allocator.free(old.body);
            self.allocator.free(old.source_id);
            if (old.action_id) |a| self.allocator.free(a);
        }
        try self.items.append(self.allocator, n);
        return false;
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

    /// Return the queue index of the active card that should be displayed next,
    /// ordered by priority then arrival. Returns null if nothing is active.
    pub fn pickActiveIndex(self: *const NotificationQueue) ?usize {
        var best: ?usize = null;
        var best_rank: u8 = 255;
        for (self.items.items, 0..) |*item, i| {
            if (item.dismissed) continue;
            const rank = item.priorityRank();
            if (rank < best_rank) {
                best_rank = rank;
                best = i;
            }
        }
        return best;
    }

    /// Find the active index >= start that has the given priority rank.
    fn nextActiveAtPriority(self: *const NotificationQueue, start: usize, rank: u8) ?usize {
        var i = start;
        while (i < self.items.items.len) : (i += 1) {
            const item = &self.items.items[i];
            if (item.dismissed) continue;
            if (item.priorityRank() == rank) return i;
        }
        return null;
    }

    /// The highest active priority rank currently in the queue.
    pub fn highestActiveRank(self: *const NotificationQueue) ?u8 {
        var rank: ?u8 = null;
        for (self.items.items) |*item| {
            if (item.dismissed) continue;
            const r = item.priorityRank();
            if (rank == null or r < rank.?) rank = r;
        }
        return rank;
    }

    /// Whether any critical or high item is waiting to be shown.
    pub fn hasUrgent(self: *const NotificationQueue) bool {
        for (self.items.items) |*item| {
            if (item.dismissed) continue;
            if (item.priority == .critical or item.priority == .high) return true;
        }
        return false;
    }
};

/// State machine for revealing one notification card at a time.
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
    /// True when the stream is intentionally paused after an urgent clears.
    paused_for_break: bool = false,
    break_since_us: u64 = 0,

    pub fn reset(self: *TypewriterState, now_us: u64) void {
        self.queue_index = 0;
        self.chars_revealed = 0;
        self.last_char_us = now_us;
        self.is_idle = false;
        self.idle_since_us = 0;
        self.paused_for_break = false;
        self.break_since_us = 0;
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

        const maybe_picked = queue.pickActiveIndex();
        if (maybe_picked == null) {
            self.reset(now_us);
            return false;
        }
        const picked_index = maybe_picked.?;
        const picked_item = &queue.items.items[picked_index];
        const picked_rank = picked_item.priorityRank();

        const current_valid = self.queue_index < queue.items.items.len;
        const current_rank: u8 = if (current_valid)
            queue.items.items[self.queue_index].priorityRank()
        else
            255;
        const current_dismissed = if (current_valid)
            queue.items.items[self.queue_index].dismissed
        else
            true;

        if (current_dismissed) {
            self.pickNext(queue, now_us);
            return true;
        }

        // Critical always interrupts immediately.
        if (picked_rank == 0 and picked_index != self.queue_index) {
            self.switchTo(picked_index, now_us);
            return true;
        }

        // Urgent cards stay idle; the widget layer handles the resume break.
        if (self.is_idle and current_rank <= 1) {
            return false;
        }

        // High interrupts normal/low only after the current card finishes.
        if (picked_rank == 1 and picked_index != self.queue_index and self.is_idle) {
            self.switchTo(picked_index, now_us);
            return true;
        }

        // Keep typing the current card.
        const item = &queue.items.items[self.queue_index];
        const text = item.body;
        if (self.chars_revealed >= text.len) {
            self.is_idle = true;
            if (self.idle_since_us == 0) self.idle_since_us = now_us;
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

    fn switchTo(self: *TypewriterState, index: usize, now_us: u64) void {
        self.queue_index = index;
        self.chars_revealed = 0;
        self.last_char_us = now_us;
        self.is_idle = false;
        self.idle_since_us = 0;
        self.paused_for_break = false;
        self.break_since_us = 0;
    }

    pub fn pickNext(self: *TypewriterState, queue: *const NotificationQueue, now_us: u64) void {
        // Prefer staying at the current priority level and rotating through
        // active cards of that level. If none left, drop to the next lower rank.
        const current_rank = if (self.queue_index < queue.items.items.len)
            queue.items.items[self.queue_index].priorityRank()
        else
            255;

        // Start searching just after current index for same-rank items.
        var next: ?usize = null;
        if (queue.nextActiveAtPriority(self.queue_index + 1, current_rank)) |ni| {
            next = ni;
        } else if (queue.nextActiveAtPriority(0, current_rank)) |ni| {
            // Wrap around to beginning of queue at same rank.
            next = ni;
        } else {
            // Drop to next lower rank.
            var rank: u8 = current_rank + 1;
            while (rank <= 3) : (rank += 1) {
                if (queue.nextActiveAtPriority(0, rank)) |ni| {
                    next = ni;
                    break;
                }
            }
        }

        if (next) |ni| {
            self.switchTo(ni, now_us);
        } else {
            // Nothing else to show; reset.
            self.reset(now_us);
        }
    }

    pub fn advanceQueue(self: *TypewriterState, queue: *const NotificationQueue) void {
        const active = queue.activeCount();
        if (active == 0) return;
        self.pickNext(queue, animation.nowUs());
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
    /// Window for grouping same-source critical events into a burst count.
    burst_window_us: u64 = 2_000_000,
    /// Pause before resuming normal stream after urgent cards clear.
    resume_break_us: u64 = 1_500_000,
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

    pub fn clear(self: *NotificationWidget) void {
        self.tw.reset(0);
        self.queue.deinit();
        self.queue = NotificationQueue.init(self.queue.allocator, 32);
    }

    pub fn push(self: *NotificationWidget, title: []const u8, body: []const u8, source_id: []const u8, opts: PushOptions) !void {
        const now = animation.nowUs();
        _ = try self.queue.push(title, body, source_id, opts, now, self.config.burst_window_us);
        // If the stream was idle or paused, move to the new highest-priority card.
        if (self.tw.is_idle or self.tw.paused_for_break) {
            self.tw.advanceQueue(&self.queue);
        }
    }

    pub fn update(self: *NotificationWidget, now_us: u64) bool {
        const alive = self.tw.update(&self.queue, now_us);

        if (self.tw.is_idle and self.queue.activeCount() > 0) {
            const item = &self.queue.items.items[self.tw.queue_index];
            const is_urgent = item.priority == .critical or item.priority == .high;
            if (!is_urgent) {
                if (now_us - self.tw.idle_since_us >= self.config.idle_timeout_us) {
                    self.tw.advanceQueue(&self.queue);
                    return true;
                }
            } else if (!self.tw.paused_for_break) {
                // Start the post-urgent pause so the user has time to read it.
                self.tw.paused_for_break = true;
                self.tw.break_since_us = now_us;
            } else if (now_us - self.tw.break_since_us >= self.config.resume_break_us) {
                // Break over; resume normal stream unless another urgent is waiting.
                const next = self.queue.pickActiveIndex();
                if (next == null or self.queue.items.items[next.?].priorityRank() > 1) {
                    self.tw.paused_for_break = false;
                    self.tw.advanceQueue(&self.queue);
                    return true;
                }
            }
        }

        return alive;
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
    _ = renderNotificationsHeight(cr, box, style_, widget, now_us);
}

/// Same as renderNotifications but returns the natural content height.
pub fn renderNotificationsHeight(
    cr: *c.cairo_t,
    box: PeekBox,
    style_: style.Style,
    widget: *NotificationWidget,
    now_us: u64,
) i32 {
    if (widget.queue.activeCount() == 0) return 0;
    const w_d: f64 = @floatFromInt(box.width);
    const h_d: f64 = @floatFromInt(box.height);
    if (w_d < 20.0 or h_d < 20.0) return 0;

    if (widget.tw.queue_index >= widget.queue.items.items.len) return 0;
    const item = &widget.queue.items.items[widget.tw.queue_index];
    if (item.dismissed) return 0;

    const h: f64 = switch (item.display_mode) {
        .typewriter => renderTypewriterCard(cr, box, style_, widget, item, now_us),
        .scroll => renderTypewriterCard(cr, box, style_, widget, item, now_us),
        .banner => renderTypewriterCard(cr, box, style_, widget, item, now_us),
        .river => renderTypewriterCard(cr, box, style_, widget, item, now_us),
    };
    return @intFromFloat(@ceil(h));
}

fn renderTypewriterCard(
    cr: *c.cairo_t,
    box: PeekBox,
    style_: style.Style,
    widget: *NotificationWidget,
    item: *NotificationCard,
    now_us: u64,
) f64 {
    _ = now_us;
    const w_d: f64 = @floatFromInt(box.width);
    const h_d: f64 = @floatFromInt(box.height);
    const gold = style_.color_border_focused.toF64();
    const text = style_.tray_text_color.toF64();
    const is_actionable = item.action_id != null;

    c.cairo_save(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    const pad_x: f64 = @floatFromInt(widget.config.hmargin);
    const content_w = w_d - 2.0 * pad_x;
    if (content_w <= 0.0) {
        c.cairo_restore(cr);
        return 0.0;
    }

    const label_font = "Fantasque Sans Mono";
    const source_font = "Fantasque Sans Mono";
    const title_font = "Fantasque Sans Mono";
    const body_font = "Fantasque Sans Mono";
    const source_size: f64 = @as(f64, style_.font_size_s) * 1.15;
    const body_size: f64 = @as(f64, style_.font_size_s) * 1.00;
    const label_size: f64 = @as(f64, style_.font_size_s) * 0.90;
    const title_size: f64 = @as(f64, style_.font_size_s) * 1.05;

    var y: f64 = pad_x + source_size;

    // Actionable warnings show the priority label first.
    if (is_actionable and item.priority == .critical) {
        c.cairo_select_font_face(cr, label_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
        c.cairo_set_font_size(cr, label_size);
        const pcolor = item.priority.labelColor();
        c.cairo_set_source_rgba(cr, pcolor[0], pcolor[1], pcolor[2], pcolor[3]);
        centerText(cr, item.priority.label(), content_w, pad_x, y);
        y += label_size * 1.4;
    }

    // Source label (from rule table) with burst count.
    const rule = defaultRule(item.source_id);
    const scolor = rule.label_color;
    c.cairo_select_font_face(cr, source_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
    c.cairo_set_font_size(cr, source_size);
    c.cairo_set_source_rgba(cr, scolor[0], scolor[1], scolor[2], scolor[3]);
    var source_buf: [256]u8 = undefined;
    const source_to_show = if (item.group_count > 1) blk: {
        const s = std.fmt.bufPrint(&source_buf, "{s} ({d})", .{ rule.label, item.group_count }) catch rule.label;
        break :blk s;
    } else rule.label;
    centerText(cr, source_to_show, content_w, pad_x, y);
    y += source_size * 1.25;

    // Actionable warnings show a detail/title line before the body.
    if (is_actionable and item.priority == .critical) {
        c.cairo_select_font_face(cr, title_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
        c.cairo_set_font_size(cr, title_size);
        c.cairo_set_source_rgba(cr, text[0], text[1], text[2], 0.92);
        const title_abbrev = abbreviateText(cr, item.title, content_w, title_size);
        centerText(cr, title_abbrev, content_w, pad_x, y);
        y += title_size * 1.2;
    }

    // Body: state/progress line shown once, centered.
    var state_buf: [256]u8 = undefined;
    const full_body = item.body;
    const visible = full_body[0..@min(widget.tw.chars_revealed, full_body.len)];
    const progress = parseProgress(full_body);

    c.cairo_select_font_face(cr, body_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
    c.cairo_set_font_size(cr, body_size);
    c.cairo_set_source_rgba(cr, text[0], text[1], text[2], 0.95);

    var body_y = y;
    if (progress) |pct| {
        const bar_h: f64 = body_size * 0.55;
        const bar_w: f64 = content_w * 0.78;
        const bar_x: f64 = pad_x + (content_w - bar_w) * 0.5;
        const bar_y: f64 = body_y + bar_h;
        if (bar_y + bar_h <= h_d) {
            // Track.
            c.cairo_set_source_rgba(cr, text[0], text[1], text[2], 0.18);
            c.cairo_rectangle(cr, bar_x, bar_y, bar_w, bar_h);
            c.cairo_fill(cr);
            // Fill. Future candy: rounded caps, shimmer gradient, glow pulse.
            const fill_w = bar_w * @as(f64, @floatFromInt(pct)) / 100.0;
            if (fill_w > 0.0) {
                c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.95);
                c.cairo_rectangle(cr, bar_x, bar_y, fill_w, bar_h);
                c.cairo_fill(cr);
            }
            body_y = bar_y + bar_h + body_size * 0.9;
        }
        // State text.
        const label = std.fmt.bufPrint(&state_buf, "{s} · {d}%", .{ extractState(full_body), pct }) catch visible;
        if (body_y + body_size <= h_d) {
            c.cairo_set_source_rgba(cr, text[0], text[1], text[2], 0.75);
            centerText(cr, label, content_w, pad_x, body_y);
        }
    } else {
        // Non-progress bodies show the full normalized text, wrapped once and abbreviated.
        const state_text = abbreviateText(cr, normalizeState(full_body), content_w, body_size);
        var offset: usize = 0;
        while (offset < state_text.len) {
            const line = nextLine(cr, state_text[offset..], content_w);
            if (body_y + body_size > h_d) {
                offset = state_text.len;
                break;
            }
            centerText(cr, line, content_w, pad_x, body_y);
            body_y += body_size * 1.35;
            offset += line.len;
            if (offset < state_text.len and state_text[offset] == ' ') offset += 1;
        }
    }

    // Action-card hint: only on actionable warnings.
    if (is_actionable and item.priority == .critical) {
        const hint_y = body_y + body_size * 0.8;
        if (hint_y + body_size <= h_d) {
            c.cairo_select_font_face(cr, body_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
            c.cairo_set_font_size(cr, body_size * 0.75);
            c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.75);
            centerText(cr, "· · ·", content_w, pad_x, hint_y);
            body_y = hint_y + body_size * 0.6;
        }
    }

    const content_bottom = body_y + body_size * 0.5;

    // Critical act-now cards get a subtle tinted backing + burnt-orange border
    // sized tightly to the rendered content.
    if (is_actionable and item.priority == .critical) {
        const pcolor = item.priority.labelColor();
        const bmargin: f64 = 4.0;
        const corner: f64 = 6.0;
        const border_h = content_bottom - bmargin * 2.0 + body_size * 0.3;
        // Tinted backing for readability.
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.55);
        roundedRect(cr, bmargin, bmargin, w_d - 2.0 * bmargin, border_h, corner);
        c.cairo_fill(cr);
        // Subtle burnt-orange border.
        c.cairo_set_source_rgba(cr, pcolor[0], pcolor[1], pcolor[2], 0.45);
        c.cairo_set_line_width(cr, 1.0);
        roundedRect(cr, bmargin, bmargin, w_d - 2.0 * bmargin, border_h, corner);
        c.cairo_stroke(cr);
    }

    // Chrome-free stream: a faint bottom rule for non-actionable cards.
    if (!is_actionable or item.priority != .critical) {
        c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.10);
        c.cairo_set_line_width(cr, 1.0);
        c.cairo_move_to(cr, 0.0, content_bottom);
        c.cairo_line_to(cr, w_d, content_bottom);
        c.cairo_stroke(cr);
    }

    c.cairo_restore(cr);
    return content_bottom;
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
    // Cairo expects a null-terminated C string; heap-allocated slices are not.
    var nt_buf: [512]u8 = undefined;
    const safe = if (txt.len < nt_buf.len) blk: {
        @memcpy(nt_buf[0..txt.len], txt);
        nt_buf[txt.len] = 0;
        break :blk nt_buf[0..txt.len :0];
    } else blk: {
        @memcpy(nt_buf[0..nt_buf.len - 1], txt[0 .. nt_buf.len - 1]);
        nt_buf[nt_buf.len - 1] = 0;
        break :blk nt_buf[0 .. nt_buf.len - 1 :0];
    };
    c.cairo_text_extents(cr, safe.ptr, &ext);
    const x = x_offset + (content_w - ext.width) * 0.5;
    c.cairo_move_to(cr, x, y_baseline);
    c.cairo_show_text(cr, safe.ptr);
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

/// Middle-ellipsis abbreviation of `text` so it fits in `max_w` at the current
/// font. If it already fits, return the original slice unchanged.
fn abbreviateText(cr: *c.cairo_t, text: []const u8, max_w: f64, _: f64) []const u8 {
    if (text.len == 0) return text;
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, @ptrCast(text.ptr), &ext);
    if (ext.width <= max_w) return text;

    const ellipsis = "...";
    c.cairo_text_extents(cr, @ptrCast(ellipsis), &ext);
    const ellipsis_w = ext.width;
    if (max_w <= ellipsis_w) return text;

    const avail = max_w - ellipsis_w;
    // Binary search for the longest prefix that fits in half the available width.
    var lo: usize = 1;
    var hi: usize = text.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        c.cairo_text_extents(cr, @ptrCast(text[0..mid].ptr), &ext);
        if (ext.width <= avail * 0.5) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    const left_len = lo - 1;

    lo = 1;
    hi = text.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        c.cairo_text_extents(cr, @ptrCast(text[text.len - mid ..].ptr), &ext);
        if (ext.width <= avail * 0.5) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    const right_len = lo - 1;

    if (left_len + right_len + 3 >= text.len) return text;
    return std.fmt.bufPrint(&abbrev_buf, "{s}{s}{s}", .{ text[0..left_len], ellipsis, text[text.len - right_len ..] }) catch text;
}

var abbrev_buf: [512]u8 = undefined;

/// Extract a small detail token from the body, e.g. file type/size for downloads.
/// Format: detail|state or detail · state. Returns empty if no detail.
fn extractDetail(body: []const u8) []const u8 {
    // Look for a '|' separator used for extra metadata.
    if (std.mem.indexOfScalar(u8, body, '|')) |idx| {
        return std.mem.trim(u8, body[0..idx], " ");
    }
    // No detail present.
    return "";
}

/// Normalize state text: "pending approval" → "Pending".
fn normalizeState(text: []const u8) []const u8 {
    if (std.mem.eql(u8, text, "pending approval")) return "Pending";
    if (std.mem.startsWith(u8, text, "pending")) return "Pending";
    if (std.mem.eql(u8, text, "completed")) return "Completed";
    if (std.mem.eql(u8, text, "failed")) return "Failed";
    if (std.mem.eql(u8, text, "blocked")) return "Blocked";
    return text;
}

/// Look for the last "NN%" in the body and return the percent value.
fn parseProgress(text: []const u8) ?u8 {
    if (text.len < 2) return null;
    var i: usize = text.len;
    while (i > 0) : (i -= 1) {
        if (text[i - 1] == '%') {
            var j = i - 1;
            while (j > 0 and std.ascii.isDigit(text[j - 1])) j -= 1;
            if (j < i - 1) {
                const n = std.fmt.parseInt(u8, text[j .. i - 1], 10) catch return null;
                return @min(100, n);
            }
        }
    }
    return null;
}

/// Extract the state word before a progress percent, e.g. "downloading" from
/// "downloading · 47%". Falls back to the whole body if no clear state.
fn extractState(text: []const u8) []const u8 {
    if (text.len == 0) return text;
    // Find the percent and walk backward over space/digits/delimiters.
    var pct: usize = text.len;
    while (pct > 0 and text[pct - 1] != '%') pct -= 1;
    if (pct == 0) return text;
    var i = pct;
    while (i > 0 and (text[i - 1] == ' ' or text[i - 1] == '·' or text[i - 1] == '-' or std.ascii.isDigit(text[i - 1]))) i -= 1;
    if (i == 0) return text;
    // Trim trailing space from the extracted state.
    var end = i;
    while (end > 0 and text[end - 1] == ' ') end -= 1;
    return text[0..end];
}
