const std = @import("std");

/// Single source of truth for window chrome dimensions and colours.
/// Every rendering path that draws borders, focus rings, chamfer highlights,
/// or widgets that display chrome reads from this structure.
pub const Style = struct {
    gap: u32 = 8,
    border_width: f32 = 2.0,
    corner_style: CornerStyle = .cut,
    corner_depth: f32 = 18.0,

    color_background: Color = Color.fromHex(0x222425),
    color_border: Color = Color.fromHex(0x1a2b3c),
    color_border_focused: Color = Color.fromHex(0x00f0ff),
    color_electric: Color = Color.fromHex(0x00f0ff),
    color_purple: Color = Color.fromHex(0xa259ff),
    color_turquoise: Color = Color.fromHex(0x00ffc8),
    color_glow: Color = Color.fromRgba(0x00f0ff, 0.18),

    pub const CornerStyle = enum {
        classic,
        cut,
        none,
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

        pub fn toF32(self: Color) [4]f32 {
            return .{
                @as(f32, self.r) / 255.0,
                @as(f32, self.g) / 255.0,
                @as(f32, self.b) / 255.0,
                @as(f32, self.a) / 255.0,
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

    /// Legacy default used by State and Split.default().  focus + 2*peek > 1.0,
    /// so Split.verify() normalises it to actual screen proportions.
    pub const default_split: SplitPreset = .{ .left_peek = 0.08, .focus = 0.94, .right_peek = 0.08 };

    /// Three-column horizontal arrangement (8% peek / 84% focus / 8% peek).
    pub const horizontal_split: SplitPreset = .{ .left_peek = 0.08, .focus = 0.84, .right_peek = 0.08 };

    /// Vertical top/bottom arrangements.
    pub const vertical_top_split: SplitPreset = .{ .left_peek = 0.0, .focus = 0.5, .right_peek = 0.5 };
    pub const vertical_bottom_split: SplitPreset = .{ .left_peek = 0.5, .focus = 0.5, .right_peek = 0.0 };
};
