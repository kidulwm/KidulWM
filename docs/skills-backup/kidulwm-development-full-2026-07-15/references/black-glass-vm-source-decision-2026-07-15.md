# Black-glass overlay decision for bob-is-a-douche VM (2026-07-15)

## Environment

- VM: `bob-is-a-douche` (SSH port 2228).
- Source tree where the running binary was built: `/home/kidul/KidulWM`, not the host `/home/dad/dev/KidulWM` repo.
- Local Zig: 0.16.0. No git in the VM tree; `/home/kidul/KidulWM` is a plain source snapshot.

## What was tried first (and failed)

Patched the *host* KidulWM repo at `/home/dad/dev/KidulWM` (branch `chrome-2x`, commit `e6da1ab`) and deployed that binary to the VM.

Symptoms:
- Tray / settings buttons disappeared.
- Compositor crashed on boot after the next restart.

Why it failed:
- The host branch uses a Cairo `src/render/chrome.zig` + `renderChrome` API with rounded/chamfer geometry.
- The VM binary was built from a different source tree that uses `wlr_scene` directly and has a stub shader (`src/render/chamfer.frag.glsl`) that is not wired into the scene graph.
- Swapping the binary pulled in a layout/chrome ABI mismatch and dropped the VM's `TrayManager` / `SettingsTray`, which only exist in the VM source tree.

Recovery:
- Restored `/usr/bin/kidulwm` from `/tmp/kidulwm.stock` in the VM.
- Reverted the host repo to clean `e6da1ab`.

## Design decision

Implement the black-glass overlay **inside the VM's own source tree** (`/home/kidul/KidulWM`), not from the host repo.

Method:
- Add a rectangular `wlr_scene_rect` behind each peek column.
- Inset it by `Style.border_width` so it sits behind the window content but does not touch the output edge.
- Enable it only for unfocused (peek) columns; keep the focused column clear.
- Keep all tray and background scene nodes untouched.

Why rectangular / why not shape-matched:
- The VM source has no active compositor-drawn border or corner geometry to fit inside. The visible window edges are whatever the client application draws.
- Adding a working rounded/cut shader pipeline would **invent** a new window shape, not copy the current one. That violates the requirement to keep borders exactly as they are now.
- A rectangular glass panel is future-proof: if the project later adds a true square-corner chrome, the same inset rectangle will fit perfectly inside the square border ring.

## Gloss note

"Background only" in this design means the compositor-owned background panel behind the peek window. The XDG client surface still renders on top in its normal opaque color. This is not a client-clip effect.

## Iteration plan

1. Back up `/home/kidul/KidulWM` to `/home/kidul/KidulWM.stock`.
2. Add `peek_glass_color` / `peek_glass_enabled` to `src/core/style.zig`.
3. In `src/window.zig`, create a glass `wlr_scene_tree` sibling before the XDG surface tree, with a `wlr_scene_rect`.
4. In `src/server.zig:applyLayout()`, move/enable/disable the glass rect per-column based on focus, sized to `target - 2 * border_width`.
5. Build, deploy to `/tmp/kidulwm.glass`, run it manually (or copy over `/usr/bin/kidulwm` after stopping service).
6. Capture and review with the user; adjust inset/alpha interactively.
