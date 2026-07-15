# SlideDeck end-stop / empty-slot behaviour

## Design decision

- SlideDeck navigation does not loop.
- Pressing `focus_next` past the last real slide moves focus onto a virtual
  **empty slot after the deck**, and stops.
- Pressing `focus_prev` before the first real slide moves focus onto a virtual
  **empty slot before the deck**, and stops.
- In an empty slot the nearest real slide is pushed fully off-screen, so the
  view is completely empty.
- Opening a new window while focus is in an empty slot inserts the new slide at
  that end and makes it the focused central slide; the nearest existing slide
  becomes the peek from that side.

## Implementation pointers

- `EmptySlot` enum and `empty_slot` field added to `SlideDeck` in
  `src/core/slidedeck.zig`.
- `virtualFocus()` returns the real slide index in normal use, `-2` for
  `before_first`, and `n+1` for `after_last`.  The extra gap pushes the nearest
  real slide fully off-screen instead of leaving it as a peek.
- `addWindow()` checks `empty_slot` first:
  - `before_first` -> `slides.insert(0, ...)`
  - `after_last` -> `slides.append(...)`
  - otherwise -> centre-out insertion as before.
- `Server.focusNext()` / `Server.focusPrev()` in `src/server.zig` detect the
  empty-slot state, clear keyboard focus with `clearFocus()`, and request a
  layout; otherwise they focus the real slide at the new index.
- `syncDeckFocus()` clears `empty_slot = .none` whenever focus returns to a
  real slide.

## Gotchas

- `get_layout` reports `focused_window` as the **slide index**, not the stable
  window ID.  When the focus is in an empty slot, it reports the nearest real
  slide's index.  This is pre-existing; update `getLayoutResponse()` and the
  IPC `LayoutResponse` struct if you need to expose the empty slot itself.
- `focusWindowByIndex()` always clears the empty slot because it selects a
  real slide.
- While in an empty slot, no slide has focus, so there is no focused dimming
  and no central chrome overlay.
