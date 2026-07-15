# KidulWM chamfered chrome ring — regression fix, 2026-07-10

File: `src/render/chrome.zig`
Context: SlideDeck side peeks were showing a mixture of chamfered, squared and rounded corners plus inconsistent border thickness. The root cause was that the `.cut` ring was not being built from a true parallel offset, and the background mask used a square outer path while the border ring used a chamfered outer path.

## Correct ring construction

For `corner_style == .cut`:

1. Compute per-corner depths from `EdgeMode`:
   - A corner is chamfered only when **both** adjacent edges are visible.
   - Hidden-seam corners are square (`depth = 0`).
   - `ChamferDepths.fromEdgeMode(depth, edges)` implements this.

2. Build the **outer** path with `chamferRect(..., depths)`.

3. Build the **inner** polygon by parallel-offsetting every outer edge:
   - Straight edges (top/right/bottom/left) move inward by `border_width`.
   - Chamfer diagonals move inward by `chamfer_border_width`.
   - Intersect adjacent offset edges to form the inner vertices.
   - Zero-length diagonals must be collapsed, otherwise the inner corner at a
     square hidden seam becomes degenerate.

4. Use the **same edge-aware outer path** for both:
   - the background mask (outer minus inner, filled with `color_background`),
   - the border ring (outer minus inner, filled with border color).
   Different outer paths leave background-coloured wedges or mismatched corners.

## SlideDeck side-peek placement matters

If the peek window's overlay is only as wide as the visible sliver, the hidden-
edge strip used to erase the border falls inside the visible region and will
over-clear chamfer triangles or visible edges.

Fix: make both `left_peek` and `right_peek` overlays full-width windows pushed
off-screen, so the hidden seam and its clear strip are outside the output.
Visible sliver is determined by where the output edge clips the larger overlay.

See also:
- `references/chrome-edge-mode-corners.md`
- `references/chrome-variable-borders.md`
- `references/chrome-iteration-lessons.md`
