# Chrome mask inner shape: follow the content rectangle, not the border ring

File: `src/render/chrome.zig`

## Problem

For `.cut` (chamfered) windows, the chrome overlay originally masked the region between the full window bounds and a *chamfered* inner polygon. Because the inner polygon was chamfered, the transparent interior followed the chamfered shape and the client surface was visible in the triangular cut-corner regions. When the client's own background colour differed from the compositor background, those triangles showed the client background "bleeding" past the chamfered border.

## Fix

The mask must treat the **content area** as a rectangle (inset by `border_width` from the wrapper), while the **border ring** keeps its edge-aware chamfered outer path and parallel-offset chamfered inner polygon.

Cairo recipe for `.cut`:

```zig
// 1. Background mask: full bounds minus rectangular content area.
squareRect(cr, 0.0, 0.0, w, h);
squareRect(cr, border, border, w - border * 2.0, h - border * 2.0);
c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_EVEN_ODD);
setSource(cr, style.color_background, 1.0);
c.cairo_fill(cr);

// 2. Border ring: chamfered outer minus parallel-offset chamfered inner.
var inner: [8][2]f64 = undefined;
const inner_count = chamferInnerPolygon(w, h, depths, border, chamfer_border, &inner);
chamferRect(cr, 0.0, 0.0, w, h, depths);
drawPolygon(cr, inner[0..inner_count]);
c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_EVEN_ODD);
setSource(cr, border_color, 1.0);
c.cairo_fill(cr);
c.cairo_set_fill_rule(cr, c.CAIRO_FILL_RULE_WINDING);
```

The rectangular content hole stays transparent so the client shows through only inside the straight border edges. The chamfer triangles are filled with the compositor background colour, giving KidulWM full ownership of the corner shape.

## General rule

| Style | Mask inner shape | Border ring inner shape |
|---|---|---|
| `.cut` | Rectangle inset by `border_width` | Parallel-offset chamfered polygon |
| `.classic` | Rounded rectangle inset by `border_width` | Parallel-offset rounded polygon |
| `.none` | Plain rectangle inset by `border_width` | Plain rectangle inset by `border_width` |

## Why not clip the surface instead?

`wlr_scene_subsurface_tree_set_clip()` is rectangular and would work for `.cut`, but it clips the client to the content rectangle in surface-local coordinates and must be reapplied on every layout and commit. Keeping the ownership in the compositor-drawn overlay is simpler: the overlay is regenerated only when size, focus, edges, scale, or style generation change, and the `bg_rect` underneath covers any transient gaps.

## Verification

Deploy to the VM, spawn Ghostty with `GTK_CSD=0 GDK_DEBUG=no-csd`, capture `screendump`, and inspect the chamfered corners. The triangles should match the desktop/compositor background (`#222425`), not the terminal's own background.
