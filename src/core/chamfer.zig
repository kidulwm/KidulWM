const std = @import("std");
const style = @import("style.zig");

/// GPU-ready colour values from src/core/style.zig.  These arrays are intended
/// to be uploaded as shader uniforms or embedded as literals.
fn toF32(c: style.Style.Color) [4]f32 {
    const inv = 1.0 / 255.0;
    return .{
        @as(f32, @floatFromInt(c.r)) * inv,
        @as(f32, @floatFromInt(c.g)) * inv,
        @as(f32, @floatFromInt(c.b)) * inv,
        @as(f32, @floatFromInt(c.a)) * inv,
    };
}

pub const colors = struct {
    pub const background = toF32(style.default().color_background);
    pub const border = toF32(style.default().color_border);
    pub const border_focused = toF32(style.default().color_border_focused);
    pub const electric = toF32(style.default().color_electric);
    pub const purple = toF32(style.default().color_purple);
    pub const turquoise = toF32(style.default().color_turquoise);
    pub const glow = toF32(style.default().color_glow);

    pub const royal_blue = border;
};

/// Chamfered-rectangle SDF stub.  `p` is the fragment position relative to the
/// rectangle centre, `half_size` is the half-extents, and `depth` is the diagonal
/// cut depth in pixels.  Negative values are inside, positive outside.
pub fn chamferSdf(p: [2]f32, half_size: [2]f32, depth: f32) f32 {
    const qx = @abs(p[0]) - half_size[0];
    const qy = @abs(p[1]) - half_size[1];
    const q = [2]f32{ qx, qy };

    // Chamfer correction: when both qx and qy are positive we are in the corner
    // region.  Push the distance toward the 45-degree cut plane.
    const corner = qx + qy + depth;
    const m = if (corner < 0.0) corner else 0.0;

    const dx = @max(q[0] + m, 0.0);
    const dy = @max(q[1] + m, 0.0);
    const outside = std.math.sqrt(dx * dx + dy * dy);
    const inside = @min(@max(q[0], q[1]), 0.0);
    return outside + inside;
}

/// RKT gradient rule: mostly royal blue, 1/4 royal purple at the top-left, and
/// 1/8 turquoise at the bottom-right.  `uv` is in [0,1] inside the widget.
pub fn gradientColor(uv: [2]f32) [4]f32 {
    const base = colors.royal_blue;
    const purple = colors.purple;
    const turquoise = colors.turquoise;

    // Top-left influence falls off with x and increases with y (assuming y up).
    const tl = (1.0 - uv[0]) * uv[1] * 0.25;
    // Bottom-right influence increases with x and falls off with y.
    const br = uv[0] * (1.0 - uv[1]) * 0.125;

    return .{
        base[0] + tl * purple[0] + br * turquoise[0],
        base[1] + tl * purple[1] + br * turquoise[1],
        base[2] + tl * purple[2] + br * turquoise[2],
        base[3],
    };
}

test "chamfer SDF is negative inside a centred rectangle" {
    const sdf = chamferSdf(.{ 0.0, 0.0 }, .{ 100.0, 100.0 }, 18.0);
    try std.testing.expect(sdf < 0.0);
}

test "gradient colour stays inside valid RGBA range" {
    const c = gradientColor(.{ 0.5, 0.5 });
    try std.testing.expect(c[0] >= 0.0 and c[0] <= 1.0);
    try std.testing.expect(c[3] >= 0.0 and c[3] <= 1.0);
}
