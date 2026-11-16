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

## One key, many seats (Barticus 2026-11-16)

Until the real kidulKey hardware arrives (not yet designed — the current
nRF52840 dongle is not USB-C), the ONE dongle key is the TEMPORARY B&B key: it
serves as the prototype signing ROOT (the "fake B&B signature" — immutable
root, roster, git B&B identity, upgrades) AND as the identity for every test
seat (ROOT / owner / user2 / a second Granny account / ...). It is a stand-in —
"fake" only in that it is not the final hardware — and is retired the moment we
lock in the right key. The password backup stays in place until then
(kidulkey.md safety rule: we never lock ourselves out).

Rulings that OUTLIVE the prototype:
  - one key, many seats   one physical key = one identity; that identity holds
    MANY seats (accounts). The same key signs in to any of them.
  - key grants identity, NOT authority   the SEAT determines what you can see
    and do — never the key. Even the King's B&B key, seated as user2, sees ONLY
    user2's partition; B&B cannot see what user2 is doing. Root-signing power
    (WHO signs the system) is strictly separate from seat visibility (WHAT a
    seat can see). Privacy is per-seat, even against the signing key's holder.

Roster consequence: resolve returns a key's full ROLE SET (not the first match),
and sign-in becomes prove -> list the key's roles -> pick the seat -> the seat
grants the partition (partitions.md) + priority. The roster FORMAT is unchanged
(a key may already carry several entries); the resolution + the sign-in flow
change.

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
