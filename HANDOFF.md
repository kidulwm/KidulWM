# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (relog 2026-10-19)

  MEGA ROACH C1 (docket #24) — the media model swap. C1 PREP DONE + committed:
    - refresh law (library-model) + lazy-art law (art-chain) LOCKED, kmedia
      92acd54. Four triggers (additions=inotify / removals=lazy-miss / manual=
      rescan-button / purchase=inject-on-delivery), no timer, no boot scan; art
      resolved only on request.
    - scanreal real-drive proof GREEN, kmedia 5636e96: Scanner produces the
      real /mnt/sda_backup/Jelly library (127 = 119 movie / 8 series / 0
      collection). Drop-in for media.zig's find-based model.
    - boot-state law LOCKED + committed, KidulWM 3e3051e (docket #8).
  NEXT SESSION KICKS OFF at slice 1: retire prewarmThread/scanCategory/execFind
  + g_movies/g_music/g_tv globals in src/ui/media.zig; build Scanner.Library
  lazily on media-card open (NOT at boot). VM-first (ksd-reset, pixman), small
  incremental commits. FOUND: kmedia App.zig writes library.cache but never
  loads it — cache-load path is unbuilt C1 work.

  kmedia lane: A/V drift wind-up fix is COMMITTED (cf21d2f) + DEPLOYED
  (/usr/local/bin/kplayd sha fbf7b926), UNVERIFIED by a real movie — next
  movie play is the check (should hold ~±6ms, not ramp).

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
