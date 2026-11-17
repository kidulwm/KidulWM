# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (2026-11-17)

  STEP 4 AUTH-STRUCTURE — the proof->mount sequence (MOUNT half) DONE + LIVE-PROVEN.
    - kushd b4ff2db: on a TRUSTED verdict, drives resolve (kalloc resolve -> token)
      -> open (kopen <by-partuuid/token> <token> <vault>/<key>.key) -> mount (kmount
      <key> /home/<key-id>, same map/sig/pub passed), non-blocking, fail-closed +
      rollback (kclose), crew ("none") no-op.
    - kidulkey d20a9db: kcarve (the carve verb — partition + LUKS2 + keygen + vault
      park; mkfs stays app-side). 7 verbs total (kalloc/kopen/kmount/kumount/kclose/
      kclean/kcarve).
    - vault-shape RESOLVED: interim plain 0600 keyfile now, kidulKey-wrap -> SE050
      backlog. Boot-mode taxonomy + defaultHome step recorded in the census.
    - Rig-proven fake + real verbs. mount(2) SUCCESS still mkfs-gated (the app's step).

  CARRIED THREADS (do not lose):
    - KSD NOT deployed: repos ahead of /mnt/ksd — mount first, then deploy.
    - KSD DRIVE (nvme1) PRESENT BUT UNMOUNTED: /mnt/ksd empty — mount first.
    - kboot + kslide-template now CLEAN (both committed; kslide stopped tracking
      build artifacts).

  NEXT SESSION: step 4b = RE-SEAT (re-mint the session public uid 1001 -> proved
    owner — the HARD half; design-freeze-first), then claim/carve (kcarve -> kalloc
    sign), the Homes provisioning UI (fill bar + name, step 6), defaultHome skeleton.
    Fire 'next' -> docket #59 resolves to re-seat. Handoff = CENSUS-NOTES top +
    kidulkey skill (the seq pattern + stderr gotcha).

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
