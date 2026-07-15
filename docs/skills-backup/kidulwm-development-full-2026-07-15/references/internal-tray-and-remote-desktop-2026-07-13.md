# Internal tray architecture for remote-desktop shells

Date: 2026-07-13
Context: KidulWM scene-graph remote desktop where the host sends compressed window damage + scene-state deltas and the remote machine composites the full desktop.

## Principle

Mission-critical shell UI (settings tray, app launcher, volume/brightness controls, system status, animation chooser) must be **compositor-internal Zig surfaces**. They live in the host KidulWM binary, draw with Cairo into the same output buffer, and are invisible as separate Wayland surfaces. A remote-desktop encoder then sees only one composited frame and a small stream of state deltas.

## Why not GTK4 layer-shell trays?

A separate GTK4 layer-shell client produces an independent `wl_surface` that KidulWM must composite. For remote desktop that means:
- The host has to encode and transmit that surface region as pixels every frame.
- The remote cannot render the panel itself without also running the GTK4 client.

Internal Zig surfaces avoid both problems.

## Where fancy GTK4 panels fit

The existing host-only rkt-dashboard (dials, weather bar, news, media) is fine as a **local-only overlay** on the host machine. It can talk to KidulWM for state but its pixels are never streamed. The remote side can draw equivalent panels from the same state, or fall back to the minimal internal tray.

## Current implementation (branch `corner-bg-fix`)

- `src/core/animation.zig`
  - `AnimationKind` enum: `.snap`, `.wobble`, `.ripple`.
  - `WindowAnimation` defaults to settled; position-only interpolation while focus changes; size and opacity snap instantly.
  - `.snap` = 120 ms `easeOutCubic`.
  - `.wobble` and `.ripple` = spring integrators with different stiffness/damping.

- `src/ui/tray.zig`
  - Compositor-internal tray attached to the root scene tree.
  - Bottom-left origin: width 120 logical px, max height 220 logical px, 12 px handle strip at the bottom edge.
  - Hovered/pinned state drives `open_amount` and a smooth slide-out.
  - One Cairo `ARGB32` buffer per output via `DataBuffer` / `wlr.SceneBuffer`, redrawn at ~15 Hz.
  - One selector button cycles the focus-transition animation kind.
  - API: `init`, `deinit`, `addOutput`, `removeOutput`, `toggle`, `update`, `handlePointerMove`, `handlePointerClick`.

- `src/server.zig`
  - Owns `tray: ui.tray.Tray`.
  - `current_transition_kind: AnimationKind` is passed to `Window.startTransition()` on real focus changes.
  - `nextAnimationKind()` cycles presets and logs the change.
  - `handlePointerMove` / `handlePointerClick` route to the tray.
  - `logPointerDiagnostic` rate-limits pointer-event logging to once per second for input debugging.

- `src/input/keyboard.zig`
  - `Mod4+t` toggles the tray pinned state.
  - `Mod4+a` cycles the animation preset.

- `src/input/pointer.zig`
  - All motion/absolute/button events first hit-test the tray.
  - Events consumed by the tray do **not** call `seat.pointerNotifyMotion` / `pointerNotifyButton`, so the tray keeps keyboard/pointer focus while open.

## Keyboard-first workflow when VM pointer is unavailable

SPICE/virt-manager pointer capture can be flaky inside a VM. Do not block tray testing on the cursor:

1. Use `Mod4+t` to toggle the tray.
2. Use `Mod4+a` to cycle animation presets.
3. Check `journalctl -u kidulwm -f` for `KidulWM: pointer motion/abs/click x=... y=...` lines to confirm whether pointer events ever reach KidulWM.
4. If no pointer lines appear, the issue is SPICE/input device capture, not KidulWM event routing.

## Migration checklist for future panels

1. Can the panel operate from compositor state alone? → internal Zig surface.
2. Does it need complex widgets/dials only available in GTK4? → local-only overlay (host only).
3. Does it need to be visible on a bare-metal remote client? → must be internal Zig surface.

## Long-term remote-desktop shape

Host sends:
- Compressed damage regions for window/slide surfaces.
- Scene-state deltas: geometry, focus, z-order, chrome style, cursor position, animation kind.
- Panel state: clock, volume/brightness, weather data, notification counts — not rendered pixels.

Remote receives that stream and composites the desktop with its own renderer, drawing the internal tray and any remote-side panels locally. With identical screen geometry on both ends, panels can be swapped freely without re-transmitting their pixels.

See also:
- `references/slidedeck-focus-transition-2026-07-13.md` — focus animation model the tray controls.
- `references/vm-untouchables-discipline.md` — deploy only to disposable clones while iterating.
