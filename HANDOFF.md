# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (relog 2026-10-14)

  MEGA ROACH (docket #24): extract the media brain out of the WM. The media
  player is the one compositor-owned app — its scan/library/art/watch-state
  lives in kidulwm/src/ui/media.zig instead of a separate client process.
  LAW LOCKED: docs/law/slide-process.md ("APP owns CONTENT, WM owns WINDOW,
  SLIDE is a PLACEMENT"). Naming: GLOSSARY.md (KEYE/kbrain/content). Cards
  C1-C5 live in slide-process.md — reconcile the two model copies to ONE, make
  kmedia a Wayland client, seat via kushd, hand play to kplayd, delete both
  dead copies. Prove in VM (ksd-reset pixman) before host. GATE: kushd is
  built+installed but NOT running — C3 needs it live.

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
