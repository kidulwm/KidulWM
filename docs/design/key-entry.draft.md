# DESIGN DRAFT — the key-entry slice (SUPERSEDED — folded into docs/law/settings.md)

Superseded 2026-11-16: Barticus locked the settings architecture into
docs/law/settings.md (Admin immutable vs Settings transportable, Mod4+T
keybind, sub-admin = delegation tree). This draft's build order was folded
there. Kept for the archive; see the law for the live rulings.

## Why now (unblocked)

#57 was sequenced behind two prerequisites, both now DONE:
  (1) input-trust re-boot-test  -> KSD boots + renders + input works (#54 MET).
  (2) Tier-2 crypto proof -> roster  -> LIVE-PROVEN: dongle 20a6b571...aabe ->
      gate -> signed roster -> TRUSTED role=owner (kidulkey/gate, this week).
So the "person" key exchange — the first user-VISIBLE consumer of the proof —
is the next slice. It is the wall that makes security VISIBLE (security-by-
invisibility is REJECTED — #57 why).

## What it is (one sentence)

A keybind opens the settings app (a normal slide, like Library); inside it,
"person" fires the kidulKey proof -> kushd re-seats the public session as the
resolved role -> kidulwm landing reveals the full roster. No password, no sudo
binary. Later the settings app rides the GPB pill bar in the SAME cut as every
other app — nothing bespoke.

## The surface (KISS, from kidulkey-entry.md "the surface")

  - The settings app IS a normal slide — same spawn + kind as Library, no
    special-casing. Opened by a KEYBIND now (exactly like ktty = Mod4+y today);
    it attaches to the GPB pill bar later.
  - Inside: one entry "person" (access required). Opening it shows ONE prompt:
    "tap your key" (WYSIWYS — device-proof.md). No password field ever.
  - On proof the gate returns the role; the session re-seats. "People" (the
    granted roster the owner manages, delegation.md) lives in the same app.

## The flow (two doors, one surface — kidulkey-entry.md)

  claim     (empty roster / first boot): the FIRST key to prove seeds the
            roster — its identity becomes entry #1 (owner), the owner's ROOT
            signs the roster from then on. Once per system, never again.
            "Empty roster -> claim" is the ONLY unclaimed state — no flag.
  sign-in   (after setup): prove -> resolve against the signed roster -> list
            the key's ROLE SET -> pick the seat -> seat grants the partition
            (partitions.md) + priority. deny-by-default throughout.

  Resolution returns the FULL role set, not the first match (one key, many
  seats). The roster FORMAT is unchanged; resolution + sign-in flow change.

## The wiring (build order — incremental, testable each step)

  1. KEYBIND -> SETTINGS SLIDE   add a keybind (proposal: Mod4+k, "settings";
     key chord is Barticus's call) that spawns a settings slide (kind .slide,
     modeled on Library's spawn). Empty shell first: title "Settings" + the
     "person" row. Proves the spawn + focus path.
  2. KEY-ENTRY SCREEN            opening "person" swaps the slide content to the
     one-prompt "tap your key" surface (no password field). Proves the in-slide
     navigation.
  3. GATE PROOF (reuse, built)   the tap -> kidulkey-gate challenge/verify ->
     "TRUSTED role=<role>" line. This is ALREADY live (slice 4 + this week's
     test roster); the slice only wires the slide's tap to the gate's verdict,
     not re-build the crypto.
  4. KUSHD RE-MINT (the real new code)   on proof, kushd RE-SEATS the session
     as the resolved role: public (uid 1001) -> owner (uid 1002, random-hash
     name). This is a kushd RE-MINT feature (the seat was minted once at boot;
     escalation is a later re-mint) — NOT a seatUid() tweak. kushd/src/main.zig
     is where the seat is minted today.
  5. LANDING REVEAL              kidulwm's landing shows the FULL roster on an
     owner seat (admin access via the key), public roster on public. This is
     the "crossing over" made visible.
  6. CLAIM FLOW                  empty roster -> first proof seeds the roster as
     owner (the roster is born from the first tap). Gates every later sign-in.

  Order note (SPEC BEFORE SURFACE): 1-2 are surface, 3-6 are the mechanism the
  surface fires. Build 1 -> 2 -> 3 -> 4 -> 5 -> 6 in order; each lands green
  before the next.

## done-when (kidulkey-entry.md test-key scenario, collapsed)

  - a keybind opens the settings app; "person" shows "tap your key";
  - the tap proves against the roster and re-seats the session as the resolved
    role (claim seeds owner on an empty roster; sign-in resolves the role set);
  - the landing reveals the full roster on owner, public roster on public;
  - no password field and no sudo binary anywhere in the path.

## Open questions (Barticus's verdict)

  1. Keybind chord for the settings app (proposal Mod4+k; ktty already holds
     Mod4+y). Confirm or rename.
  2. First cut scope: full settings shell (title + person + People roster
     view) vs minimal person-only slide. Proposal: minimal — "person" first,
     People-roster view is its own later cut (delegation.md surface).
  3. Deploy ordering (loose end): the GPB + kidul-flow + re-centred pill bar
     are BUILT but NOT deployed (/mnt/ksd still ddd961c, nvme1 unmounted). Do
     we VM-prove + deploy that first, or build this slice while it waits?

## Not this slice (explicitly out of scope)

  - The GPB pill-bar attachment of the settings app (the SHARED cut with every
    other app — a later, separate cut per #57 state).
  - partition MECHANISM (key-gated mount) — #59 step (4), after this slice.
  - fTPM quote + sealed-secret release — the attestation APEX build, later.
  - "rando sign-in" (attach own drive + key) — later sub-flow, same door.
