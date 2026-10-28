// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");

/// Runtime-toggleable gauge settings, read from
/// ~/.config/kidulwm/gauges.toml (per-user) with /etc/kidulwm/gauges.toml
/// as a system fallback. Everything defaults to hidden/off; the Settings
/// app will expose these as toggles later.
///
/// Schema (all keys optional):
///   [gauges]
///   show_temp = false        # master switch for the cpu/gpu (and later ram) gauge group
///   temp_threshold_f = 88.0  # when show_temp is on, still hide until this temp
///   show_ram = false         # reserved: ram gauge rejoins the group later
pub const GaugeConfig = struct {
    show_temp: bool = false,
    temp_threshold_f: f64 = 88.0,
    show_ram: bool = false,
};

pub fn load(allocator: std.mem.Allocator) GaugeConfig {
    var cfg = GaugeConfig{};

    const path_buf: []const u8 = blk: {
        if (std.c.getenv("HOME")) |home_c| {
            const home = std.mem.span(home_c);
            break :blk std.fs.path.join(allocator, &.{ home, ".config", "kidulwm", "gauges.toml" }) catch "";
        }
        break :blk "";
    };
    defer if (path_buf.len > 0) allocator.free(path_buf);

    const content = readFirst(allocator, path_buf, "/etc/kidulwm/gauges.toml") orelse return cfg;
    defer allocator.free(content);

    parseInto(&cfg, content);
    return cfg;
}

fn readFirst(allocator: std.mem.Allocator, user_path: []const u8, sys_path: []const u8) ?[]u8 {
    if (user_path.len > 0) {
        if (readFileAlloc(allocator, user_path)) |data| return data else |_| {}
    }
    if (readFileAlloc(allocator, sys_path)) |data| return data else |_| {}
    return null;
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const path_z = try allocator.dupeSentinel(u8, path, 0);
    defer allocator.free(path_z);
    const linux = std.os.linux;
    const file_fd = linux.open(path_z, .{ .ACCMODE = .RDONLY }, 0);
    if (@as(isize, @bitCast(file_fd)) < 0) return error.FileNotFound;
    const fd: i32 = @intCast(file_fd);
    defer _ = linux.close(fd);

    var content = std.ArrayList(u8).empty;
    errdefer content.deinit(allocator);
    var read_buf: [4096]u8 = undefined;
    while (true) {
        const n = linux.read(fd, &read_buf, read_buf.len);
        if (n < 0) return error.ReadFailed;
        if (n == 0) break;
        try content.appendSlice(allocator, read_buf[0..@as(usize, @intCast(n))]);
    }
    return content.toOwnedSlice(allocator);
}

fn parseInto(cfg: *GaugeConfig, content: []const u8) void {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#' or line[0] == '[') continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        var value = std.mem.trim(u8, line[eq + 1 ..], " \t");
        // Strip trailing comment.
        if (std.mem.indexOfScalar(u8, value, '#')) |h| value = std.mem.trim(u8, value[0..h], " \t");
        // Strip quotes.
        if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"')
            value = value[1 .. value.len - 1];

        if (std.mem.eql(u8, key, "show_temp")) {
            cfg.show_temp = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "on") or std.mem.eql(u8, value, "1");
        } else if (std.mem.eql(u8, key, "show_ram")) {
            cfg.show_ram = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "on") or std.mem.eql(u8, value, "1");
        } else if (std.mem.eql(u8, key, "temp_threshold_f")) {
            cfg.temp_threshold_f = std.fmt.parseFloat(f64, value) catch cfg.temp_threshold_f;
        }
    }
}
