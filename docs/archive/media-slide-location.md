# LAW — the media slide's truth is its scene tree, never the focus deck

SUPERSEDED 2026-09-08 by `media-is-a-slide.md` — the sentinel design this
law patched has been retired. Kept for history only; do not implement
against this document.

Locked 2026-09-07 (host session, Barticus: "free to go, Gods Speed").
Applies to the compositor-owned media player slide (the sibling sentinel).

## The law

The media slide exists on exactly ONE output at a time. Its ground truth is
the OUTPUT's scene tree (`output.media_slide.isOpen()`), NOT the deck boolean
(`deck.media_slide_open`) and NOT the keyboard-focus deck.

Any open/close/toggle must:

1. FIND the slide where it actually lives (scan outputs for
   `media_slide.isOpen()`), never assume it lives on the focus deck.
2. CLOSE that one — clear that output's tree AND that deck's flag —
   regardless of where the cursor or keyboard focus currently sits.
3. NEVER open a second slide while one is open anywhere.

## Why (the bug this kills)

`mediaSlideToggle` resolved its target from `currentDeck()` (the
keyboard-focus output). Sequence that broke it:

  - boot: cursor parks on the Kogan (origin 0,0 wins) → focused_output=Kogan
  - open media → slide + deck flag land on the KOGAN
  - cursor moves to laptop, click → focusFollowsCursor → focused_output=laptop
  - toggle again → currentDeck() = laptop deck → laptop flag is FALSE →
    reconcile checks only the laptop output (never opened) → no-op →
    openMediaSlide() opens a SECOND slide on the laptop while the Kogan one
    stays live.

Result: two slides, two decks, both think they own it. Close from the laptop
only ever reaches the laptop deck; the Kogan slide is orphaned and "stuck
open". Same root, two symptoms (wrong-output + won't-close).

## Corollary (other slides)

Overview is a deck MODE, not a per-output sentinel tree, so it cannot split
this way. The media slide is the only sibling sentinel with BOTH a per-output
scene tree AND a per-deck flag that can disagree across outputs. Do not give
any future sentinel this split without a location-aware toggle.
