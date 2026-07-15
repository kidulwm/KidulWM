# Wallpaper + chamfer bleed iteration (2026-07-13)

Stable fallback: `good-bg-wallpaper` (commit `bb13c77`) — `29b8c55` geometry with wallpaper restored.

## What actually caused the visible "bleed"

- The `.cut` chrome mask was filling chamfer triangles with `theme.color_background`.
- Terminal background color matched `color_background` almost exactly, so the mask looked like client bleed against the wallpaper.
- Diagnostic: set `color_background` to bright green. If the triangles turn green, the mask is reaching them.
  - If they were still terminal-colored, client surface would be above/in front or the mask outer was too small.
  - In this session the triangles turned green, confirming the issue is the solid fill, not client bleed.

## Failed quick fixes

- Increasing mask inner-polygon inset (`+2.0s`, `+4.0s`) reached the triangles but still produced a solid patch against the wallpaper.
- Removing `bg_rect` and transparent mask showed wallpaper in the triangles but exposed empty gaps between the border and client content.
- Rectangular `surface_tree` clip shifts content; `wlr_scene` only supports axis-aligned rectangular clips, so it cannot clip a chamfer-triangle.

## Candidate fixes to compare

1. **Transparent triangles + surface clip** — drop the background mask in `.cut`, clip the XDG surface to the wrapper bounds, keep `bg_rect` so gaps stay filled. Corners show the output wallpaper; risk is if client shadows extend into the triangles.
2. **Wallpaper-fill triangles** — in the chrome mask, fill the chamfer triangles with the actual output wallpaper. No geometry changes; works with any static wallpaper but requires copying wallpaper pixels into the chrome Cairo surface.
3. **Keep solid `color_background` mask** — current baseline behaviour. Looks like bleed when wallpaper differs from terminal background.

## Long-term fix

- A wlroots patch for non-rectangular subsurface-tree clip / shape would cleanly solve this, but is not available now.

## Workflow lesson

- When the user says "do what we did last time", retrieve the actual prior implementation from git (`git show <commit>:<file>`) rather than reinstalling external tools or reimplementing from memory.
- After any good build the user wants to keep, commit and tag immediately: `git add -A && git commit && git tag <name>`.
- For rendering A/B tests, build the variants on the host and deploy to isolated states rather than repeatedly overwriting the single running binary.
