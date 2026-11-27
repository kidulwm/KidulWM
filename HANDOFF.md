# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (2026-11-27 last — "WE HAVE SOUND": AMP FIX HELD, THREE FAULTS OPEN)

  Sound is AUDIBLE on KSD. The silence was never code: ksd-mixer.log shows
  Master 0% [-65.25dB] [off] before ksd-mixer-init and 87 [100%] [0dB] [on]
  after. Nothing else changed. What stands between us and a working player:

  (a) MUSIC CRACKLE — "like multiples of the same track". NOT a pile-up: the
      boot's pipewire log holds exactly ONE kmedia node at a time (six
      create/destroy cycles, zero overlap). Lead suspect: the latency-feedback
      pacer targets a hardcoded 100ms while the graph reports the node at
      1440/48000 = 30ms, so the correction is permanently ~ -35ms and the
      player over-writes the sink until PipeWire drops the overflow. Music is
      also the only 44.1k->48k swresample path. The instrument that would have
      said so was DEAD — ksd-streamwatch called `pactl`, which the image does
      not ship; it logged one `sink-inputs=0` line and went silent. REWRITTEN
      to pw-cli + a DAC delay/avail/hw_ptr trace, deployed. One boot decides.

  (b) MOVIE, NO PICTURE — VA-API ACTIVE, P010 whole-surface import live,
      kplay composited 1281 frames, then isDone at 26.7s of a 3h film. Test:
      play one 8-bit NV12 film. Shows -> the P010 sampler is the fault.
      Also black -> the display path is.

  (c) TV DEAD — it IS attached: DP-3 3840x2160@30, enabled, and FRAMETRACE-OUT
      freezes it at rendered=126 while eDP-1 climbs to 3779. Its hdmi-stereo
      sink IS enumerated but is not the default (nothing routes to it), and the
      TV channels need network + a CA store (bundle + `ca_file` LANDED this
      session; DNS was still failing at 03:02).

  LANDED + DEPLOYED this session: kplayd sha 912921c1 (4,682,064B, ca_file at
  both live-open sites; rollback .prev-20261127-1316), ksd-streamwatch 3,686B,
  /etc/ssl/certs/ca-certificates.crt 185,311B. Drive back to ro. Prior slice
  (SINK CAPS, EDID LPCM) landed in the census entry below it.

  DO NOT COMMIT THE kmedia TREE. Barticus, verbatim: "keep it as is until we
  have a working player; once we can prove it works, then we commit 'minus the
  PII'." The dirty tree IS the artifact if a relog kills this session.

  Barticus: "a movie should surf the card's channels, be it 2.1, 5.1 or atmos."
  The player was lying: Player.zig hardcoded `AUDIO_CHANNELS = 2`, so every 5.1
  film was folded to stereo BEFORE the graph saw it (centre mixed into L/R,
  dialogue with it) and an 8ch sink was never offered 8ch. Channels are now read
  per open from the sink's EDID; out = min(sink, source); never up-mix; the
  x0.707 fold guard applies only when a fold really happens. Law:
  kmedia/docs/law/audio-sink.md (8 rules + evidence + the open list).

  LANDED + DEPLOYED (bobdotrix, kmedia — TREE DELIBERATELY DIRTY, see below):
    src/player/SinkCaps.zig  EDID CEA-861 LPCM parse from /sys/class/drm,
                             quantise 1/2/6/8, KMEDIA_AUDIO_CHANNELS override,
                             every failure = 2ch (unknown never reads as capable)
    src/player/Player.zig    aud_channels decided per open, av layout default,
                             explicit pa_channel_map above 2ch, mono dupes to 2
    build steps              `zig build sinkcaps`    10/10 unit tests
                             `zig build sinkpolicy`  4/4 end-to-end cases
    deployed                 /mnt/ksd/usr/local/bin/kplayd sha 514a7ed5 (4,681,760B)
                             rollback  .prev-20261127-1241 (4,429,888 = this morning)
                             NEEDED set identical to the old binary; drive back to ro

  DO NOT COMMIT THE kmedia TREE. Barticus, verbatim: "keep it as is until we
  have a working player; once we can prove it works, then we commit 'minus the
  PII'." The dirty tree IS the artifact if a relog kills this session.

  NEXT BOOT ACTION (Barticus) — read this journal line before touching anything:
    [player] audio out Nch (sink Mch via edid|override|fallback, source Kch)
  M is what the Kogan actually claims; it settles the question the whole session
  argued about. Then test Turing Red (TrueHD 8ch) and one AC-3 5.1 title. If the
  panel lies, KMEDIA_AUDIO_CHANNELS=<n> outranks EDID and logs `via override`.

  SEPARATE, STILL OPEN: the live SILENCE. CENSUS top (today) lands it downstream
  of the graph — mixer/amp, not code, not config, not timing. amixer + alsactl
  are now ON the drive, so the next boot can READ and unmute hw:0,3 (HDMI)
  instead of guessing. VAAPI is CLOSED (proven: iHD + libigdgmm -> "VA-API hw
  decode armed", silicon decoding at 1x).

## Prior attack (2026-11-27 late — AUDIO SINK: KSD HAS NO udev)

  ONE CAUSE FOR NO-SOUND AND NO-VISION: there has never been a sink in the KSD
  audio graph. libspa-alsa.so on the image ships exactly one enumerator,
  `api.alsa.enum.udev`; KSD has no /lib/udev, no udevd, no /run/udev, so
  WirePlumber's monitor.alsa enumerates zero devices and says nothing
  (kushd-wireplumber.log: 0 alsa lines, 0 udev lines, 49 boots). kplayd's
  pa_simple stream then parks in PAUSED and the player tears down with it.

  The "kidulwm crash-loop" theory is DEAD: 76 boot banners = 49 boots (~one
  each), the tail incarnation logged 130 FRAMETRACE lines = it ran the whole
  boot, and the last kushd seating block ends the file with no death after it.
  Yellow kidulwm rows in htop = threads of one compositor. Heat = software
  decode/GL (no VAAPI), not a loop.

  LANDED (bobdotrix):
    /mnt/ksd/etc/pipewire/pipewire.conf.d/10-ksd-alsa.conf — adapter sinks from
      api.alsa.pcm.sink: analog hw:0,0 default (1000), HDMI hw:0,3 TV (900).
      Chroot-proven with the host's pw-cli against real /dev: both Audio/Sink,
      error=None. No udev, no daemon, no new process.
    kplayd close-reason instrumentation (kmedia 4237e89, deployed ReleaseSafe
      sha 963c486d): `[kplayd] close: reason=isDone pos/dur | client_close |
      client_stop | new_open | shell_closed`. kidulwm has NO send_close, so the
      next boot's act log names why playback ends.
  DEPLOY RULE: kplayd builds ReleaseSafe (4.43MB); plain `zig build` = 14MB Debug.
  VAAPI: CLOSED 2026-11-27 (libigdgmm.so.12 shipped; iHD loads, "VA-API hw decode
  armed", silicon decoding proven at 1x). The "one cause" framing above is
  RETIRED by CENSUS top: the sinks landed and the graph is proven, and the live
  silence sits downstream of it (mixer/amp).

## Prior attack (2026-11-27, the parity cut — SUPERSEDED, attribution RETIRED)

  KPLAYD AUDIO LIFETIME — sound is a ROOTFS gap, not a front-end bug.
  (RETIRED 2026-11-27 late: kplayd is not being replaced mid-stream — it writes
  into a graph with no sink. See the current attack above.) The
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
