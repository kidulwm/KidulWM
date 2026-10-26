# Kidul filler zones — house identity at the hard stops

Status: LOCKED — Barticus 2026-10-26.
Origin: the kfiles top-nav redesign (2026-10-26). A nav dead-end became an
  identity surface. Barticus: "we didn't just create a feature out of a bug —
  we created a system-wide visual concept out of one."
Related: styles (design-language.md — THE PILL / CFC law / whispy icons /
  chrome retreat), kfiles top-nav spec, INPUT law.

## Concept

CFC + hard stops means every hard-stop edge of a focus row carries an EMPTY
zone where nothing navable sits. These are not dead space — they are IDENTITY
SLOTS. Each holds a "kidul filler": a subtle, non-navable design mark that
whispers "Kidul" instead of shouting it. It is KSD's identity "not shoved in
your face, but there when you need it", and it moves with the times.

## The law (properties)

1. SUBTLE — present when you look, absent when you don't. Dim fill (fg60
   token), small, never competes with content or focus. Identity, not a
   billboard.
2. NON-NAVABLE — a filler is chrome, never a control. Never focusable, never
   in the kidulFlow. (THE PILL = interactive; a filler = framing art — a MARK
   in the hard-stop zone, not a button.)
3. EPHEMERAL ART, PERMANENT SLOT — the SLOT (geometry + mechanism) is locked
   and shared; the ART in it is swappable and evolves (seasonal, per-app,
   design-language iterations). Fillers change over time BY DESIGN.
4. APP-CONTEXTUAL — every KSD app's top bar (media player, files, browser,
   settings) has its own filler zones and marks, but the slot MECHANISM is
   one shared spec.

## The zones (hard-stop edges)

A CFC focus row hard-stops at BOTH extremes. Two zone kinds:

- LEFT zone  — space left of the first nav element (before the crumb trail /
  end-crumb / first pill).
- RIGHT zone — space right of the last nav element (after [SETTINGS] / last
  pill).

kfiles top bar (true CFC, LOCKED):
  FILES    LEFT = left-of-crumb-trail ;  RIGHT = right-of-[SETTINGS]
  DRIVES   LEFT = left-of-end-crumb    ;  RIGHT = right-of-[SETTINGS]
  SETTINGS LEFT = left-of-end-crumb    ;  RIGHT = the logo slot

(media player / browser / settings zones enumerated when those apps adopt
the CFC top bar. The media player already reserves a logo slot in THE UP+1
state — the filler law generalises it.)

## Mechanism (code)

- One shared slot abstraction: `drawFiller(cr, zone, x, y, w, h, scale)`,
  `zone` = .left / .right. Slot geometry is whatever space remains at the
  hard-stop edge after the nav layout; the mark draws centred, dim, inert.
- ART IS DATA, NOT CODE: a zone -> mark registry, so the mark can change over
  time without touching nav layout. Placeholder = a dim "NEEDS FILLER" label
  (text or png) centred in the slot until the kidul marks are designed.
- The mark obeys the house icon language (whispy strokes) and the dim token.
- Implemented per-app (each satellite app owns its own render); the SPEC and
  dim token are shared via styles. First instance: kfiles drawFiller() in the
  SETTINGS hard-stop right zone (commit 8471b42).
