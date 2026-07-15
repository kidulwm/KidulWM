# Black-glass peek overlay — implementation recipe

Session: 2026-07-15. Target: rounded-corner CachyOS builds.

## The right starting point

- Branch: `chrome-2x`.
- Rounded reference commit: `da2a384` (`corner_style = .classic`).
- **Do not use** `b970fe9` (chamfer) or the later `e6da1ab` chamfer HEAD for rounded glass work.
- `bob-is-a-douche` and `cachyos-kidulwm-rounded-fun` are rounded clones from around `da2a384`.

## What the user wants

A black-glass overlay over the **background only** of the SlideDeck peek windows.

- Borders stay exactly as they are.
- Overlay is clipped to the **inner content rounded shape** (inset by `border_width`).
- Top/bottom near-black (`~0.97` alpha) so labels/settings read.
- Middle more translucent (`~0.45` alpha) so slide content shows.
- Drawn **before** the existing mask fill + border ring so the border paints on top unchanged.

## Minimal change set

1. `src/core/style.zig`: only adjust `peek_glass_alpha_*` defaults.
   - `peek_glass_alpha_top = 0.97`
   - `peek_glass_alpha_mid = 0.45`
   - `peek_glass_alpha_outer = 0.50`
   - `peek_glass_alpha_inner = 0.10`
2. `src/render/chrome.zig`:
   - In `renderChrome`, after clearing the surface transparent, if `is_peek`, call `drawPeekGlass` before the existing mask fill/border ring block.
   - In `drawPeekGlass`, build the **inner content rounded path** (`windowPath(cr, border, border, w - border*2, h - border*2, inner_style)` where `inner_style.corner_depth = depth - border`) and clip to it.
   - Fill the clipped area with the vertical and horizontal black gradients.
   - Draw the label inside the glass.
   - Restore the clip.
   - Leave the mask fill + border ring + hidden-edge clear exactly as they were.

## Failure modes observed

- **Glass clipped to the full outer shape**, then border ring redrawn on top: border disappeared / looked grey because the glass covered the border pixel area.
- **Glass inset by `border + depth + 1` as a rectangle**: left a transparent gap between glass and border ring, exposing the compositor background → "grey border underneath".
- **Adding seam strokes / recolouring borders**: violated "leave the border alone".
- **Reverting to `b970fe9`**: brought chamfers back into the rounded VM.
- **Deploying without waiting for review**: wasted iterations while the user was already frustrated.

## Verification

1. Back up the VM's `/usr/bin/kidulwm` to the host before deploying.
2. Deploy to a disposable rounded clone (e.g. `bob-is-a-douche`, SSH port 2228, SPICE 5901).
3. Spawn ≥3 Ghostty windows, focus the middle slide so both peeks show.
4. Stop. Let Barticus judge the screen; do not override with `vision_analyze`.
