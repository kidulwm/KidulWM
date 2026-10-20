# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (2026-10-20)

  MEGA ROACH C1 (docket #24) — the media model swap. C1 PREP DONE + committed:
    - refresh law (library-model) + lazy-art law (art-chain) LOCKED, kmedia
      92acd54. Four triggers (additions=inotify / removals=lazy-miss / manual=
      rescan-button / purchase=inject-on-delivery), no timer, no boot scan; art
      resolved only on request.
    - scanreal real-drive proof GREEN, kmedia 5636e96: Scanner produces the
      real /mnt/sda_backup/Jelly library (127 = 119 movie / 8 series / 0
      collection). Drop-in for media.zig's find-based model.
    - boot-state law LOCKED + committed, KidulWM 3e3051e (docket #8).
  C1 SLICE 1 DONE (this session, verdict 135): find-shell scan + boot prewarm
    retired. media.zig builds the library lazily on first media-card open via
    kmedia Scanner (scanRootAs/scanMusic), flattened into the same per-file
    LibraryEntry the wall renders (flat bridge). execFind/scanCategory(popen)/
    prewarmThread/spawnPrewarm + server.zig spawnPrewarm call all deleted.
    PARITY PROVEN: movies 516 = find 516, music 27 = 27 (scanreal flatten).
    Commits KidulWM 0b67e5a + kmedia 4ab8e2d. DEPLOYED to ksd-reset (sha
    9e2a990d, .bak-c1slice1) — smoke green (TV scan in-process, no panic).
    NOT retired yet: g_movies/g_music/g_tv globals + LibraryEntry — they die
    with C2 (kmedia becomes the client; WM stops owning media presentation).
  NEXT: C2 client-ify — make kmedia a standalone Wayland client (foreign
    surface, xdg-toplevel), no compositor scene tree, no render-to-buffer.
    No kushd gate (that is C3). Host relog first to eyeball slice 1 (media
    wall = all 516 movies / 27 music, identical look, now from Scanner).

  kmedia lane: A/V drift wind-up fix is COMMITTED (cf21d2f) + DEPLOYED
  (/usr/local/bin/kplayd sha fbf7b926), UNVERIFIED by a real movie — next
  movie play is the check (should hold ~±6ms, not ramp).

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
