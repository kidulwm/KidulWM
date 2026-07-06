const std = @import("std");

/// Single source of truth for window chrome dimensions and colours.
/// Every rendering path that draws borders, focus rings, chamfer highlights,
/// or widgets that display chrome reads from this structure.
pub const Style = struct {
    gap: u32 = 8,
    border_width: f32 = 2.0,
    corner_style: CornerStyle = .cut,
    corner_depth: f32 = 18.0,

    color_background: Color = Color.fromHex(0x0a0e17),
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
    };
};

pub fn default() Style {
    return .{};
}
