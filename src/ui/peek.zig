const std = @import("std");
const wlr = @import("wlroots");
const c = @import("dm").c;
const linux = std.os.linux;
const Style = @import("../core/style.zig").Style;
const Theme = @import("../core/theme.zig").Theme;
const DataBuffer = @import("../render/buffer.zig").DataBuffer;
const WeatherWidget = @import("weather.zig").WeatherWidget;
const GaugeWidget = @import("gauge.zig").GaugeWidget;
const DrivesWidget = @import("drives.zig").DrivesWidget;
const NetworkWidget = @import("network.zig").NetworkWidget;

/// PEEK (TASKCARD-3, locked vocabulary ruling): the model is slides in a
/// slidedeck. The left/right screen-edge slivers are PEEKS — the visible
/// edges of the side slides. Widgets live in the peek strips.
///
/// Permanent per-output edge furniture: left + right peeks. EXIT dots and
/// slide counts (signage) at the vertical center, plus the restored widget
/// stack ported verbatim from the pre-demolition painters
/// (e12ff6e~1:src/ui/tray.zig — geometry constants transcribed, not
/// re-tuned):
///
///   LEFT peek, top-to-bottom:  weather (moon + temp, 215 logical pill),
///                              gauges (GPU/CPU mercury), drives list,
///                              KSD logo bottom-anchored (inert click).
///   RIGHT peek, top-to-bottom: network icon in a 34*scale status strip,
///                              24h clock + 3-line date beneath it.
///
/// Peeks paint from the first frame on every output, every boot — no lazy
/// paths. The ONE AND ONLY hide condition (VISIBILITY LAW, Barticus
/// 2026-09-16): the whole peek set (widgets + signage) hides while any
/// slide is fullscreen. setHidden(bool) drives it from deck fullscreen
/// state; there is no other show/hide logic anywhere.
///
/// Geometry law for the signage strip: peek_fraction 0.06 of the output
/// width; EXIT dots sit 1 char-space from the slide border (inner peek
/// edge); the slide-count digit sits 1 char-space from the screen edge.
/// One click router: click = walk to the neighbor on that side.
pub const peek_fraction: f64 = 0.06;

const icon_size: u32 = 20; // px tall (unscaled), signage strip height
const exit_dots_w: u32 = 72; // px wide for the EXIT dot-matrix itself
const num_font_scale: f64 = 0.9;
const clock_h: u32 = 28; // px tall (unscaled) for the clock readout

pub const Side = enum { left, right };

// ── Widget geometry constants (ported verbatim from e12ff6e~1:tray.zig) ──
// Clock pill (old tray drawWidget, ~lines 2479-2485).
const clock_peek_hmargin: i32 = 2;
const clock_peek_vmargin: i32 = 20;
const clock_max_pill_base: f64 = 185.0; // logical, multiplied by scale
const clock_max_pill_lo: i32 = 80;
const clock_pill_w_lo: i32 = 20;
const clock_pill_h_lo: i32 = 40;
// Weather pill (old tray drawWeatherWidget, ~lines 2679-2687).
const weather_peek_hmargin: i32 = 2;
const weather_peek_vmargin: i32 = 8;
const weather_max_pill_side: i32 = 215; // logical, every output (CFC law)
// Gauge pill (old tray drawGaugeWidget, ~lines 2944-2955).
const gauge_peek_hmargin: i32 = 2;
const gauge_peek_vmargin: i32 = 8;
const gauge_weather_height: i32 = 215;
// Drives pill (old tray drawDrivesWidget, ~lines 3046-3056).
const drives_peek_hmargin: i32 = 2;
const drives_peek_vmargin: i32 = 8;
const drives_weather_height: i32 = 215;
// KSD logo (old tray drawLogoWidget, ~lines 2808-2822).
const logo_margin: i32 = 17;
const logo_fit_scale: f64 = 0.85;

const WidgetSlot = struct {
    scene_buffer: ?*wlr.SceneBuffer = null,
    buffer: ?*wlr.Buffer = null,
    last_w: i32 = -1,
    last_h: i32 = -1,
    last_x: i32 = -1,
    last_y: i32 = -1,
    last_scale: f32 = -1.0,
    last_minute: i32 = -1,
    last_theme_generation: u32 = 0,
};

pub const Peek = struct {
    overlay_tree: *wlr.SceneTree,
    style: Style,

    left_tree: ?*wlr.SceneTree = null,
    right_tree: ?*wlr.SceneTree = null,
    left_signage: ?*wlr.SceneBuffer = null,
    right_signage: ?*wlr.SceneBuffer = null,
    /// Clock readout in the right peek (widget painter v1).
    clock_buffer: ?*wlr.SceneBuffer = null,

    output_width: u32 = 0,
    output_height: u32 = 0,
    scale: u32 = 1,
    /// Output's global layout origin — scene coords are layout-global, so
    /// the per-output peek nodes carry this offset.
    box_x: i32 = 0,
    box_y: i32 = 0,

    has_left: bool = false,
    has_right: bool = false,
    left_count: u32 = 0,
    right_count: u32 = 0,
    last_minute: i64 = -1,
    /// VISIBILITY LAW: true while any slide is fullscreen — the whole peek
    /// set (widgets + signage) is disabled. The ONLY hide condition.
    hidden: bool = false,

    // Restored peek widgets (per-output buffers, shared widget STATE lives
    // in the Widgets struct on the server — initialized at server init,
    // never lazily).
    weather_slot: WidgetSlot = .{},
    gauge_slot: WidgetSlot = .{},
    drives_slot: WidgetSlot = .{},
    logo_slot: WidgetSlot = .{},
    clock_slot: WidgetSlot = .{},

    pub fn init(overlay_tree: *wlr.SceneTree, style: Style) Peek {
        return .{ .overlay_tree = overlay_tree, .style = style };
    }

    pub fn deinit(self: *Peek) void {
        if (self.left_tree) |t| t.node.destroy();
        if (self.right_tree) |t| t.node.destroy();
        inline for (.{ "weather_slot", "gauge_slot", "drives_slot", "logo_slot", "clock_slot" }) |name| {
            const slot = &@field(self, name);
            if (slot.scene_buffer) |sb| sb.node.destroy();
            if (slot.buffer) |b| wlr.Buffer.drop(b);
        }
        self.* = .{ .overlay_tree = self.overlay_tree, .style = self.style };
    }

    /// Born on output birth / mode change: the trees exist from the first
    /// frame and are NEVER disabled afterwards (no hide API). All widgets
    /// paint here — first frame, every time, no lazy paths.
    pub fn updateOutput(self: *Peek, width: u32, height: u32, scale: u32, box_x: i32, box_y: i32, widgets: *Widgets) void {
        self.output_width = width;
        self.output_height = height;
        self.scale = @max(1, scale);
        self.box_x = box_x;
        self.box_y = box_y;
        if (self.left_tree == null) {
            self.left_tree = self.overlay_tree.createSceneTree() catch null;
        }
        if (self.right_tree == null) {
            self.right_tree = self.overlay_tree.createSceneTree() catch null;
        }
        self.renderSignage(.left);
        self.renderSignage(.right);
        self.refreshClock();
        self.refreshWidgets(widgets);
    }

    /// VISIBILITY LAW (the only hide condition): hide the whole peek set —
    /// widgets AND signage — while any slide is fullscreen. Disabling the
    /// trees kills render AND the peek-edge hitboxes, so fullscreen apps
    /// own the screen edges.
    pub fn setHidden(self: *Peek, hidden: bool) void {
        if (self.hidden == hidden) return;
        self.hidden = hidden;
        const enabled = !hidden;
        if (self.left_tree) |t| t.node.setEnabled(enabled);
        if (self.right_tree) |t| t.node.setEnabled(enabled);
    }

    /// Neighbor availability + counts changed (deck walk): repaint signage.
    pub fn setNeighbors(self: *Peek, has_left: bool, has_right: bool, left_count: u32, right_count: u32) void {
        if (self.has_left == has_left and self.has_right == has_right and
            self.left_count == left_count and self.right_count == right_count) return;
        self.has_left = has_left;
        self.has_right = has_right;
        self.left_count = left_count;
        self.right_count = right_count;
        self.renderSignage(.left);
        self.renderSignage(.right);
    }

    fn leftPeekBox(self: *const Peek) ?PeekBox {
        const out_w: i32 = @intCast(self.output_width);
        const peek_w: i32 = @intFromFloat(@as(f64, @floatFromInt(out_w)) * peek_fraction);
        if (peek_w <= 0 or self.output_height == 0) return null;
        return .{ .x = self.box_x, .y = self.box_y, .width = peek_w, .height = @intCast(self.output_height) };
    }

    fn rightPeekBox(self: *const Peek) ?PeekBox {
        const out_w: i32 = @intCast(self.output_width);
        const peek_w: i32 = @intFromFloat(@as(f64, @floatFromInt(out_w)) * peek_fraction);
        if (peek_w <= 0 or self.output_height == 0) return null;
        return .{ .x = self.box_x + out_w - peek_w, .y = self.box_y, .width = peek_w, .height = @intCast(self.output_height) };
    }

    /// Repaint every restored peek widget. Cache fields gate the redraw so
    /// a no-change call repositions only — same pattern as the old painters.
    pub fn refreshWidgets(self: *Peek, widgets: *Widgets) void {
        self.drawWeatherWidget(widgets);
        self.drawGaugeWidget(widgets);
        self.drawDrivesWidget(widgets);
        self.drawLogoWidget(widgets);
        self.drawClockWidget(widgets);
    }

    /// Clock painter (v1 readout below the signage): refreshed on the
    /// minute (called from a server timer).
    pub fn refreshClock(self: *Peek) void {
        const minute = currentMinute();
        if (minute == self.last_minute and self.clock_buffer != null) return;
        self.last_minute = minute;
        const tree = self.right_tree orelse return;

        const s: i32 = @max(1, @as(i32, @intCast(self.scale)));
        const out_w: i32 = @intCast(self.output_width);
        const peek_w: i32 = @intFromFloat(@as(f64, @floatFromInt(out_w)) * peek_fraction);
        if (peek_w <= 0) return;
        const px_w: i32 = peek_w * s;
        const px_h: i32 = @as(i32, @intCast(clock_h)) * s;

        const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, px_w, px_h) orelse return;
        if (c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) {
            c.cairo_surface_destroy(surface);
            return;
        }
        const cr = c.cairo_create(surface) orelse {
            c.cairo_surface_destroy(surface);
            return;
        };
        defer c.cairo_destroy(cr);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        // HH:MM, dim gold, centered in the peek.
        var buf: [8]u8 = undefined;
        const text = formatClock(&buf);
        const gold = self.style.color_gold.toF64();
        c.cairo_select_font_face(cr, "JetBrains Mono", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
        const fs: f64 = @floatFromInt(px_h);
        c.cairo_set_font_size(cr, fs * 0.62);
        var ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, text.ptr, &ext);
        const wf: f64 = @floatFromInt(px_w);
        c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 0.86);
        c.cairo_move_to(cr, (wf - ext.width) / 2.0 - ext.x_bearing, (fs - ext.height) / 2.0 - ext.y_bearing);
        c.cairo_show_text(cr, text.ptr);
        c.cairo_surface_flush(surface);

        const data = c.cairo_image_surface_get_data(surface) orelse {
            c.cairo_surface_destroy(surface);
            return;
        };
        const stride = c.cairo_image_surface_get_stride(surface);
        const bytes = @as([*]u8, @ptrCast(data))[0..@intCast(stride * px_h)];
        const buf2 = DataBuffer.create(bytes, px_w, px_h, stride) catch {
            c.cairo_surface_destroy(surface);
            return;
        };
        c.cairo_surface_destroy(surface);
        const sb = tree.createSceneBuffer(buf2) catch {
            wlr.Buffer.drop(buf2);
            return;
        };
        wlr.Buffer.drop(buf2);
        sb.setDestSize(@intCast(peek_w), @intCast(clock_h));
        // Pin to the right peek, just below the vertical-center signage.
        const x = self.box_x + out_w - peek_w;
        const y = self.box_y + @divFloor(@as(i32, @intCast(self.output_height)), 2) +
            @as(i32, @intCast(icon_size));
        sb.node.setPosition(x, y);
        if (self.clock_buffer) |old| old.node.destroy();
        self.clock_buffer = sb;
    }

    fn renderSignage(self: *Peek, side: Side) void {
        const tree = switch (side) {
            .left => self.left_tree orelse return,
            .right => self.right_tree orelse return,
        };
        const enabled = switch (side) {
            .left => self.has_left,
            .right => self.has_right,
        };
        const count = switch (side) {
            .left => self.left_count,
            .right => self.right_count,
        };

        const old = switch (side) {
            .left => self.left_signage,
            .right => self.right_signage,
        };
        if (old) |o| o.node.destroy();
        switch (side) {
            .left => self.left_signage = null,
            .right => self.right_signage = null,
        }
        // No neighbor on this side: the peek shows no signage (but the TREE
        // lives — peeks never hide; only their signage is absent at the row
        // ends, which is exactly the EXIT-sign law: ends are where the sign
        // is loudest, and a missing sign means "nowhere to walk").
        if (!enabled) return;

        const s: i32 = @max(1, @as(i32, @intCast(self.scale)));
        const out_w: i32 = @intCast(self.output_width);
        const peek_w: i32 = @intFromFloat(@as(f64, @floatFromInt(out_w)) * peek_fraction);
        if (peek_w <= 0) return;
        const px_w: i32 = peek_w * s;
        const px_h: i32 = @as(i32, @intCast(icon_size)) * s;

        const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, px_w, px_h) orelse return;
        if (c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) {
            c.cairo_surface_destroy(surface);
            return;
        }
        const cr = c.cairo_create(surface) orelse {
            c.cairo_surface_destroy(surface);
            return;
        };
        defer c.cairo_destroy(cr);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);
        c.cairo_set_source_rgba(cr, 0.30, 0.29, 0.25, 0.86);

        const wf: f64 = @floatFromInt(px_w);
        const hf: f64 = @floatFromInt(px_h);
        const sf: f64 = @floatFromInt(s);
        paintExitDotsSkin(cr, wf, hf, sf, side, count);
        c.cairo_surface_flush(surface);

        const data = c.cairo_image_surface_get_data(surface) orelse {
            c.cairo_surface_destroy(surface);
            return;
        };
        const stride = c.cairo_image_surface_get_stride(surface);
        const bytes = @as([*]u8, @ptrCast(data))[0..@intCast(stride * px_h)];
        const buf = DataBuffer.create(bytes, px_w, px_h, stride) catch {
            c.cairo_surface_destroy(surface);
            return;
        };
        c.cairo_surface_destroy(surface);
        const sb = tree.createSceneBuffer(buf) catch {
            wlr.Buffer.drop(buf);
            return;
        };
        wlr.Buffer.drop(buf);
        sb.setDestSize(@intCast(peek_w), @intCast(icon_size));
        const x: i32 = switch (side) {
            .left => self.box_x,
            .right => self.box_x + out_w - peek_w,
        };
        const y = self.box_y + @divFloor(@as(i32, @intCast(self.output_height)) - @as(i32, @intCast(icon_size)), 2);
        sb.node.setPosition(x, y);
        switch (side) {
            .left => self.left_signage = sb,
            .right => self.right_signage = sb,
        }
    }

    /// One click router: click = walk to the neighbor on that side.
    /// Output-local coords; returns the side clicked, or null.
    pub fn handleClick(self: *const Peek, x: f64, y: f64) ?Side {
        if (self.hidden) return null; // fullscreen owns the screen edges
        const out_w: f64 = @floatFromInt(self.output_width);
        const out_h: f64 = @floatFromInt(self.output_height);
        const peek_w: f64 = out_w * peek_fraction;
        if (y < 0 or y >= out_h) return null;
        if (self.has_left and x >= 0 and x < peek_w) return .left;
        if (self.has_right and x >= out_w - peek_w and x < out_w) return .right;
        return null;
    }

    // ── Restored widget painters (ported verbatim geometry from ─────────
    // ── e12ff6e~1:src/ui/tray.zig — do NOT re-tune) ──────────────────────

    /// Weather widget, top of the left peek. Port of old tray
    /// drawWeatherWidget (lines 2663-2766). Redraw gated on minute, theme
    /// generation, scale, and pill box.
    fn drawWeatherWidget(self: *Peek, widgets: *Widgets) void {
        const box = self.leftPeekBox() orelse return;
        if (box.width <= 0 or box.height <= 0) return;
        const tree = self.left_tree orelse return;
        const widget = &self.weather_slot;

        const current_minute = currentMinuteOfDay();
        const style_ = self.style;
        const theme_gen = widgets.theme.generation;
        const scale: f32 = @floatFromInt(self.scale);

        // Geometry below is verbatim from the old tray drawWeatherWidget.
        const peek_hmargin = weather_peek_hmargin;
        const peek_vmargin = weather_peek_vmargin;
        // CFC scale law: logical geometry NEVER multiplies by scale — scale
        // is applied once at raster time. 215 logical on every output.
        const max_pill_side: i32 = weather_max_pill_side;
        const pill_w: i32 = @max(20, @min(box.width - 2 * peek_hmargin, max_pill_side));
        const pill_h: i32 = @max(40, @min(box.height - 2 * peek_vmargin, max_pill_side));
        const pill_x = box.x + peek_hmargin + @divTrunc(box.width - 2 * peek_hmargin - pill_w, 2);
        const pill_y = box.y + peek_vmargin + 4;

        const redraw = widget.scene_buffer == null or
            widget.last_w != pill_w or
            widget.last_h != pill_h or
            widget.last_x != pill_x or
            widget.last_y != pill_y or
            widget.last_scale != scale or
            widget.last_minute != current_minute or
            widget.last_theme_generation != theme_gen;

        if (!redraw) {
            tree.node.setPosition(pill_x, pill_y);
            tree.node.raiseToTop();
            return;
        }

        widget.last_w = pill_w;
        widget.last_h = pill_h;
        widget.last_x = pill_x;
        widget.last_y = pill_y;
        widget.last_scale = scale;
        widget.last_minute = current_minute;
        widget.last_theme_generation = theme_gen;

        paintSlot(widgets.allocator, widget, tree, pill_w, pill_h, pill_x, pill_y, scale, struct {
            fn paint(cr: *c.cairo_t, w: *Widgets, dev_w: i32, dev_h: i32, px: i32, py: i32, sc: f32, st: Style) void {
                w.weather.renderPeek(cr, .{ .x = px, .y = py, .width = dev_w, .height = dev_h }, st, sc);
            }
        }.paint, widgets, style_);
    }

    /// Gauge widget below the weather pill, left peek. Port of old tray
    /// drawGaugeWidget (lines 2932-3032).
    fn drawGaugeWidget(self: *Peek, widgets: *Widgets) void {
        const full_box = self.leftPeekBox() orelse return;
        if (full_box.width <= 0 or full_box.height <= 0) return;
        const tree = self.left_tree orelse return;
        const widget = &self.gauge_slot;

        const style_ = self.style;
        const theme_gen = widgets.theme.generation;
        const scale: f32 = @floatFromInt(self.scale);

        // Geometry verbatim from the old tray drawGaugeWidget.
        const peek_hmargin = gauge_peek_hmargin;
        const peek_vmargin = gauge_peek_vmargin;
        // CFC scale law: weather strip is 215 logical on every output; scale
        // is applied at raster time only.
        const weather_height: i32 = gauge_weather_height;
        // Split the remaining left-peek area: gauges at the top, drives below.
        const total_h = @max(0, full_box.height - weather_height - peek_vmargin * 2);
        const gauge_h_i: i32 = @max(40, total_h);
        const pill_w: i32 = @max(20, full_box.width - 2 * peek_hmargin);
        const pill_x = full_box.x + peek_hmargin + @divTrunc(full_box.width - 2 * peek_hmargin - pill_w, 2);
        const pill_y = full_box.y + weather_height + peek_vmargin + 4;
        const pill_h = gauge_h_i;

        const redraw = widget.scene_buffer == null or
            widget.last_w != pill_w or
            widget.last_h != pill_h or
            widget.last_x != pill_x or
            widget.last_y != pill_y or
            widget.last_scale != scale or
            widget.last_theme_generation != theme_gen;

        if (!redraw) {
            tree.node.setPosition(pill_x, pill_y);
            tree.node.raiseToTop();
            return;
        }

        widget.last_w = pill_w;
        widget.last_h = pill_h;
        widget.last_x = pill_x;
        widget.last_y = pill_y;
        widget.last_scale = scale;
        widget.last_theme_generation = theme_gen;

        paintSlot(widgets.allocator, widget, tree, pill_w, pill_h, pill_x, pill_y, scale, struct {
            fn paint(cr: *c.cairo_t, w: *Widgets, dev_w: i32, dev_h: i32, px: i32, py: i32, sc: f32, st: Style) void {
                w.gauge.renderPeek(cr, .{ .x = px, .y = py, .width = dev_w, .height = dev_h }, st, sc);
            }
        }.paint, widgets, style_);
    }

    /// Drives widget below the gauges, left peek. Port of old tray
    /// drawDrivesWidget (lines 3034-3164). The old painters gated the drive
    /// list on the files app being open; with the overlay gone there is no
    /// such signal, so the list renders unconditionally (drives.zig simply
    /// enumerates /dev in that branch).
    fn drawDrivesWidget(self: *Peek, widgets: *Widgets) void {
        const full_box = self.leftPeekBox() orelse return;
        if (full_box.width <= 0 or full_box.height <= 0) return;
        const tree = self.left_tree orelse return;
        const widget = &self.drives_slot;

        const style_ = self.style;
        const theme_gen = widgets.theme.generation;
        const scale: f32 = @floatFromInt(self.scale);

        // Geometry verbatim from the old tray drawDrivesWidget.
        const peek_hmargin = drives_peek_hmargin;
        const peek_vmargin = drives_peek_vmargin;
        // CFC scale law: weather strip is 215 logical on every output; scale
        // is applied at raster time only.
        const weather_height: i32 = drives_weather_height;
        const total_h = @max(0, full_box.height - weather_height - peek_vmargin * 2);
        const gauge_h_i: i32 = @max(40, @divTrunc(total_h * 4, 10));
        const drives_h_i: i32 = @max(40, total_h - gauge_h_i);
        const pill_w: i32 = @max(20, full_box.width - 2 * peek_hmargin);
        const pill_x = full_box.x + peek_hmargin + @divTrunc(full_box.width - 2 * peek_hmargin - pill_w, 2);
        const pill_y = full_box.y + weather_height + peek_vmargin + 4 + gauge_h_i;
        const pill_h = drives_h_i;

        const redraw = widget.scene_buffer == null or
            widget.last_w != pill_w or
            widget.last_h != pill_h or
            widget.last_x != pill_x or
            widget.last_y != pill_y or
            widget.last_scale != scale or
            widget.last_theme_generation != theme_gen;

        if (!redraw) {
            tree.node.setPosition(pill_x, pill_y);
            tree.node.raiseToTop();
            return;
        }

        widget.last_w = pill_w;
        widget.last_h = pill_h;
        widget.last_x = pill_x;
        widget.last_y = pill_y;
        widget.last_scale = scale;
        widget.last_theme_generation = theme_gen;

        paintSlot(widgets.allocator, widget, tree, pill_w, pill_h, pill_x, pill_y, scale, struct {
            fn paint(cr: *c.cairo_t, w: *Widgets, dev_w: i32, dev_h: i32, px: i32, py: i32, sc: f32, st: Style) void {
                w.drives.renderPeek(cr, .{ .x = px, .y = py, .width = dev_w, .height = dev_h }, st, sc, true);
            }
        }.paint, widgets, style_);
    }

    /// KSD logo, bottom-anchored in the left peek. Port of old tray
    /// ensureLogoSurface + drawLogoWidget (lines 2768-2917). Static: no
    /// polling, no timers — repaints only on layout/scale/theme change.
    /// The click is inert (peeks own their one click router).
    fn drawLogoWidget(self: *Peek, widgets: *Widgets) void {
        const full_box = self.leftPeekBox() orelse return;
        if (full_box.width <= 0 or full_box.height <= 0) return;
        const tree = self.left_tree orelse return;
        const widget = &self.logo_slot;
        widgets.ensureLogoSurface();
        const surf = widgets.logo_surface orelse return;
        if (widgets.logo_w <= 0 or widgets.logo_h <= 0) return;

        const style_ = self.style;
        const theme_gen = widgets.theme.generation;
        const scale: f32 = @floatFromInt(self.scale);

        // Fit the logo to the peek width and center it at the bottom.
        // CFC scale law: 17 logical gap on every output (raster scales it).
        const margin: i32 = logo_margin;
        const avail_w: f64 = @floatFromInt(full_box.width - 2 * margin);
        const avail_h: f64 = @floatFromInt(@min(full_box.width, @max(24, full_box.height)));
        const src_w: f64 = @floatFromInt(widgets.logo_w);
        const src_h: f64 = @floatFromInt(widgets.logo_h);
        const fit = @min(avail_w / src_w, avail_h / src_h) * logo_fit_scale; // a little smaller, per the eye test
        const draw_w: i32 = @max(1, @as(i32, @intFromFloat(@round(src_w * fit))));
        const draw_h: i32 = @max(1, @as(i32, @intFromFloat(@round(src_h * fit))));
        const bx = full_box.x + @divTrunc(full_box.width - draw_w, 2);
        // Bottom gap = the REAL rendered side gap (margin + centering slack/2),
        // so the mark sits in an even field on all three sides.
        const side_gap: i32 = @divTrunc(full_box.width - draw_w, 2);
        const by = full_box.y + full_box.height - draw_h - side_gap;

        const redraw = widget.scene_buffer == null or
            widget.last_w != draw_w or
            widget.last_h != draw_h or
            widget.last_x != bx or
            widget.last_y != by or
            widget.last_scale != scale or
            widget.last_theme_generation != theme_gen;

        if (!redraw) {
            tree.node.setPosition(bx, by);
            tree.node.raiseToTop();
            return;
        }

        widget.last_w = draw_w;
        widget.last_h = draw_h;
        widget.last_x = bx;
        widget.last_y = by;
        widget.last_scale = scale;
        widget.last_theme_generation = theme_gen;

        const dev_w: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(draw_w)) * scale));
        const dev_h: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(draw_h)) * scale));
        const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, dev_w);
        if (stride <= 0) return;
        const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(dev_h));
        const temp = widgets.allocator.alloc(u8, buf_size) catch return;
        defer widgets.allocator.free(temp);
        @memset(temp, 0);

        const surface = c.cairo_image_surface_create_for_data(temp.ptr, c.CAIRO_FORMAT_ARGB32, dev_w, dev_h, stride);
        defer c.cairo_surface_destroy(surface);
        const cr = c.cairo_create(surface) orelse return;
        defer c.cairo_destroy(cr);

        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        // KSD treatment: paint the glyph in three soft layers instead of one
        // flat tone — a whisper-dark pass under everything, the main border-
        // color body slightly dimmer than before, then a faint brighter kiss
        // on the top 40% (light from above, like the aurora wash). The wave
        // at the bottom gets only the dark+body layers, so it reads shaded.
        const bc = style_.color_border.toF64();
        const sx = @as(f64, @floatFromInt(dev_w)) / src_w;
        const sy = @as(f64, @floatFromInt(dev_h)) / src_h;

        // Layer 1 — umbra: same glyph offset down a hair, very dark. Gives
        // the whole mark depth and pulls the wave into shadow.
        c.cairo_save(cr);
        c.cairo_scale(cr, sx, sy);
        c.cairo_translate(cr, 0.0, src_h * 0.03);
        c.cairo_set_source_rgba(cr, bc[0] * 0.25, bc[1] * 0.25, bc[2] * 0.25, 0.6);
        c.cairo_mask_surface(cr, surf, 0.0, 0.0);
        c.cairo_restore(cr);

        // Layer 2 — body: the glyph itself, 0.70 alpha (was 0.80 — softer,
        // lets the umbra breathe through so the mark stops reading solid).
        c.cairo_save(cr);
        c.cairo_scale(cr, sx, sy);
        c.cairo_set_source_rgba(cr, bc[0], bc[1], bc[2], 0.70);
        c.cairo_mask_surface(cr, surf, 0.0, 0.0);
        c.cairo_restore(cr);

        // Layer 3 — crown light: glyph again, brighter, clipped to the top
        // 40% so the K stem top and the S/D catch a faint sheen; the wave
        // (bottom ~35%) never sees this pass and stays shaded.
        c.cairo_save(cr);
        c.cairo_rectangle(cr, 0.0, 0.0, @floatFromInt(dev_w), @as(f64, @floatFromInt(dev_h)) * 0.40);
        c.cairo_clip(cr);
        c.cairo_scale(cr, sx, sy);
        c.cairo_set_source_rgba(cr, @min(1.0, bc[0] * 1.35), @min(1.0, bc[1] * 1.35), @min(1.0, bc[2] * 1.35), 0.35);
        c.cairo_mask_surface(cr, surf, 0.0, 0.0);
        c.cairo_restore(cr);

        commitSlot(widget, tree, temp, dev_w, dev_h, stride, draw_w, draw_h, bx, by);
    }

    /// Clock widget, top of the right peek: network icon in a 34*scale
    /// status strip at the top, 24h time beneath, 3-line date block below.
    /// Port of old tray drawWidget (lines 2461-2660). Redraw gated on
    /// minute, theme generation, scale, and pill box.
    fn drawClockWidget(self: *Peek, widgets: *Widgets) void {
        const box = self.rightPeekBox() orelse return;
        if (box.width <= 0 or box.height <= 0) return;
        const tree = self.right_tree orelse return;
        const widget = &self.clock_slot;

        const current_minute = currentMinuteOfDay();
        const tstyle = self.style;
        const theme_gen = widgets.theme.generation;
        const scale: f32 = @floatFromInt(self.scale);

        // Content-sized widget, horizontally centered, filling the top of the right peek.
        const peek_hmargin = clock_peek_hmargin;
        const peek_vmargin = clock_peek_vmargin;
        const max_pill_side: i32 = @max(clock_max_pill_lo, @as(i32, @intFromFloat(clock_max_pill_base * @as(f64, scale))));
        const pill_w: i32 = @max(clock_pill_w_lo, @min(box.width - 2 * peek_hmargin, max_pill_side));
        const pill_h: i32 = @max(clock_pill_h_lo, @min(box.height - 2 * peek_vmargin, max_pill_side));
        const pill_x = box.x + peek_hmargin + @divTrunc(box.width - 2 * peek_hmargin - pill_w, 2);
        const pill_y = box.y + peek_vmargin;

        const needs_redraw = widget.scene_buffer == null or
            widget.last_w != pill_w or
            widget.last_h != pill_h or
            widget.last_x != pill_x or
            widget.last_y != pill_y or
            widget.last_scale != scale or
            widget.last_minute != current_minute or
            widget.last_theme_generation != theme_gen;

        if (!needs_redraw) {
            tree.node.setPosition(pill_x, pill_y);
            tree.node.raiseToTop();
            return;
        }

        widget.last_w = pill_w;
        widget.last_h = pill_h;
        widget.last_x = pill_x;
        widget.last_y = pill_y;
        widget.last_scale = scale;
        widget.last_minute = current_minute;
        widget.last_theme_generation = theme_gen;

        const dev_w: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(pill_w)) * scale));
        const dev_h: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(pill_h)) * scale));
        const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, dev_w);
        if (stride <= 0) return;
        const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(dev_h));
        const temp = widgets.allocator.alloc(u8, buf_size) catch |err| {
            std.log.err("KidulWM: clock widget buffer alloc failed: {}", .{err});
            return;
        };
        defer widgets.allocator.free(temp);
        @memset(temp, 0);

        const surface = c.cairo_image_surface_create_for_data(temp.ptr, c.CAIRO_FORMAT_ARGB32, dev_w, dev_h, stride);
        defer c.cairo_surface_destroy(surface);
        const cr = c.cairo_create(surface) orelse {
            std.log.err("KidulWM: failed to create cairo context for clock widget", .{});
            return;
        };
        defer c.cairo_destroy(cr);

        c.cairo_save(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        const card_font = "Fantasque Sans Mono";
        const muted_color = tstyle.color_text_muted.toF64();
        const w_d: f64 = @floatFromInt(dev_w);
        const h_d: f64 = @floatFromInt(dev_h);
        const status_strip_h: f64 = 34.0 * @as(f64, scale);

        // Network icon is drawn first at the top of the same buffer,
        // shifted 7px left with the clock content just underneath it.
        c.cairo_save(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);
        c.cairo_translate(cr, -7.0 * @as(f64, scale), 0.0);
        widgets.network.renderPeek(cr, .{
            .x = 0,
            .y = 0,
            .width = dev_w,
            .height = @as(i32, @intFromFloat(status_strip_h)),
        }, tstyle, scale);
        c.cairo_restore(cr);

        // 24-hour time, natural font proportions, no squish.
        const hour = @as(i32, @intCast(localTm().tm_hour));
        const minute = @as(i32, @intCast(localTm().tm_min));

        var hour_buf: [4:0]u8 = undefined;
        @memset(&hour_buf, 0);
        const hour_str = std.fmt.bufPrintZ(&hour_buf, "{s}{d}", .{ if (hour < 10) "0" else "", hour }) catch "00";
        var minute_buf: [4:0]u8 = undefined;
        @memset(&minute_buf, 0);
        const minute_str = std.fmt.bufPrintZ(&minute_buf, "{s}{d}", .{ if (minute < 10) "0" else "", minute }) catch "00";
        var combined_buf: [16:0]u8 = undefined;
        @memset(&combined_buf, 0);
        const num_str = std.fmt.bufPrintZ(&combined_buf, "{s}:{s}", .{ hour_str, minute_str }) catch "00:00";

        const big_font_size: f64 = @as(f64, tstyle.font_size_m) * 1.9 * scale;

        const gold4 = tstyle.color_border_focused.toF64();

        c.cairo_select_font_face(cr, card_font, c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);

        var num_ext: c.cairo_text_extents_t = undefined;
        var current_size = big_font_size;
        c.cairo_set_font_size(cr, current_size);
        c.cairo_text_extents(cr, num_str, &num_ext);
        while (num_ext.width > w_d - 8.0 and current_size > 6.0) {
            current_size *= 0.92;
            c.cairo_set_font_size(cr, current_size);
            c.cairo_text_extents(cr, num_str, &num_ext);
        }

        // Top buffer: 10pt gap between the status strip and the clock digits,
        // matching the weather side.
        const top_pad: f64 = status_strip_h + 10.0 * scale;
        const num_baseline_y = num_ext.height + top_pad;
        const time_x = (w_d - num_ext.width) * 0.5 - 9.0 * scale;

        c.cairo_set_source_rgba(cr, gold4[0], gold4[1], gold4[2], 1.0);
        c.cairo_move_to(cr, time_x, num_baseline_y);
        c.cairo_show_text(cr, num_str);

        // 3-line date block below the time, each line centered.
        const tm = localTm();
        const weekday_name = weekdayName(tm.tm_wday);
        const day = @as(i32, @intCast(tm.tm_mday));
        var day_buf: [32:0]u8 = undefined;
        @memset(&day_buf, 0);
        const day_str = std.fmt.bufPrintZ(&day_buf, "{d}{s}", .{ day, ordinalSuffix(day) }) catch "1st";

        var date_font_size: f64 = @as(f64, tstyle.font_size_s) * 1.3 * scale;
        var line_gap = date_font_size * 1.25;
        while (num_baseline_y + line_gap * 3.6 + date_font_size * 0.3 > h_d and date_font_size > 6.0) {
            date_font_size *= 0.92;
            line_gap *= 0.92;
        }
        const date_block_top = num_baseline_y + line_gap * 1.5;

        const month_name = monthName(tm.tm_mon);
        const date_lines = [_][]const u8{ weekday_name, day_str, month_name };
        const date_weights = [_]c.cairo_font_weight_t{
            c.CAIRO_FONT_WEIGHT_NORMAL,
            c.CAIRO_FONT_WEIGHT_NORMAL,
            c.CAIRO_FONT_WEIGHT_NORMAL,
        };
        for (date_lines, date_weights, 0..) |line_txt, weight, i| {
            fitAndDraw(
                cr,
                card_font,
                date_font_size,
                weight,
                line_txt,
                muted_color[0],
                muted_color[1],
                muted_color[2],
                0.95,
                w_d,
                4.0 * scale,
            );
            var ext2: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, @ptrCast(line_txt.ptr), &ext2);
            const y = date_block_top + @as(f64, @floatFromInt(i)) * line_gap;
            // Date sits 7px left with the clock, plus 3px back right.
            c.cairo_move_to(cr, (w_d - ext2.width) * 0.5 - 4.0 * scale, y);
            c.cairo_show_text(cr, @ptrCast(line_txt.ptr));
        }
        c.cairo_restore(cr);

        commitSlot(widget, tree, temp, dev_w, dev_h, stride, pill_w, pill_h, pill_x, pill_y);
    }
};

const PeekBox = struct { x: i32, y: i32, width: i32, height: i32 };

/// Shared widget state for the peek strips. Owned by the server,
/// initialized at server init — never lazily. Poll pattern ported from the
/// old overlay update(): weather.update() (10-min cache read internally),
/// network.update() (2s scan internally) run from the server's widget
/// timer; gauge/drives sample at paint time (no update method, as before).
pub const Widgets = struct {
    allocator: std.mem.Allocator,
    weather: WeatherWidget,
    gauge: GaugeWidget,
    drives: DrivesWidget,
    network: NetworkWidget,
    theme: *const Theme,
    logo_surface: ?*c.cairo_surface_t = null,
    logo_w: i32 = 0,
    logo_h: i32 = 0,

    pub fn init(allocator: std.mem.Allocator, theme: *const Theme) Widgets {
        return .{
            .allocator = allocator,
            .weather = WeatherWidget.init(allocator),
            .gauge = GaugeWidget.init(allocator),
            .drives = DrivesWidget.init(allocator),
            .network = NetworkWidget.init(allocator),
            .theme = theme,
        };
    }

    pub fn deinit(self: *Widgets) void {
        self.weather.deinit();
        self.gauge.deinit();
        self.drives.deinit();
        self.network.deinit();
        if (self.logo_surface) |surf| c.cairo_surface_destroy(surf);
        self.logo_surface = null;
    }

    /// Poll the stateful widgets — call from the server's widget timer.
    pub fn update(self: *Widgets) void {
        self.weather.update();
        self.network.update();
    }

    /// Load the KSD logo mask once and keep it for the compositor's
    /// lifetime. LOW-POWER LAW (Barticus 2026-09-15): the logo is a static
    /// image — no polling, no timers, no animation. Ported verbatim from
    /// the old tray ensureLogoSurface.
    pub fn ensureLogoSurface(self: *Widgets) void {
        if (self.logo_surface != null) return;
        const png = @embedFile("assets/ksd_logo_mask.png");
        const fd = std.posix.memfd_create("ksd_logo", 0) catch return;
        defer _ = std.c.close(fd);
        _ = std.c.ftruncate(fd, @intCast(png.len));
        const mem = std.c.mmap(null, png.len, std.os.linux.PROT{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0);
        const MAP_FAILED: *anyopaque = @ptrFromInt(std.math.maxInt(usize));
        if (mem == MAP_FAILED) return;
        defer _ = std.c.munmap(@alignCast(mem), png.len);
        const mem_slice = @as([*]u8, @ptrCast(mem))[0..png.len];
        @memcpy(mem_slice, png);
        var path_buf: [64]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, "/proc/self/fd/{d}", .{fd}) catch return;
        const surf = c.cairo_image_surface_create_from_png(path.ptr);
        if (surf == null) return;
        if (c.cairo_surface_status(surf) != c.CAIRO_STATUS_SUCCESS) {
            c.cairo_surface_destroy(surf);
            return;
        }
        self.logo_surface = surf;
        self.logo_w = c.cairo_image_surface_get_width(surf);
        self.logo_h = c.cairo_image_surface_get_height(surf);
    }
};

/// Paint a widget pill into a fresh ARGB32 buffer and commit it as the
/// slot's scene buffer (old tray buffer dance, verbatim).
fn paintSlot(
    allocator: std.mem.Allocator,
    widget: *WidgetSlot,
    tree: *wlr.SceneTree,
    pill_w: i32,
    pill_h: i32,
    pill_x: i32,
    pill_y: i32,
    scale: f32,
    paint_fn: *const fn (cr: *c.cairo_t, widgets: *Widgets, dev_w: i32, dev_h: i32, px: i32, py: i32, sc: f32, st: Style) void,
    widgets: *Widgets,
    style_: Style,
) void {
    const dev_w: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(pill_w)) * scale));
    const dev_h: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(pill_h)) * scale));
    const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, dev_w);
    if (stride <= 0) return;
    const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intCast(dev_h));
    const temp = allocator.alloc(u8, buf_size) catch return;
    defer allocator.free(temp);
    @memset(temp, 0);

    const surface = c.cairo_image_surface_create_for_data(temp.ptr, c.CAIRO_FORMAT_ARGB32, dev_w, dev_h, stride);
    defer c.cairo_surface_destroy(surface);
    const cr = c.cairo_create(surface) orelse return;
    defer c.cairo_destroy(cr);

    c.cairo_save(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    c.cairo_paint(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    paint_fn(cr, widgets, dev_w, dev_h, pill_x, pill_y, scale, style_);

    c.cairo_restore(cr);

    commitSlot(widget, tree, temp, dev_w, dev_h, stride, pill_w, pill_h, pill_x, pill_y);
}

fn commitSlot(widget: *WidgetSlot, tree: *wlr.SceneTree, data: []const u8, dev_w: i32, dev_h: i32, stride: i32, dest_w: i32, dest_h: i32, x: i32, y: i32) void {
    const buffer = DataBuffer.create(data, dev_w, dev_h, @intCast(stride)) catch return;
    if (widget.buffer) |old| wlr.Buffer.drop(old);
    widget.buffer = buffer;
    if (widget.scene_buffer) |old| old.node.destroy();
    const sb = tree.createSceneBuffer(buffer) catch {
        wlr.Buffer.drop(buffer);
        widget.buffer = null;
        return;
    };
    sb.setDestSize(dest_w, dest_h);
    widget.scene_buffer = sb;
    tree.node.setPosition(x, y);
    tree.node.raiseToTop();
}

fn currentMinute() i64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(linux.CLOCK.REALTIME, &ts);
    return @divFloor(@as(i64, ts.sec), 60);
}

extern "c" fn time(timep: ?*i64) i64;

fn localTm() Tm {
    var now: i64 = time(null);
    var tm: Tm = undefined;
    if (localtime_r(&now, &tm) == null) return std.mem.zeroes(Tm);
    return tm;
}

fn currentMinuteOfDay() i32 {
    const tm = localTm();
    return @as(i32, @intCast(tm.tm_min)) + @as(i32, @intCast(tm.tm_hour)) * 60;
}

fn formatClock(buf: *[8]u8) [:0]const u8 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(linux.CLOCK.REALTIME, &ts);
    // Kernel REALTIME is UTC; apply the host's local offset via libc
    // localtime_r (tm_gmtoff) — no TZ parsing on our side.
    const off = localOffsetSeconds(@as(i64, ts.sec));
    const local_secs: u64 = @intCast(@max(0, @as(i64, ts.sec) + off));
    const lh = (local_secs % 86400) / 3600;
    const lm = (local_secs % 3600) / 60;
    return std.fmt.bufPrintZ(buf, "{d:0>2}:{d:0>2}", .{ lh, lm }) catch "--:--";
}

extern "c" fn localtime_r(timep: *const i64, result: *Tm) ?*Tm;
const Tm = extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
    tm_gmtoff: i64,
    tm_zone: ?[*:0]const u8,
};

fn localOffsetSeconds(now: i64) i64 {
    var tm: Tm = undefined;
    if (localtime_r(&now, &tm) == null) return 0;
    return tm.tm_gmtoff;
}

// Date helpers ported verbatim from e12ff6e~1:src/ui/tray.zig.

fn ordinalSuffix(n: i32) []const u8 {
    const m = @mod(n, 100);
    if (m >= 11 and m <= 13) return "th";
    return switch (@mod(n, 10)) {
        1 => "st",
        2 => "nd",
        3 => "rd",
        else => "th",
    };
}

fn weekdayName(wday: c_int) []const u8 {
    return switch (wday) {
        0 => "Sunday",
        1 => "Monday",
        2 => "Tuesday",
        3 => "Wednesday",
        4 => "Thursday",
        5 => "Friday",
        6 => "Saturday",
        else => "",
    };
}

fn monthName(mon: c_int) []const u8 {
    return switch (mon) {
        0 => "January",
        1 => "February",
        2 => "March",
        3 => "April",
        4 => "May",
        5 => "June",
        6 => "July",
        7 => "August",
        8 => "September",
        9 => "October",
        10 => "November",
        11 => "December",
        else => "",
    };
}

/// fit_and_draw from the old tray, verbatim: shrink-to-fit then leave the
/// pen color set for the caller's cairo_show_text.
fn fitAndDraw(
    cr: *c.cairo_t,
    font: [*:0]const u8,
    base_size: f64,
    weight: c.cairo_font_weight_t,
    txt: []const u8,
    r: f64,
    g: f64,
    b: f64,
    a: f64,
    max_w: f64,
    margin: f64,
) void {
    c.cairo_select_font_face(cr, font, c.CAIRO_FONT_SLANT_NORMAL, weight);
    var size = base_size;
    c.cairo_set_font_size(cr, size);
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, @ptrCast(txt.ptr), &ext);
    while (ext.width > max_w - 2.0 * margin and size > 6.0) {
        size *= 0.92;
        c.cairo_set_font_size(cr, size);
        c.cairo_text_extents(cr, @ptrCast(txt.ptr), &ext);
    }
    c.cairo_set_source_rgba(cr, r, g, b, a);
}

// ── exit_dots skin (the skin source of truth, now lives here) ───────────

fn paintExitDotsSkin(cr: *c.cairo_t, w: f64, h: f64, s: f64, side: Side, slide_count: u32) void {
    const dots_f: f64 = @as(f64, @floatFromInt(exit_dots_w)) * s;
    const char_sp: f64 = measureCharSpace(cr, h);
    const num_w: f64 = measureSlideCount(cr, h, slide_count);

    // EXIT dots: 1 char-space in from the slide-border side.
    const dots_x: f64 = if (side == .left) w - char_sp - dots_f else char_sp;
    c.cairo_save(cr);
    c.cairo_translate(cr, dots_x, 0.0);
    paintExitDots(cr, dots_f, h, s);
    c.cairo_restore(cr);

    // Digit: 1 char-space in from the screen-edge side.
    if (num_w > 0) {
        const num_x: f64 = if (side == .left) char_sp else w - char_sp - num_w;
        drawSlideCount(cr, h, slide_count, num_x);
    }
}

fn measureSlideCount(cr: *c.cairo_t, h: f64, count: u32) f64 {
    if (count == 0) return 0;
    var buf: [8]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, "{d}", .{count}) catch return 0;
    c.cairo_save(cr);
    c.cairo_set_font_size(cr, h * num_font_scale);
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, text.ptr, &ext);
    c.cairo_restore(cr);
    return ext.width;
}

fn measureCharSpace(cr: *c.cairo_t, h: f64) f64 {
    c.cairo_save(cr);
    c.cairo_set_font_size(cr, h * num_font_scale);
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, "0", &ext);
    c.cairo_restore(cr);
    return ext.x_advance;
}

fn drawSlideCount(cr: *c.cairo_t, h: f64, count: u32, tx: f64) void {
    var buf: [8]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, "{d}", .{count}) catch return;
    c.cairo_save(cr);
    c.cairo_set_font_size(cr, h * num_font_scale);
    var ext: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, text.ptr, &ext);
    const ty: f64 = (h - ext.height) / 2.0 - ext.y_bearing;
    c.cairo_move_to(cr, tx - ext.x_bearing, ty);
    c.cairo_show_text(cr, text.ptr);
    c.cairo_restore(cr);
}

/// EXIT dot-matrix — 4x5 gold dots spelling E-X-I-T.
/// Theater exit signage. Same dot language as the kmedia helix balls.
fn paintExitDots(cr: *c.cairo_t, w: f64, h: f64, _: f64) void {
    const dot_r: f64 = @min(w, h) * 0.05;
    const dot_spacing: f64 = dot_r * 3.0;
    const letter_w: f64 = 5.0 * dot_spacing;
    const letter_h: f64 = 6.0 * dot_spacing;
    const letter_gap: f64 = dot_spacing * 0.8;

    const total_w: f64 = 4.0 * letter_w + 3.0 * letter_gap;
    const start_x: f64 = (w - total_w) / 2.0;
    const start_y: f64 = (h - letter_h) / 2.0;

    const e = [6][5]u8{
        .{ 1, 1, 1, 1, 1 },
        .{ 1, 0, 0, 0, 0 },
        .{ 1, 1, 1, 1, 0 },
        .{ 1, 0, 0, 0, 0 },
        .{ 1, 0, 0, 0, 0 },
        .{ 1, 1, 1, 1, 1 },
    };
    const x_l = [6][5]u8{
        .{ 1, 0, 0, 0, 1 },
        .{ 0, 1, 0, 1, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 1, 0, 1, 0 },
        .{ 1, 0, 0, 0, 1 },
    };
    const i_l = [6][5]u8{
        .{ 0, 1, 1, 1, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 1, 1, 1, 0 },
    };
    const t_l = [6][5]u8{
        .{ 1, 1, 1, 1, 1 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 0, 0, 1, 0, 0 },
        .{ 1, 0, 0, 0, 0 },
    };

    const letters = [_][6][5]u8{ e, x_l, i_l, t_l };

    for (letters, 0..) |letter, li| {
        const lx = start_x + @as(f64, @floatFromInt(li)) * (letter_w + letter_gap);
        for (letter, 0..) |row, ri| {
            for (row, 0..) |on, ci| {
                if (on == 1) {
                    const cx = lx + @as(f64, @floatFromInt(ci)) * dot_spacing + dot_r;
                    const cy = start_y + @as(f64, @floatFromInt(ri)) * dot_spacing + dot_r;
                    c.cairo_arc(cr, cx, cy, dot_r, 0.0, 2.0 * std.math.pi);
                    c.cairo_fill(cr);
                }
            }
        }
    }
}
