const std = @import("std");
const c = @import("dm").c;
const Style = @import("../core/style.zig").Style;
const slidedeck = @import("../core/slidedeck.zig");
const chrome_renderer = @import("chrome.zig");

/// One tile in the place-card grid: which deck slide, and its rect inside
/// the card (card-local coords, pre-scale).
pub const Tile = struct {
    slide_index: usize,
    x: i32,
    y: i32,
    w: u32,
    h: u32,
    parked: bool,
    cursor: bool,
};

/// Compute the tile layout for a deck about to be shown in the sentinel
/// overview slide. Same grid math as the lens (band = focused slide area,
/// 2 cols, recency order, parked bottom row) but expressed card-local and
/// returned as a flat list the caller can hit-test against.
pub fn layoutTiles(deck: *slidedeck.SlideDeck, out: []Tile, cursor_recency: usize) usize {
    const n = deck.slides.items.len;
    var count: usize = 0;
    for (0..n) |i| {
        if (count >= out.len) break;
        const cursor_idx = deck.slideIndexAtRecency(cursor_recency);
        const r = deck.overviewTargetForSlideInflated(i, cursor_idx);
        if (r.width == 0) continue;
        const rec = deck.recencyPos(i);
        out[count] = .{
            .slide_index = i,
            .x = r.x,
            .y = r.y,
            .w = r.width,
            .h = r.height,
            .parked = deck.slides.items[i].parked,
            .cursor = rec != null and rec.? == cursor_recency,
        };
        count += 1;
    }
    return count;
}

/// Render the card background: a dark rounded panel filling the slide area,
/// with the single-border gold ring drawn around the cursor tile (the debug
/// ring, proven shape — border chrome lives INSIDE the card now, same
/// coordinate space as the tiles).
pub fn renderCard(
    style_: Style,
    width: i32,
    height: i32,
    scale: u32,
    tiles: []const Tile,
) ?*c.cairo_surface_t {
    if (width <= 0 or height <= 0) return null;
    const s: i32 = @max(1, @as(i32, @intCast(scale)));
    const bw: i32 = width * s;
    const bh: i32 = height * s;
    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, bw, bh) orelse return null;
    const cr = c.cairo_create(surface) orelse {
        c.cairo_surface_destroy(surface);
        return null;
    };
    defer c.cairo_destroy(cr);

    // Transparent start — the compositor background/wallpaper shows around
    // the card panel edges if the slide area is inset.
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_paint(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    const w: f64 = @floatFromInt(bw);
    const h: f64 = @floatFromInt(bh);

    // Card panel: near-black rounded rect over the full slide.
    const panel = style_.color_card_mat.toF64();
    c.cairo_set_source_rgba(cr, panel[0], panel[1], panel[2], 0.92);
    roundedRect(cr, 0, 0, w, h, style_.card_mat_depth * @as(f64, @floatFromInt(s)));
    c.cairo_fill(cr);

    // Cursor tile ring: single gold stroke (debug-step ring, same shape as
    // renderMiniRing but drawn card-local where it CAN'T miss its tile).
    const sf: f64 = @floatFromInt(s);
    const line_w: f64 = @max(2.0, @as(f64, style_.border_width) * sf * 2.0);
    for (tiles) |t| {
        if (!t.cursor) continue;
        const gold = style_.color_gold.toF64();
        c.cairo_set_source_rgba(cr, gold[0], gold[1], gold[2], 1.0);
        c.cairo_set_line_width(cr, line_w);
        const inset = line_w * 0.5;
        roundedRect(
            cr,
            @as(f64, @floatFromInt(t.x)) * sf + inset,
            @as(f64, @floatFromInt(t.y)) * sf + inset,
            @as(f64, @floatFromInt(t.w)) * sf - line_w,
            @as(f64, @floatFromInt(t.h)) * sf - line_w,
            style_.corner_depth * sf * 0.5,
        );
        c.cairo_stroke(cr);
    }

    // Parked tiles get a subtle dim wash so they read as "asleep" even
    // before any per-mini styling pass.
    for (tiles) |t| {
        if (!t.parked) continue;
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.45);
        roundedRect(
            cr,
            @as(f64, @floatFromInt(t.x)) * sf,
            @as(f64, @floatFromInt(t.y)) * sf,
            @as(f64, @floatFromInt(t.w)) * sf,
            @as(f64, @floatFromInt(t.h)) * sf,
            style_.corner_depth * sf * 0.5,
        );
        c.cairo_fill(cr);
    }

    return surface;
}

fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
    const radius = @min(r, w / 2.0, h / 2.0);
    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, x + w - radius, y + radius, radius, -std.math.pi / 2.0, 0.0);
    c.cairo_arc(cr, x + w - radius, y + h - radius, radius, 0.0, std.math.pi / 2.0);
    c.cairo_arc(cr, x + radius, y + h - radius, radius, std.math.pi / 2.0, std.math.pi);
    c.cairo_arc(cr, x + radius, y + radius, radius, std.math.pi, 3.0 * std.math.pi / 2.0);
    c.cairo_close_path(cr);
}

pub fn surfacePixels(surface: *c.cairo_surface_t) struct { pixels: []const u8, width: i32, height: i32, stride: i32 } {
    const stride = c.cairo_image_surface_get_stride(surface);
    const width = c.cairo_image_surface_get_width(surface);
    const height = c.cairo_image_surface_get_height(surface);
    const data = c.cairo_image_surface_get_data(surface);
    const bytes = @as([*]u8, @ptrCast(data))[0..@intCast(stride * height)];
    return .{ .pixels = bytes, .width = width, .height = height, .stride = stride };
}
