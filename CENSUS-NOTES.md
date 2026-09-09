# MEDIA CENSUS — live hunt state (bobdotrix, started 2026-09-09)
# Read THIS FILE first in any new session during the media hunt. Update it
# after every repro/verdict. Delete/retire it into HANDOFF when done.

## 2026-09-09 VERDICT: invisible-video root cause FOUND + FIXED (kmedia)
The census logs told the whole story once read per-stream instead of
aggregated:
- "Invisible video" is NOT file #2 — it's the FILE. Raya (audio starts
  ~4.6 min in → container clock ≈ 0) played fine; Bob.Marley (audio starts
  at 790.88s absolute) never showed a frame.
- Evidence: OPEN#1 (Bob.Marley) produced exactly 2 PRES in ~60s, both
  lagging ~800-960ms vs the absolute audio clock; 6312 AUGAPs; compositor
  logged committed=0 dropped=80 and "refresh NULL: no va_frame". OPEN#2
  (the same file re-opened) even fired AUPTS jump=-1696000 — the audio
  pipeline saw the discontinuity.
- Root cause (Player.zig): video frame PTS was compared against an audio
  master clock that starts near 0, but both were ABSOLUTE container
  timestamps. For a file whose audio starts at t=790s, every early video
  frame reads as "not due yet" — black screen with audio until the clock
  catches up. "A few stills got through after a minute" = the audio clock
  finally overtaking the first video PTS values.
- mpv law applied: --start=0 means playback time 0 = first frame. mpv
  normalises away the container start offset; we did not.
- FIX (kmedia/src/Player.zig, commit ffc8877): learn vid_base_pts_us /
  aud_base_pts_us from the first timestamp each stream produces, rebase
  both to a 0-based timeline in the decoder (video) and audioLoop
  (clock + DAC anchor). Resume-seek target converts normalised → absolute
  via container start_time; post-seek (resume AND mid-play) the bases are
  reset and video display is gated (seek_armed) until the audio ring
  re-primes — mpv's wait-for-audio-after-seek.
- Census-law note: the prime suspect (playTimerMs ceil) is NOT the
  invisible-video cause. See below — the REAL cadence bug was elsewhere.

## 2026-09-09 VERDICT 2: stutter root cause FOUND + FIXED (kmedia 6af6ea5)
The ceil suspect was looking at the wrong clock. The compositor-side
playTimerMs ceil is harmless (it only wakes the playloop; the present
decision lives in Player.tick). The damage was INSIDE the playloop:
- Raya evidence (VA-API active, ~2% CPU, decode clean): PRES p50=166ms,
  62% of deltas >70ms when the ideal is a steady 41.7ms (24fps). The
  decoder was never the bottleneck — the display clock was.
- FAULT 1: the vsync grid in advanceVideoFrame() FLOOR'd the due-clock
  to the previous grid edge (@divFloor). At 143Hz (6.945ms slots) a
  24fps frame stayed "not due yet" for 1-2 extra ticks past its slot →
  presents landed a half-to-full frame-period late, every frame.
  FIX: snap the grid clock UP (ceil) to the first edge at-or-after the
  raw clock — mpv display-sync presents at the next vsync >= pts,
  never below it.
- FAULT 2: after any stall, the ring held several ALL-due frames but
  the loop displayed ONE then broke — N stale frames smeared recovery
  over N wrong-phase ticks. FIX: drain the stale prefix (frames whose
  successor is already due) in the same tick, count as drops, display
  the newest due frame. One PRES, back on grid.
- Both in kmedia/src/Player.zig, commit 6af6ea5. playertest 28 PASS.

## LINKAGE ANSWER (the "half our problem" question) + FIX
KidulWM statically includes kmedia as SOURCE MODULES (build.zig reads
../kmedia/src/{c,av,libkmedia}.zig directly — no .so, no .a, no
package pin). ldd shows no kmedia. Consequence: a kmedia commit is
INVISIBLE at runtime until KidulWM is rebuilt + redeployed + reloaded.
That's what lost the morning (deployed probes that weren't).
FIX (KidulWM build.zig + main.zig): compile-time provenance stamps —
build runs git rev-parse on BOTH repos, bakes them in via addOptions,
and main logs at boot:
  "KidulWM boot (kidulwm=XXXXXXX kmedia=YYYYYYY)"
session.log now proves which player code is actually running. Verified
live: the fresh binary strings show kidulwm=2e37c87 kmedia=6af6ea5.
Architecture (in-process, zero-copy VA-API dmabuf into the scene
graph) is CORRECT and stays — mpv libmpv embedders do the same. The
only real cost is player-crash = compositor-crash; accepted.

## WHAT CHANGED TODAY (running list, newest last)
- kmedia ffc8877  Player.zig  start-PTS normalisation (invisible-video)
- kmedia 6af6ea5  Player.zig  vsync-ceil + stale-backlog drain (stutter)
- KidulWM build.zig + main.zig (UNCOMMITTED) provenance stamps
- CENSUS-NOTES.md (this file) updated per change
DEPLOY: KidulWM ReleaseSafe rebuilt with BOTH kmedia fixes baked in
(zig-out/bin/kidulwm, stamps 2e37c87/6af6ea5). NOT YET DEPLOYED to
/usr/local/bin — the running compositor is still the old binary.
Deploy + reload + repro (Raya for stutter, Bob.Marley for invisible)
closes symptoms 1 and 2.


## THE THREE SYMPTOMS (Barticus, 2026-09-09)
1. STUTTER on playback. — root-caused (vsync-floor + backlog-smear),
   fixed in 6af6ea5. REPRO NEEDED on new binary to close.
2. SECOND VIDEO INVISIBLE — root-caused to start-PTS offset, fixed in
   ffc8877. REPRO NEEDED on the new binary to close.
3. MAYBE-LOCKUP — watchdog showed 129-151fps steady, i915 irqs counting,
   compositor never wedged during the hunt. Downgraded: no evidence.

## THE LAW THIS HUNT RUNS ON
- External-bug law: if the player measures clean and the symptom persists,
  the bug is NOT in the player. Check the seams (cache, lifecycle, timers).
- Census first, fix second. NO PATCHES on theory. The scorecard names the
  boundary, THEN we fix.
- Yesterday's failure mode was: symptom→theory→patch→new symptom. BANNED.

## PRIME SUSPECT (stutter) — playTimerMs() ceil bug, KidulWM src/server.zig
  143.998Hz panel → 6.945ms vsync → @divTrunc(+999) ceil → 7ms timer.
  Timer at 142.9Hz vs panel 143.998Hz → present phase drifts ~1Hz →
  periodic judder beat. Code's own comment warns firing early drifts
  phase, yet it CEILS. Fix direction: fire at or just under vsync
  (floor, or fractional timer), verify against scorecard late_avg/drops.

## DEPLOYED STATE (verify hashes, never assume)
- /usr/local/bin/kidulwm = 1f934d708ee72c50afad95552fe07a17a1fbfbdbb6db70a314d3786908d4577b
  = commit 2e37c87 (signed) — [present] instrumentation. DEPLOYED 09:58 via
  mv-aside (old binary kept open by running compositor → .old-running).
  Takes effect ONLY AFTER Barticus reloads the compositor session.
- kidulwm-session: KMEDIA_TIMING=1 exported (line 26, .bak kept) so the
  in-process player's Timing.zig writes /tmp/kmedia-timing.log every boot
  during the hunt.
- KidulWM commits: 8ff8b0a (vsync-cadence timer, has the ceil suspect),
  2e37c87 ([present] probes). kmedia: f5c082c (displayed_pts_us stamp).
- Old running binary: /usr/local/bin/kidulwm.old-running (pre-2e37c87).
- .bak-5b0d95e also exists. session wrapper bak: kidulwm-session.bak.
- Watchdog: kmedia-watchdog.service active, /var/log/kmedia-watchdog.log.
- Persistent compositor log: ~/.local/state/kidulwm/session.log.

## WHAT THE SENSORS SHOW (the scorecard: kmedia/tools/census-scorecard.py)
  python3 /home/dad/dev/kmedia/tools/census-scorecard.py [start_iso] [end_iso]
- PLAYER side (/tmp/kmedia-timing.log): PRES delta histogram = cadence,
  lag = a/v drift, DROP/STARVE/AUGAP = decode/ring health.
- COMPOSITOR side ([present] in session.log/journal):
  per-frame: surface, gen, cache hit/miss, late=Xms (audioclock-pts proxy)
  per-sec:   committed=N dropped=N hit=N miss=N memcpy=N late_avg late_max
- WATCHDOG: frames/s, media_open/ready/active flags, i915 irqs.

## VERDICT KEYS — what answer looks like what
- STUTTER: PRES delta p95 tight + [present] dropped rising + late drift
  pattern → cadence/timer (ceil suspect). PRES delta p95 huge + STARVE →
  decode starve → file-side. AUGAP spikes → audio ring.
- INVISIBLE B: [media] "gen now" bumps on stop; play B shows
  committed=0 with cache=miss+surface reused → cache/lifecycle STILL alive.
  committed=N but black → scene-node/present path, not cache.
- LOCKUP: watchdog heartbeat stops → compositor dead; heartbeat lives,
  frames/s 0 → GPU wedge (i915 irqs frozen) → journal for i915 errors.

## REPRO SCRIPT (Barticus runs, Bob watches live)
  play video A ~30s → close slide → reopen → play video B.
  Bob tails: ~/.local/state/kidulwm/session.log + watchdog + timing log.

## STANDING OPEN (from HANDOFFs, not this hunt)
- pause-pill chrome placement (letterbox gutter anchor) — cosmetic, parked.
- backups owed: 67+ commits ahead (sda1/Codeberg/Apocalypse).
- 2 uncommitted debug log lines in KidulWM src/ui/media.zig (gen logging)
  + HANDOFF.md addendum — leave them, commit when hunt closes.
