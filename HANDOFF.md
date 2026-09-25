# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — verdict 62 = current position + next test

## Current position (2026-09-25, pre-reboot)

  - Verdict 62 (current): the RAM climb (~5GB) is TWO leaks, both through the
    zero-copy present path — (a) kidulwm compositor 2.5GB RSS = verdict-57
    dmabuf-staging fingerprint (33 x ~27.8MB anon chunks), retention returned
    via per-frame setBuffer -> texture recreate -> GEM leak; (b) kplayd 224MB =
    session-30 VA-device leak (~1 renderD128 fd + ~72-133MB GEM per video).
    Also: VAAPI "hwaccel init error" since ~16:19 (decode falls to software) —
    suspected wedged iHD driver from the leaks; REBOOT to confirm.
  - Verdict 61 FIXED + DEPLOYED (kmedia b55fda1 + 51817f9, binary c8b2d9da): the
    "second movie won't play" poll-loop wedge — real cause was the PRESENT path
    (eglSwapBuffers interval 1 blocked in wl_display_dispatch_queue forever once
    the slide closed). Fix = eglSwapInterval(0). Play-close-play CONFIRMED
    working by Barticus. Drop-back = .bak-6909a72a / .bak-a64ef0c3.
  - Verdict 60 DEPLOYED + LIVE (kidulwm 03d9f15d): idle-blank no longer cuts
    fullscreen video. Relog already done.
  - Verdict 59 DEPLOYED + LIVE (kmedia 5e1cb13): live-TV reconnect open carries
    rw_timeout.

## Next action (post-reboot, in order)

  1. REBOOT/relog (bobdotrix dies on relog — this file is the bridge).
  2. Verify VAAPI returns: play a video, grep "VA-API hw decode ACTIVE" in the
     journal. Absent = driver still wedged (separate issue).
  3. Pin + fix the compositor retention (THE 2.5GB fish): per-frame setBuffer ->
     texture recreate -> GEM leak. Fix = cache imported buffer per VASurfaceID
     (~8 slots), create scene node once, setBuffer the cached entry; or
     destroy+recreate node on surface CHANGE. See verdict 52 Card A + the
     video-playback-architecture skill.
  4. Then the kplayd VA-device leak (session 30): pin the import-path ref before
     any unref (no UAF guess). C probe /tmp/vadevice_probe.c is the template.

## Trip wires / commands / secrets

  KNOWN_CMDS.md   build, deploy, VM (ksd-reset 192.168.122.87 / fresh-one FROZEN), SSH
  AGENTS.md       secrets map + agent strategy + build gotchas
