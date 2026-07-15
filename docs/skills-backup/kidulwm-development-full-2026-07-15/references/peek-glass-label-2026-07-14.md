# Peek-slide black glass overlay and program label

Implemented 2026-07-14 for the `kidulwm-glass` work VM. Adds a compositor-drawn black-glass overlay + gold program-name label to SlideDeck side peeks. The focused window is unchanged.

## Design targets

- Cover the **full peek slide wrapper** with a black-glass overlay:
  - Vertical alpha fade: more solid black at the top and bottom edges, more transparent through the middle.
  - Horizontal alpha fade: inner edge (the one abutting the focused window) stays more transparent; outer edge (off-screen) gets an extra darker overlay.
  - A top gloss highlight gives the glass its "shiny" look.
- The overlay must reach the border line/corners. Draw it across the entire wrapper; the compositor chrome border ring is then drawn on top so it stays fully visible and colored.
- Render the program name in gold at the top of the peek, anchored toward the visible inner edge.
- Only show the label on peek windows, not the focused window.

## Files changed

- `src/core/style.zig` — new tokens:
  - `peek_glass_alpha_top`, `peek_glass_alpha_mid`
  - `peek_glass_alpha_outer`, `peek_glass_alpha_inner`
  - `peek_glass_alpha_glow`, `peek_glass_glow_height`
  - `peek_label_font_size`, `peek_label_inset`
- `src/window.zig` — capture `toplevel.title` and `toplevel.app_id` via `set_title`/`set_app_id` listeners; compute a short label; invalidate chrome cache on label changes.
- `src/render/chrome.zig` — `renderChrome()` now accepts `label: ?[]const u8` and draws `drawPeekGlass()` before the border ring when `edges != .all`. The glass covers the full wrapper; the border ring is drawn afterwards so it remains on top.

## wlroots binding shape (0.20.x zig-wlroots)

```zig
pub const XdgToplevel = extern struct {
    title: ?[*:0]u8,
    app_id: ?[*:0]u8,
    events: extern struct {
        set_title: wl.Signal(void),
        set_app_id: wl.Signal(void),
    },
};
```

Read current strings with `std.mem.sliceTo(ptr, 0)`. Listeners receive `void`, so re-read the toplevel field inside the handler.

## Label lookup priority

1. Known `app_id` nickname map (case-insensitive substring match):
   - `ghostty` → `"Ghostty"`
   - `nano` → `"Nano"`
   - `helium`, `brave`, `chrome`, `firefox` → `"Helium"` (generic browser name for now)
   - `hermes`, `bob` → `"Bob"`
2. Cleaned raw `app_id` (strip reverse-DNS segments such as `com.example.`).
3. First space-delimited word of the window title.
4. `"App"`.

Keep nickname map in `Window.computePeekLabel()`; update as new commonly-used apps appear.

## Rendering recipe

The glass is drawn into the **same** Cairo ARGB32 surface used for the chrome border overlay, before the background mask and border ring. Because `chrome_tree` is a sibling of `surface_tree` inside the wrapper `scene_tree`, the glass sits above the client surface but below the chrome border (the border is drawn later in the same surface).

Cairo steps in `drawPeekGlass(cr, x, y, w, h, style, edges, label)`:

1. Vertical linear gradient from `(x,y)` to `(x,y+h)` with stops:
   - `0.0` → black, `peek_glass_alpha_top`
   - `0.5` → black, `peek_glass_alpha_mid`
   - `1.0` → black, `peek_glass_alpha_top`
   Fill the full wrapper rectangle.
2. Horizontal linear gradient over the same rectangle. For a left peek the inner edge is on the right, so the gradient ramps from outer (left) to inner (right). For a right peek it ramps from outer (right) to inner (left). Stops:
   - outer edge → black, `peek_glass_alpha_outer`
   - inner edge → black, `peek_glass_alpha_inner`
3. Gloss highlight: vertical linear gradient from `(x,y)` to `(x, y + h * peek_glass_glow_height)` with stops:
   - `0.0` → white, `peek_glass_alpha_glow`
   - `1.0` → white, `0.0`
   Fill the top portion with `CAIRO_OPERATOR_OVER`.
4. Label at `(pad, pad + font_size)`, right-aligned for right peek, left-aligned for left peek. Draw a 1 px black shadow first, then the gold text.

The background mask and border ring are drawn in `renderChrome` **after** the glass, so the frame sits on top and stays fully visible.

Font used: `FantasqueSansM Nerd Font` bold; fallback to Cairo's default if missing.

## Cache key

The chrome cache key in `Window.updateChrome` must include:
- width, height
- focus state
- `EdgeMode`
- output scale
- style generation
- current label string

A label change sets `chrome_width = 0; chrome_height = 0` to force regeneration without needing a separate label cache field.

## Deployment pitfall observed

The service `ExecStart=/usr/bin/kidulwm` must be stopped before overwriting the binary; otherwise `cp` fails with `Text file busy`. Copy to `/usr/bin/kidulwm`, not `/usr/local/bin/kidulwm`. Typical deploy:

```bash
scp -P 2225 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm.new
ssh -p 2225 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && \
   sudo cp /tmp/kidulwm.new /usr/bin/kidulwm && \
   sudo chmod 755 /usr/bin/kidulwm && \
   sudo systemctl start kidulwm && \
   systemctl is-active kidulwm'
```
