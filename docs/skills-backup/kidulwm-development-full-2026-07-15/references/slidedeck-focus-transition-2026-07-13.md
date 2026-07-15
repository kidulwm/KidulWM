# SlideDeck focus transitions: snap at rest, animate only while focus moves

Date: 2026-07-13
VM: cachyos-kidulwm-rounded-fun

## User requirement

- Windows must always sit in their correct SlideDeck positions when the deck is at rest.
- Motion should only happen during a focus change and should resolve quickly (≈120 ms).
- Position should animate; size and opacity should snap instantly so the final layout is never wrong while moving.
- Earlier full-spring approach caused windows to overshoot / crawl because size was also being integrated and chrome rebuilt every frame.

## Final design

1. `Window.setLayoutTarget()` records the new target. Size/opacity snap immediately; position is only animated if a transition is active.
2. When no transition is active (`animation.last_us == 0`), `setLayoutTarget()` also snaps `cur_x`/`cur_y` to the target. This guarantees every window is correctly placed at rest.
3. `Server.applyLayout()` detects a focus change by comparing the currently focused slide id with a stored `last_focused_slide_id`. If it changed, it calls `Window.startTransition()` for every mapped window *after* calling `setLayoutTarget()`.
4. `Window.startTransition()` captures the window's current `cur_x`/`cur_y` as `start_x`/`start_y` and records `last_us = now`.
5. `Window.tickAnimation()` interpolates from `start_x/y` to `target_x/y` over 120 ms using an easeOutCubic curve. When the duration elapses it snaps to target and clears `last_us` so the next layout is instant again.

## Key code pointers

- `src/core/animation.zig` — `WindowAnimation` keeps `start_x`, `start_y`, `last_us`, `position_duration_us`, `position_ease_power`.
- `src/window.zig` — `setLayoutTarget()`, `startTransition()`, `tickAnimation()`.
- `src/server.zig` — `applyLayout()` focus-change detection and `startTransition()` calls.

## Why this beats the spring approach

- Integrating position + size with a physics spring made the focused window and peeks misalign during motion, causing overlap and off-screen drift.
- Integrating size forced `updateChrome()` to regenerate the Cairo overlay every frame, which is expensive in a VM and made animations feel slow.
- With position-only interpolation, size/opacity snap, so the final SlideDeck geometry is always correct; only the position slides over 120 ms.

## Tuning knobs

- `position_duration_us` in `WindowAnimation`: current value 120_000 (120 ms). Decrease for snappier motion; increase to make the slide more visible.
- `position_ease_power`: current value 3 (easeOutCubic). Use 1 for linear, 2 for quad, etc.

## Caveats

- If the user spams focus changes within the 120 ms window, `startTransition()` is called again mid-flight and starts from the current interpolated position. This usually looks fine.
- The focused window's client surface snaps to the new target size immediately. Because the wrapper is moving, the content edge may show a transient gap until the position interpolation finishes; this is generally acceptable for 120 ms.
