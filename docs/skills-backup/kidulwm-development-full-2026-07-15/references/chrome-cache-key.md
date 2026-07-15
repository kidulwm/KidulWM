# Chrome overlay cache key

`Window.updateChrome` in `src/window.zig` builds a Cairo overlay for each window and caches it to avoid redrawing every layout pass.

## Fields that must be in the cache key

The cached state must include anything that changes the **appearance of the overlay**, not just its size or colour:

- width / height
- `focused` (changes border colour and focus glow)
- output scale
- `chrome_style_generation`
- **`EdgeMode`** — which edges/corners are drawn vs cleared

## Failure mode when EdgeMode is omitted

- A window changing from `right_peek` to `left_peek` has the same logical size, so the old overlay surface is reused.
- The old overlay still has the previous hidden-edge clear strips and corner shapes.
- Visible symptom: a peek window shows stale rounded background, missing border on the newly visible seam edge, or wrong corner shaping.
- Scrolling/forcing another redraw eventually replaces it, confirming stale cache.

## Fix pattern

- Store the last used `EdgeMode` on the window.
- Compare with the requested `EdgeMode` in the "same" check.
- Regenerate if it changed.
- For Zig structs, add an explicit `eql` helper since `==` is not automatically allowed on plain structs.
