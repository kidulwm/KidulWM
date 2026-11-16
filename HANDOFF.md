# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (2026-11-16)

  THE APEX (attestation) — security law arc FROZEN this session, ZERO built.
    - Commits 7f47732..7b7ac97: kidulkey-entry.md (claim vs sign-in, one key
      many seats), logs.md (zero standing read, on-demand key-tap grant),
      attestation.md (THE APEX: the kidulKey is the GATE — verifies the host,
      refuses to unseal on a dirty one), kidulkey.md (GATE role added).
    - The surgery (next build phase): partition/isolation + fTPM wiring +
      key-hardware + sealed-secret release + kushd seat. All unbuilt; the law
      is the spec the build must obey.
    - Pill bar work (0f2559d + cfe2113) DONE + recorded, NOT deployed.

  CARRIED THREADS (do not lose):
    - kboot UNCOMMITTED: seed-users.sh + src/main.zig (mtime Nov 13).
    - kslide-template dirty: zig-out/bin/kslide-template.
    - KSD NOT deployed: repo ahead of /mnt/ksd (still ddd961c).
    - KSD DRIVE (nvme1) PRESENT BUT UNMOUNTED: /mnt/ksd empty — mount first.

  NEXT SESSION: the surgery (partition/isolation first, then fTPM + key-hardware
    + attestation), or fire 'next' for the top non-DONE docket. Law is frozen;
    build starts from clean context on top of it.

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
