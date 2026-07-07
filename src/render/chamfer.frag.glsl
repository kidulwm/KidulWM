#version 320 es
precision highp float;

// Chamfer / cut-corner SDF fragment shader stub for KidulWM chrome.
// Colours are mirrored from src/core/style.zig.

layout(location = 0) uniform vec2 u_resolution;
layout(location = 1) uniform vec2 u_size;
layout(location = 2) uniform float u_border_width;
layout(location = 3) uniform float u_chamfer_depth;
layout(location = 4) uniform vec4 u_color_background;
layout(location = 5) uniform vec4 u_color_border;
layout(location = 6) uniform vec4 u_color_focused;
layout(location = 7) uniform vec4 u_color_glow;
layout(location = 8) uniform int u_focused; // 0 or 1

in vec2 v_uv;
out vec4 frag_color;

const vec4 ROYAL_BLUE = vec4(0.102, 0.169, 0.235, 1.0); // #1a2b3c
const vec4 ROYAL_PURPLE = vec4(0.635, 0.349, 1.0, 1.0);  // #a259ff
const vec4 TURQUOISE = vec4(0.0, 1.0, 0.784, 1.0);       // #00ffc8

// RKT gradient rule: mostly royal blue, 1/4 purple top-left, 1/8 turquoise bottom-right.
vec4 rkt_gradient(vec2 uv) {
    float tl = (1.0 - uv.x) * uv.y * 0.25;
    float br = uv.x * (1.0 - uv.y) * 0.125;
    return ROYAL_BLUE + tl * ROYAL_PURPLE + br * TURQUOISE;
}

// Signed distance to a rectangle with 45-degree chamfered corners.
float sd_chamfered_rect(vec2 p, vec2 half_size, float depth) {
    vec2 q = abs(p) - half_size;
    float m = min(q.x + q.y + depth, 0.0);
    vec2 d = max(q + vec2(m), 0.0);
    return length(d) + min(max(q.x, q.y), 0.0);
}

void main() {
    // Map v_uv ([0,1]) to local pixel coordinates centred on the widget.
    vec2 pixel = (v_uv - 0.5) * u_size;

    float sdf = sd_chamfered_rect(pixel, u_size * 0.5, u_chamfer_depth);

    vec4 fill = rkt_gradient(v_uv);
    vec4 border = u_focused != 0 ? u_color_focused : u_color_border;

    // Smooth fill/border transition at the inner edge of the border.
    float inner_edge = sdf + u_border_width;
    float alpha_border = 1.0 - smoothstep(0.0, 1.0, inner_edge);
    float alpha_fill = 1.0 - smoothstep(0.0, 1.0, -inner_edge);

    // Outer glow for focused chrome.
    float glow = u_focused != 0 ? exp(-sdf * sdf / (u_border_width * u_border_width + 0.001)) * 0.25 : 0.0;

    frag_color = mix(fill, border, alpha_border);
    frag_color = mix(frag_color, u_color_glow, glow);
    frag_color.a = max(alpha_fill, alpha_border);
}
