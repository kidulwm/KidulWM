// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");

/// Boot-target setting — WHICH app the system seats as PRIMARY on cold boot.
/// Read from ~/.config/kidulwm/boot.toml (per-user) with
/// /etc/kidulwm/boot.toml as a system fallback. Everything defaults to `pc`.
///
/// This is the GENERAL setting that replaces the old static env bool
/// (KIDULWM_BOOT_MEDIA=1). boot-state.md (LOCKED 2026-10-19): the setting,
/// not the behaviour, is the law — static boot-to-TV was the gremlin.
///
/// Schema (all keys optional):
///   [boot]
///   target = "pc"            # pc | tv | remember-last | <app-id>
///
///   pc            = no boot-appliance spawn; keyless boot lands empty (host
///                   default). Preserves the old host behaviour (env unset).
///   tv            = spawn the media PLAYER appliance (the A5 boot ladder).
///   remember-last = the RESOLVER: read the last-primary record, restore it.
///   <app-id>      = autostart a named app (a hotel menu is just a target).
///
/// Only `tv` has a live consumer today — it maps to the in-process media
/// player boot ladder. `remember-last` and `<app-id>` are the far side of
/// docket #8, resolved by kushd at seating time after the MEGA ROACH
/// (docket #24) C1-C3. The setting itself is durable across that cut.
pub const Target = enum {
    pc,
    tv,
    remember_last,
    app_id,
};

pub const BootConfig = struct {
    target: Target = .pc,
    /// The app-id payload when target == .app_id. Fixed buffer — no
    /// allocation, no lifetime coupling to the parsed file text.
    app_id: [64]u8 = @splat(0),
    app_id_len: usize = 0,
};

pub fn load(allocator: std.mem.Allocator) BootConfig {
    var cfg = BootConfig{};

    const path_buf: []const u8 = blk: {
        if (std.c.getenv("HOME")) |home_c| {
            const home = std.mem.span(home_c);
            break :blk std.fs.path.join(allocator, &.{ home, ".config", "kidulwm", "boot.toml" }) catch "";
        }
        break :blk "";
    };
    defer if (path_buf.len > 0) allocator.free(path_buf);

    const content = readFirst(allocator, path_buf, "/etc/kidulwm/boot.toml") orelse return cfg;
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

fn parseInto(cfg: *BootConfig, content: []const u8) void {
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

        if (std.mem.eql(u8, key, "target")) {
            if (std.mem.eql(u8, value, "pc")) {
                cfg.target = .pc;
            } else if (std.mem.eql(u8, value, "tv")) {
                cfg.target = .tv;
            } else if (std.mem.eql(u8, value, "remember-last") or std.mem.eql(u8, value, "remember_last")) {
                cfg.target = .remember_last;
            } else {
                // Any other value is an app-id (a hotel menu is just a target).
                cfg.target = .app_id;
                const n = @min(value.len, cfg.app_id.len);
                @memcpy(cfg.app_id[0..n], value[0..n]);
                cfg.app_id_len = n;
            }
        }
    }
}

test "boot target parse: defaults and variants" {
    const allocator = std.testing.allocator;

    // Empty / comment-only input -> default pc.
    {
        var cfg = BootConfig{};
        parseInto(&cfg, "# nothing here\n[boot]\n");
        try std.testing.expectEqual(Target.pc, cfg.target);
    }

    // tv.
    {
        var cfg = BootConfig{};
        parseInto(&cfg, "[boot]\ntarget = \"tv\"\n");
        try std.testing.expectEqual(Target.tv, cfg.target);
    }

    // remember-last (hyphen form).
    {
        var cfg = BootConfig{};
        parseInto(&cfg, "target = remember-last  # trailing comment\n");
        try std.testing.expectEqual(Target.remember_last, cfg.target);
    }

    // remember_last (underscore form).
    {
        var cfg = BootConfig{};
        parseInto(&cfg, "target = remember_last\n");
        try std.testing.expectEqual(Target.remember_last, cfg.target);
    }

    // app-id target carries the payload.
    {
        var cfg = BootConfig{};
        parseInto(&cfg, "target = com.hotel.menu\n");
        try std.testing.expectEqual(Target.app_id, cfg.target);
        try std.testing.expectEqualStrings("com.hotel.menu", cfg.app_id[0..cfg.app_id_len]);
    }

    // A value longer than the fixed buffer is clamped, not truncated-to-garbage.
    {
        var cfg = BootConfig{};
        parseInto(&cfg, "target = this-is-an-app-id-far-longer-than-sixty-four-characters-so-it-must-clamp\n");
        try std.testing.expectEqual(Target.app_id, cfg.target);
        try std.testing.expectEqual(cfg.app_id.len, cfg.app_id_len);
    }

    _ = allocator;
}
