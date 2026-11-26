# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (2026-11-27, updated after the parity cut)

  KPLAYD AUDIO LIFETIME — sound is a ROOTFS gap, not a front-end bug. The
  2026-11-27 mirror-host parity read landed its two real halves (see below) and
  killed the misdiagnosis: the pulse stream ksound watches is kplayd's OWN
  (Player.zig:773 registers it under the hardcoded name "kmedia"), and ksound
  LAW 5 reaps a stream whose owner pid dies. The 233<->234 flip = kplayd being
  replaced mid-play. Same class as the missing libigdgmm.so.12 (no iHD -> no
  VAAPI -> software GL, frames commit but present black) and the libOpenCL
  exit-127 boot loop.

  LANDED (bobdotrix, kmedia da1b9ed, deployed /mnt/ksd/usr/local/bin/kmedia sha
  f9d989ed, m.2 back ro):
    CUT 1 music BACKGROUNDS — new `audio_active`; music no longer sets
      player_active, so Wayland.zig never calls xdg_toplevel_set_fullscreen and
      render() keeps painting the wall. Keys stay local; Escape stops audio.
    CUT 2 TV pill mirrors host — watch.state read once (WatchState.readText),
      tv.sortByWatchCounts in App.init, rebuild() lands .tv on
      TvChannels.lastWatchedIndex() (live-tv.md §Watch-state).
    RETRACTED (do not build): "leaveGrid must clear up_plus_one" (R4 landing IS
      up_plus_one) and "adjustScrollToSelection must clamp" (host
      max_scroll_offset = total_rows-1, the clamp is a no-op).
  VERIFIED: zig build clean; walltest PASSES on real roots (CLEAN EXIT).

## Prior attack (2026-11-27 morning — BITE 2, superseded)

  BITE 2 — PROVE SOUND + VISION ON KSD. Session 2026-11-27 (bobdotrix) diagnosed
  the first live-TV-attempt post-re-slice.

  CODE VERIFIED ABOARD: deployed kmedia sha f96982bd == git HEAD 9b6fa05 (R4 wall)
  byte-identical; kidulwm has mediaCardToggle=3 (client-spawn, R2); media.env +
  kidulwm-session + bill.kush kplayd=body all present. Library SCAN WORKS (86
  items — the R4 wall + env seam is alive).

  BLOCKERS DIAGNOSED + ONE FIXED:
    1. INTEGER OVERFLOW at Wall.zig:493+505: enterGrid/exitUpPlusOne `n-1` underflows
       when pill has 0 cards → panic. FIXED (a5b8add): n-1 → n-|1. DEPLOYED to
       /mnt/ksd/usr/local/bin/kmedia sha 74e3adcf.
    2. SEGFAULT at 0x40 in buildMediaCards (line 275) ← movePillLeft on LEFT-arrow
       from TV → Movies. NOT fully diagnosed. Headless pass (walltest sort/card ok);
       may be Cairo/font-config under empty $HOME on KSD, or a layout corruption.
       Fresh crash log from new binary will narrow.

  kplayd STATUS: crash-looped on libOpenCL.so.1 ~25x at last boot before stabilizing
  (chroot ldd NOW clean — libOpenCL present, ld.so.cache regenerated 00:18, kushd
  final seat = kplayd pid=236 stable, "listening on /run/user/1001/kplay.sock").
  Audio stack PROBABLY UP. Verify at next boot: kushd-kplayd.log "listening" at END.

  FRAMETRACE: last session kplay=0, fullscreen enter=0, video revealed=0 — NO
  playback was ever initiated (client segfaulted on nav before sending open_live
  to kplayd). Sound = none for same reason.

  NEXT BOOT ACTION (Barticus):
    - MUSIC: Enter a music card → audio plays, wall stays UP and navigable, NO
      black fullscreen; Escape stops it.
    - TV: watch a channel, back out, switch pills and return → TV lands on that
      channel and the most-watched has risen to the top.
    - Then watch /mnt/ksd/var/log/kushd-kplayd.log: if the stream's pid still
      flips mid-play, kplayd is dying (rootfs) — that is the current docket.

  NEXT DOCKET (bobdotrix, post boot):
    - Read /mnt/ksd/var/log/kushd-kplayd.log → "listening" at END = kplayd UP
    - Read /mnt/ksd/var/log/kushd-spawn.log → crash traces (if any)
    - Read /mnt/ksd/var/log/kushd-kidulwm.log → FRAMETRACE kplay=N, fullscreen enter/reveal
    - If segfault persists: diagnose 0x40 with fresh binary, fix, redeploy
    - If client survives nav: verify open_live reaches kplayd, then sound+vision

  CARRIED (claim/carve, frozen): carve-subvolume + re-seat + privacy guard +
  kidulkey lanes — parked behind BITE 2, not blocking.

  kmedia HANDOFF: separate file at /home/dad/dev/kmedia/HANDOFF.md — prior sessions
  (50-53) are audio-master clock fix + present-throttle investigation. This session's
  fixes are in CENSUS-NOTES (top) + the kmedia commit history.

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
  m.2 time barometer (is this the latest boot?):
    mount | grep /mnt/ksd → ro? → find /mnt/ksd -newermt "YYYY-MM-DD HH:MM" = empty
    → those logs are the last boot. No guessing.
  ld.so.cache check: `strings /mnt/ksd/etc/ld.so.cache | grep <libname>` — verify
    every needed lib is IN the cache before telling Barticus "it'll resolve."
