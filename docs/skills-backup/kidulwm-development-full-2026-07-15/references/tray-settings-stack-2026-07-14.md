# Settings-stack tray design — 2026-07-14

Context: KidulWM internal compositor tray in `src/ui/tray.zig`.

## Design

- Bottom-anchored menu inside the **left-peek panel**.
- **Transparent background**: only buttons are drawn.
- One fixed **Settings** button near the bottom, just inside the right border of the left-peek slide.
- Hover **or** click expands a vertical stack of buttons **above** Settings.
- Each button spans the left-peek width up to the focused slide (`focus_left - info.x - margins`).
- Equal item height and gap; about five buttons fill the lower third of the peek.
- Stack becomes scrollable when items exceed the available height.
- Tray must sit on the dedicated **overlay scene tree** so it draws above side peeks and focused slides.

## Implementation notes

- Keep a single button list where index `0` is always the Settings toggle.
- `open_amount` animates upward from the Settings top; only stack indices `1..` are revealed.
- `scroll_offset` is in logical pixels; clamp between `0` and `total_stack_height - max_visible_stack_height`.
- Hit-test in local tree coordinates:
  - Settings if `local_y >= settings_top`.
  - Otherwise `idx = floor((settings_top - local_y + scroll_offset) / (button_height + gap)) + 1`.
- For keyboard nav, default Up/Down moves `selected_index`; auto-scroll to keep selection visible.
