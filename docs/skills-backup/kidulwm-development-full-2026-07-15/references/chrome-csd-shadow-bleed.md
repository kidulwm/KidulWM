# Chrome mask does not stop CSD shadows from bleeding past chamfers

## Symptom

At chamfered (`.cut`) window corners, dark pixels from the client surface protrude past the border into the gap/compositor background. Pixel sampling shows colour values such as `(29, 30, 31)` and `(30, 32, 33)` — darker than KidulWM's `color_background` (`#222425` ≈ `34, 36, 37`).

## Root cause

GTK/libadwaita clients often ignore `zxdg_decoration_manager_v1` server-side-decoration mode. Even though KidulWM requests `.server_side`, the client still paints a CSD shadow/title bar that extends beyond the window's content geometry. The shadow can be 4–10 px or more below the visible content edge.

Our chrome overlay can overdraw the mask by a few pixels, but a 1 px overdraw only masks 1 px of shadow. The rest of the shadow leaks past the border.

## Fix

Since we own the chrome, stop the surface from rendering outside its content geometry, not just mask over it. Use `wlr_scene_subsurface_tree_set_clip()` (exposed by zig-wlroots as `wlr.SceneNode.subsurfaceTreeSetClip`) on the tree returned by `wlr_scene_xdg_surface_create()`. The clip rectangle is the XDG geometry rectangle (`toplevel.base.geometry`).

This discards CSD shadows, title bars, and rounded-corner padding so only the actual client content is visible inside the inner polygon, and the chrome mask can cleanly fill everything outside it with `theme.color_background`.

If `subsurfaceTreeSetClip` does not stop the leak in your wlroots build, use the full-surface chrome mask approach instead: the chrome overlay is rendered at the full `surface.current` size and positioned with the XDG geometry offset so the wrapper-content inner polygon is correct and the entire shadow region is filled with `theme.color_background`. See `references/chrome-mask-full-surface-2026-07-13.md` for the full recipe.

## Workflow / verification

- Vision models (including `vision_analyze` of QEMU screendumps) may miss subtle colour bleed, especially on dark wallpapers. When the user reports "still there", sample actual pixel values from the close-up crop to confirm what colour is leaking.
- Look for pixel rows with values darker than `color_background` just outside the border — that is almost always a client CSD shadow, not the compositor background.
- When a fix works on the VM screendump but the user still sees bleed, ask for a fresh screenshot from their display; the QEMU renderer path can differ from the host monitor.
