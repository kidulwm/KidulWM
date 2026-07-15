# 2026-07-15 — Peek glass + colored rim final

## What
Peek chrome now renders full dark glass to the wrapper edge with a hard 2 px border colored by `style.color_border` (same as unfocused slides).

## Key lesson
Compositor chrome must be parented under `server.overlay_tree` and raised each frame to render above the client surface. Per-window chrome trees are occluded.

## Files changed
- `src/render/chrome.zig`
- `src/window.zig`
- `src/core/style.zig`
- `src/server.zig`

## Verification
User confirmed visible border and glass; tagged `greatest-yet` at `b6ff45d`.

## See also
- `docs/KIDULWM_CHROME_LAYERS.md`
