# LAW — the Landing (files/browser/media converge on one look & feel)

LOCKED 2026-10-26, Barticus present. Q.A resolved: the media title is "Library".
AMENDED 2026-10-26 (later): the space above the bar is EMPTY "awaiting design"
for now — the KISS title + Batik corners + KidulWorks sig (props 2/3/4/6) are a
LATER pass, not the current landing. Current clean landing = pill bar CFC'd +
content centred + ZERO crumbs + empty space above.

Lane: cross-app (kfiles, kidul-browser, kmedia).
Related: styles (CFC law, THE PILL, corner language, whispy icons, Granny test),
  kfiles-top-nav spec, kidul-filler-zones law, chrome law.

## Problem

The three main apps — FILES, BROWSER, MEDIA PLAYER — each reached for the same
landing state independently, in different ways, not knowing they were all after
one thing. Watching the kfiles top bar CFC'd (pills centred + user files centred
below, crumbs gone) is what made it land:

  "we've kept leading towards a cohesive system look & feel without really
  knowing if & how ... files -> browser -> media player ... all searching for
  the same thing & we just found it."

## Concept — the Landing

One landing shape, three apps. When a top pill owns the stage, the surface is a
clean CENTRED stage and nothing else:

  - the pill bar CFC'd dead-centre (w/2 AND h/2 — kmedia slide law #1),
  - the app's content centred below it,
  - ZERO breadcrumbs (crumbs are a while-browsing aid, never a landing element),
  - above the bar: the Batik corners, the centred title, and the KidulWorks sig.

Granny never needs to know she is using "kfiles" or "kidul-browser" — she needs
to know she is in HER FILES, on HER BROWSER, watching HER LIBRARY. The app id
disappears; a KISS title tells her what the app does.

## The law (properties)

1. CLEAN LANDING (CFC + zero crumbs). A top pill focused = the Landing: pill bar
   CFC'd dead-centre, content centred below, ZERO crumbs. This is the GOAL look,
   not an accident. Crumbs show only while actually browsing a folder, and even
   then as display-only context in the left panel (never navable, never on the
   landing).

2. KISS TITLE, never an app id — and it is CENTRED. The top filler is a
   plain-language title of what the app DOES, written in a really nice hand, dead
   centre ("in the middle on all"). It tracks the focused pill:
       kfiles   FILES -> "Folders & Files"    DRIVES -> "Drives"    SETTINGS -> "Settings"
       browser          -> "Browser"
       kmedia   landing-> "Library"
   One classy-and-clean text style shared across all three. KISS — explains the
   app to Granny and any noob, never names the code.

3. BATIK CORNER ART (not a picture). The corners carry the STYLE of Batik
   pattern — the house's own textile language, subtle, cinematic — rendered in
   the USER'S BORDER COLOR (the corner literally wears the user's chosen colour)
   with slightly over-stylised cinematic chamfer-ish corners. NON-navable,
   identity "not shoved in your face". Whispy, house corner language. ART IS
   DATA, NOT CODE (a corner -> mark registry; the pattern evolves without
   touching nav layout). The earlier "goddess picture" idea was dropped in favour
   of Batik — more kidul, more subtle, personalised by the border colour.

4. FULL SPACE ABOVE THE BAR. The entire vertical space above the pill bar is
   usable for the title + corner art — the landing is not cramped into a thin
   strip.

5. ONE LANGUAGE, THREE APPS. The landing shape (centred bar + centred content +
   centred title + Batik corners + KidulWorks sig) is IDENTICAL across
   files/browser/media. Only the title and the content swap. Freeze once, build
   three times to match.

6. KIDULWORKS SIGNATURE (B&B). A small "KidulWorks" logo in purple & blue — the
   B&B signature colours, timeless — sits just above the focused pill, small
   enough that the colour never distracts from the pill's focus, but placed so it
   walks the eye up and down the line: title -> sig -> focused pill. NOT big,
   wisely placed, our mark on every surface.

## Relationship to existing law

- EXTENDS kidul-filler-zones: the Batik corners + centred title + KidulWorks sig
  ARE the first filler marks (the filler-zones "first marks" open question). The
  "NEEDS FILLER" placeholder retires in favour of them.
- REFINES kfiles-top-nav: the focus model (focused element centres, hard stops)
  is unchanged; this law names the Landing as the resting state and gives the top
  filler its content.
- GROUNDS styles: CFC law (focus centres), THE PILL, corner language (ROUND =
  interactive / CHAMFER = framing), whispy icon strokes, Granny test (what does
  Granny want on landing? — her files, her browser, her library, in plain words).
- CHROME LAW note: the Batik corners + title + sig are SLIDE SELF-FRAME art
  (client side, per-app), not compositor window chrome — they obey full-bleed (no
  art on a full-bleed surface).

## Reversals

- Reverses the interim "crumbs in the top-left void" (kfiles commit d89cbf5):
  crumbs leave the top entirely — they merge into the LEFT panel as display-only
  context (docket #35), and show ZERO crumbs on the Landing.
- Reverses the earlier "goddess picture" framing of the corner art in favour of
  Batik pattern.
- Reverses nothing else against locked law.

## Rulings (this lock)

- Q.A  kmedia landing title: "Library" (Barticus 2026-10-26). Warm, classy, names
  the PLACE not the stuff, parallels "Folders & Files", and is the word the whole
  family already owns from Plex/Jellyfin.
- Q.B  corner art: Batik pattern (Barticus 2026-10-26), not a goddess picture.
- Q.C  placement: title CENTRED, Batik in the corners, KidulWorks sig above the
  focused pill (Barticus 2026-10-26).
- Q.D  LANDING UNIFICATION (2026-11-14, GSI): every app's landing = the title ABOVE
  the CFC'd app-top bar, content below — identical across apps. The media player's
  tiles-above-the-bar landing is corrected to match (title above, tiles below).
  The media library's movement (down into tiles, back up to the bar) is exactly
  the resting position every app should open on.
