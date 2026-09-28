# CHROME LAW — the compositor draws no window chrome

LOCKED 2026-09-28.

## The sentence

The border is the screen's outer edge, not a window's.

## The law

1. NO COMPOSITOR CHROME. The compositor draws no window border, no rounded or
   chamfered corner mask, no title bar, and no full-window compositor-side
   buffer. It composites the client's surface and nothing else.

2. FULLSCREEN = BARE PASS-THROUGH. A fullscreen surface reaches scanout
   untouched — no corner mask, no border, no per-frame clip. The screen's edge
   IS the border. (Sharpens fullscreen.md ruling 7.)

3. WINDOWED = CLIENT-SIDE. A windowed client frames itself (xdg-decoration
   .client_side). Its own rounded corners and its own frame are its own
   business, not ours.

4. NO FULL-WINDOW BUFFER. The compositor must not allocate a full-window ARGB
   raster to paint a border. Pin (2026-09-28): window.updateChrome →
   DataBuffer.create duped 27.14MB per layout event, never released — ~3GB
   anon per session, the RSS wedge. (Sharpens fullscreen.md ruling 8.)

## What gets deleted

- window.Window.updateChrome's full-window cairo + DataBuffer path.
- server-side decoration mode (.server_side) — clients go .client_side.

## What stays

- Gaps between slides (the deck's own separation).
- Compositor-owned slides (peeks, media slide, overview cards) keep their own
  geometry — this law is about WINDOW chrome, not compositor slide art.
