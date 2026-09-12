# LAW: SCREENS — 1 boss, 1 truth (DRAFT for Barticus lock, 2026-09-12)

## The sentence
The Boss is the computer. Screens are numbered slaves. The Boss sends
the visuals to the screens and the sound to the speakers — on time,
every time. Nothing else holds anything.

## LAW 1 — The Boss
There is exactly ONE boss and it is THE COMPUTER — never a screen.
The Boss owns ALL truth and ALL work:
  - the player, the clock (DAC), the ksound floor table
  - every truth query (audio_live, player state, liveness)
  - the compositor, the play_timer, the scene graph
Giving any of this to anything else (a screen, a widget, a mirror) is
how the ghosts got in: +707ms, stale dot, frozen second video — every
one was an ownership leak, something holding a piece of truth and
lying about it later.

## LAW 2 — Slaves are numbered addresses
Every screen is a slave, numbered in connect order: slave 1, 2, 3...
A slave is a scanout target — a cable, not a computer. Zero slaves =
headless; perfectly expressible, nothing breaks. Slaves never own
state, never derive truth, never pace anything. Unplug a slave and
nothing anywhere else changes.

## LAW 3 — The pack
Widgets + controls + the crawl are a PACK — one indivisible thing the
Boss holds and deals to exactly ONE slave at a time. Default: slave 1
(first connected). The user may move the pack to another slave; it is
a grant, not a birthright, and it is always in exactly one place.
The slave holding the pack disappears → the pack returns to the Boss →
redealt (lowest-numbered slave, or the user's standing pick).

## LAW 4 — Slides ride focus
Slides (the media slide included) open on the screen in focus — any
slave. Content follows the eyes; the pack stays where it was dealt.

## LAW 5 — One clock, borrowed crystals
The Boss's clock is the DAC. Presentation on any slave quantizes to
THAT slave's vsync interval (wlr_output.refresh, read live — screens
report their credentials; we never store per-screen timing tables).
One clock, one timer, and the Boss asks the presenting slave "what's
your beat?" each frame. A borrowed crystal is a parameter, not an owner.

## LAW 6 — Latency honesty
Boss-owns-everything adds ZERO latency: truth queries are intra-process
or ~50µs cached socket reads; video is zero-copy dmabuf into the
slave's scene node; the HDMI cable carries pixels at the screen's own
refresh. The only real offset is vsync phase (slaves are not
phase-locked; worst case one frame period) — handled by LAW 5.

## Why this law exists (census record)
2026-09-09→12 hunt: every persistent media bug traced to ownership
ambiguity — which output's timer, which widget's player, which tray's
liveness, which screen's vsync. N owners = N truths = ghosts.
The Master/slave-screens metaphor was wrong because it made a SCREEN
special; the correct unit of ownership is the machine. Boss/slaves/pack
(Barticus, 2026-09-12) makes every ownership question have a constant
answer. Design target: Granny has ONE TV — slave 1 holds the pack and
that is the whole story. The wall of screens is the flex, and the flex
is a degenerate case of the product.
