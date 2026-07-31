const std = @import("std");
const c = @import("dm").c;

/// Moon phase descriptor.
pub const Phase = struct {
    /// Fraction illuminated, 0..1.
    illumination: f64,
    /// Days since new moon, 0..29.53.
    age: f64,
    /// Phase name.
    name: []const u8,
};

/// Reference new moon: 2000-01-06 18:14 UTC.
const ref_new_moon_j2000: f64 = 2451549.2596;
const synodic_month: f64 = 29.53058867;

/// Convert Unix seconds to Julian Date.
fn unixToJulianDate(utc_s: i64) f64 {
    return @as(f64, @floatFromInt(utc_s)) / 86400.0 + 2440587.5;
}

/// Compute phase for the given Unix timestamp (UTC).
pub fn phaseForUnixSeconds(utc_s: i64) Phase {
    const jd = unixToJulianDate(utc_s);
    const days_since_ref = jd - ref_new_moon_j2000;
    const cycles = days_since_ref / synodic_month;
    const age = (cycles - std.math.floor(cycles)) * synodic_month;
    const frac = age / synodic_month;

    const angle = frac * 2.0 * std.math.pi;
    const illumination = 0.5 * (1.0 - std.math.cos(angle));

    const name = phaseName(frac);
    return .{
        .illumination = illumination,
        .age = age,
        .name = name,
    };
}

fn phaseName(frac: f64) []const u8 {
    if (frac < 0.03) return "New Moon";
    if (frac < 0.22) return "Waxing Crescent";
    if (frac < 0.28) return "First Quarter";
    if (frac < 0.47) return "Waxing Gibbous";
    if (frac < 0.53) return "Full Moon";
    if (frac < 0.72) return "Waning Gibbous";
    if (frac < 0.78) return "Last Quarter";
    if (frac < 0.97) return "Waning Crescent";
    return "New Moon";
}

/// Render a moon into a Cairo context.
/// Uses a shaded-sphere look: spherical body, soft terminator, radial limb darkening.
pub fn renderMoon(cr: *c.cairo_t, cx: f64, cy: f64, r: f64, phase: Phase, outline_color: [4]f64, shadow_color: [4]f64) void {
    const frac = phase.age / synodic_month;
    const phase_angle = frac * 2.0 * std.math.pi;

    // Body disc uses the shadow color as a faint base. Paint a full disc first.
    c.cairo_save(cr);

    // 1. Base full disc (dark side)
    c.cairo_set_source_rgba(cr, shadow_color[0], shadow_color[1], shadow_color[2], shadow_color[3]);
    c.cairo_arc(cr, cx, cy, r, 0, 2 * std.math.pi);
    c.cairo_fill(cr);

    // 2. Lit cap as a cosine-shaped mask across the disc.
    // Map phase to terminator x offset: at new moon -r, full moon 0, new moon +r.
    // cos(phase_angle) goes 1 -> -1 -> 1 over the cycle; x ranges -r..r.
    const terminator_x = -r * std.math.cos(phase_angle);
    const lit_fraction = 0.5 * (1.0 - std.math.cos(phase_angle));

    if (lit_fraction > 0.001) {
        // Clip to the moon disc.
        c.cairo_arc(cr, cx, cy, r, 0, 2 * std.math.pi);
        c.cairo_clip(cr);
        defer _ = c.cairo_clip(cr);

        // Build a soft horizontal step from shadow to light across the terminator.
        // We paint with the outline/gold color and vary alpha to make it fade.
        const soft: f64 = r * 0.35; // terminator softness

        // Compute alpha stops across the gradient band. The lit side is to the right of
        // terminator_x for a waxing moon, but the cos() formulation handles both halves.
        // Use a horizontal linear alpha gradient from shadow to light.
        // The gradient covers the terminator band: [terminator_x - soft, terminator_x + soft].
        const grad = c.cairo_pattern_create_linear(terminator_x - soft, 0.0, terminator_x + soft, 0.0);
        defer c.cairo_pattern_destroy(grad);

        // The sign of the terminator shift flips each half-cycle; we flip the gradient stops
        // to keep lit side on the correct half of the disc.
        if (frac < 0.5) {
            // Waxing: light on right side of terminator.
            c.cairo_pattern_add_color_stop_rgba(grad, 0.0, outline_color[0], outline_color[1], outline_color[2], 0.0);
            c.cairo_pattern_add_color_stop_rgba(grad, 0.5, outline_color[0], outline_color[1], outline_color[2], outline_color[3]);
            c.cairo_pattern_add_color_stop_rgba(grad, 1.0, outline_color[0], outline_color[1], outline_color[2], outline_color[3]);
        } else {
            // Waning: light on left side of terminator.
            c.cairo_pattern_add_color_stop_rgba(grad, 0.0, outline_color[0], outline_color[1], outline_color[2], outline_color[3]);
            c.cairo_pattern_add_color_stop_rgba(grad, 0.5, outline_color[0], outline_color[1], outline_color[2], outline_color[3]);
            c.cairo_pattern_add_color_stop_rgba(grad, 1.0, outline_color[0], outline_color[1], outline_color[2], 0.0);
        }

        c.cairo_set_source(cr, grad);
        c.cairo_arc(cr, cx, cy, r, 0, 2 * std.math.pi);
        c.cairo_fill(cr);

        // 3. Subtle spherical shading overlay (radial gradient from center to rim),
        // using the outline color at low alpha on the limb and a highlight on the top-left.
        const sphere = c.cairo_pattern_create_radial(cx - r * 0.3, cy - r * 0.3, 0.0, cx, cy, r);
        defer c.cairo_pattern_destroy(sphere);
        c.cairo_pattern_add_color_stop_rgba(sphere, 0.0, outline_color[0], outline_color[1], outline_color[2], 0.18);
        c.cairo_pattern_add_color_stop_rgba(sphere, 0.55, outline_color[0], outline_color[1], outline_color[2], 0.05);
        c.cairo_pattern_add_color_stop_rgba(sphere, 1.0, 0.0, 0.0, 0.0, 0.35);
        c.cairo_set_source(cr, sphere);
        c.cairo_arc(cr, cx, cy, r, 0, 2 * std.math.pi);
        c.cairo_fill(cr);
    } else if (phase.illumination > 0.99) {
        // Full moon: entirely lit, but still add the sphere shading.
        const sphere = c.cairo_pattern_create_radial(cx - r * 0.3, cy - r * 0.3, 0.0, cx, cy, r);
        defer c.cairo_pattern_destroy(sphere);
        c.cairo_pattern_add_color_stop_rgba(sphere, 0.0, outline_color[0], outline_color[1], outline_color[2], 0.18);
        c.cairo_pattern_add_color_stop_rgba(sphere, 0.55, outline_color[0], outline_color[1], outline_color[2], 0.05);
        c.cairo_pattern_add_color_stop_rgba(sphere, 1.0, 0.0, 0.0, 0.0, 0.35);
        c.cairo_arc(cr, cx, cy, r, 0, 2 * std.math.pi);
        c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], outline_color[3]);
        c.cairo_fill(cr);
        c.cairo_set_source(cr, sphere);
        c.cairo_arc(cr, cx, cy, r, 0, 2 * std.math.pi);
        c.cairo_fill(cr);
    }

    // Inner rim border glow: a subtle ring of the border color just inside the outline.
    const rim = c.cairo_pattern_create_radial(cx, cy, r * 0.78, cx, cy, r);
    defer c.cairo_pattern_destroy(rim);
    c.cairo_pattern_add_color_stop_rgba(rim, 0.0, outline_color[0], outline_color[1], outline_color[2], 0.0);
    c.cairo_pattern_add_color_stop_rgba(rim, 0.75, outline_color[0], outline_color[1], outline_color[2], 0.0);
    c.cairo_pattern_add_color_stop_rgba(rim, 1.0, outline_color[0], outline_color[1], outline_color[2], 0.55);
    c.cairo_set_source(cr, rim);
    c.cairo_arc(cr, cx, cy, r, 0, 2 * std.math.pi);
    c.cairo_fill(cr);

    // Rim outline.
    c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], outline_color[3]);
    c.cairo_set_line_width(cr, 2.0);
    c.cairo_arc(cr, cx, cy, r, 0, 2 * std.math.pi);
    c.cairo_stroke(cr);

    c.cairo_restore(cr);
}

pub fn renderMoonForBox(cr: *c.cairo_t, box: anytype, top_padding: i32, phase: Phase, outline_color: [4]f64, shadow_color: [4]f64) void {
    const box_w: f64 = @floatFromInt(box.width);
    const cx = box.x + box.width / 2;
    const cy = box.y + top_padding + @divTrunc(box.height - top_padding, 4);
    const r: f64 = @min(box_w / 2.8, @as(f64, @floatFromInt(@divTrunc(box.height - top_padding, 5))));
    renderMoon(cr, @floatFromInt(cx), @floatFromInt(cy), r, phase, outline_color, shadow_color);
}

/// Write a 5-phase moon test strip to the provided PNG path using Cairo.
pub fn renderMoonTestStrip(path: []const u8, outline_color: [4]f64, shadow_color: [4]f64) !void {
    const w = 900;
    const h = 140;
    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, w, h) orelse return error.CairoSurfaceFailed;
    defer c.cairo_surface_destroy(surface);
    const cr = c.cairo_create(surface) orelse return error.CairoCreateFailed;
    defer c.cairo_destroy(cr);

    c.cairo_set_source_rgba(cr, 0.13, 0.14, 0.15, 1.0);
    c.cairo_paint(cr);

    const phases = [_]f64{ 0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875 };
    const step: f64 = @as(f64, w) / phases.len;
    for (phases, 0..) |frac, i| {
        const px = step * @as(f64, @floatFromInt(i)) + step / 2.0;
        const py = @as(f64, h) / 2.0;
        const r = 48.0;
        const age = frac * synodic_month;
        const illum = 0.5 * (1.0 - std.math.cos(frac * 2.0 * std.math.pi));
        const ph: Phase = .{ .illumination = illum, .age = age, .name = phaseName(frac) };
        renderMoon(cr, px, py, r, ph, outline_color, shadow_color);

    }

    _ = c.cairo_surface_write_to_png(surface, path.ptr);
}
