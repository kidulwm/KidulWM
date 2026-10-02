// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const c = @import("dm").c;
const style = @import("../core/style.zig");

/// Mat drawer signature. Implementations receive a cairo context already
/// cleared; they should paint the card body + rim and set a clip to the
/// interior (inset by half the border width) so callers can paint widgets.
pub const MatDrawer = *const fn (
    cr: *c.cairo_t,
    tstyle: style.Style,
    w: f64,
    h: f64,
) void;

/// Registry of named card mat styles.
pub const Registry = struct {
    entries: []const Entry,

    pub const Entry = struct {
        name: []const u8,
        drawer: MatDrawer,
    };

    const default_entries = [_]Entry{
        .{ .name = "cinematic_shadow", .drawer = drawCinematicShadow },
        .{ .name = "gallery_mat", .drawer = drawGalleryMat },
        .{ .name = "deep_float", .drawer = drawDeepFloat },
        .{ .name = "paper_edge", .drawer = drawPaperEdge },
        .{ .name = "black_glass_halo", .drawer = drawBlackGlassHalo },
    };

    pub const default: Registry = .{ .entries = &default_entries };

    pub fn find(self: Registry, name: []const u8) ?Entry {
        for (self.entries) |e| {
            if (std.mem.eql(u8, e.name, name)) return e;
        }
        return null;
    }

    pub fn drawNamed(self: Registry, cr: *c.cairo_t, style_: style.Style, w: f64, h: f64) void {
        const name = std.enums.tagName(style.Style.CardMatStyle, style_.card_mat_style) orelse "black_glass_halo";
        if (self.find(name)) |e| {
            e.drawer(cr, style_, w, h);
        } else {
            drawBlackGlassHalo(cr, style_, w, h);
        }
    }
};

fn cornerDepth(tstyle: style.Style, w: f64, h: f64) f64 {
    return @min(@as(f64, tstyle.card_mat_depth), @min(w, h) * 0.05);
}

fn outlinePath(cr: *c.cairo_t, tstyle: style.Style, x: f64, y: f64, w: f64, h: f64, depth: f64) void {
    switch (tstyle.corner_style) {
        .round => roundedRect(cr, x, y, w, h, depth),
        .chamfer => chamferedRect(cr, x, y, w, h, depth),
        .square => squareRect(cr, x, y, w, h),
    }
}

fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
    const radius = @min(r, w / 2.0, h / 2.0);
    if (radius <= 0.0) {
        c.cairo_rectangle(cr, x, y, w, h);
        return;
    }
    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, x + w - radius, y + radius, radius, -std.math.pi / 2.0, 0.0);
    c.cairo_arc(cr, x + w - radius, y + h - radius, radius, 0.0, std.math.pi / 2.0);
    c.cairo_arc(cr, x + radius, y + h - radius, radius, std.math.pi / 2.0, std.math.pi);
    c.cairo_arc(cr, x + radius, y + radius, radius, std.math.pi, 3.0 * std.math.pi / 2.0);
    c.cairo_close_path(cr);
}

fn chamferedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, ch: f64) void {
    const chamfer = @min(ch, w / 2.0, h / 2.0);
    c.cairo_new_sub_path(cr);
    c.cairo_move_to(cr, x + chamfer, y);
    c.cairo_line_to(cr, x + w - chamfer, y);
    c.cairo_line_to(cr, x + w, y + chamfer);
    c.cairo_line_to(cr, x + w, y + h - chamfer);
    c.cairo_line_to(cr, x + w - chamfer, y + h);
    c.cairo_line_to(cr, x + chamfer, y + h);
    c.cairo_line_to(cr, x, y + h - chamfer);
    c.cairo_line_to(cr, x, y + chamfer);
    c.cairo_close_path(cr);
}

fn squareRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64) void {
    c.cairo_rectangle(cr, x, y, w, h);
}

fn insetForClip(tstyle: style.Style) f64 {
    return @max(1.0, tstyle.card_mat_border_width * 0.5);
}

fn clipInterior(cr: *c.cairo_t, tstyle: style.Style, w: f64, h: f64) void {
    const inset = insetForClip(tstyle);
    const d = cornerDepth(tstyle, w, h);
    outlinePath(cr, tstyle, inset, inset, w - 2.0 * inset, h - 2.0 * inset, @max(0.0, d - inset));
    c.cairo_clip(cr);
}

// ------------------------------------------------------------------
// Style 1: cinematic_shadow
// A bold, wide shadow on the right/bottom that makes the card lift off
// the slide. Body is the card mat colour at the pinned 91% opacity.
// ------------------------------------------------------------------
fn drawCinematicShadow(cr: *c.cairo_t, tstyle: style.Style, w: f64, h: f64) void {
    const bg = tstyle.color_card_mat;
    const rim = tstyle.color_card_border;
    const d = cornerDepth(tstyle, w, h);
    const sw = tstyle.card_mat_border_width;
    const bg4 = bg.toF64();
    const rim4 = rim.toF64();

    c.cairo_save(cr);
    // Drop shadow (soft, far).
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);
    c.cairo_new_sub_path(cr);
    const sx = 24.0;
    const sy = 28.0;
    outlinePath(cr, tstyle, sx, sy, w, h, d);
    const shadow = c.cairo_pattern_create_rgba(0.0, 0.0, 0.0, 0.55).?;
    c.cairo_set_source(cr, shadow);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(shadow);
    c.cairo_restore(cr);

    // Solid body.
    outlinePath(cr, tstyle, 0.0, 0.0, w, h, d);
    c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], 0.91);
    c.cairo_fill(cr);

    // Rim.
    outlinePath(cr, tstyle, 0.0, 0.0, w, h, d);
    c.cairo_set_source_rgba(cr, rim4[0], rim4[1], rim4[2], rim4[3]);
    c.cairo_set_line_width(cr, sw);
    c.cairo_stroke(cr);

    clipInterior(cr, tstyle, w, h);
}

// ------------------------------------------------------------------
// Style 2: gallery_mat
// Museum-card look: card body is lighter and more opaque, a thin inner
// bevel line, and a 2-step mat lip on the inside edge.
// ------------------------------------------------------------------
fn drawGalleryMat(cr: *c.cairo_t, tstyle: style.Style, w: f64, h: f64) void {
    const bg = tstyle.color_card_mat;
    const rim = tstyle.color_card_border;
    const d = cornerDepth(tstyle, w, h);
    const sw = tstyle.card_mat_border_width;
    const bg4 = bg.toF64();
    const rim4 = rim.toF64();

    // Body at 91% opacity with a subtle warm tint lifted from the border.
    outlinePath(cr, tstyle, 0.0, 0.0, w, h, d);
    c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], 0.91);
    c.cairo_fill(cr);

    // Outer rim.
    outlinePath(cr, tstyle, 0.0, 0.0, w, h, d);
    c.cairo_set_source_rgba(cr, rim4[0], rim4[1], rim4[2], rim4[3]);
    c.cairo_set_line_width(cr, sw);
    c.cairo_stroke(cr);

    // Inner mat step: a second rounded rectangle inset ~12 px creates the
    // appearance of a raised mat board inside the frame.
    const inset = @min(12.0, @min(w, h) * 0.08);
    outlinePath(cr, tstyle, inset, inset, w - 2.0 * inset, h - 2.0 * inset, @max(0.0, d - inset * 0.5));
    c.cairo_set_source_rgba(cr, rim4[0], rim4[1], rim4[2], 0.18);
    c.cairo_set_line_width(cr, 1.0);
    c.cairo_stroke(cr);

    clipInterior(cr, tstyle, w, h);
}

// ------------------------------------------------------------------
// Style 3: deep_float
// Heavy vignette inside the border so the edges sink back while the
// center pops forward. A thin bright rim on top/left sells the depth.
// ------------------------------------------------------------------
fn drawDeepFloat(cr: *c.cairo_t, tstyle: style.Style, w: f64, h: f64) void {
    const bg = tstyle.color_card_mat;
    const rim = tstyle.color_card_border;
    const d = cornerDepth(tstyle, w, h);
    const sw = tstyle.card_mat_border_width;
    const bg4 = bg.toF64();
    const rim4 = rim.toF64();

    // Body.
    outlinePath(cr, tstyle, 0.0, 0.0, w, h, d);
    c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], 0.91);
    c.cairo_fill(cr);

    // Inner vignette.
    c.cairo_save(cr);
    outlinePath(cr, tstyle, sw, sw, w - 2.0 * sw, h - 2.0 * sw, @max(0.0, d - sw));
    c.cairo_clip(cr);
    const vig = c.cairo_pattern_create_radial(w * 0.5, h * 0.45, w * 0.15, w * 0.5, h * 0.5, w * 0.75).?;
    c.cairo_pattern_add_color_stop_rgba(vig, 0.0, 0.0, 0.0, 0.0, 0.00);
    c.cairo_pattern_add_color_stop_rgba(vig, 0.55, 0.0, 0.0, 0.0, 0.18);
    c.cairo_pattern_add_color_stop_rgba(vig, 1.0, 0.0, 0.0, 0.0, 0.48);
    c.cairo_set_source(cr, vig);
    c.cairo_paint(cr);
    c.cairo_pattern_destroy(vig);
    c.cairo_restore(cr);

    // Soft top-left light bevel.
    c.cairo_save(cr);
    outlinePath(cr, tstyle, sw * 0.5, sw * 0.5, w - sw, h - sw, @max(0.0, d - sw * 0.5));
    c.cairo_clip(cr);
    const glow = c.cairo_pattern_create_linear(0.0, 0.0, d * 1.5, d * 1.5).?;
    c.cairo_pattern_add_color_stop_rgba(glow, 0.0, 1.0, 1.0, 1.0, 0.18);
    c.cairo_pattern_add_color_stop_rgba(glow, 1.0, 1.0, 1.0, 1.0, 0.0);
    c.cairo_set_source(cr, glow);
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, 0.0, 0.0);
    c.cairo_line_to(cr, d * 3.0, 0.0);
    c.cairo_line_to(cr, 0.0, d * 3.0);
    c.cairo_close_path(cr);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(glow);
    c.cairo_restore(cr);

    // Outer rim.
    outlinePath(cr, tstyle, 0.0, 0.0, w, h, d);
    c.cairo_set_source_rgba(cr, rim4[0], rim4[1], rim4[2], rim4[3]);
    c.cairo_set_line_width(cr, sw);
    c.cairo_stroke(cr);

    clipInterior(cr, tstyle, w, h);
}

// ------------------------------------------------------------------
// Style 4: paper_edge
// Flat, layered paper strips around the perimeter giving a die-cut
// relief with no heavy drop shadow.
// ------------------------------------------------------------------
fn drawPaperEdge(cr: *c.cairo_t, tstyle: style.Style, w: f64, h: f64) void {
    const bg = tstyle.color_card_mat;
    const rim = tstyle.color_card_border;
    const d = cornerDepth(tstyle, w, h);
    const sw = tstyle.card_mat_border_width;
    const bg4 = bg.toF64();
    const rim4 = rim.toF64();

    // Layered paper strips around the edge (top, left, right, bottom).
    const strip = @min(10.0, @min(w, h) * 0.05);
    const steps = [_]struct { dx: f64, dy: f64, a: f64 }{
        .{ .dx = 0.0, .dy = 0.0, .a = 0.22 },
        .{ .dx = 3.0, .dy = 3.0, .a = 0.18 },
        .{ .dx = 6.0, .dy = 6.0, .a = 0.12 },
    };
    for (steps) |s| {
        outlinePath(cr, tstyle, s.dx, s.dy, w, h, d);
        c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], s.a);
        c.cairo_fill(cr);
    }

    // Body.
    outlinePath(cr, tstyle, 0.0, 0.0, w, h, d);
    c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], 0.91);
    c.cairo_fill(cr);

    // Inner subtle rim.
    outlinePath(cr, tstyle, strip, strip, w - 2.0 * strip, h - 2.0 * strip, @max(0.0, d - strip));
    c.cairo_set_source_rgba(cr, rim4[0], rim4[1], rim4[2], 0.22);
    c.cairo_set_line_width(cr, 1.0);
    c.cairo_stroke(cr);

    // Outer rim.
    outlinePath(cr, tstyle, 0.0, 0.0, w, h, d);
    c.cairo_set_source_rgba(cr, rim4[0], rim4[1], rim4[2], rim4[3]);
    c.cairo_set_line_width(cr, sw);
    c.cairo_stroke(cr);

    clipInterior(cr, tstyle, w, h);
}

// ------------------------------------------------------------------
// Style 5: black_glass_halo (original)
// Black glass body with halo vignette + bevel highlights, preserving the
// existing look. This is the default.
// ------------------------------------------------------------------
fn drawBlackGlassHalo(cr: *c.cairo_t, tstyle: style.Style, w: f64, h: f64) void {
    const bg = tstyle.color_card_mat;
    const rim = tstyle.color_card_border;
    const d = cornerDepth(tstyle, w, h);
    const sw = tstyle.card_mat_border_width;
    const bg4 = bg.toF64();
    const rim4 = rim.toF64();

    // 1. Solid body fill.
    outlinePath(cr, tstyle, 0.0, 0.0, w, h, d);
    c.cairo_set_source_rgba(cr, bg4[0], bg4[1], bg4[2], 0.91);
    c.cairo_fill(cr);

    // 2. Inner rim lighting.
    c.cairo_save(cr);
    outlinePath(cr, tstyle, sw, sw, w - 2.0 * sw, h - 2.0 * sw, @max(0.0, d - sw));
    c.cairo_clip(cr);

    const glow_w: f64 = 3.0;
    const tl = c.cairo_pattern_create_linear(0.0, 0.0, glow_w, glow_w).?;
    c.cairo_pattern_add_color_stop_rgba(tl, 0.0, 1.0, 1.0, 1.0, 0.22);
    c.cairo_pattern_add_color_stop_rgba(tl, 1.0, 1.0, 1.0, 1.0, 0.00);
    c.cairo_set_source(cr, tl);
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, 0.0, 0.0);
    c.cairo_line_to(cr, glow_w * 2.0, 0.0);
    c.cairo_line_to(cr, 0.0, glow_w * 2.0);
    c.cairo_close_path(cr);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(tl);

    const br = c.cairo_pattern_create_linear(w - glow_w, h - glow_w, w, h).?;
    c.cairo_pattern_add_color_stop_rgba(br, 0.0, 0.0, 0.0, 0.0, 0.00);
    c.cairo_pattern_add_color_stop_rgba(br, 1.0, 0.0, 0.0, 0.0, 0.45);
    c.cairo_set_source(cr, br);
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, w, h);
    c.cairo_line_to(cr, w - glow_w * 2.0, h);
    c.cairo_line_to(cr, w, h - glow_w * 2.0);
    c.cairo_close_path(cr);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(br);

    c.cairo_restore(cr);

    // 3. Outer card rim.
    outlinePath(cr, tstyle, 0.0, 0.0, w, h, d);
    c.cairo_set_source_rgba(cr, rim4[0], rim4[1], rim4[2], rim4[3]);
    c.cairo_set_line_width(cr, sw);
    c.cairo_stroke(cr);

    clipInterior(cr, tstyle, w, h);
}

/// Draw the drop shadow cast by a card onto the focused slide behind it.
/// The shadow occupies the gap between the focused-window box and the card.
/// The caller clears the surface.
pub fn drawCardShadow(
    cr: *c.cairo_t,
    tstyle: style.Style,
    box_w: f64,
    box_h: f64,
    card_w: f64,
    card_h: f64,
) void {
    // Disabled: the shadow around cards has been turned off.
    _ = cr; _ = tstyle; _ = box_w; _ = box_h; _ = card_w; _ = card_h;
}

