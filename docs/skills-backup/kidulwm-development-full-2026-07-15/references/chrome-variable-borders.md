# Variable-thickness chamfered borders in KidulWM

Session: 2026-07-11. Goal: keep chamfer diagonal legs thick while making straight sides thinner.

## Core idea

A chamfered window frame has two kinds of edges:

1. **Straight edges** (top, bottom, left, right) — thickness controlled by `border_width`.
2. **Chamfer diagonals** (the four 45° cuts at the corners) — thickness controlled by `chamfer_border_width`.

If the inner cutout is just a scaled copy of the outer shape, both edge types share the same perpendicular inset and cannot be tuned independently.

## Geometry

For `.cut` chamfers, build the frame as an even-odd filled ring:

- Outer polygon: the familiar chamfered rectangle.
- Inner polygon: each edge moved inward by its own thickness:
  - Straight edges move inward by `border_width` perpendicularly.
  - Diagonal edges move inward by `chamfer_border_width` perpendicularly.
- Inner vertices are recomputed as intersections of adjacent offset edges.

Zig helpers added to `src/render/chrome.zig`:

```zig
const EdgeOffset = struct { a: [2]f64, b: [2]f64 };

fn inwardOffsetEdge(p1: [2]f64, p2: [2]f64, inset: f64) EdgeOffset { ... }
fn lineIntersection(a1: [2]f64, a2: [2]f64, b1: [2]f64, b2: [2]f64) [2]f64 { ... }
fn chamferRing(cr: *c.cairo_t, w: f64, h: f64, depth: f64, straight_inset: f64, chamfer_inset: f64) void { ... }
```

Then fill:

```zig
chamferRing(cr, w, h, depth, border, chamfer_border);
c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_EVEN_ODD);
setSource(cr, border_color, 1.0);
c.cairo_fill(cr);
```

## Theme tokens

In `src/core/style.zig`:

```zig
border_width: f32 = 4.0,
chamfer_border_width: f32 = 6.0,
```

Wire both into `applyTheme` in `src/server.zig`, and add a `set_theme` branch in `src/kidulwm-control.zig` so the CLI actually sends the `set_theme` request (otherwise it returns `UnknownCommand`).

## Edge trimming

When trimming hidden/shared edges, the strip width must account for the larger border:

```zig
const clear_w = @min(w / 2.0, depth + @max(border, chamfer_border) + 1.0);
```

## Verification pitfall

Small differences (1-2 px at 1920x1080) can be invisible to vision tools and even to human eyes in a full screenshot. Before concluding that a variable-thickness change has no effect, first use an exaggerated gap such as `border_width=20` with `chamfer_border_width=2` to prove the code path is active. Once the extreme case is visible, tune back to subtle values and inspect zoomed crops of a single chamfer corner.

## Verification recipe

1. `zig build && zig build test --summary all`
2. Offline VM swap or restart KidulWM.
3. Launch Ghostty with `GTK_CSD=0 GDK_DEBUG=no-csd`.
4. Set values live:

```bash
ssh -p 2222 kidul@127.0.0.1 'WAYLAND_DISPLAY=wayland-1 kidulwm-control set_theme border_width 2'
ssh -p 2222 kidul@127.0.0.1 'WAYLAND_DISPLAY=wayland-1 kidulwm-control set_theme chamfer_border_width 3'
```

5. QEMU monitor screendump (see `references/visual-verification.md`).

## Trade-off

The inner corners where straight and diagonal thicknesses differ will not be a perfect parallel chamfer; they become slightly squared/stepped. This is usually acceptable visually if the straight side is only modestly thinner than the chamfer.

Related: `references/compositor-chrome-buffers.md`, `references/chrome-chamfer-inset-2026-07-11.md`, `references/chrome-iteration-lessons.md`.
