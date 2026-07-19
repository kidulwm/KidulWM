const std = @import("std");
const c = @import("../dm/c.zig").c;

/// Moon phase descriptor.
pub const Phase = struct {
    /// Fraction illuminated, 0..1.
    illumination: f64,
    /// Days since new moon, 0..29.53.
    age: f64,
    /// Phase name.
    name: []const u8,
};

/// Reference new moon: 2000-01-06 18:14 UTC (known new moon).
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

    // Illumination follows 0.5 * (1 - cos(2*pi*frac)) for waxing,
    // but matches visual fraction of lit disk.
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
/// phase_frac is 0..1 (0 = new, 0.5 = full).
/// Color should be the border/focus color for the outline and lit part.
pub fn renderMoon(cr: *c.cairo_t, cx: f64, cy: f64, r: f64, phase: Phase, outline_color: [4]f64, shadow_color: [4]f64) void {
    const frac = phase.age / synodic_month;
    const lit_right = frac < 0.5;

    // Clip to the moon disk.
    c.cairo_save(cr);
    c.cairo_arc(cr, cx, cy, r, 0, 2 * std.math.pi);
    c.cairo_clip(cr);

    // Fill the dark side.
    c.cairo_set_source_rgba(cr, shadow_color[0], shadow_color[1], shadow_color[2], shadow_color[3]);
    c.cairo_paint(cr);

    // Draw lit side: we model the terminator as an ellipse whose x-radius
    // varies from -r to +r.  At new moon it's -r (all dark), full moon +r
    // (all lit), quarters 0 (half lit).
    const t = if (frac <= 0.5) 1.0 - 4.0 * frac else 4.0 * (frac - 0.5) - 1.0;
    const rx = t * r;

    c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], outline_color[3]);
    c.cairo_arc(cr, cx, cy, r, 0, 2 * std.math.pi);
    c.cairo_fill(cr);

    // Carve out the dark half-ellipse with shadow color.
    c.cairo_set_source_rgba(cr, shadow_color[0], shadow_color[1], shadow_color[2], shadow_color[3]);
    c.cairo_save(cr);
    c.cairo_translate(cr, cx, cy);
    // For first half, shadow is right for waxing crescent etc; the math below
    // carves the appropriate ellipse half.
    if (lit_right) {
        c.cairo_scale(cr, rx, r);
        c.cairo_arc(cr, (if (rx >= 0) @as(f64, 1.0) else @as(f64, -1.0)), 0, 1, 0, 2 * std.math.pi);
    } else {
        c.cairo_scale(cr, -rx, r);
        c.cairo_arc(cr, (if (-rx >= 0) @as(f64, 1.0) else @as(f64, -1.0)), 0, 1, 0, 2 * std.math.pi);
    }
    c.cairo_fill(cr);
    c.cairo_restore(cr);

    c.cairo_restore(cr);

    // Outline.
    c.cairo_set_source_rgba(cr, outline_color[0], outline_color[1], outline_color[2], outline_color[3]);
    c.cairo_set_line_width(cr, 1.5);
    c.cairo_arc(cr, cx, cy, r, 0, 2 * std.math.pi);
    c.cairo_stroke(cr);
}
