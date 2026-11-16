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

## Owner authority — all logs, zero standing read for B&B (Barticus 2026-11-16)

The OWNER seat holds the full history and the highest priority (QoS + policy,
cells.md). The ROOT (the B&B signing key) and B&B the agent hold ZERO standing
READ — not even the live logs. The drain (root) WRITES logs and never reads them
back. Logs past the ~200MB window rotate into the owner's encrypted .md archive,
decryptable ONLY by the owner (logs.md). The owner is truly the owner: the whole
immutable record is theirs; everyone else is architecturally blinded to it,
provably, in code — not a promise.

B&B (us) reads a log ONLY when the user grants it: a kidulKey tap = consent, a
scoped read for that one task, then it closes. Zero standing access is the
"monkey off our back" — we can't do it if we tried, and that's provable. The
owner may delegate a scoped read to a service-bob (security / customer-service)
the same way: ON REQUEST, a grant on the delegation tree (delegation.md: log
read is attenuating), never standing access. Safety (encryption) + ownership
(owner holds the data) + usability (delegate on request).

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
