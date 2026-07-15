# Peek sliver alignment, dim overlay, and inner glow — session notes

**Date:** 2026-07-12  
**Commits:** `ed1aa96` "peek: show the correct visible sliver for left/right peeks", `29b8c55` "style: unify 2 px / 2.5 px borders, muted gold palette; remove dim and inner glow"  
**Branch:** `chrome-2x`

## Problem sequence

1. Peeks showed correctly only at empty-slot boundaries; in the middle of the deck they showed only the compositor background fill.
2. After fixing the sliver alignment, the right peek looked darker than the left peek and center slide.
3. Focused windows had a thin interior line that looked like a 0.5 px chamfer-width excess.

## Root causes

### Peek offsets were using the buffer top-left, not the XDG geometry top-left

`wlr_scene_xdg_surface_create` positions the **XDG geometry top-left** of the surface at the scene-tree origin. Offsets should therefore be expressed in content-geometry coordinates, not raw buffer coordinates. Subtracting `geometry.x` / `geometry.y` pushed the actual content out of the visible sliver and left only CSD shadow/background visible.

Correct natural-size offsets for a full-width peek wrapper:

| Peek side | Visible sliver | Offset `x` |
|---|---|---|
| Left peek | wrapper left edge | `0` |
| Right peek | wrapper right edge | `target_w - geometry.width` |

This also means `setSurfaceDestSize()` for peeks should restore the **natural buffer size** so the offset logic matches the committed buffer.

### Dim overlay made right peek darker

`updateDim` adds a `wlr.SceneRect` sized to `surface.current.width`/`height` with `dim_color = {0,0,0,0.18}`. The visible right-peek sliver happened to sit under a portion of that overlay where it darkened the edge differently from the left peek. Setting the alpha to `0.0` made both peeks and the focused window equally bright.

### Inner glow stroke caused the thin line

`renderChrome` drew a 1 px glow stroke just inside the inner border edge for focused windows (`color_glow`, alpha 0.35). Separating the variables made it look like a chamfer-width mismatch, but it was the glow stroke. Removing it eliminated the line.

## Final style tokens (commit `29b8c55`)

```zig
border_width: f32 = 2.0;
chamfer_border_width: f32 = 2.5;
corner_depth: f32 = 16.0;
corner_style: CornerStyle = .cut;

color_border: Color = Color.fromHex(0x4d4a40);          // unfocused / peeks
color_border_focused: Color = Color.fromHex(0x696555);   // focused
```

Previous palette for reference:

```zig
color_border: Color = Color.fromHex(0x5e5a4c);
color_border_focused: Color = Color.fromHex(0x948e7b);
```

- Inner glow stroke: removed.
- Peek dim overlay: alpha `0.0` (disabled).

## Verification approach used

- Rebuilt `kidulwm` on the host.
- Copied the binary via SSH to `/tmp/kidulwm.new` and swapped `/usr/bin/kidulwm` inside the VM with `systemctl stop/start`.
- Captured live VM screenshots with `virsh -c qemu:///system screenshot cachyos-kidulwm /tmp/kidulwm-screenshot.png`.
- Used the vision tool to inspect whether peeks showed window content or only the fill color.

## Files touched in this fix

- `src/window.zig`: `setSurfaceOffsetForPeek()` natural-size offsets; `dim_color` alpha `0.0`.
- `src/core/style.zig`: border widths and border colors.
- `src/render/chrome.zig`: removed focused inner glow stroke.
