# Slide unification — every slide is a full-bleed slide

Status: SPEC (frozen for verdict — the WHAT, Barticus 2026-10-06). No code yet.
This is the GREAT RESET's core: ONE slide shape, everything full-bleed, no
special-cased surfaces.

## The law

Every surface in the deck is ONE kind of thing: a full-bleed 16:9 slide with
zero chrome over it (VERDICT 110 — widgets live only on the row ends + the
far-left slide). Compositor-owned surfaces are ordinary slides, not exceptions.

## 1. Apps are slides (ghostty first)

ghostty, the media player, and the former tray (home) slide all "act funny"
today — each carries special spawn / focus / destroy plumbing. They must
behave like every other slide: spawn, walk, park, quit through the stock paths.

## 2. The media player is a persistent slide (parked left)

- The media player slide stays OPEN, parked to the LEFT in the deck while
  something (movie / TV) plays.
- When the movie/TV ends or quits, it FADES BACK to the still-open media
  player slide — no re-spawn, no re-pin.
- The ONLY open/close of the media player is the USER's. Nothing auto-spawns
  or auto-destroys it.

## 3. Audio (songs) control panel

While a song plays, a small control panel sits at the TOP of the media player
slide. (Video is full-bleed; audio gets a compact top control.)

## 4. No landing/home page — it is the far-left slide

Rename the home/landing slide to "the far left slide in the row". There is no
landing or home page: the left and right slide SPACES are the same thing — the
row ends (VERDICT 110's "nobody home" slots). Rows start from the far-left
slide space.

Open question (affirmed): does starting every row from the far-left slide space
simplify things? Yes — the row ends are already the widget home; making the
"home" slide just another slide in that space removes the special
spawn/focus/destroy machinery.

## Consequences (to verify in the cleanup pass)

- Cut the home-slide `ephemeral` flag + `homeSlideFocusOrSpawn`/`Close` special
  paths (session-and-deck-spec.md A7) — home becomes a plain slide.
- Cut the media "sentinel sibling" special casing (kidulwm-ui: media_slide.zig
  virtual empty_slot) — media is a plain persistent slide, parked left.
- ghostty / apps: confirm no remaining special casing; they are plain slides.

## Relationship to the brig (micro-brig.md)

The movie/TV that "plays while the media player sits parked left" is the
brig's slide producer: a foreign-code cell that renders one surface at the
slide size and the host presents it 1:1. When it stops, focus fades back to
the still-open media player slide — exactly §2 above. One slide shape for
apps, compositor surfaces, AND foreign-code cells.
