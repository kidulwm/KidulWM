# LAW — the key-entry flow (claim vs sign-in) (DRAFT — pending GSI)

The kidulKey pill opens the key-entry slide — the surface where the kidulKey
proves WHO you are and the system seats you. One door, two flows. KISS: no
password field ever appears.

## Two flows (Barticus 2026-11-16)

  claim    (first boot / empty roster)  the FIRST key to prove on a fresh
           system IS the owner. The roster is empty, so the first proof seeds
           it: the key's identity becomes the roster's first entry (owner),
           and the owner's ROOT signs the roster from then on. This is the
           "initial login" — once per system, then never again.
  sign-in  (after setup)                prove -> resolve against the signed
           roster -> seat as the resolved role (tv / child-1..5 / guest /
           adult / nas / remote / owner / ...). The "after-setup" sign in.

The roster being empty IS the unclaimed state — no separate "claimed" flag.
"Empty roster -> claim; non-empty -> sign in." deny-by-default throughout
(kid.md, roster-format.md): an absent or struck key never seats.

## The surface (KISS)

The kidulKey pill opens the key-entry slide (a normal slide, like Library).
Inside, one prompt: "tap your key" (WYSIWYS — device-proof.md). On proof the
gate (kidulkey-gate) returns the role; kushd then re-seats the public session
as that role (re-mint, not a seatUid() tweak — docket). "People" is the
granted roster the owner manages (delegation.md); "rando sign-in" (attach
your own drive + own key) is a later sub-flow, same door.

## The test-key scenario (done-when)

  1. crypto (this session)   a signed test roster maps the live dongle's key
                             -> a role; kidulkey-gate challenges it, the human
                             taps, and the gate prints TRUSTED role=<role>.
  2. claim                   empty roster + first proof seeds owner (the
                             roster is born from the first tap).
  3. surface                 the key-entry slide wired to gate + kushd seat.

## Relationship to existing law

  kidulkey.md       the key family, two-key rule, WYSIWYS (unchanged).
  roster-format.md  the roster shape + deny-by-default (unchanged).
  device-proof.md   the tap-to-sign proof (unchanged).
  delegation.md     "People" = the admin/roster door (the owner manages it).
  public-seat.md    owner uid 1002 / public uid 1001 (the seat targets).
