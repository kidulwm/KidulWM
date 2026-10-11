# Slide unification — every slide is a full-bleed slide

Status: SPEC (frozen for verdict — the WHAT, Barticus 2026-10-06). No code yet.
This is the GREAT RESET's core: ONE slide shape, everything full-bleed, no
special-cased surfaces.

## The law

Every surface in the deck is ONE kind of thing: a full-bleed 16:9 slide with
zero chrome over it (VERDICT 110 — widgets live only on the row ends + the
far-left slide). Compositor-owned surfaces are ordinary slides, not exceptions.

## Owner class (LOCKED 2026-10-06, Barticus)

The face is a FLAT slideDeck. There is no "under/over" on the face — every
slide is full-screen, nothing sits above or below a slide. The one thing that
distinguishes slides is WHO OWNS THEM. Three owner classes:

  host-owned   the face's own surfaces — home slide, media player slide,
               overview. No arm; the compositor itself.
  cell-owned   the pen (kcell) — foreign DISTRO + our code, fork/exec arm.
  brig-owned   the KVM guest — foreign CODE, the second arm.

Every app maps to exactly one owner class. Owner class is a SEATING fact: kushd
decides who is seated and by which arm; kidulwm only CONSUMES it to tag a slide.
It is NOT a boot fact (that's kboot/kmodd's separate machine-class: tv | brig).

"Under/over" survives ONLY below the face, in video+audio — the playback
present-path (scanout above the deck, the curtain, the audio clock). That is
godcodemode.md + playback.md, not the slide model.

Naming discipline (three "class" words, never blur):
  machine class  kboot/kmodd — tv | brig (what this box IS, module selection).
  seat class     kushd — system | service | user | restricted (the walls).
  owner class    face — host-owned | cell-owned | brig-owned (who owns a slide).
Always say the full phrase ("owner class"); bare "class" is the seat class.
"CID" remains the AF_VSOCK context id (host CID=2, guest CID=3) — do NOT
overload it with owner class.

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

## §5 Chrome border — BUILT (2026-10-12, verdict 115)

"Zero chrome over an app slide" was SPEC ONLY (bf3650d); it is now built.
Barticus (2026-10-12) sharpened it into a geometry rule:

  full screen (one slide fills the whole output) -> zero chrome
  2+ slides on screen (split / peeks)              -> border on each slide
  full -> smaller transition                        -> border back same frame

Implemented as `SlideDeck.focusedSlideIsFullBleed()` — a GEOMETRY test
(focused slide's target >= output box), not the `fullscreen` hotkey flag.
Both chrome decision sites (server.zig per-output loop + headless fallback)
call it. Law frozen in docs/law/chrome.md §2-§4.
