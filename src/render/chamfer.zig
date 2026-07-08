const std = @import("std");

pub usingnamespace @import("../core/chamfer.zig");

/// GLSL fragment shader stub for chamfered/cut-corner window borders.
///
/// Inputs:
///   - v_uv        surface UV in [0,1]
///   - v_size      window size in pixels
///   - v_corner    corner style: 0=classic, 1=cut, 2=none
///
/// Uniforms (single source of truth from core/style.zig):
///   - border_width   width in pixels
///   - depth          chamfer cut depth in pixels
///   - color_border   vec4
///   - color_focused  vec4
///   - color_glow     vec4
pub const fragment_glsl_stub =
    \\  #version 320 es
    \\  precision mediump float;
    \\  in vec2 v_uv;
    \\  in vec2 v_size;
    \\  flat in int v_corner;
    \\  uniform float u_border_width;
    \\  uniform float u_depth;
    \\  uniform vec4 u_color_border;
    \\  uniform vec4 u_color_focused;
    \\  uniform vec4 u_color_glow;
    \\  out vec4 frag_color;
    \\  float chamfer_sdf(vec2 p, vec2 h, float d) {
    \\      vec2 q = abs(p) - h;
    \\      float c = q.x + q.y + d;
    \\      float m = min(c, 0.0);
    \\      vec2 r = max(q + vec2(m), vec2(0.0));
    \\      return length(r) + max(max(q.x, q.y), 0.0);
    \\  }
    \\  void main() {
    \\      vec2 half_size = v_size * 0.5;
    \\      vec2 p = (v_uv - vec2(0.5)) * v_size;
    \\      float d = chamfer_sdf(p, half_size - u_border_width, u_depth);
    \\      vec4 color = mix(u_color_border, u_color_focused, 0.0);
    \\      float border = smoothstep(0.0, 1.0, d) - smoothstep(u_border_width, u_border_width + 1.0, d);
    \\      frag_color = mix(color, u_color_glow, border * 0.3);
    \\  }
;

test "GLSL stub is non-empty" {
    try std.testing.expect(fragment_glsl_stub.len > 0);
}
