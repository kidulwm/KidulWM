// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const toml = @import("toml");
const message = @import("notify_message.zig");

const c = @cImport({
    @cInclude("systemd/sd-bus.h");
});

pub const Config = struct {
    global: GlobalConfig = .{},
    rules: []Rule = &[_]Rule{},

    pub const GlobalConfig = struct {
        allow_unknown: bool = false,
        default_ttl_ms: i32 = 8000,
    };
};

pub const Rule = struct {
    app: []const u8 = "",
    summary_pattern: []const u8 = "",
    body_pattern: []const u8 = "",
    format: []const u8 = "",
    enabled: bool = true,

    regex: ?std.regex.Regex = null,
    summary_re: ?std.regex.Regex = null,
    body_re: ?std.regex.Regex = null,

    pub fn deinit(self: *Rule, allocator: std.mem.Allocator) void {
        if (self.regex) |*re| re.deinit();
        if (self.summary_re) |*re| re.deinit();
        if (self.body_re) |*re| re.deinit();
        allocator.free(self.app);
        allocator.free(self.summary_pattern);
        allocator.free(self.body_pattern);
        allocator.free(self.format);
    }
};

var g_running = std.atomic.Value(bool).init(true);

fn connectUnixSocket(path: []const u8) !i32 {
    const fd_i: i32 = @intCast(linux.socket(linux.AF.UNIX, linux.SOCK.STREAM, 0));
    if (fd_i < 0) return error.SocketFailed;
    errdefer _ = linux.close(fd_i);

    var addr: std.posix.sockaddr.un = std.mem.zeroes(std.posix.sockaddr.un);
    addr.family = linux.AF.UNIX;
    const path_len = @min(path.len, addr.path.len - 1);
    @memcpy(addr.path[0..path_len], path[0..path_len]);
    addr.path[path_len] = 0;
    const addr_len: u32 = @intCast(@offsetOf(std.posix.sockaddr.un, "path") + path_len + 1);
    const rc = linux.connect(fd_i, @ptrCast(&addr), addr_len);
    if (rc != 0) return error.ConnectFailed;
    return fd_i;
}

fn sendNotification(allocator: std.mem.Allocator, socket_path: []const u8, title: []const u8, body: []const u8, source_id: []const u8) void {
    const fd = connectUnixSocket(socket_path) catch |err| {
        std.log.err("failed to connect to kidulwm socket: {}", .{err});
        return;
    };
    defer _ = linux.close(fd);

    const req = message.Request{ .notification_test = .{
        .title = title,
        .body = body,
        .source_id = source_id,
    } };
    const payload = message.encodeRequest(allocator, req) catch |err| {
        std.log.err("failed to encode notification request: {}", .{err});
        return;
    };
    defer allocator.free(payload);

    _ = linux.write(fd, payload.ptr, payload.len);
    _ = linux.write(fd, "\n", 1);
}

fn sanitize(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var buf = try std.ArrayList(u8).initCapacity(allocator, raw.len);
    errdefer buf.deinit();

    var i: usize = 0;
    var last_was_space = false;
    while (i < raw.len) {
        const ch = raw[i];
        if (ch == '<') {
            // Skip HTML/Markup tag.
            while (i < raw.len and raw[i] != '>') i += 1;
            if (i < raw.len) i += 1;
            continue;
        }
        if (ch == '&') {
            if (std.mem.startsWith(u8, raw[i..], "&quot;")) {
                try buf.append('"');
                i += 6;
                last_was_space = false;
                continue;
            } else if (std.mem.startsWith(u8, raw[i..], "&amp;")) {
                try buf.append('&');
                i += 5;
                last_was_space = false;
                continue;
            } else if (std.mem.startsWith(u8, raw[i..], "&lt;")) {
                try buf.append('<');
                i += 4;
                last_was_space = false;
                continue;
            } else if (std.mem.startsWith(u8, raw[i..], "&gt;")) {
                try buf.append('>');
                i += 4;
                last_was_space = false;
                continue;
            }
        }
        if (ch == '\n' or ch == '\r' or ch == '\t' or ch == ' ') {
            if (!last_was_space) {
                try buf.append(' ');
                last_was_space = true;
            }
            i += 1;
            continue;
        }
        try buf.append(ch);
        last_was_space = false;
        i += 1;
    }

    const trimmed = std.mem.trim(u8, buf.items, " \t\r\n");
    const duped = try allocator.dupe(u8, trimmed);
    return duped;
}

fn applyRule(allocator: std.mem.Allocator, rule: *const Rule, app_name: []const u8, summary: []const u8, body: []const u8) !?[]u8 {
    if (!rule.enabled) return null;
    if (rule.app.len > 0 and !std.mem.eql(u8, rule.app, app_name)) return null;

    const clean_summary = try sanitize(allocator, summary);
    defer allocator.free(clean_summary);
    const clean_body = try sanitize(allocator, body);
    defer allocator.free(clean_body);

    var captures: std.StringHashMap([]const u8) = std.StringHashMap([]const u8).init(allocator);
    defer {
        var it = captures.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        captures.deinit();
    }

    _ = rule;
    _ = clean_summary;
    _ = clean_body;
    _ = captures;
    return null;
}

fn loadConfig(allocator: std.mem.Allocator, path: []const u8) !Config {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024);
    defer allocator.free(data);

    var parser = toml.parse(allocator, data) catch |err| {
        std.log.err("failed to parse config: {}", .{err});
        return error.ConfigParseFailed;
    };
    defer parser.deinit();

    var cfg: Config = .{};

    if (parser.root.getTable("global")) |global| {
        if (global.getBool("allow_unknown")) |v| cfg.global.allow_unknown = v;
        if (global.getInteger("default_ttl_ms")) |v| cfg.global.default_ttl_ms = @intCast(v);
    }

    if (parser.root.getArray("rule")) |arr| {
        const n = arr.items.len;
        cfg.rules = try allocator.alloc(Rule, n);
        for (arr.items, 0..) |item, i| {
            const t = item.table;
            cfg.rules[i] = .{
                .app = try allocator.dupe(u8, if (t.getString("app")) |s| s else ""),
                .summary_pattern = try allocator.dupe(u8, if (t.getString("summary_pattern")) |s| s else ""),
                .body_pattern = try allocator.dupe(u8, if (t.getString("body_pattern")) |s| s else ""),
                .format = try allocator.dupe(u8, if (t.getString("format")) |s| s else ""),
                .enabled = if (t.getBool("enabled")) |v| v else true,
            };
        }
    }

    return cfg;
}

fn freeConfig(cfg: *Config, allocator: std.mem.Allocator) void {
    for (cfg.rules) |*rule| rule.deinit(allocator);
    allocator.free(cfg.rules);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var socket_path_buf: [256]u8 = undefined;
    const runtime = posix.getenv("XDG_RUNTIME_DIR") orelse "/run/user/1000";
    const socket_path = try std.fmt.bufPrint(&socket_path_buf, "{s}/kidulwm-control.sock", .{runtime});

    const config_home = posix.getenv("XDG_CONFIG_HOME") orelse "/home/kidul/.config";
    var config_path_buf: [512]u8 = undefined;
    const config_path = try std.fmt.bufPrint(&config_path_buf, "{s}/kidulwm/notifications.conf", .{config_home});

    var cfg = loadConfig(allocator, config_path) catch |err| blk: {
        std.log.warn("using default config ({s}: {})", .{ config_path, err });
        break :blk Config{};
    };
    defer freeConfig(&cfg, allocator);

    _ = cfg;
    _ = socket_path;
}
