# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (2026-11-23)

  STEP 4 — RE-SEAT + CONDUCTOR-RECONNECT PROBE: PASSED ON REAL HARDWARE.
    The tower booted Boot0001 "KSD" and ran clean. The three most recent boots
    seat kidulwm class=conductor uid 990 (bill.kush), /etc/kushd/conductor = "990",
    current boot has ZERO died-kidulwm / panic / refused. Surface rename live:
    "UserHome summoned (KidulHome → UserHome)". homes-gate end-to-end correct
    (freeze → TRUSTED role=owner / UNTRUSTED / busy → resolve → "no local
    partition" → thaw). The crash-loop in the trail (status=6/256) was ALL
    pre-conductor-flip class=user history — the flip FIXED it. Also fixed
    boot-watch.sh blindness (NUL padding + wrong 990 lookup) — KidulWM b0dc01b,
    signed B&B, pushed Codeberg+GitHub.

  CARRIED THREADS (do not lose):
    - KidulWM is the ONLY repo touched this slice (tools/boot-watch.sh) — committed
      + pushed clean. kushd/kboot/kidulkey all clean (only build.log untracked).
    - 2nd dongle still to order (real two-key cold SE050 ceremony deferred —
      current is a DISPOSABLE dev root, test-namespaced, TEST-ONLY).
    - Vault keyfile still 0 (no carve yet).

  NEXT SESSION: PRIVACY GUARD — owner frames blank/blur on lock/re-auth, never a
    persisted snapshot. Then claim/carve (kcarve -> kalloc sign) -> Homes
    provisioning UI (fill bar + name) -> defaultHome skeleton. Full design frozen
    (re-seat.md + re-seat-mount.draft.md + re-seat-entry.draft.md, all 6 steps
    built + proven). Handoff = CENSUS-NOTES top + re-seat.md (law) +
    re-seat-entry.draft.md (build order).

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
