# Tray input and interaction notes

Date: 2026-07-13

## Pointer routing

Pointer motion/absolute/button events are intercepted in `src/input/pointer.zig`. If `server.handlePointerMove()` / `server.handlePointerClick()` report a hit, the event is consumed and NOT forwarded to the Wayland seat. This is intentional: it prevents the focused window from stealing focus while the tray is being interacted with.

If pointer events seem to do nothing:

1. Check `journalctl -u kidulwm -f` for `KidulWM: pointer motion x=... y=...` log lines.
2. If no lines appear, the pointer device is not reaching KidulWM (SPICE capture, missing device, etc). Fix the VM input, not KidulWM.
3. If lines appear but the tray does not react, the hit-test in `tray.zig` is wrong — check the current origin and geometry.

## Keyboard fallback

When the VM pointer is unavailable, use:

- `Mod4+t` — toggle the tray pinned/open state.
- `Mod4+a` — cycle animation preset.

These bindings live in `src/input/keyboard.zig`. Keep keyboard fallback for any future tray controls, because SPICE/VM pointer capture cannot be relied on.

## Bottom-left origin

The tray is a vertical panel that rises from the bottom-left corner:

- Width: 120 logical px.
- Max height: 220 logical px (clamped to 50% of output height).
- Handle strip: 12 logical px tall, flush to the bottom edge.
- Selector button is drawn just above the handle.

The bottom-left placement stays inside the left 8% SlideDeck peek margin and avoids the focused slide.
