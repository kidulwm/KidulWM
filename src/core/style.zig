const std = @import("std");

/// Single source of truth for window chrome dimensions and colours.
/// Every rendering path that draws borders, focus rings, focus highlights,
/// or widgets that display chrome reads from this structure.
pub const Style = struct {
    gap: u32 = 8,
    border_width: f32 = 2.0,
    corner_style: CornerStyle = .round,
    corner_depth: f32 = 16.0,
    card_mat_depth: f32 = 14.0,
    card_mat_border_width: f32 = 2.0,

    color_background: Color = Color.fromHex(0x222425),
    color_border: Color = Color.fromHex(0x4d4a40),
    color_border_focused: Color = Color.fromHex(0x696555),
    color_card_border: Color = Color.fromHex(0x3b382f),
    color_card_mat: Color = Color.fromHex(0x0a0a0b),
    card_mat_style: CardMatStyle = .black_glass_halo,
    color_electric: Color = Color.fromHex(0x00f0ff),
    color_purple: Color = Color.fromHex(0xa259ff),
    color_turquoise: Color = Color.fromHex(0x00ffc8),
    color_gold: Color = Color.fromHex(0x948e7b),
    color_gold_dim: Color = Color.fromHex(0x5e5a4c),
    color_glow: Color = Color.fromRgba(0x948e7b, 0.35),

    peek_glass_alpha_top: f32 = 0.97,
    peek_glass_alpha_mid: f32 = 0.45,
    peek_glass_alpha_outer: f32 = 0.90,
    peek_glass_alpha_inner: f32 = 0.55,
    peek_glass_border_color: Color = Color.fromHex(0x4d4a40),
    peek_label_font_size: f32 = 15.0,
    peek_label_inset: i32 = 10,

    tray_font_size: f32 = 16.0,
    tray_text_color: Color = Color.fromHex(0x948e7b),
    tray_text_focused_color: Color = Color.fromHex(0xb8b09b),
    tray_bg_color: Color = Color.fromHex(0x0a0a0b),
    tray_icon_size: f32 = 24.0,
    tray_icon_gap: f32 = 8.0,
    color_text_muted: Color = Color.fromHex(0x6a6354),

    font_size_s: f32 = 13.0,
    font_size_m: f32 = 16.0,
    font_size_l: f32 = 22.0,

    // Weather widget tokens.
    weather_moon_color: Color = Color.fromHex(0x696555),
    weather_temp_color: Color = Color.fromHex(0xb8b09b),
    weather_minmax_color: Color = Color.fromHex(0x948e7b),
    weather_icon_color: Color = Color.fromHex(0x948e7b),
    weather_anim_color: Color = Color.fromHex(0xb8b09b),
    weather_widget_min_width: f32 = 72.0,
    weather_peek_anim_budget_ms: u32 = 3000,
    weather_idle_break_ms: u32 = 600000,
    weather_active_interval_ms: u32 = 900000,

    show_title_bars: bool = false,

    pub const CornerStyle = enum {
        round,
        chamfer,
        square,
    };

    pub const CardMatStyle = enum {
        cinematic_shadow,
        gallery_mat,
        deep_float,
        paper_edge,
        black_glass_halo,

        pub fn fromString(s: []const u8) ?CardMatStyle {
            if (std.mem.eql(u8, s, "cinematic_shadow")) return .cinematic_shadow;
            if (std.mem.eql(u8, s, "gallery_mat")) return .gallery_mat;
            if (std.mem.eql(u8, s, "deep_float")) return .deep_float;
            if (std.mem.eql(u8, s, "paper_edge")) return .paper_edge;
            if (std.mem.eql(u8, s, "black_glass_halo")) return .black_glass_halo;
            return null;
        }
    };

    pub const Color = packed struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,

        pub fn fromHex(hex: u24) Color {
            return .{
                .r = @intCast((hex >> 16) & 0xFF),
                .g = @intCast((hex >> 8) & 0xFF),
                .b = @intCast(hex & 0xFF),
                .a = 0xFF,
            };
        }

        pub fn fromRgba(hex: u24, alpha: f32) Color {
            return .{
                .r = @intCast((hex >> 16) & 0xFF),
                .g = @intCast((hex >> 8) & 0xFF),
                .b = @intCast(hex & 0xFF),
                .a = @intCast(std.math.clamp(@as(u32, @intFromFloat(alpha * 255.0)), 0, 255)),
            };
        }

        pub fn fromString(s: []const u8) !Color {
            return parseColorString(s);
        }

        pub fn parseColorString(s: []const u8) !Color {
            const t = std.mem.trim(u8, s, " \t\r\n");
            if (t.len == 0) return error.InvalidColor;
            if (std.mem.startsWith(u8, t, "rgba(")) return parseRgba(t);
            if (std.mem.startsWith(u8, t, "rgb(")) return parseRgb(t);
            const hex = if (t[0] == '#') t[1..] else t;
            if (hex.len != 6 and hex.len != 8) return error.InvalidColor;
            const r = try std.fmt.parseInt(u8, hex[0..2], 16);
            const g = try std.fmt.parseInt(u8, hex[2..4], 16);
            const b = try std.fmt.parseInt(u8, hex[4..6], 16);
            const a: u8 = if (hex.len == 8) try std.fmt.parseInt(u8, hex[6..8], 16) else 0xFF;
            return .{ .r = r, .g = g, .b = b, .a = a };
        }

        fn parseRgba(s: []const u8) !Color {
            var inner = s[5..];
            if (inner.len > 0 and inner[inner.len - 1] == ')') inner = inner[0 .. inner.len - 1];
            var parts: [4]f32 = undefined;
            var i: usize = 0;
            var it = std.mem.splitScalar(u8, inner, ',');
            while (it.next()) |part| : (i += 1) {
                if (i >= 4) return error.InvalidColor;
                parts[i] = std.fmt.parseFloat(f32, std.mem.trim(u8, part, " \t")) catch return error.InvalidColor;
            }
            if (i != 4) return error.InvalidColor;
            return .{
                .r = floatComponent(parts[0]),
                .g = floatComponent(parts[1]),
                .b = floatComponent(parts[2]),
                .a = floatAlpha(parts[3]),
            };
        }

        fn parseRgb(s: []const u8) !Color {
            var inner = s[4..];
            if (inner.len > 0 and inner[inner.len - 1] == ')') inner = inner[0 .. inner.len - 1];
            var parts: [3]f32 = undefined;
            var i: usize = 0;
            var it = std.mem.splitScalar(u8, inner, ',');
            while (it.next()) |part| : (i += 1) {
                if (i >= 3) return error.InvalidColor;
                parts[i] = std.fmt.parseFloat(f32, std.mem.trim(u8, part, " \t")) catch return error.InvalidColor;
            }
            if (i != 3) return error.InvalidColor;
            return .{
                .r = floatComponent(parts[0]),
                .g = floatComponent(parts[1]),
                .b = floatComponent(parts[2]),
                .a = 255,
            };
        }

        fn floatComponent(v: f32) u8 {
            const scaled = if (v <= 1.0) v * 255.0 else v;
            return @intCast(std.math.clamp(@as(u32, @intFromFloat(scaled)), 0, 255));
        }

        fn floatAlpha(v: f32) u8 {
            return @intCast(std.math.clamp(@as(u32, @intFromFloat(v * 255.0)), 0, 255));
        }

        pub fn toF32(self: Color) [4]f32 {
            return .{
                @as(f32, self.r) / 255.0,
                @as(f32, self.g) / 255.0,
                @as(f32, self.b) / 255.0,
                @as(f32, self.a) / 255.0,
            };
        }

        pub fn toF64(self: Color) [4]f64 {
            return .{
                @as(f64, self.r) / 255.0,
                @as(f64, self.g) / 255.0,
                @as(f64, self.b) / 255.0,
                @as(f64, self.a) / 255.0,
            };
        }
    };
};

/// Convenience pre-computed default-style values.
pub const default_style = default();

pub fn default() Style {
    return .{};
}

/// Layout geometry tokens.  These are used by both the IPC state machine and the
/// layout engine so gap/split values stay consistent across the compositor.
pub const layout = struct {
    pub const gap: u32 = 8;
    pub const peek: f32 = 0.08;

    pub const SplitPreset = struct {
        left_peek: f32,
        focus: f32,
        right_peek: f32,
    };

    /// Default three-column split (8% peek / 84% focus / 8% peek).
    pub const default_split: SplitPreset = .{ .left_peek = 0.06, .focus = 0.88, .right_peek = 0.06 };

    /// Three-column horizontal arrangement (8% peek / 84% / 8% peek).
    pub const horizontal_split: SplitPreset = .{ .left_peek = 0.06, .focus = 0.88, .right_peek = 0.06 };

    /// Vertical top/bottom arrangements.
    pub const vertical_top_split: SplitPreset = .{ .left_peek = 0.0, .focus = 0.5, .right_peek = 0.5 };
    pub const vertical_bottom_split: SplitPreset = .{ .left_peek = 0.5, .focus = 0.5, .right_peek = 0.0 };
};
