// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");

/// Physical output arrangement, read from ~/.config/kidulwm/outputs.toml
/// (per-user) with /etc/kidulwm/outputs.toml as a system fallback.
///
/// The arandr lesson: "mirrored" is just two outputs at the same origin, and
/// addAuto extending right from whatever happened to be there first can land
/// an output exactly where you don't want it. Placement is physical reality,
/// declared once here; everything downstream (cursor, deck, getBox) obeys.
///
/// Coordinates are LOGICAL units (post-scale), because that's the space the
/// layout, cursor, and clients all live in. Under the CFC scale law the Kogan
/// 4K is scale 2 -> 1920x1080 logical; the Predator panel is scale 1.
///
/// Schema (all entries optional; unknown outputs fall back to addAuto):
///   [arrange]
///   HDMI-A-1 = { x = 0, y = 0, scale = 1.7 }  # Kogan, top, fractional override
///   eDP-1    = { x = 0, y = 1080 }            # Predator, bottom, auto law (1x)
///
/// `scale` is optional. When present it OVERRIDES the CFC integer scale law
/// for that output (user-manipulable display setting; auto law stays the
/// default when absent). Fractional values are supported: buffer surfaces
/// allocate at ceil(scale) and cairo rescales by scale/ceil, so widgets stay
/// crisp. This is the first per-output user display setting — shape future
/// settings (text size etc.) the same way: declared here, auto by default.
pub const Placement = struct {
    name: []const u8,
    x: i32,
    y: i32,
    scale: ?f32 = null,
    /// "no1" screen: the home/primary output. smartLock parks the cursor
    /// here on wake so it never resurfaces on a slow-to-power monitor.
    primary: bool = false,
};

/// Validation result for a would-be outputs.toml load.
/// `problems` is a human-readable list; empty means clean.
pub const Validation = struct {
    problems: std.ArrayList([]const u8),

    pub fn ok(self: *const Validation) bool {
        return self.problems.items.len == 0;
    }
};

/// Parse + sanity-check the user outputs.toml WITHOUT touching live state.
/// Catches the classic footguns before a wm_reset applies them:
///   - two outputs declared at the same origin (the mirror incident)
///   - negative/absurd coordinates
///   - duplicate output names
/// Returns a Validation whose problems list is empty when clean.
pub fn validate(allocator: std.mem.Allocator) Validation {
    var v = Validation{ .problems = std.ArrayList([]const u8).empty };
    const layout = load(allocator);

    // Duplicate names / origin collisions.
    var i: usize = 0;
    while (i < layout.count) : (i += 1) {
        const a = layout.placements[i];
        if (a.x < -10000 or a.x > 100000 or a.y < -10000 or a.y > 100000) {
            const msg = std.fmt.allocPrint(allocator, "outputs.toml: {s} has absurd coords {d},{d}", .{ a.name, a.x, a.y }) catch continue;
            v.problems.append(allocator, msg) catch {};
        }
        var j: usize = i + 1;
        while (j < layout.count) : (j += 1) {
            const b = layout.placements[j];
            if (std.mem.eql(u8, a.name, b.name)) {
                const msg = std.fmt.allocPrint(allocator, "outputs.toml: {s} declared twice", .{a.name}) catch continue;
                v.problems.append(allocator, msg) catch {};
            }
            if (a.x == b.x and a.y == b.y) {
                const msg = std.fmt.allocPrint(allocator, "outputs.toml: {s} and {s} share origin {d},{d} (this is how screens mirror)", .{ a.name, b.name, a.x, a.y }) catch continue;
                v.problems.append(allocator, msg) catch {};
            }
        }
    }
    return v;
}

pub const OutputLayout = struct {
    placements: [8]Placement = undefined,
    count: usize = 0,

    pub fn find(self: *const OutputLayout, name: []const u8) ?Placement {
        for (self.placements[0..self.count]) |p| {
            if (std.mem.eql(u8, p.name, name)) return p;
        }
        return null;
    }
};

pub fn load(allocator: std.mem.Allocator) OutputLayout {
    var layout = OutputLayout{};

    const path_buf: []const u8 = blk: {
        if (std.c.getenv("HOME")) |home_c| {
            const home = std.mem.span(home_c);
            break :blk std.fs.path.join(allocator, &.{ home, ".config", "kidulwm", "outputs.toml" }) catch "";
        }
        break :blk "";
    };
    defer if (path_buf.len > 0) allocator.free(path_buf);

    const content = readFirst(allocator, path_buf, "/etc/kidulwm/outputs.toml") orelse return layout;
    defer allocator.free(content);

    parseInto(allocator, &layout, content);
    return layout;
}

fn readFirst(allocator: std.mem.Allocator, user_path: []const u8, sys_path: []const u8) ?[]u8 {
    if (user_path.len > 0) {
        if (readFileAlloc(allocator, user_path)) |data| return data else |_| {}
    }
    if (readFileAlloc(allocator, sys_path)) |data| return data else |_| {}
    return null;
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const path_z = try allocator.dupeZ(u8, path);
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

fn parseInto(allocator: std.mem.Allocator, layout: *OutputLayout, content: []const u8) void {
    var in_arrange = false;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (line[0] == '[') {
            in_arrange = std.mem.eql(u8, line, "[arrange]");
            continue;
        }
        if (!in_arrange) continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const name = std.mem.trim(u8, line[0..eq], " \t\"");
        var value = std.mem.trim(u8, line[eq + 1 ..], " \t");
        if (std.mem.indexOfScalar(u8, value, '#')) |h| value = std.mem.trim(u8, value[0..h], " \t");
        // Expect: { x = N, y = N }
        if (value.len < 2 or value[0] != '{') continue;
        var x: ?i32 = null;
        var y: ?i32 = null;
        var scale: ?f32 = null;
        var primary = false;
        var fields = std.mem.tokenizeAny(u8, value[1 .. value.len - 1], ",");
        while (fields.next()) |field| {
            const f_eq = std.mem.indexOfScalar(u8, field, '=') orelse continue;
            const f_key = std.mem.trim(u8, field[0..f_eq], " \t");
            const f_val = std.mem.trim(u8, field[f_eq + 1 ..], " \t");
            if (std.mem.eql(u8, f_key, "scale")) {
                // Fractional override (e.g. 1.7) — NOT an int; parse float.
                scale = std.fmt.parseFloat(f32, f_val) catch continue;
                continue;
            }
            if (std.mem.eql(u8, f_key, "primary")) {
                primary = std.mem.eql(u8, f_val, "true") or std.mem.eql(u8, f_val, "1") or
                    std.mem.eql(u8, f_val, "yes") or std.mem.eql(u8, f_val, "on");
                continue;
            }
            const num = std.fmt.parseInt(i32, f_val, 10) catch continue;
            if (std.mem.eql(u8, f_key, "x")) x = num;
            if (std.mem.eql(u8, f_key, "y")) y = num;
        }
        if (x == null or y == null or layout.count >= layout.placements.len) continue;
        layout.placements[layout.count] = .{
            .name = allocator.dupe(u8, name) catch continue,
            .x = x.?,
            .y = y.?,
            .scale = scale,
            .primary = primary,
        };
        layout.count += 1;
        std.log.info("KidulWM: output arrangement {s} -> {d},{d}", .{ name, x.?, y.? });
    }
}
