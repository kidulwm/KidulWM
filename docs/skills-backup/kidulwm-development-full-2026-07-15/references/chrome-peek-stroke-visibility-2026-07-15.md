# Peek-glass colored border visibility — 2026-07-15

## Symptom

The black glass overlay fills the peek, but a colored border around it is invisible, and changing the border color has no visible effect.

## Root causes found

1. **Scene order.** If chrome is inside the per-window scene tree, GTK4/libadwaita CSD draws its own frame and shadows on top. Move `chrome_tree` to a direct child of `server.scene.tree` and call `node.raiseToTop()` so it is above every window. Position it at the window's world coordinates each frame.
2. **Edge-trim width.** The hidden-edge clear used `clear_w = depth + border + 1.0`. With `corner_depth` still nonzero even when `corner_style = .none`, this erased ~17 px of the visible seam. For square-corner peeks use `clear_w = border + 1.0` or disable the trim entirely.
3. **Blending mode.** Drawing the stroke with `CAIRO_OPERATOR_OVER` blends the stroke into the near-opaque black glass and makes it disappear. Use `CAIRO_OPERATOR_SOURCE` for the edge stroke so the color is written opaquely.

## Final working render order for peeks

1. Clear the full wrapper to transparent.
2. Draw black glass gradient into the wrapper bounds, offset only for the single hidden edge.
3. Fill the background mask + original border ring with `EVEN_ODD` fill rule.
4. Draw the new colored stroke with `CAIRO_OPERATOR_SOURCE` just inside the wrapper bounds.
5. Clear only the hidden edge(s) with a narrow strip.

## Code anchor (`src/render/chrome.zig`)

```zig
const outer_border_w: f64 = 2.0 * @as(f64, @floatFromInt(s));
c.cairo_set_line_width(cr, outer_border_w);
setSource(cr, style.peek_glass_border_color, 1.0);
c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
c.cairo_rectangle(cr, outer_border_w / 2.0, outer_border_w / 2.0, w - outer_border_w, h - outer_border_w);
c.cairo_stroke(cr);
c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);
```

## Theme token

`peek_glass_border_color` lives in `src/core/style.zig` and is meant for users to tune.

## Verification

Use a bright diagnostic color first (yellow or bright red). If it still does not appear, the overlay is not on the root scene tree. If a bright color appears but the normal color does not, the normal color is too dark against the glass or the blending mode is wrong.
