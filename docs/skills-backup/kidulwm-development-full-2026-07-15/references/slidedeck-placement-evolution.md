# SlideDeck layout evolution: placement, clipping, and rounded corners

Session notes for the sequence that produced the current SlideDeck neighbour placement.

## Problem statement

- Left unfocused window was visible underneath the transparent focused center window.
- It was showing its **leftmost** ~8% instead of its **rightmost** ~8%.
- Hard scene clips to prevent stale-buffer leakage were squareing off rounded corners and client-side shading.

## Resolution sequence

1. **Geometry fix** — changed `horizontalTarget(-1)` in `src/core/slidedeck.zig`:
   - `x = -self.width + left_w`
   - `width = self.width`
   - This places the full-width left neighbour mostly off-screen, exposing only its rightmost `left_w` pixels abutting the focused window.

2. **Stale-buffer clip** — added `Window.updateClip()` using `wlr_scene_subsurface_tree_set_clip` in `src/window.zig`, called from `applyLayout()` in `src/server.zig`.
   - Clipped to the layout target size.
   - Kept the dim overlay sized from the surface buffer to preserve rounded corners.

3. **Corner regression** — the hard clip cut rounded corners / shading on the right/bottom edges because scene clip rectangles are axis-aligned and cannot express rounded shapes.

4. **Clip removal** — removed the clip calls once off-screen positioning was verified to prevent leakage on its own.
   - Corners returned to perfect client-side rounded/shaded look.

## Commits in this order

- `2c2a675` — slidedeck: clip surface subtree to layout target, keep dim overlay on surface buffer.
- `22e1467` — slidedeck: show rightmost sliver of left neighbour butt-up to focused window.
- `cc61090` — slidedeck: remove hard scene clip; rely on off-screen positioning for corners.

## Verification during this session

- Before removing the clip, corners appeared square on the top-right and both bottom edges (clip boundary cutting client-side CSD/shadows), while top-left remained rounded. This matched the expected axis-aligned-clip symptom.
- After removing `updateClip()` calls from `Server.applyLayout()` while keeping off-screen neighbour placement, all visible window corners returned to a consistent rounded CSD look.
- Screenshot fallback used because KidulWM does not implement `wlr-screencopy-v1`: `virsh ... qemu-monitor-command cachyos-kidulwm --hmp 'screendump /tmp/vm-screenshot.ppm'`, then `magick convert /tmp/vm-screenshot.ppm /tmp/vm-screenshot.png`.

## Takeaway

For SlideDeck, off-screen positioning is preferable to hard clipping because client-side rounded corners and shadows are destroyed by axis-aligned scene clips. Only re-introduce clipping if stale buffers leak back on-screen, and then try to keep the clip boundary hidden behind opaque overlap. When iterating on polish, commit the known-good geometry state first so the clip/corner experiments do not regress placement.
