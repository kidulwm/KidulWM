# Chrome / border geometry

Single source of truth for KidulWM chamfered (`cut`) and rounded (`classic`)
window chrome. Last verified: chrome-2x branch, commit `b970fe9`.

## Tokens

All live in `src/core/style.zig`.

- `border_width` — perpendicular thickness of straight top/bottom/left/right edges.
- `chamfer_border_width` — perpendicular thickness of the 45° diagonal legs at
  `.cut` corners. Usually set slightly thicker than `border_width` so the human
  eye reads the legs as equal (e.g. `3.0` vs `3.5`).
- `corner_depth` — depth of the chamfer cut from each corner.
- `corner_style` — `.cut`, `.classic`, or `.none`.

## How `.cut` (chamfer) works

`renderChrome()` in `src/render/chrome.zig` builds the window frame as a ring:

1. Compute an outer chamfer polygon with per-corner depths.
2. Compute a matching inner polygon that is a parallel offset of the outer one:
   - straight edges move inward by `border_width`
   - 45° diagonal legs move inward by `chamfer_border_width`
   - adjacent offset edges intersect to give the inner vertices
3. Fill the ring (`outer - inner`) with the border colour.
4. Fill the outside area with the compositor background colour to hide client
   rounded corners / shadows.

Key rule: the background mask must cover the **entire window bounds** (use
`squareRect(0, 0, w, h)`), while the border ring uses the edge-aware chamfered
outer path. This hides client rounded corners / shadows in the cut-off triangles
without producing background-coloured wedges.

Because side-peek chrome is a **full-window overlay** positioned off-screen,
the hidden-edge clear strips fall outside the visible sliver and do not clip the
top/bottom borders. Do not shrink the chrome buffer to the visible sliver.

## Edge-aware corners

A corner gets a chamfer only if **both** adjacent edges are visible. If one edge
is hidden (shared seam / off-screen edge), that corner is square so the remaining
straight border runs cleanly to the seam.

Mapping in `src/render/chrome.zig::ChamferDepths.fromEdgeMode`:

| window role | top | right | bottom | left | chamfered corners | square corners |
|-------------|-----|-------|--------|------|-------------------|----------------|
| focused     | yes | yes   | yes    | yes  | all four          | none           |
| `left_peek` | yes | yes   | yes    | no   | TL, TR, BR        | BL             |
| `right_peek`| yes | no    | yes    | yes  | TL, BL, BR        | TR             |

The `EdgeMode` is set in `src/server.zig`; side peeks expose the seam-adjacent
edge and hide the off-screen edge.

## Geometry constants

For `.cut` with default tokens:

- `border_width = 3.0`
- `chamfer_border_width = 3.5`
- `corner_depth` — depth of the outer chamfer cut

The inner chamfer depth is not a separate token; it is derived by the parallel
offset of each edge. There is no pre-shrink such as
`depth - (border + chamfer_border) * 0.5`; that produces a too-thin border.

## Anti-patterns that broke chrome before

- `squareRect()` for the mask outer path while the ring used `chamferRect()`:
  caused background wedges and squared-off visible corners.
- Pre-shrinking `inner_depths` with `(border + chamfer_border) * 0.5`: made
  chamfer borders super thin.
- Shrinking the chrome overlay to the visible sliver: the hidden-edge clear
  strip then falls inside the visible area and clips the top/bottom borders.
  Keep side-peek chrome as a full-window overlay and let correct off-screen
  placement hide the outer edge instead.

## Verification recipe

1. Build: `zig build && zig build test --summary all`
2. Deploy: scp `zig-out/bin/kidulwm` to VM `/usr/bin/kidulwm`, restart service.
3. Spawn ≥3 Ghostty windows, cycle focus with `kidulwm-control focus_next`.
4. Capture `QEMU` screendump of left peek, focused, and right peek states.
5. Check:
   - focused window: four chamfered corners, uniform border thickness
   - side peeks: only the seam-adjacent edge visible, square corner at hidden seam
   - no rounded-corner bleed (client CSD rounded corners masked by overlay)
   - no background-colour wedges at corners
