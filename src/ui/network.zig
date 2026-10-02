// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const c = @import("dm").c;
const c_std = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("dirent.h");
    @cInclude("time.h");
});
const style = @import("../core/style.zig");
const theme_mod = @import("../core/theme.zig");

pub const NetworkState = enum {
    none,
    disconnected,
    connected,
};

pub const NetworkCard = struct {
    open: bool = false,

    pub fn toggle(self: *NetworkCard) void {
        self.open = !self.open;
    }

    pub fn close(self: *NetworkCard) void {
        self.open = false;
    }
};

pub const Status = struct {
    network: NetworkState = .none,
    brightness: f64 = 1.0,
    vpn_active: bool = false,
    battery_present: bool = false,
    battery_charging: bool = false,
    battery_level: f64 = 1.0,
};

pub const NetworkWidget = struct {
    allocator: std.mem.Allocator,
    card: NetworkCard = .{},
    state: NetworkState = .none,
    last_scan_ms: u64 = 0,
    status: Status = .{},
    /// Beacon override: when set, the peek icon uses this severity color
    /// instead of the connected/disconnected color. Set by the peek after
    /// scanning /tmp/kidul-signals/*.state for worst severity.
    beacon_override: bool = false,
    beacon_severity: u8 = 0, // 0=ok, 1=warning, 2=alert, 3=muted

    const scan_interval_ms: u64 = 2000;
    const brightness_step_ratio: f64 = 0.05;

    pub fn init(allocator: std.mem.Allocator) NetworkWidget {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *NetworkWidget) void {
        _ = self;
    }

    pub fn toggleCard(self: *NetworkWidget) void {
        self.card.toggle();
    }

    pub fn closeCard(self: *NetworkWidget) void {
        self.card.close();
    }

    pub fn isCardOpen(self: *const NetworkWidget) bool {
        return self.card.open;
    }

    fn nowMs() u64 {
        var ts: std.os.linux.timespec = undefined;
        if (std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts) != 0) {
            return 0;
        }
        return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / 1_000_000;
    }

    pub fn update(self: *NetworkWidget) void {
        const now = nowMs();
        if (now -% self.last_scan_ms >= scan_interval_ms) {
            self.scanState();
            self.scanBrightness();
            self.scanVpn();
            self.scanBattery();
            self.status.network = self.state;
            self.last_scan_ms = now;
        }
    }

    pub fn needsRedraw(self: *const NetworkWidget) bool {
        // The icon shape is determined entirely by state, and the state is polled
        // internally.  The peek redraw loop already re-runs every frame the peek
        // is moving/visible, so a state change will be picked up on the next pass.
        // Returning true here once per scan would be useful but is not required for
        // a Granny-simple proof-of-life.
        _ = self;
        return false;
    }

    fn scanState(self: *NetworkWidget) void {
        var any_iface: bool = false;
        var any_up: bool = false;

        const dir = c_std.opendir("/sys/class/net");
        if (dir == null) {
            self.state = .none;
            return;
        }
        defer _ = c_std.closedir(dir);

        var entry: ?*c_std.dirent = null;
        while (true) {
            entry = c_std.readdir(dir);
            if (entry == null) break;
            const name = std.mem.sliceTo(&entry.?.d_name, 0);
            if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..") or std.mem.eql(u8, name, "lo")) {
                continue;
            }

            any_iface = true;

            var path_buf: [256:0]u8 = undefined;
            @memset(&path_buf, 0);
            const path = std.fmt.bufPrintZ(&path_buf, "/sys/class/net/{s}/operstate", .{name}) catch continue;
            const f = c_std.fopen(path, "r");
            if (f == null) continue;
            defer _ = c_std.fclose(f);

            var line_buf: [32:0]u8 = undefined;
            @memset(&line_buf, 0);
            if (c_std.fgets(&line_buf, @intCast(line_buf.len), f) != null) {
                const line = std.mem.sliceTo(&line_buf, 0);
                if (std.mem.startsWith(u8, line, "up")) {
                    any_up = true;
                }
            }
        }

        if (any_up) {
            self.state = .connected;
        } else if (any_iface) {
            self.state = .disconnected;
        } else {
            self.state = .none;
        }
    }

    pub const PeekBox = struct {
        x: i32,
        y: i32,
        width: i32,
        height: i32,
    };

    fn scanBrightness(self: *NetworkWidget) void {
        var controller_buf: [128:0]u8 = undefined;
        @memset(&controller_buf, 0);
        if (!findBacklightController(&controller_buf)) {
            self.status.brightness = 1.0;
            return;
        }
        const controller = std.mem.sliceTo(&controller_buf, 0);

        var max_path: [256:0]u8 = undefined;
        @memset(&max_path, 0);
        const max_path_z = std.fmt.bufPrintZ(&max_path, "/sys/class/backlight/{s}/max_brightness", .{controller}) catch return;
        const max = readIntFile(max_path_z);
        if (max <= 0) {
            self.status.brightness = 1.0;
            return;
        }

        var cur_path: [256:0]u8 = undefined;
        @memset(&cur_path, 0);
        const cur_path_z = std.fmt.bufPrintZ(&cur_path, "/sys/class/backlight/{s}/brightness", .{controller}) catch return;
        const current = readIntFile(cur_path_z);

        self.status.brightness = if (max > 0) std.math.clamp(@as(f64, @floatFromInt(current)) / @as(f64, @floatFromInt(max)), 0.0, 1.0) else 1.0;
    }

    fn scanVpn(self: *NetworkWidget) void {
        self.status.vpn_active = false;
        const dir = c_std.opendir("/sys/class/net");
        if (dir == null) return;
        defer _ = c_std.closedir(dir);

        var entry: ?*c_std.dirent = null;
        while (true) {
            entry = c_std.readdir(dir);
            if (entry == null) break;
            const name = std.mem.sliceTo(&entry.?.d_name, 0);
            if (name.len == 0 or name[0] == '.') continue;
            if (std.mem.startsWith(u8, name, "wg") or
                std.mem.startsWith(u8, name, "tun") or
                std.mem.startsWith(u8, name, "tap") or
                std.mem.startsWith(u8, name, "vpn"))
            {
                self.status.vpn_active = true;
                break;
            }
        }
    }

    // Battery source of truth: the signal-battery satellite writes
    // /tmp/kidul-signals/battery.detail ("pct charging minutes health profile").
    // Fall back to /sys only when the satellite isn't running.
    fn scanBattery(self: *NetworkWidget) void {
        self.status.battery_present = false;
        self.status.battery_charging = false;
        self.status.battery_level = 1.0;

        const f = c_std.fopen("/tmp/kidul-signals/battery.detail", "r");
        if (f != null) {
            defer _ = c_std.fclose(f);
            var line_buf: [128:0]u8 = undefined;
            @memset(&line_buf, 0);
            if (c_std.fgets(&line_buf, @intCast(line_buf.len), f) != null) {
                const line = std.mem.trim(u8, std.mem.sliceTo(&line_buf, 0), " \t\r\n");
                var it = std.mem.tokenizeAny(u8, line, " \t");
                const pct_s = it.next() orelse "";
                const chg_s = it.next() orelse "0";
                const pct = std.fmt.parseInt(i32, pct_s, 10) catch -1;
                if (pct >= 0) {
                    self.status.battery_present = true;
                    self.status.battery_charging = std.mem.eql(u8, chg_s, "1");
                    self.status.battery_level = @as(f64, @floatFromInt(std.math.clamp(pct, 0, 100))) / 100.0;
                    return;
                }
            }
        }

        // Fallback: direct /sys read (satellite not running)
        const names = [_][]const u8{ "BAT0", "BAT1" };
        for (names) |name| {
            var present_path: [256:0]u8 = undefined;
            @memset(&present_path, 0);
            const present_z = std.fmt.bufPrintZ(&present_path, "/sys/class/power_supply/{s}/present", .{name}) catch continue;
            if (readIntFile(present_z) != 1) continue;

            self.status.battery_present = true;

            var cap_path: [256:0]u8 = undefined;
            @memset(&cap_path, 0);
            const cap_z = std.fmt.bufPrintZ(&cap_path, "/sys/class/power_supply/{s}/capacity", .{name}) catch continue;
            const cap = readIntFile(cap_z);
            self.status.battery_level = @as(f64, @floatFromInt(std.math.clamp(cap, 0, 100))) / 100.0;

            var status_path: [256:0]u8 = undefined;
            @memset(&status_path, 0);
            const status_z = std.fmt.bufPrintZ(&status_path, "/sys/class/power_supply/{s}/status", .{name}) catch continue;
            var status_buf: [32:0]u8 = undefined;
            @memset(&status_buf, 0);
            const sf = c_std.fopen(status_z, "r");
            if (sf == null) continue;
            defer _ = c_std.fclose(sf);
            if (c_std.fgets(&status_buf, @intCast(status_buf.len), sf) != null) {
                const line = std.mem.sliceTo(&status_buf, 0);
                const lower = std.ascii.lowerString(&status_buf, line);
                self.status.battery_charging = std.mem.startsWith(u8, lower, "charging") or std.mem.startsWith(u8, lower, "full");
            }
        }
    }

    pub fn renderPeek(self: *const NetworkWidget, cr: *c.cairo_t, box: PeekBox, style_: style.Style, scale: f32) void {
        const w_d: f64 = @floatFromInt(box.width);
        const h_d: f64 = @floatFromInt(box.height);
        if (w_d < 8.0 or h_d < 8.0) return;

        const scale_f: f64 = @as(f64, scale);
        const gold = style_.color_border_focused.toF64();
        const warning = [4]f64{ 0.851, 0.447, 0.18, 0.85 };

        // Larger network icon; smaller satellites stay subtle.
        const net_size: f64 = 16.0 * scale_f;
        const sat_size: f64 = 11.0 * scale_f;

        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);
        c.cairo_set_line_cap(cr, c.CAIRO_LINE_CAP_ROUND);
        c.cairo_set_line_join(cr, c.CAIRO_LINE_JOIN_ROUND);

        const show_vpn = self.status.vpn_active;
        // Battery glyph only appears on battery power — hidden on AC/charging.
        const show_battery = self.status.battery_present and !self.status.battery_charging;

        // Vertically nudge the whole icon group down so it reads as part of the
        // peek immediately above the clock.
        const cy = h_d * 0.55;
        const net_cx = w_d * 0.5;

        // Draw the always-present network icon centered.
        const net_color = if (self.beacon_override) switch (self.beacon_severity) {
            0 => gold, // ok
            1 => warning, // warning (amber)
            2 => .{ 0.72, 0.18, 0.18, 0.85 }, // alert (red)
            3 => style_.color_text_muted.toF64(), // muted (grey)
            else => gold,
        } else if (self.status.network != .connected) warning else gold;
        drawNetworkIcon(cr, net_cx, cy, net_size * 0.5, self.status.network, net_color);

        // Known place to look: battery to the LEFT of the beacon, VPN further left.
        const bat_gap: f64 = 18.0 * scale_f;
        var left_cx = net_cx - net_size * 0.5 - bat_gap;
        if (show_battery) {
            const cx = left_cx - sat_size * 0.5;
            const color = if (self.status.battery_level < 0.2 and !self.status.battery_charging) warning else gold;
            // Optical nudge: glyph rides low vs the beacon — tune by eye.
            const bat_y_nudge: f64 = 4.5 * scale_f;
            drawBatteryIcon(cr, cx, cy - bat_y_nudge, sat_size * 0.5, self.status.battery_level, self.status.battery_charging, color);
            left_cx = cx - sat_size * 0.5 - bat_gap;
        }
        if (show_vpn) {
            const cx = left_cx - sat_size * 0.5;
            drawVpnIcon(cr, cx, cy, sat_size * 0.5, gold);
        }
    }

    fn drawNetworkIcon(cr: *c.cairo_t, cx: f64, cy: f64, r: f64, state: NetworkState, color: [4]f64) void {
        c.cairo_set_source_rgba(cr, color[0], color[1], color[2], color[3]);
        c.cairo_set_line_width(cr, 1.2);

        // Tiny dot at the base.
        c.cairo_new_path(cr);
        c.cairo_arc(cr, cx, cy + r * 0.45, r * 0.16, 0, 2.0 * std.math.pi);
        c.cairo_fill(cr);

        // Three radiating arcs, whispy and open.
        const arcs = [_]struct { y: f64, span: f64 }{
            .{ .y = r * 0.15, .span = r * 0.55 },
            .{ .y = -r * 0.15, .span = r * 0.95 },
            .{ .y = -r * 0.45, .span = r * 1.35 },
        };
        for (arcs) |a| {
            c.cairo_new_path(cr);
            c.cairo_arc(cr, cx, cy + a.y, a.span, std.math.pi * 0.75, std.math.pi * 2.25);
            c.cairo_stroke(cr);
        }

        if (state == .disconnected or state == .none) {
            // Small cross strike through the dot.
            const x0 = cx - r * 0.25;
            const x1 = cx + r * 0.25;
            const y0 = cy + r * 0.2;
            const y1 = cy + r * 0.7;
            c.cairo_new_path(cr);
            c.cairo_move_to(cr, x0, y0);
            c.cairo_line_to(cr, x1, y1);
            c.cairo_move_to(cr, x1, y0);
            c.cairo_line_to(cr, x0, y1);
            c.cairo_set_line_width(cr, 1.5);
            c.cairo_stroke(cr);
        }
    }

    fn drawBrightnessIcon(cr: *c.cairo_t, cx: f64, cy: f64, r: f64, color: [4]f64) void {
        c.cairo_set_source_rgba(cr, color[0], color[1], color[2], color[3]);
        c.cairo_set_line_width(cr, 1.2);
        // Small central circle.
        const center_r = r * 0.25;
        c.cairo_new_path(cr);
        c.cairo_arc(cr, cx, cy, center_r, 0, 2.0 * std.math.pi);
        c.cairo_stroke(cr);

        // Eight very fine rays, uneven lengths for a hand-drawn feel.
        const rays = [_]struct { a: f64, inner: f64, outer: f64 }{
            .{ .a = 0.0, .inner = center_r + r * 0.18, .outer = r },
            .{ .a = std.math.pi / 4.0, .inner = center_r + r * 0.12, .outer = r * 0.92 },
            .{ .a = std.math.pi / 2.0, .inner = center_r + r * 0.18, .outer = r },
            .{ .a = std.math.pi * 0.75, .inner = center_r + r * 0.12, .outer = r * 0.92 },
            .{ .a = std.math.pi, .inner = center_r + r * 0.18, .outer = r },
            .{ .a = std.math.pi * 1.25, .inner = center_r + r * 0.12, .outer = r * 0.92 },
            .{ .a = std.math.pi * 1.5, .inner = center_r + r * 0.18, .outer = r },
            .{ .a = std.math.pi * 1.75, .inner = center_r + r * 0.12, .outer = r * 0.92 },
        };
        for (rays) |ray| {
            const x1 = cx + std.math.cos(ray.a) * ray.inner;
            const y1 = cy + std.math.sin(ray.a) * ray.inner;
            const x2 = cx + std.math.cos(ray.a) * ray.outer;
            const y2 = cy + std.math.sin(ray.a) * ray.outer;
            c.cairo_new_path(cr);
            c.cairo_move_to(cr, x1, y1);
            c.cairo_line_to(cr, x2, y2);
            c.cairo_set_line_width(cr, 1.0);
            c.cairo_stroke(cr);
        }
    }

    fn drawVpnIcon(cr: *c.cairo_t, cx: f64, cy: f64, r: f64, color: [4]f64) void {
        c.cairo_set_source_rgba(cr, color[0], color[1], color[2], color[3]);
        c.cairo_set_line_width(cr, 1.2);
        // Shield outline: top arc + tapering sides.
        c.cairo_new_path(cr);
        const top = cy - r * 0.65;
        const bottom = cy + r * 0.55;
        const left = cx - r * 0.6;
        const right = cx + r * 0.6;
        c.cairo_move_to(cr, cx, top);
        c.cairo_line_to(cr, right, top + r * 0.35);
        c.cairo_line_to(cr, right - r * 0.12, bottom);
        c.cairo_line_to(cr, cx, bottom + r * 0.22);
        c.cairo_line_to(cr, left + r * 0.12, bottom);
        c.cairo_line_to(cr, left, top + r * 0.35);
        c.cairo_close_path(cr);
        c.cairo_stroke(cr);

        // Tiny keyhole dot in the center.
        c.cairo_new_path(cr);
        c.cairo_arc(cr, cx, cy + r * 0.05, r * 0.14, 0, 2.0 * std.math.pi);
        c.cairo_fill(cr);
    }

    // Kidul battery: landscape "car battery" — whispy rounded body with two
    // terminal posts on top, 6 waved cell-bars inside (a real 12V car
    // battery = 6 cells). Bars rise from the bottom with charge — a fill
    // level, not a gauge. Bolt wisp when charging.
    fn drawBatteryIcon(cr: *c.cairo_t, cx: f64, cy: f64, r: f64, level: f64, charging: bool, color: [4]f64) void {
        c.cairo_set_line_cap(cr, c.CAIRO_LINE_CAP_ROUND);

        const w = r * 3.9;
        const h = r * 2.4;
        const nub_h = r * 0.45;
        // Total glyph = posts + body. Center the WHOLE glyph on cy so it
        // rides the same centerline as the beacon, not below it.
        const total_h = nub_h + h;
        const y = cy - total_h * 0.5 + nub_h;
        const x = cx - w * 0.5;

        // Whispy body outline.
        c.cairo_set_source_rgba(cr, color[0], color[1], color[2], color[3]);
        c.cairo_set_line_width(cr, 1.2);
        c.cairo_new_path(cr);
        roundedRect(cr, x, y, w, h, h * 0.22);
        c.cairo_stroke(cr);

        // Two terminal posts on the top edge.
        const post_w = r * 0.63;
        const post_h = nub_h * 1.3;
        for ([2]f64{ 0.18, 0.82 }) |fx| {
            const px = x + w * fx - post_w * 0.5;
            c.cairo_new_path(cr);
            roundedRect(cr, px, y - post_h + 0.5, post_w, post_h, post_h * 0.4);
            c.cairo_fill(cr);
        }

        if (charging) {
            // Bolt wisp inside — centered on the body, not the glyph.
            const body_cy = y + h * 0.5;
            c.cairo_new_path(cr);
            c.cairo_move_to(cr, cx + r * 0.30, body_cy - r * 0.68);
            c.cairo_line_to(cr, cx - r * 0.18, body_cy + r * 0.03);
            c.cairo_line_to(cr, cx + r * 0.21, body_cy + r * 0.03);
            c.cairo_line_to(cr, cx - r * 0.30, body_cy + r * 0.68);
            c.cairo_set_line_width(cr, 1.4);
            c.cairo_stroke(cr);
            return;
        }

        // 6 waved cell-bars. Ghost bars full height; lit portion rises from
        // the bottom with charge — the fill level is the top of the lit part.
        const cell_count = 6;
        const pad_x = r * 0.5;
        const inner_w = w - pad_x * 2.0;
        const top_y = y + r * 0.45;
        const bot_y = y + h - r * 0.45;
        const full_h = bot_y - top_y;
        const fill_h = full_h * std.math.clamp(level, 0.0, 1.0);
        var i: i32 = 0;
        while (i < cell_count) : (i += 1) {
            const frac = (@as(f64, @floatFromInt(i)) + 0.5) / @as(f64, cell_count);
            const rx = x + pad_x + frac * inner_w;
            const mid_y = (top_y + bot_y) * 0.5;
            const sway = r * 0.18;

            // Ghost: full-height, barely there.
            c.cairo_set_source_rgba(cr, color[0], color[1], color[2], 0.15);
            c.cairo_set_line_width(cr, 0.9);
            c.cairo_new_path(cr);
            c.cairo_move_to(cr, rx, top_y);
            c.cairo_curve_to(cr, rx - sway, top_y + full_h * 0.3, rx + sway, mid_y - full_h * 0.1, rx, mid_y);
            c.cairo_curve_to(cr, rx - sway, mid_y + full_h * 0.1, rx + sway, bot_y - full_h * 0.3, rx, bot_y);
            c.cairo_stroke(cr);

            // Lit: from the bottom up to the fill line.
            if (fill_h > 1.0) {
                const fill_top = bot_y - fill_h;
                const fmid_y = (fill_top + bot_y) * 0.5;
                c.cairo_set_source_rgba(cr, color[0], color[1], color[2], 0.9);
                c.cairo_set_line_width(cr, 1.4);
                c.cairo_new_path(cr);
                c.cairo_move_to(cr, rx, fill_top);
                c.cairo_curve_to(cr, rx - sway, fill_top + fill_h * 0.3, rx + sway, fmid_y - fill_h * 0.1, rx, fmid_y);
                c.cairo_curve_to(cr, rx - sway, fmid_y + fill_h * 0.1, rx + sway, bot_y - fill_h * 0.3, rx, bot_y);
                c.cairo_stroke(cr);
            }
        }
    }

    fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
        const rr = @min(r, w / 2.0, h / 2.0);
        c.cairo_new_sub_path(cr);
        c.cairo_move_to(cr, x + rr, y);
        c.cairo_line_to(cr, x + w - rr, y);
        c.cairo_arc(cr, x + w - rr, y + rr, rr, -std.math.pi / 2.0, 0);
        c.cairo_line_to(cr, x + w, y + h - rr);
        c.cairo_arc(cr, x + w - rr, y + h - rr, rr, 0, std.math.pi / 2.0);
        c.cairo_line_to(cr, x + rr, y + h);
        c.cairo_arc(cr, x + rr, y + h - rr, rr, std.math.pi / 2.0, std.math.pi);
        c.cairo_line_to(cr, x, y + rr);
        c.cairo_arc(cr, x + rr, y + rr, rr, std.math.pi, std.math.pi * 1.5);
        c.cairo_close_path(cr);
    }

    fn drawBeams8(cr: *c.cairo_t, cx: f64, cy: f64, inner: f64, outer: f64, color: [4]f64, width: f64) void {
        c.cairo_set_source_rgba(cr, color[0], color[1], color[2], color[3]);
        c.cairo_set_line_width(cr, width);
        const delta = outer - inner;
        const dirs = [_][2]f64{
            .{ -1.0, -1.0 }, .{ 1.0, -1.0 }, .{ -1.0, 1.0 }, .{ 1.0, 1.0 },
            .{ 0.0, -1.0 }, .{ 0.0, 1.0 }, .{ -1.0, 0.0 }, .{ 1.0, 0.0 },
        };
        for (dirs) |d| {
            const len = if (d[0] == 0.0 or d[1] == 0.0) delta * 0.8 else delta;
            const nx = d[0];
            const ny = d[1];
            const hl = @sqrt(nx * nx + ny * ny);
            const dx = nx / hl;
            const dy = ny / hl;
            const x1 = cx + dx * inner;
            const y1 = cy + dy * inner;
            const x2 = cx + dx * (inner + len);
            const y2 = cy + dy * (inner + len);
            c.cairo_move_to(cr, x1, y1);
            c.cairo_line_to(cr, x2, y2);
            c.cairo_stroke(cr);
        }
    }

    pub fn renderCard(self: *const NetworkWidget, cr: *c.cairo_t, w_d: f64, h_d: f64, style_: style.Style, scale: f32) void {
        _ = scale;
        // Full slide: fill background, no card frame.
        const bg4 = style_.color_card_mat.toF64();
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], 0.91);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        const gold = style_.color_border_focused.toF64();
        const muted = style_.color_text_muted.toF64();

        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
        const title_size: f64 = @as(f64, style_.font_size_l) * 1.2;
        c.cairo_set_font_size(cr, title_size);

        var title_ext: c.cairo_text_extents_t = undefined;
        const title = "Network";
        c.cairo_text_extents(cr, title, &title_ext);
        const title_x = (w_d - title_ext.width) * 0.5;
        const title_y = h_d * 0.25 + title_ext.height * 0.5;
        c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], gold[3]);
        c.cairo_move_to(cr, title_x, title_y);
        c.cairo_show_text(cr, title);

        const status_str = switch (self.state) {
            .none => "No connection configured",
            .disconnected => "Configured but not connected",
            .connected => "Connected",
        };
        const body_size: f64 = @as(f64, style_.font_size_m);
        c.cairo_select_font_face(cr, @ptrCast("Fantasque Sans Mono"), c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
        c.cairo_set_font_size(cr, body_size);

        var status_ext: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, status_str, &status_ext);
        const status_x = (w_d - status_ext.width) * 0.5;
        const status_y = title_y + title_size * 1.6;
        c.cairo_set_source_rgba(cr, muted[0], muted[1], muted[2], muted[3]);
        c.cairo_move_to(cr, status_x, status_y);
        c.cairo_show_text(cr, status_str);
    }

    pub fn adjustBrightness(self: *NetworkWidget, delta: f64) void {
        _ = self;
        const dir: i32 = if (delta > 0.0) 1 else -1;

        var controller_buf: [128:0]u8 = undefined;
        @memset(&controller_buf, 0);
        if (!findBacklightController(&controller_buf)) {
            std.log.info("KidulWM: no backlight controller found; brightness scroll stubbed", .{});
            return;
        }
        const controller = std.mem.sliceTo(&controller_buf, 0);

        var max_path: [256:0]u8 = undefined;
        @memset(&max_path, 0);
        const max_path_z = std.fmt.bufPrintZ(&max_path, "/sys/class/backlight/{s}/max_brightness", .{controller}) catch return;
        const max = readIntFile(max_path_z);
        if (max <= 0) {
            std.log.info("KidulWM: backlight {s} max_brightness unreadable", .{controller});
            return;
        }

        var cur_path: [256:0]u8 = undefined;
        @memset(&cur_path, 0);
        const cur_path_z = std.fmt.bufPrintZ(&cur_path, "/sys/class/backlight/{s}/brightness", .{controller}) catch return;
        const current = readIntFile(cur_path_z);

        const step: i64 = @max(1, @divFloor(max, 20));
        const new_val: i64 = std.math.clamp(current + @as(i64, dir) * step, 1, max);

        const f = c_std.fopen(cur_path_z, "w");
        if (f == null) {
            std.log.info("KidulWM: cannot open backlight brightness for writing", .{});
            return;
        }
        defer _ = c_std.fclose(f);
        var write_buf: [32:0]u8 = undefined;
        @memset(&write_buf, 0);
        const write_str = std.fmt.bufPrintZ(&write_buf, "{d}", .{new_val}) catch return;
        _ = c_std.fputs(write_str, f);
        std.log.info("KidulWM: brightness adjusted to {d}/{d}", .{ new_val, max });
    }

    fn findBacklightController(out: *[128:0]u8) bool {
        const dir = c_std.opendir("/sys/class/backlight");
        if (dir == null) return false;
        defer _ = c_std.closedir(dir);

        var entry: ?*c_std.dirent = null;
        while (true) {
            entry = c_std.readdir(dir);
            if (entry == null) break;
            const name = std.mem.sliceTo(&entry.?.d_name, 0);
            if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            @memset(out, 0);
            @memcpy(out[0..name.len], name);
            return true;
        }
        return false;
    }

    fn readIntFile(path: [*:0]const u8) i64 {
        const f = c_std.fopen(path, "r");
        if (f == null) return -1;
        defer _ = c_std.fclose(f);
        var buf: [64:0]u8 = undefined;
        @memset(&buf, 0);
        if (c_std.fgets(&buf, @intCast(buf.len), f) == null) return -1;
        const line = std.mem.sliceTo(&buf, 0);
        return std.fmt.parseInt(i64, std.mem.trim(u8, line, " \t\r\n"), 10) catch -1;
    }
};
