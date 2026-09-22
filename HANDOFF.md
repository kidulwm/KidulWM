# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — verdict 56 = current position + next test

## Current position (2026-09-22)

  - Verdict 56 DEPLOYED (binary 5438118f): the .video slide is DELETED,
    fullscreen is a MODE the card enters/leaves. See CENSUS verdicts 57+56.
    .bak-1afc2343 (verdict 55) is the drop-back.
  - Verdict 57 (this session): the idle-RAM wedge (~800MB after videos) is
    the OLD .video slide's retained buffers — SAME-GPU, so verdict 53's
    "cross-GPU closed" was wrong/incomplete. 28 x ~27-30MB MAP_PRIVATE anon
    chunks in kidulwm's smaps, surviving close. Verdict 56 deletes the path.
  - Separate OPEN leak (kmedia/kplayd): VA-API device per video (~1
    renderD128 fd + ~72-133MB GEM each). Plain decode probe closes clean ->
    extra ref lives in the zero-copy export/import path; needs that repro
    before fixing. Recorded in kmedia HANDOFF + CENSUS verdict 57.

## Next action

  Relog (kidulwm picks up 5438118f). Play 2-3 videos to natural end + quit.
  Then verify BOTH: kidulwm RSS ~900MB and FLAT after warmup; and idle
  `ls /proc/$(pgrep -x kplayd)/fd | grep renderD128` = 0. Drop-back if the
  fullscreen fade misbehaves = kidulwm.bak-1afc2343.

## Trip wires / commands / secrets

  KNOWN_CMDS.md   build, deploy, VM (ksd-reset 192.168.122.87 / fresh-one FROZEN), SSH
  AGENTS.md       secrets map + agent strategy + build gotchas