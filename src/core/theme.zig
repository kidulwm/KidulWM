const std = @import("std");
const Style = @import("style.zig").Style;
const toml = @import("toml");

/// Runtime theme configuration loaded from external TOML files.
///
/// Theme mirrors all fields in the static `Style` defaults so every
/// hard-coded color/metric can be overridden without recompilation.
///
/// The `generation` counter is bumped on every successful load or
/// individual value change. Renderers that cache theme-derived buffers
/// can compare this to know when to regenerate.
pub const Theme = struct {
    style: Style,
    generation: u32 = 0,

    // Theme-driven tray metrics. Mirrors layout constants in tray.zig.
    button_height: i32 = 44,
    button_gap: i32 = 8,
    corner_radius: i32 = 8,
    icon_size: i32 = 24,
    icon_gap: i32 = 8,
    tray_top_margin: i32 = 48,
    tray_bottom_margin: i32 = 10,
    tray_hmargin: i32 = 8,
    barry_button_height: i32 = 84,
    corner_style: []const u8 = "round",

    // Animation state scalars exposed to any module that needs them.
    tray_open_s: f64 = 0.320,
    tray_close_snap_s: f64 = 0.125,
    tray_settle_pulse_s: f64 = 0.170,
    underline_spring_stiffness: f64 = 80.0,
    barry_follow_delay_s: f64 = 3.0,

    const Self = @This();

    /// Initialize with the built-in default style values.
    pub fn initDefaults() Self {
        return .{ .style = Style{} };
    }

    /// Load from the first file that exists in the search chain.
    /// Returns error if a file exists but cannot be parsed.
    pub fn reload(self: *Self, allocator: std.mem.Allocator) !void {
        const paths = try searchPaths(allocator);
        defer {
            for (paths) |p| allocator.free(p);
            allocator.free(paths);
        }

        for (paths) |path| {
            const exists = fileExists(path);
            if (!exists) continue;
            try self.loadFromFile(allocator, path);
            std.log.info("KidulWM: loaded theme from {s}", .{path});
            return;
        }

        std.log.info("KidulWM: no theme.toml found, using defaults", .{});
    }

    /// Parse a concrete TOML path and apply it to the runtime style.
    pub fn loadFromFile(self: *Self, allocator: std.mem.Allocator, path: []const u8) !void {
        const text = readFileAlloc(allocator, path) catch |err| {
            std.log.err("KidulWM: failed to read theme '{s}': {}", .{ path, err });
            return err;
        };
        defer allocator.free(text);

        var parser = toml.Parser(Config).init(allocator);
        defer parser.deinit();
        var result = parser.parseString(text) catch |err| {
            std.log.err("KidulWM: failed to parse theme '{s}': {}", .{ path, err });
            return err;
        };
        defer result.deinit();

        self.applyConfig(&result.value);
        self.generation +%= 1;
    }

    /// Bump generation when callers apply individual key/value overrides
    /// through IPC.
    pub fn bumpGeneration(self: *Self) void {
        self.generation +%= 1;
    }

    fn applyConfig(self: *Self, cfg: *const Config) void {
        self.style.color_background = parseColor(cfg.colors.background) orelse self.style.color_background;
        self.style.color_gold = parseColor(cfg.colors.gold) orelse self.style.color_gold;
        self.style.color_gold_dim = parseColor(cfg.colors.gold_dim) orelse self.style.color_gold_dim;
        self.style.color_glow = parseColor(cfg.colors.gold_soft) orelse self.style.color_glow;
        self.style.color_border = parseColor(cfg.colors.border) orelse self.style.color_border;
        self.style.color_border_focused = parseColor(cfg.colors.border_focused) orelse self.style.color_border_focused;
        self.style.color_card_border = parseColor(cfg.colors.card_border) orelse self.style.color_card_border;
        self.style.color_electric = parseColor(cfg.colors.electric) orelse self.style.color_electric;
        self.style.color_purple = parseColor(cfg.colors.purple) orelse self.style.color_purple;
        self.style.color_turquoise = parseColor(cfg.colors.turquoise) orelse self.style.color_turquoise;
        self.style.tray_text_color = parseColor(cfg.colors.text_body) orelse self.style.tray_text_color;
        self.style.tray_text_focused_color = parseColor(cfg.colors.text_focused) orelse self.style.tray_text_focused_color;
        self.style.tray_bg_color = parseColor(cfg.colors.black_glass) orelse self.style.tray_bg_color;
        self.style.color_text_muted = parseColor(cfg.colors.text_muted) orelse self.style.color_text_muted;
        self.style.peek_glass_border_color = self.style.color_border;

        // Weather tokens.
        self.style.weather_moon_color = parseColor(cfg.colors.weather_moon) orelse self.style.weather_moon_color;
        self.style.weather_temp_color = parseColor(cfg.colors.weather_temp) orelse self.style.weather_temp_color;
        self.style.weather_minmax_color = parseColor(cfg.colors.weather_minmax) orelse self.style.weather_minmax_color;
        self.style.weather_icon_color = parseColor(cfg.colors.weather_icon) orelse self.style.weather_icon_color;
        self.style.weather_anim_color = parseColor(cfg.colors.weather_anim) orelse self.style.weather_anim_color;
        self.style.weather_widget_min_width = @floatFromInt(cfg.spacing.weather_widget_min_width);
        self.style.weather_peek_anim_budget_ms = cfg.animation.weather_peek_anim_duration_ms;

        // Typography / geometry.
        self.style.font_size_s = @floatFromInt(cfg.typography.font_size_s);
        self.style.font_size_m = @floatFromInt(cfg.typography.font_size_m);
        self.style.font_size_l = @floatFromInt(cfg.typography.font_size_l);
        self.style.tray_font_size = self.style.font_size_m;

        // Window chrome geometry from theme.
        self.style.border_width = @floatFromInt(cfg.spacing.border_width);

        // Corner style propagates to both Theme (string) and Style (enum).
        if (std.mem.eql(u8, cfg.spacing.corner_style, "round")) {
            self.style.corner_style = .round;
        } else if (std.mem.eql(u8, cfg.spacing.corner_style, "chamfer")) {
            self.style.corner_style = .chamfer;
        } else if (std.mem.eql(u8, cfg.spacing.corner_style, "square")) {
            self.style.corner_style = .square;
        }

        // Spacing is consumed by tray.zig via the Theme struct helpers below.
        self.button_height = cfg.spacing.button_height;
        self.button_gap = cfg.spacing.button_gap;
        self.corner_radius = cfg.spacing.corner_radius;
        self.icon_size = cfg.spacing.icon_size;
        self.icon_gap = cfg.spacing.icon_gap;
        self.tray_top_margin = cfg.spacing.tray_top_margin;
        self.tray_bottom_margin = cfg.spacing.tray_bottom_margin;
        self.tray_hmargin = cfg.spacing.tray_hmargin;
        self.barry_button_height = cfg.spacing.barry_button_height;
        self.corner_style = cfg.spacing.corner_style;

        // Animation timers are seconds/float.
        self.tray_open_s = @as(f64, @floatFromInt(cfg.animation.tray_open_ms)) / 1000.0;
        self.tray_close_snap_s = @as(f64, @floatFromInt(cfg.animation.tray_close_snap_ms)) / 1000.0;
        self.tray_settle_pulse_s = @as(f64, @floatFromInt(cfg.animation.tray_settle_pulse_ms)) / 1000.0;
        self.underline_spring_stiffness = cfg.animation.underline_spring_stiffness;
        self.barry_follow_delay_s = cfg.animation.barry_follow_delay_s;
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

    fn searchPaths(allocator: std.mem.Allocator) ![]const []const u8 {
        var list = std.ArrayList([]const u8).empty;
        errdefer {
            for (list.items) |p| allocator.free(p);
            list.deinit(allocator);
        }

        if (std.c.getenv("HOME")) |home_c| {
            const home = std.mem.span(home_c);
            const user = try std.fs.path.join(allocator, &.{ home, ".config", "kidulwm", "theme.toml" });
            try list.append(allocator, user);
        }
        try list.append(allocator, try allocator.dupe(u8, "/etc/kidulwm/theme.toml"));
        try list.append(allocator, try allocator.dupe(u8, "/usr/share/kidulwm/theme.toml"));
        return list.toOwnedSlice(allocator);
    }

    fn fileExists(path: []const u8) bool {
        const path_z = std.heap.c_allocator.dupeZ(u8, path) catch return false;
        defer std.heap.c_allocator.free(path_z);
        const linux = std.os.linux;
        const fd = linux.open(path_z, .{ .ACCMODE = .RDONLY }, 0);
        if (@as(isize, @bitCast(fd)) < 0) return false;
        _ = linux.close(@intCast(fd));
        return true;
    }
};

/// TOML schema. Field names match the canonical token names.
const Config = struct {
    metadata: Metadata = .{},
    colors: ColorTokens = .{},
    typography: TypeTokens = .{},
    spacing: SpacingTokens = .{},
    animation: AnimationTokens = .{},
};

const Metadata = struct {
    name: []const u8 = "KidulWM Default",
    version: []const u8 = "1.0.0",
};

const ColorTokens = struct {
    background: []const u8 = "#222425",
    gold: []const u8 = "#948e7b",
    gold_dim: []const u8 = "#5e5a4c",
    gold_soft: []const u8 = "rgba(148, 142, 123, 0.35)",
    text_body: []const u8 = "#948e7b",
    text_focused: []const u8 = "#b8b09b",
    text_muted: []const u8 = "#6a6354",
    black_glass: []const u8 = "rgba(10, 10, 11, 0.92)",
    black_glass_mid: []const u8 = "rgba(10, 10, 11, 0.60)",
    black_glass_deep: []const u8 = "rgba(4, 4, 5, 0.78)",
    rim_light: []const u8 = "rgba(255, 255, 255, 0.08)",
    border: []const u8 = "#4d4a40",
    border_focused: []const u8 = "#696555",
    card_border: []const u8 = "#3b382f",
    urgent: []const u8 = "#BF616A",
    info: []const u8 = "#88C0D0",
    purple: []const u8 = "#a259ff",
    turquoise: []const u8 = "#00ffc8",
    blue: []const u8 = "#5E81AC",
    electric: []const u8 = "#00f0ff",
    weather_moon: []const u8 = "#696555",
    weather_temp: []const u8 = "#b8b09b",
    weather_minmax: []const u8 = "#948e7b",
    weather_icon: []const u8 = "#948e7b",
    weather_anim: []const u8 = "#b8b09b",
};

const TypeTokens = struct {
    font_mono: []const u8 = "Fantasque Sans Mono",
    font_size_s: i32 = 13,
    font_size_m: i32 = 16,
    font_size_l: i32 = 22,
};

const SpacingTokens = struct {
    border_width: i32 = 2,
    corner_style: []const u8 = "round",
    button_height: i32 = 44,
    button_gap: i32 = 8,
    corner_radius: i32 = 8,
    icon_size: i32 = 24,
    icon_gap: i32 = 8,
    tray_top_margin: i32 = 48,
    tray_bottom_margin: i32 = 10,
    tray_hmargin: i32 = 8,
    barry_button_height: i32 = 84,
    char_buffer_m: f64 = 16.0,
    weather_widget_min_width: i32 = 72,
};

const AnimationTokens = struct {
    tray_open_ms: i32 = 320,
    tray_close_snap_ms: i32 = 125,
    tray_settle_pulse_ms: i32 = 170,
    underline_spring_stiffness: f64 = 80.0,
    barry_follow_delay_s: f64 = 3.0,
    window_transition_ms: i32 = 120,
    weather_peek_anim_duration_ms: u32 = 3000,
};

fn parseColor(s: []const u8) ?Style.Color {
    return Style.Color.fromString(s) catch null;
}
