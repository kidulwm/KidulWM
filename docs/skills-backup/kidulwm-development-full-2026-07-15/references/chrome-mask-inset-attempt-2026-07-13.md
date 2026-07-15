# KidulWM chrome mask-inset attempt — 2026-07-13

**Goal:** Stop CSD shadows / rounded corners from bleeding through the chamfered corner triangles without touching geometry.

**Constraint:** Keep `.corner_style = .cut` and the existing `border_width` / `chamfer_border_width` / `corner_depth` tokens. Do not change slide placement, surface offsets, or `setSurfaceOffsetForPeek`.

## What was tried

1. **Reset to `29b8c55`** (`style: unify 2 px / 2.5 px borders, muted gold palette; remove dim and inner glow`).
   - Geometry good.
   - Chamfer bleed visible (CSD shadow from client surface showing past the cut corners).

2. **`subsurfaceTreeSetClip` clip at `(0,0,w,h)`** on every `applyLayout`.  
   Broke geometry: focused content shifted up/left ~20 px, left/right peeks leaked past seams.

3. **Clip at `(geom.x,geom.y,w,h)`**.  
   New artifact appeared in the gap between left-peek and focused slide; content looked cropped.

4. **Removed all clips** to restore good geometry.

5. **Mask-inset tweak (`src/render/chrome.zig`)** — add 1 logical px of extra inset to the mask inner polygon while keeping the ring inner polygon unchanged.
   - Changed only the mask path:
     - `mask_inset = chamfer_border + 1.0 * scale`
     - `chamferInnerPolygon(... border, mask_inset, &mask_inner)`
     - mask draws `squareRect(0,0,w,h)` minus `mask_inner`
     - ring still draws `chamferRect(...)` minus `inner`
   - Built and deployed.

## Result

Pending user visual check on `/tmp/screenshot40.png` / latest VM state.

## If this does not work, next candidates

- The surface itself drawing outside the wrapper because CSD shadow extends past the wrapper bounds; fix then requires clipping the XDG surface to the content area, but must account for peek-edge offset and not just focused geometry.
- Hidden-edge clear strips (`DEST_OUT` in renderChrome) removing mask/border at seams; reduce clear width or move mask after clear.
- Mask outer currently `squareRect` and should already cover corner triangles; if bleed persists, the inner polygon may be collapsing near small dimensions (ensure `w/h` checks are large enough).

## Lesson

Never respond to ".corner_style" requests under frustration. If the user says "get rid of the chamfer mess," they mean the leak around the chamfer, not the chamfer itself.
