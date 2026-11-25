# LAW — the Landing (files/browser/media converge on one look & feel)

LOCKED 2026-10-26, Barticus present. Q.A resolved: the media title is "Library".
AMENDED 2026-11-14 (later): the space above the bar is EMPTY "awaiting design"
for now — the KISS title + Batik corners + Kidul Systems name (props 2/3/4/6) are a
LATER pass, not the current landing. Current clean landing = pill bar CFC'd +
content centred + ZERO crumbs + empty space above.
AMENDED 2026-11-14 (GSI): the brand is KIDUL SYSTEMS (was KidulWorks); the sig
LOGO retires in favour of the plain name (naming.md — no logo, no sig, just the
name). The system title ABOVE UserHome = "Kidul TV" (naming.md).
AMENDED 2026-11-26 (GSI, BITE 1): the mark returns as a first-class LOGO —
REVERSING "the sig retires". One mark, two presentations keyed to seat (see "The
Kidul mark" below), theme-immune, art-is-data. The space above the bar is no
longer empty — the mark fills it. Content below the bar is a transparent depth
ladder, NEVER above the bar.

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
  - above the bar: the Batik corners, the centred title, and the Kidul Systems name.

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
   centred title + Batik corners + Kidul Systems name) is IDENTICAL across
   files/browser/media. Only the title and the content swap. Freeze once, build
   three times to match.

6. THE KIDUL MARK (was the "Kidul Systems name"; AMENDED 2026-11-26). The
   mark is the brand element at the top — a wordmark "Kidul Systems" in purple
   & blue (the B&B colours), theme-immune. It REPLACES the older "small name
   above the pill" AND the outline system title: one mark, no double-name.
   Two presentations keyed to seat — see "The Kidul mark" below. NOT big when
   authenticated; the hero when keyless.

## The Kidul mark — two presentations + depth ladder (LOCKED 2026-11-26)

The mark is the brand element at the top, with exactly two presentation states
gated by seat identity (public-seat.md):

  KEYLESS (public seat) — the mark is BIG, the hero. Centred on the landing CFC
  at h/2, honour-sized (~1/4 viewport height), with the widget faces + navDots.
  NO pill bar (keyless has no apps). Nothing competes with the mark.

  AUTHENTICATED (signed in, deck in the usersBar) — the mark SHRINKS into a
  centred top band (~top 1/3 of the userBar height), one motion (<200ms, no
  fade), then static. It never moves while pills are walked.

  DEPTH LADDER — the authenticated UserHome landing (Library = the first
  focused pill). Below the shrunk mark, from focus outward — full opacity down
  to transparent; NOTHING above the bar:

    mark            (top band)    brand constant, full opacity, static
    usersBar                      FULL opacity — the CFC'd focus
    category bar    (Movies·TV·Music, the library's internal filter)   TRANSPARENT
    media peeks     (top ~2/3 of the top media tiles, recognisable)    TRANSPARENT,
                                                                       a touch more

  Only the usersBar is full-opacity focus; everything below it is PERCENTAGE
  TRANSPARENT (alpha), just enough to show the next step if you moved down —
  never enough to steal the CFC focus.

  TRANSPARENCY, NOT FADE (locked, Barticus's correction): the diminished
  objects are rendered at reduced ALPHA (see-through), NEVER faded / dimmed /
  blurred. The usersBar is full opacity; the objects below are a % transparent.
  No blur, no dim shader, no "black frost".

  NOTHING ABOVE THE BAR (locked): the media wall's old "top row above the pill
  bar" (the top 5 tiles rendered above the library category bar) is REMOVED.
  Content sits BELOW the bar only — the mark owns everything above it. This
  completes this law's own Q.D ("tiles below the bar, never above").

  ART IS DATA, NOT CODE: the mark is a data asset in the mark registry (with the
  Batik corners, §3); two sizes (hero / band) are the only layout facts the code
  knows. The mark's own ART (the wave/crab drawing) ships as data later — a
  placeholder wordmark carries the slot first.

  RENDER SITES (correcting the docket's pointer): the mark renders on the two
  compositor slides — `.home` (KidulHome, keyless hero) and `.user_home`
  (usersBar, shrunk band) — server.zig + src/ui/users_bar.zig. NOT media.zig
  (its LANDING/THE UP/THE DOWN/STANDARD are the media WALL's movement states, a
  different axis). The media wall is untouched by this cut. Full spec:
  docs/design/logo-landing-amendment.draft.md (LOCKED).

## Relationship to existing law

- EXTENDS kidul-filler-zones: the Batik corners + centred title + Kidul Systems name
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
- Reverses the "no logo, no sig, just the plain name" ruling (naming.md + this
  file's 2026-11-14 amendment): the mark returns, first-class, AS a logo.
- Reverses "the space above the bar is EMPTY, awaiting design": the mark fills it.
- Realizes naming.md's "logo — later job": now. The mark's own ART stays a later
  data drop (placeholder wordmark first).
- Word fix: the mark says "Kidul Systems", never "KidulWorks".
- Reverses nothing else against locked law.

## Rulings (this lock)

- Q.A  kmedia landing title: "Library" (Barticus 2026-10-26). Warm, classy, names
  the PLACE not the stuff, parallels "Folders & Files", and is the word the whole
  family already owns from Plex/Jellyfin.
- Q.B  corner art: Batik pattern (Barticus 2026-10-26), not a goddess picture.
- Q.C  placement: title CENTRED, Batik in the corners, Kidul Systems name above the
  focused pill (Barticus 2026-10-26).
- Q.D  LANDING UNIFICATION (2026-11-14, GSI): every app's landing = the title ABOVE
  the CFC'd AppHome bar, content below — identical across apps. The media player's
  tiles-above-the-bar landing is corrected to match (title above, tiles below).
  The media library's movement (down into tiles, back up to the bar) is exactly
  the resting position every app should open on.
- THE KIDUL MARK (2026-11-26, BITE 1, "yes to your recs" + transparency
  correction): mark shape = No.2 wave/crab wordmark "Kidul Systems", crab-dot the
  separable symbol, motion = intro/outro GIF only [Q.A]; keyless hero at h/2,
  ~1/4 viewport, widgets + navDots, no pill bar [Q.B]; shrink = centred top band
  ~top 1/3 of the userBar, one motion <200ms no fade, static while app-tops slide
  [Q.C]; the mark absorbs the text title, no double-name [Q.D]; theme-immunity =
  constant brand asset, never re-derived from theme [Q.E]; this cut freezes the
  presentation + brand, and the mark's own ART ships as data later [Q.F].
  TRANSPARENCY-NOT-FADE [Barticus's correction]: the ladder below the CFC is
  percentage ALPHA transparency, never fade/dim/blur — usersBar full opacity,
  category bar + media peeks transparent (peeks a touch more). NOTHING above the
  bar. Library = the first focused pill on the authenticated UserHome landing.
