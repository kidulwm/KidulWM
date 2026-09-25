# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — verdict 61 = current position + next test

## Current position (2026-09-25)

  - Verdict 61 FIXED + DEPLOYED (kmedia b55fda1 + 51817f9, binary c8b2d9da): the
    "second movie won't play" kplayd poll-loop wedge. REAL cause = the PRESENT
    path: render() -> eglSwapBuffers (interval 1) blocked in
    wl_display_dispatch_queue forever once the slide closed and the compositor
    stopped presenting. Fix = eglSwapInterval(0) (never blocks; vsync pacing is
    the frame-callback gate), plus door (b) bounded teardown (threads_alive +
    2s join + exit(1)). Also shipped: O_NONBLOCK read path (a separate latent
    wedge). See CENSUS verdict 61. Drop-back = .bak-6909a72a (read-path-only)
    / .bak-a64ef0c3 (verdict 59).
  - Verdict 60 DEPLOYED + LIVE (KidulWM a1b2928, kidulwm 03d9f15d): idle-blank
    no longer cuts fullscreen video (playbackInhibitsBlank sees video_fullscreen).
    Relog already done — the running compositor is 03d9f15d.
  - Verdict 59 DEPLOYED + LIVE (kmedia 5e1cb13): live-TV reconnect open now
    carries rw_timeout (no play-until-reboot on a dead feed).

## Next action

  Eye-test on the TV (Barticus), all owed this session:
    - play -> close -> play x3 (the second movie must just play).
    - live channel -> let it cut -> close -> play (no wedge).
    - after close: ls /proc/$(pgrep -x kplayd)/fd | grep renderD128 == empty.
    - simulated wedge (kill -STOP the reader, then close) -> systemd respawns <3s.
  Then the separate session-30 clean-close VA-device leak (third ref in
  Gl.zig importVaFrame) — the RAM climber; needs the import-path repro before
  any unref (no UAF guess).

## Trip wires / commands / secrets

  KNOWN_CMDS.md   build, deploy, VM (ksd-reset 192.168.122.87 / fresh-one FROZEN), SSH
  AGENTS.md       secrets map + agent strategy + build gotchas
