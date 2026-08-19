const std = @import("std");
const xkb = @import("xkbcommon");

pub const Action = union(enum) {
    spawn: []const u8,
    focus_next,
    focus_prev,
    tray_toggle,
    tray_select_next,
    tray_select_prev,
    tray_activate,
    media_card_toggle,
    signals_card_toggle,
    next_animation,
    close_focused,
    reload,
    park_toggle,
    none,
};

const Keybind = struct {
    mod4: bool,
    ctrl: bool = false,
    sym: xkb.Keysym,
    action: Action,
};

fn defaultKeybinds(allocator: std.mem.Allocator) std.ArrayList(Keybind) {
    var list = std.ArrayList(Keybind).empty;
    const ghostty = allocator.dupe(u8, "/usr/bin/ghostty") catch &[_]u8{};
    list.append(allocator, .{ .mod4 = true, .sym = xkb.Keysym.Return, .action = .{ .spawn = ghostty } }) catch {
        if (ghostty.len > 0) allocator.free(ghostty);
    };
    list.append(allocator, .{ .mod4 = true, .sym = xkb.Keysym.j, .action = .focus_next }) catch {};
    list.append(allocator, .{ .mod4 = true, .sym = xkb.Keysym.k, .action = .focus_prev }) catch {};
    list.append(allocator, .{ .mod4 = true, .sym = xkb.Keysym.t, .action = .tray_toggle }) catch {};
    list.append(allocator, .{ .mod4 = true, .sym = xkb.Keysym.a, .action = .next_animation }) catch {};
    list.append(allocator, .{ .mod4 = true, .sym = xkb.Keysym.Up, .action = .tray_select_prev }) catch {};
    list.append(allocator, .{ .mod4 = true, .sym = xkb.Keysym.Down, .action = .tray_select_next }) catch {};
    list.append(allocator, .{ .mod4 = true, .sym = xkb.Keysym.m, .action = .media_card_toggle }) catch {};
    list.append(allocator, .{ .mod4 = false, .ctrl = true, .sym = xkb.Keysym.m, .action = .signals_card_toggle }) catch {};
    const browser = allocator.dupe(u8, "/usr/local/bin/launch-kidul-browser.sh") catch &[_]u8{};
    list.append(allocator, .{ .mod4 = true, .sym = xkb.Keysym.c, .action = .{ .spawn = browser } }) catch {
        if (browser.len > 0) allocator.free(browser);
    };
    list.append(allocator, .{ .mod4 = true, .sym = xkb.Keysym.q, .action = .close_focused }) catch {};
    list.append(allocator, .{ .mod4 = false, .ctrl = true, .sym = xkb.Keysym.q, .action = .close_focused }) catch {};
    list.append(allocator, .{ .mod4 = true, .sym = xkb.Keysym.r, .action = .reload }) catch {};
    list.append(allocator, .{ .mod4 = false, .ctrl = true, .sym = xkb.Keysym.b, .action = .park_toggle }) catch {};
    return list;
}

pub const Keybinds = struct {
    allocator: std.mem.Allocator,
    binds: std.ArrayList(Keybind),
    fallback: bool,

    const Self = @This();

    pub fn defaults(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .binds = defaultKeybinds(allocator),
            .fallback = true,
        };
    }

    pub fn load(allocator: std.mem.Allocator) Self {
        const home_c = std.c.getenv("HOME");
        if (home_c == null) {
            std.log.warn("KidulWM: no HOME env var; using built-in keybinds", .{});
            return defaults(allocator);
        }
        const home = std.mem.span(home_c.?);
        const user_path = std.fs.path.join(allocator, &[_][]const u8{ home, ".config", "kidulwm", "keybinds.conf" }) catch |err| {
            std.log.warn("KidulWM: failed to build config path ({}); using built-in keybinds", .{err});
            return defaults(allocator);
        };
        defer allocator.free(user_path);
        return loadFromPath(allocator, user_path);
    }

    fn loadFromPath(allocator: std.mem.Allocator, path: []const u8) Self {
        const path_z = allocator.dupeZ(u8, path) catch |err| {
            std.log.warn("KidulWM: failed to allocate path ({}); using built-in keybinds", .{err});
            return defaults(allocator);
        };
        defer allocator.free(path_z);

        const linux = std.os.linux;
        const file_fd = linux.open(path_z, .{ .ACCMODE = .RDONLY }, 0);
        if (@as(isize, @bitCast(file_fd)) < 0) {
            const err = errnoAbs(file_fd);
            if (err == error.FileNotFound) {
                std.log.info("KidulWM: user keybinds file '{s}' not found; using built-in defaults", .{path});
            } else {
                std.log.warn("KidulWM: cannot open keybinds file '{s}' (open error); using built-in defaults", .{path});
            }
            return defaults(allocator);
        }
        const fd: i32 = @intCast(file_fd);
        defer _ = linux.close(fd);

        var content = std.ArrayList(u8).empty;
        defer content.deinit(allocator);

        var read_buf: [4096]u8 = undefined;
        while (true) {
            const n = linux.read(fd, &read_buf, read_buf.len);
            if (n < 0) {
                std.log.warn("KidulWM: error reading keybinds file '{s}'; using built-in defaults", .{path});
                return defaults(allocator);
            }
            if (n == 0) break;
            content.appendSlice(allocator, read_buf[0..@as(usize, @intCast(n))]) catch {
                std.log.warn("KidulWM: failed to append keybinds buffer; using built-in defaults", .{});
                return defaults(allocator);
            };
        }

        var list = std.ArrayList(Keybind).empty;
        errdefer {
            for (list.items) |bind| {
                switch (bind.action) {
                    .spawn => |cmd| allocator.free(cmd),
                    else => {},
                }
            }
            list.deinit(allocator);
        }

        var it = std.mem.tokenizeScalar(u8, content.items, '\n');
        var line_no: usize = 0;
        while (it.next()) |line_raw| : (line_no += 1) {
            const line = std.mem.trim(u8, line_raw, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;

            const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse {
                std.log.warn("KidulWM: keybinds line {d} missing '=': '{s}'; using built-in defaults", .{ line_no, line });
                return defaults(allocator);
            };
            const left = std.mem.trim(u8, line[0..eq_idx], " \t");
            const right = std.mem.trim(u8, line[eq_idx + 1 ..], " \t");
            if (left.len == 0 or right.len == 0) {
                std.log.warn("KidulWM: keybinds line {d} has empty side; using built-in defaults", .{line_no});
                return defaults(allocator);
            }

            var mod4 = false;
            var ctrl = false;
            var key_part: []const u8 = left;
            if (std.mem.startsWith(u8, left, "Mod4+")) {
                mod4 = true;
                key_part = left[5..];
            } else if (std.mem.startsWith(u8, left, "Mod+")) {
                mod4 = true;
                key_part = left[4..];
            }
            if (std.mem.startsWith(u8, key_part, "Ctrl+")) {
                ctrl = true;
                key_part = key_part[5..];
            }

            const sym = parseKeysym(key_part) orelse {
                std.log.warn("KidulWM: keybinds line {d} unknown key '{s}'; using built-in defaults", .{ line_no, key_part });
                return defaults(allocator);
            };

            const action = parseAction(allocator, right) orelse {
                std.log.warn("KidulWM: keybinds line {d} unknown action '{s}'; using built-in defaults", .{ line_no, right });
                return defaults(allocator);
            };

            list.append(allocator, .{ .mod4 = mod4, .ctrl = ctrl, .sym = sym, .action = action }) catch {
                std.log.warn("KidulWM: failed to append keybind; using built-in defaults", .{});
                switch (action) {
                    .spawn => |cmd| allocator.free(cmd),
                    else => {},
                }
                return defaults(allocator);
            };
        }

        if (list.items.len == 0) {
            std.log.warn("KidulWM: keybinds file '{s}' had no bindings; using built-in defaults", .{path});
            return defaults(allocator);
        }

        std.log.info("KidulWM: loaded {d} keybinds from '{s}'", .{ list.items.len, path });
        return .{
            .allocator = allocator,
            .binds = list,
            .fallback = false,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.binds.items) |bind| {
            switch (bind.action) {
                .spawn => |cmd| self.allocator.free(cmd),
                else => {},
            }
        }
        self.binds.deinit(self.allocator);
    }

    pub fn match(self: *const Self, mod4_active: bool, ctrl_active: bool, sym: xkb.Keysym) ?Action {
        for (self.binds.items) |bind| {
            if (bind.mod4 == mod4_active and bind.ctrl == ctrl_active and bind.sym == sym) {
                return bind.action;
            }
        }
        return null;
    }

    fn errnoAbs(rc: usize) std.posix.OpenError {
        _ = rc;
        return error.FileNotFound;
    }

    fn parseKeysym(str: []const u8) ?xkb.Keysym {
        const map = [_]struct { []const u8, xkb.Keysym }{
            .{ "Return", xkb.Keysym.Return },
            .{ "Enter", xkb.Keysym.Return },
            .{ "Escape", xkb.Keysym.Escape },
            .{ "Up", xkb.Keysym.Up },
            .{ "Down", xkb.Keysym.Down },
            .{ "Left", xkb.Keysym.Left },
            .{ "Right", xkb.Keysym.Right },
            .{ "space", xkb.Keysym.space },
            .{ "Tab", xkb.Keysym.Tab },
            .{ "a", xkb.Keysym.a },
            .{ "b", xkb.Keysym.b },
            .{ "c", xkb.Keysym.c },
            .{ "d", xkb.Keysym.d },
            .{ "e", xkb.Keysym.e },
            .{ "f", xkb.Keysym.f },
            .{ "g", xkb.Keysym.g },
            .{ "h", xkb.Keysym.h },
            .{ "i", xkb.Keysym.i },
            .{ "j", xkb.Keysym.j },
            .{ "k", xkb.Keysym.k },
            .{ "l", xkb.Keysym.l },
            .{ "m", xkb.Keysym.m },
            .{ "n", xkb.Keysym.n },
            .{ "o", xkb.Keysym.o },
            .{ "p", xkb.Keysym.p },
            .{ "q", xkb.Keysym.q },
            .{ "r", xkb.Keysym.r },
            .{ "s", xkb.Keysym.s },
            .{ "t", xkb.Keysym.t },
            .{ "u", xkb.Keysym.u },
            .{ "v", xkb.Keysym.v },
            .{ "w", xkb.Keysym.w },
            .{ "x", xkb.Keysym.x },
            .{ "y", xkb.Keysym.y },
            .{ "z", xkb.Keysym.z },
            .{ "0", xkb.Keysym.@"0" },
            .{ "1", xkb.Keysym.@"1" },
            .{ "2", xkb.Keysym.@"2" },
            .{ "3", xkb.Keysym.@"3" },
            .{ "4", xkb.Keysym.@"4" },
            .{ "5", xkb.Keysym.@"5" },
            .{ "6", xkb.Keysym.@"6" },
            .{ "7", xkb.Keysym.@"7" },
            .{ "8", xkb.Keysym.@"8" },
            .{ "9", xkb.Keysym.@"9" },
        };
        for (map) |entry| {
            if (std.mem.eql(u8, str, entry[0])) return entry[1];
        }
        return null;
    }

    fn parseAction(allocator: std.mem.Allocator, str: []const u8) ?Action {
        if (std.mem.eql(u8, str, "focus_next")) return .focus_next;
        if (std.mem.eql(u8, str, "focus_prev")) return .focus_prev;
        if (std.mem.eql(u8, str, "tray_toggle")) return .tray_toggle;
        if (std.mem.eql(u8, str, "tray_select_next")) return .tray_select_next;
        if (std.mem.eql(u8, str, "tray_select_prev")) return .tray_select_prev;
        if (std.mem.eql(u8, str, "tray_activate")) return .tray_activate;
        if (std.mem.eql(u8, str, "media_card_toggle")) return .media_card_toggle;
        if (std.mem.eql(u8, str, "signals_card_toggle")) return .signals_card_toggle;
        if (std.mem.eql(u8, str, "next_animation")) return .next_animation;
        if (std.mem.eql(u8, str, "close_focused")) return .close_focused;
        if (std.mem.eql(u8, str, "reload")) return .reload;
        if (std.mem.eql(u8, str, "park_toggle")) return .park_toggle;
        if (std.mem.eql(u8, str, "open_slide")) {
            const cmd = allocator.dupe(u8, "/usr/bin/ghostty") catch return null;
            return .{ .spawn = cmd };
        }
        if (std.mem.startsWith(u8, str, "spawn ")) {
            const cmd = allocator.dupe(u8, str[6..]) catch return null;
            return .{ .spawn = cmd };
        }
        return null;
    }
};
