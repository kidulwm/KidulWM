// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");

/// Display Manager visual tokens. Matches KidulWM chrome where it makes sense,
/// but tuned for a dark, classy login surface.
pub const Style = struct {
    // Backgrounds
    color_bg: Color = Color.fromHex(0x1B1D1E),
    color_card_bg: Color = Color.fromHex(0x25282A),

    // Gold family
    color_gold: Color = Color.fromHex(0xD4AF37),
    color_gold_dim: Color = Color.fromHex(0x948E7B),
    color_gold_soft: Color = Color.fromRgba(0xD4AF37, 0.18),

    // Company gradient accents
    color_purple: Color = Color.fromHex(0x7C3AED),
    color_blue: Color = Color.fromHex(0x2563EB),
    color_turquoise: Color = Color.fromHex(0x06B6D4),

    // Functional
    color_text: Color = Color.fromHex(0xD8DEE9),
    color_text_dim: Color = Color.fromHex(0x948E7B),
    color_warning: Color = Color.fromHex(0xF97316),

    // Geometry
    card_width: f64 = 420.0,
    card_height: f64 = 260.0,
    corner_cut: f64 = 20.0,
    border_width: f64 = 2.0,
    corner_highlight_width: f64 = 1.2,

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

        pub fn fromRgba(hex: u24, alpha: f64) Color {
            return .{
                .r = @intCast((hex >> 16) & 0xFF),
                .g = @intCast((hex >> 8) & 0xFF),
                .b = @intCast(hex & 0xFF),
                .a = @intCast(std.math.clamp(@as(u32, @intFromFloat(alpha * 255.0)), 0, 255)),
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
