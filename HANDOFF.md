# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (2026-11-25)

  CLAIM/CARVE — STEPS 1+3+4 BUILT + PUSHED; DISK-GUARD LAW LOCKED (d25a228).

  The claim/carve slice (docs/design/claim-carve.draft.md) has landed through
  step 4 in three trees: claim detection (kushd e424f21 route CLAIM verdict +
  gate c934fea three-way split), the ceremony surface (KidulWM 613e280 name
  letter-walk + fill bar + consent nag, both input surfaces from scratch, +
  d9256a6 hold-to-fine repeat), and the carve wiring (kushd cf7fab9 retain
  claim key-id + 096c021 homes-carve verb — label->parent-disk resolution
  fail-closed, fork kcarve, relay CARVED). Disk-guard LAW LOCKED (d25a228,
  btrfs SUBVOLUME carve unit / fscrypt deferred / drive-class per-deployment).

  CARRIED THREADS (do not lose):
    - STEP 4 RECONCILIATION (the live divergence): kcarve + homes-carve carve a
      raw PARTITION (sgdisk -n + LUKS2), but disk-guard ruling A made the
      production carve unit a btrfs SUBVOLUME. Reconcile the carve mechanism
      against ruling A before step 5, or rule it explicitly deferred.
    - step 5 = allocation + roster seed, SIGNED with the PROVED owner key via
      the gate (NEVER kalloc's TEST seed) — the signing boundary.
    - steps 6 (defaultHome skeleton) + 7 (mount-on-proof close) follow.
    - NOT deployed to KSD this cut; 2nd dongle still to order; vault keyfile
      still 0 (no real carve has run).

  NEXT SESSION: reconcile step 4 carve unit (subvolume vs partition), then
    build step 5 (seed + sign with proved owner key). Handoff = CENSUS-NOTES
    top + claim-carve.draft.md (build order) + disk-guard.md (law).

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
