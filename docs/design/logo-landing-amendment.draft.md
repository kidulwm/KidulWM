# THE KIDUL MARK — logo/landing amendment (LOCKED, v2)

LOCKED 2026-11-26, Barticus present, GSI; RE-CUT v2 same day (Barticus's steer:
symbol, not wordmark). Folded into `landing.md` (§The Kidul mark, §6, Reversals,
Rulings) and `naming.md` (§The Kidul mark). This file is the full spec the laws
point at. v2 = the mark is a TEXTLESS SYMBOL with a KEYHOLE at its centre — no
"Kidul Systems" wordmark; keyless = CFC'd dead centre + Time top-right + Weather
left + navDots; authenticated = top-centre + the alias under it, weather/time
still shown. The depth ladder (transparency-not-fade, nothing above the bar,
Library first) is unchanged from v1.

## The steer (why now)

The KSD PRESENTATION pivot, BITE 1 (design-first): "Upgrade the small KidulWorks
sig to a first-class brand element — BIG on the public-seat landing CFC (keyless),
then SHRUNK into the top ~1/3 when the deck drops into the userBar
(authenticated). Content below slides the app-tops as the pills are walked —
logo static on top, app-top peeks change with pill focus. Freeze as an amendment
to law/landing.md (brand, theme-immune) BEFORE code."

Why it is the right first bite: the visible half of keys/entry (People app, the
key-entry ceremony) renders ON these surfaces. Proving the presentation — the
brand mark big-and-hero -> small-and-steady across the sign-in boundary —
unblocks that visible half without touching the parked cold-crypto seam
(ksign / SE050 / attestation are non-decaying and stay parked).

## Concept — one mark, two presentations, keyed to the seat

The mark is the brand element at the top of the deck, and it has exactly two
presentation states gated by seat identity:

  KEYLESS (public seat) — the mark is BIG, the hero. Centred on the landing CFC,
  nothing competes with it. This is the face of "a Kidul TV" before anyone signs
  in: mark + widget faces + navDots on KidulHome. No pill bar (keyless has no
  apps — that is the whole point of the keyless landing).

  AUTHENTICATED (signed in -> deck in the usersBar) — the mark SHRINKS to a top
  band (~top 1/3 of the userBar height), static, while the app-top titles slide
  BENEATH it as pills are walked. The mark never moves during pill-walking; only
  the app-top peek changes. The apps bar does its job under a steady mark.

  BRAND IS THEME-IMMUNE — the mark wears the house identity (the purple+blue /
  trident colour ramp) and no user theme repaints it. Same rule THE PILL already
  holds (media.zig "THE PILL spec — brand-locked, theme-immune"). A theme may
  recolour everything else; the mark is a constant.

  ART IS DATA, NOT CODE — the mark is a data asset in a registry (like the Batik
  corner marks, landing.md §3), evolvable without touching nav layout. The
  static mark is the norm; any motion (crab/seagull) is intro/outro GIF only.

## Reversals (this amendment reopens, explicitly)

1. Realizes `naming.md` §"The KidulWorks mark (logo — later job)" — that "later"
   is now. The mark stops being a deferred concept and becomes a first-class
   surface element.

2. Reverses "no logo, no sig, just the plain name" (`naming.md` §system title; the
   "KidulWorks sig retires" line). The sig's successor — the mark — IS landing, as
   a logo, not as bare text.

3. Reverses "outline-only, no branding" for the KidulHome title (`environment.md`
   §system title; `naming.md` §system title). The system-name title is promoted to
   the mark: branded, not outline.

4. Realizes landing.md's "the space above the bar is EMPTY, awaiting design"
   deferral — the mark fills that space.

5. WORD FIX (drifted term): the mark says **Kidul Systems** (the product brand),
   never "KidulWorks" (the code layer). `naming.md` §mark's two concept sketches
   (No.1 hammer, No.2 wave) both stamp "KidulWorks" — if realized as a wordmark,
   the word flips to "Kidul Systems". "KidulWorks" stays the code/git identity
   (app_id `com.kidulworks.*`, the workshop brand) and is NOT what surfaces.

## Presentation spec (what freezes now)

- KEYLESS hero: mark centred at h/2 on KidulHome, honour-sized (recommendation
  Q.B), widget faces + navDots retained, no pill bar.
- AUTHENTICATED band: mark settles into a top band ~top 1/3 of the userBar, one
  motion (<200ms, no fade — house rule), then static. app-tops (the per-app
  title peeks) slide beneath it as pills walk.
- Theme-immunity: mark colours baked into the asset (trident ramp), never
  re-derived from the active theme; themes may not repaint the mark.
- Data, not code: mark = registry asset; layout knows only its slot + the two
  sizes.

## Canonical impl — CORRECTION to the docket

The docket names "KidulWM src/ui/media.zig (PILL_*/renderCard) + server.zig
deck-state (LANDING/UP/DOWN/STANDARD)". That pointer is a one-word-N-jobs drift.
`LANDING / THE UP / THE DOWN / STANDARD` are the MEDIA WALL's movement states in
`media.zig` MediaWidget — NOT the deck axis the mark lives on. The mark renders
on TWO compositor slides:

  `server.zig` `.home` slide        — KidulHome (the boot root, Top layer) = the
                                      KEYLESS hero presentation.
  `server.zig` `.user_home` slide   — the usersBar = the AUTHENTICATED shrunk
                                      presentation; `src/ui/users_bar.zig`
                                      (which already carries "THE PILL —
                                      brand-locked house spec").

The media wall (media.zig PILL_*) is untouched by this bite. Census the actual
render sites for `.home` / `.user_home` before the code cut (do not chase
media.zig).

## Verdict (2026-11-26, Barticus present, GSI)

v2 SUPERSEDES Q.A: the mark is a textless SYMBOL (keyhole at centre), not the
No.2 wordmark — see the "The steer" above restated as the v2 shape. Q.B/C/D
re-ruled for the symbol: keyless = dead-centre hero + Time top-right + Weather
left; authenticated = top-centre + alias under it, weather/time still shown.

A–F locked "yes to your recs". PLUS the depth-ladder correction (Barticus):

  On the AUTHENTICATED UserHome landing, Library = the FIRST focused pill:
    usersBar CFC'd, FULL opacity — the focus.
    below it, the library's category pill bar (Movies·TV·Music), TRANSPARENT.
    below that, the tops of the top media cards (~2/3 of the tile), recognisable,
    TRANSPARENT — the same as the category bar, or a touch more.
  Nothing sits ABOVE the bar: the media wall's old "top row / top 5" tiles above
  the category bar are REMOVED. The mark owns everything above the bar.
  Mechanism = PERCENTAGE ALPHA transparency, NOT fade/dim/blur ("transparency
  not fade — my bad"). usersBar full opacity; below it the objects are a %
  transparent so they never steal the CFC focus, just show what the next step
  would be if you moved down.

## Open questions (lettered, with recommendations)

- Q.A  THE MARK'S SHAPE. Realize naming.md's No.2 (wave-over-sand, crab-as-i-dot,
  Flotsam & Jetsam) as a wordmark, with the crab-dot as the separable symbol.
  REC: No.2 wordmark, word = "Kidul Systems"; crab detail reserved for the
  intro/outro GIF only; static wordmark is the norm.
- Q.B  KEYLESS "BIG" — SIZE + what else shows. REC: mark honour-height ~1/4 the
  viewport height, centred at h/2, with widget faces + navDots, NO pill bar.
  (Alternative: smaller, with the pill bar below — rejected on the "nothing
  competes" hero rule, but flagging since it changes the keyless landing
  materially.)
- Q.C  THE SHRINK — where exactly is "top ~1/3", and is it animated. REC: the
  mark settles into a centred top band occupying the top third of the userBar
  slide; one motion, <200ms, no fade; then static while app-tops slide beneath.
- Q.D  does the mark ABSORB the text title. REC: yes — the mark IS the name, so
  the separate "Kidul TV"/"Kidul Systems" outline title above the bar retires
  where the mark appears (no double-name: a logo AND the same words as text).
- Q.E  THEME-IMMUNITY scope. REC: mark = constant brand asset (trident ramp),
  never re-derived from theme; this is the concrete meaning of "theme-immune"
  in the steer. Confirm this matches the intended brand element.
- Q.F  SCOPE OF THIS CUT. REC: freeze the PRESENTATION + brand position NOW
  (BITE 1); the mark's own ART (the wave/crab drawing) stays the data-asset
  "later job" naming.md already flagged, delivered as data, not code, when ready.
  Presentation can land with a placeholder wordmark; art drops in without a
  layout cut.

## Build-order note (after lock)

This is a presentation cut, not a mark-art cut. After lock: census the `.home` /
`.user_home` render sites (server.zig + users_bar.zig), then land the two-state
slot (hero @ h/2 on `.home`, top-band on `.user_home`) with the placeholder
wordmark, theme-immune and data-registered. The crab/wave art is its own later
data drop (Q.F).
