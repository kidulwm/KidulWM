# CHROME LAW — thin border, no full-window buffer

LOCKED 2026-09-28. AMENDED 2026-09-28 (border restored as scene-rect stroke).

## The sentence

The border is a thin stroke, not a full-window mask. The screen's outer
edge is its own border.

## The law

1. THIN BORDER ONLY. The compositor may draw a window border, but only as a
   thin solid stroke built from scene-graph rects (`createSceneRect`). No
   cairo raster, no DataBuffer, no rounded or chamfered corner mask, no
   title bar. A square 1-2px ring is the whole of it.

2. FULLSCREEN = BARE PASS-THROUGH. A fullscreen surface reaches scanout
   untouched — no corner mask, no border, no per-frame clip. The screen's
   edge IS the border. (Sharpens fullscreen.md ruling 7.)

3. WINDOWED = THIN BORDER + CLIENT. A windowed client may frame itself
   (xdg-decoration .client_side); the compositor still draws the thin
   border so every foreign window has a boundary. KSD's own apps will
   drop the compositor border and self-frame (fade-to-black, 96% opacity)
   later — client-side, not compositor-side.

4. NO FULL-WINDOW BUFFER. The compositor must not allocate a full-window
   ARGB raster to paint a border. Pin (2026-09-28): window.updateChrome →
   DataBuffer.create duped 27.14MB per layout event, never released — ~3GB
   anon per session, the RSS wedge. Scene rects are O(perimeter), no leak
   by construction. (Sharpens fullscreen.md ruling 8.)

5. BORDER COLOR IS A THEME TOKEN. The thin border colour is
   `Style.color_border_focused` and re-renders on `chrome_style_generation`
   bump, so borders change in sync with every widget on theme reload.

## What gets deleted

- window.Window.updateChrome's full-window cairo + DataBuffer path.
- server-side decoration mode (.server_side) — clients go .client_side.

## What stays

- Gaps between slides (the deck's own separation).
- Compositor-owned slides (peeks, media slide, overview cards) keep their own
  geometry — this law is about WINDOW chrome, not compositor slide art.
