# Peek black-glass overlay recipe

For KidulWM SlideDeck peek windows. The intent is a black-glass skin over the
peek interior while the original chrome border ring stays fully visible on top.

## Visual targets

- Full peek window area inside the border: dark/black, reads as glass.
- Top and bottom strips: near-black and opaque enough for labels and controls.
- Middle: more translucent so the underlying slide content shows.
- Outer edge (off-screen side): slightly deeper black.
- Inner seam edge (next to focused slide): subtle gold glow.
- Border ring: **drawn on top, unchanged**. If the border disappears, the glass
  has overwritten it — revert and restore draw order, or clip the glass to the
  inner content shape if the body is too opaque.

## Style tokens

Live in `src/core/style.zig`:

```zig
peek_glass_alpha_top: f32 = 0.97,
peek_glass_alpha_mid: f32 = 0.45,
peek_glass_alpha_outer: f32 = 0.50,
peek_glass_alpha_inner: f32 = 0.10,
peek_glass_alpha_seam: f32 = 0.22,
peek_glass_alpha_rim: f32 = 0.14,
```

## Render order in `src/render/chrome.zig`

1. Start transparent.
2. If this is a peek (`!edges.eql(EdgeMode.all)`):
   - Clip to the **full outer window path** (`windowPath(0,0,w,h,scaled_style)`)
     when the glass is translucent enough for the border to show through.
   - Clip to the **inner content shape** (rounded rect inset by `border_width`)
     when the glass is near-opaque (e.g. top/bottom alpha ~0.97) so the border
     ring does not disappear. See `references/peek-glass-border-visibility-2026-07-15.md`.
   - Fill vertical gradient: top `0.97`, mid `0.45`, bottom `0.97`.
   - Add horizontal overlay from outer edge (`peek_glass_alpha_outer`) to inner
     edge (`peek_glass_alpha_inner`).
   - Thin top rim glow at `border + 1.5` with alpha `peek_glass_alpha_rim`.
   - Thin gold inner-seam glow along the edge abutting the focused slide.
   - Program label anchored to the inner (visible) edge.
3. Fill the mask/border-ring region with `color_background` even-odd.
4. Fill the border ring with `border_color` even-odd **on top of the glass**.
5. Trim hidden/shared edges with `CAIRO_OPERATOR_DEST_OUT`.

## Hard "do not" list

- Do not replace, recolor, or stroke the border ring as part of the glass change.
- Do not add inner seam strokes to compensate for a disappearing border.
- Do not change `color_border`, `color_border_focused`, or `border_width`.
- If the border looks grey or missing after a glass attempt, revert
  `src/render/chrome.zig` to a known-good commit and start the overlay-only
  change again.

## Verification

- `zig build && zig build test --summary all`
- Deploy to a disposable VM, spawn >=3 Ghostty windows, cycle focus so both
  peeks are visible.
- Confirm border ring is continuous and the interior reads as dark/black glass.
- Barticus judges the final look; do not accept/reject based on vision tools.
