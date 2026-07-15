# Peek-slide black glass finish

2026-07-14 work on `old-64gb-good` (port 2224) and earlier `kidulwm-glass` iterations (port 2225).

## User corrections that shaped the finish

1. "Black glass" must be **more black than any other color by a long shot** — not a literal pitch-black flat overlay, and not a medium-grey tint. Body should be near-black charcoal.
2. The glass must sit **over/on top of the background inside the original borders**, not become the borders. The original border ring must remain intact and drawn on top.
3. The border edge abutting the focused window — e.g. the **right edge of a left peek** — must be clearly visible.
4. Final shaping:
   - Top and bottom strips very dark (~97% opacity) so window-name labels and the settings button stand out.
   - Middle more transparent so slide content shows.
   - Thin glow just inside the gold border at the top, not a broad white wash.
   - Original gold border must remain untouched on top.

## Correct draw order in `renderChrome`

1. Transparent clear.
2. Draw black glass overlay for peeks, clipped to the full rounded window shape.
3. Draw the original mask/border ring exactly as before, on top of the glass.
4. DEST_OUT the hidden edges.

The glass is an **underlay** for the border; never overwrite the border ring.

## Current style tokens (alpha only)

```zig
peek_glass_alpha_top: f32 = 0.97,
peek_glass_alpha_mid: f32 = 0.45,
peek_glass_alpha_outer: f32 = 0.90,
peek_glass_alpha_inner: f32 = 0.55,
```

Top/bottom opaque near-black; middle see-through.

## `drawPeekGlass` recipe

- Clip to `windowPath(x, y, w, h, scaled_style)` so the glass respects the corners and goes all the way to the edge.
- Vertical gradient: top and bottom at `peek_glass_alpha_top`, center at `peek_glass_alpha_mid`.
- Horizontal gradient: outer edge at `peek_glass_alpha_outer`, inner seam at `peek_glass_alpha_inner`.
- Thin inner rim glow just inside the border at the top (~2–4 px, low alpha gold/white).
- Thin gold inner-seam glow near the focused slide edge (~10–14 px, low alpha `color_gold`).
- Gold program label anchored toward the inner edge with black shadow.

## Common pitfalls

- **Do not clip the glass to a smaller inset shape.** That leaves a gap or makes the border look missing.
- **Do not draw a separate "frame" of glass.** The border should be the original border ring, not a glass gradient pretending to be a border.
- **If the border disappears**, the glass layer likely overwrote it or the border ring was skipped. Restore the original ring draw order before adjusting colors.
- **Do not use broad white/grey top gradients.** They make the glass look grey and 1980s. Use a thin inner rim glow only.

## Verification checklist

For a left-peek / middle-window shot:
- Left peek reads as black glass.
- A visible border separates left peek from middle window.
- Border is the original gold/brown color, not a grey glass frame.
- Top and bottom are dark enough for labels and the settings button.
- Middle is more transparent than top/bottom.
