# Black-glass peek overlay session — 2026-07-14

Working VM: `old-64gb-good` (clone of rounded-best), SSH port 2224 (runtime hostfwd), SPICE 127.0.0.1:5901.
Base commit for chrome work: `da2a384`.

## Design target (final)

- The black-glass overlay covers the **entire peek slide background** and is clipped to the window corners.
- The **original border ring stays untouched** — do not replace it with glass or redraw it in a different color.
- Top and bottom are near-black at **~0.97 alpha** so window-name labels and the settings button stand out.
- The middle is more transparent, around **0.45 alpha**, so slide content is still visible.
- Only a **thin rim glow** just inside the border sells the glass material.
- The border edge that abuts the focused window (right edge of a left peek, left edge of a right peek) must remain clearly visible.

## Implementation notes

- Tokens live in `src/core/style.zig` using `peek_glass_alpha_*` floats.
- Drawing is in `src/render/chrome.zig`, `drawPeekGlass()`.
- Clip glass to the **inner content shape** (inset by `border_width`) so the full border ring is preserved.
- Draw glass **before** the border ring so the border paints on top.
- Keep the original `color_border` / `color_border_focused` palette; changing border colors is a separate decision and should not be mixed with the glass overlay change.

## What went wrong during the session

- Drawing the glass to the full outer window shape and then redrawing the border ring caused the border to disappear/read as grey.
- Making the glass too light/grey was rejected; it must read as **more black than any other color by a long shot**.
- Over-explaining and continuing to patch while the user was frustrated escalated the session.

## Verification

- Deploy, then let Barticus judge the screen. Do not rely on `vision_analyze` for subtle border/glass calls.
- Capture QEMU monitor screendumps only when requested or for record-keeping after the user approves the look.
