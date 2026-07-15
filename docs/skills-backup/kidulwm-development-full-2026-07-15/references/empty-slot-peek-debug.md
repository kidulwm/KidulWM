# Debugging phantom peeks at SlideDeck edges

## Symptom

At the far end of a SlideDeck (empty slot before first or after last), moving one step back into the deck shows a peek on the empty side that shouldn't be there. The real first/last slide becomes the focused slide, but a phantom neighbour peek is also rendered.

## Common cause

Something resets `SlideDeck.empty_slot` from `.before_first`/`.after_last` back to `.none` before the layout pass completes, making the deck believe it is at a real border between two slides instead of at the virtual edge.

Two usual sources:

1. **`applyLayout()` calls `focusWindow()` while in an empty slot.**
   - `applyLayout()` often iterates the deck and calls `self.focusWindow(window)` on the focused slide after the layout loop.
   - If `deck.empty_slot != .none`, this call triggers `syncDeckFocus()`, which sets `focused_index` from the focused window's position and clears the empty slot.
   - **Fix:** guard the refocus with `if (deck_ptr.empty_slot == .none)`.

2. **Mouse click in empty slot calls `focusAtCursor()`.**
   - `handleButton` in the pointer manager calls `server.focusAtCursor()` on every button press.
   - If the cursor is over a peek window while the deck is in an empty slot, `focusAtCursor()` calls `focusWindow()`, which resets the empty slot.
   - **Fix:** return early from `focusAtCursor()` when `currentDeck().empty_slot != .none`.

## Verification

Add temporary logs to:

- `SlideDeck.focusNext()` / `focusPrev()`
- `Server.applyLayout()` after `deck.sync()`
- `Server.focusAtCursor()`

Watch the sequence:

```
foccusPrev: none -> before_first
applyLayout: deck empty=before_first
focusNext: from before_first -> idx=0
applyLayout: deck empty=none
```

If the log shows a `focusWindow` event between the empty-slot layout and the next `focusNext`, check whether it came from `applyLayout` (refocus guard) or `focusAtCursor` (click guard).

## Files involved

- `src/core/slidedeck.zig` — `empty_slot`, `focusNext()`, `focusPrev()`
- `src/server.zig` — `applyLayout()`, `focusAtCursor()`, `focusWindow()`
- `src/input/pointer.zig` — `handleButton()`

## Related references

- `references/slidedeck-empty-slots.md` for the empty-slot design.
