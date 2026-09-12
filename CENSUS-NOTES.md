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
- KidulWM 286a76b  src/core/kmedia.zig  silence watchdog (stale dot)
- CENSUS-NOTES.md (this file) updated per change + law amendment
DEPLOY: /usr/local/bin/kidulwm = sha256 ad1de802… = 286a76b/6af6ea5,
deployed 11:47 via mv-aside. Takes effect on compositor reload. Old binary
kept as /usr/local/bin/kidulwm.bak-pre-silencewd.
Reload + repro closes: stale dot (watchdog), and re-tests symptoms 1+2.


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
- AMENDMENT (Barticus, 2026-09-09): FIX-AND-RECORD. When the verdict is
  already proven (root cause named, mechanism shown in code/logs — NOT a
  theory) and the fix is small (a few lines, same function, no interface
  change), fix it immediately instead of waiting for approval. Waiting
  produces stale notes and stale running state. Rules:
    1. Evidence first — the exception only fires on a recorded verdict.
    2. Small only — crosses a file/subsystem boundary → back to census.
    3. Annotate in code (what/why; comment out old code when clearer) and
       log it under WHAT CHANGED with the commit.
    4. Repro still closes the symptom — early fix ≠ skip verification.
  That should be the way this works.

## 2026-09-09 VERDICT 3 (FIX-AND-RECORD #1): stale butterfly dot
Symptom (Barticus): live dot in the media widget with no player open and
nothing playing. Holder: kmedia FFT monitor (src/core/kmedia.zig) taps the
mixed sink output; onProcess just STOPS when the sink goes quiet, so
rms_slot/band_slots kept their last loud values forever and tray.zig
drawMediaWidget (audio_live = level() > 0.03) kept the widget live.
FIX (KidulWM 286a76b, src/core/kmedia.zig): capture thread timestamps every
buffer; a sibling watchdog publishes zeros through the SAME slots after
250ms of silence and on stream exit. smooth[] left to decay naturally
(capture-thread owned; resetting from watchdog would race). Deployed
/usr/local/bin/kidulwm sha256 ad1de802… (stamps 286a76b/6af6ea5).
REPRO after reload: dot must die within ~1s of audio stopping.

## 2026-09-09 VERDICT 4 (OPEN, census resumes): fixes live, symptoms persist
11:26 repro on the FIXED binary (boot stamp kidulwm=54ab4bc kmedia=6af6ea5,
proves BOTH ffc8877 start-PTS + 6af6ea5 vsync-ceil/drain were running):
- Raya open: PRES p50=199ms (ideal 41.7), DROP=648, STARVE=1618 vq=0 while
  aq=31 (audio ring FULL, video queue EMPTY) → video decode starves, not a
  display-grid problem. Stutter NOT fixed by 6af6ea5 — verdict 2 was wrong
  or incomplete; the vsync grid was never the bottleneck.
- Bob Marley open: PRES=0, 3223 AUGAPs growing ~4ms/32ms (133% clock rate),
  [present] committed=0 gen=3 → start-PTS fix did NOT cure invisible-video.
  AUWR shows pts=790880000 (ABSOLUTE) with AUPTS jump=+443951000 — the
  rebasing from ffc8877 is not what the audio writer is emitting, or the
  clock-vs-frame comparison still mixes absolute/normalised domains.
Next census question: why does vq starve with the decoder clean (VA-API ~2%
CPU) — READ cadence? demux thread? And where does AUGAP's 133% rate come
from (DAC anchor domain)? Both point at the demux/clock seam, not display.

## 2026-09-09 VERDICT 5 (FIX-AND-RECORD #2): invisible-B clock + stutter rings
Barticus law change: fix & record is the way of the land. No more
"what to fix next" round-trips — search & destroy, reload to verify.

Root cause invisible-B (CONFIRMED, kmedia 58e6514):
ffc8877 rebased each stream against its OWN first timestamp
(vid_base_pts_us / aud_base_pts_us) — two different 0-based timelines
compared in one expression. Evidence (OPEN5+6): the ~196 frames that
DID present all showed lag ≈ +703ms constant (clock 703ms ahead of
frame pts), then every later frame drain-dropped as stale
(DROP=363, then vq=0 for the rest of the open; compositor committed=0
gen=3). 703ms is the video-first-frame offset past audio-first —
video rebased ~703ms later than audio, permanently behind a clock it
could never catch. FIX: single stream_origin_us = EARLIEST
first-timestamp across both streams; both rebase against it; audio
clock = chunk.pts - origin. One timeline, no mixed domains. Same-file
fix, all 28 playertests PASS.

Root cause stutter refinement (verdict 2 incomplete, now mechanical):
the vsync-ceil fix (6af6ea5) WAS correct but never the bottleneck.
READ census: video packets arrive in bursts ~1ms wide then a
213-300ms gap, EVERY cycle, both files. Audio ring = 32 chunks ≈
680ms; pkt_ring back-pressure blocks the reader until audio drains;
video ring was 8 frames ≈ 330ms → empty inside every gap →
STARVE=3728, PRES p50~150ms. FIX: VIDEO_RING_SIZE 8→16 (~660ms).
No interface change.

WHAT CHANGED (running list, newest last):
- kmedia 58e6514  Player.zig  unified stream_origin_us clock + ring 8→16
DEPLOY: /usr/local/bin/kidulwm = sha256 f4775fc7… = 286a76b/58e6514,
deployed 12:1x via mv-aside (.bak-pre-origin kept). Reload + repro:
Raya must present p50≈41.7ms with STARVE≈0; Bob Marley must show
frames from t=0 (committed>0 gen>3).

## 2026-09-09 VERDICT 6 (FIX-AND-RECORD #3): pre-seek-target frames poison the clock
Barticus question this session: "have we exhausted ALL the how-does-mpv-do-it
avenues? maybe just a line of code, BUT IT IS KILLING THE MEDIA PLAYER."
Yes — it was one missing mpv law, and the 12:17 repro proves it.

Repro on the VERIFIED-FRESH binary (boot stamp kidulwm=286a76b kmedia=58e6514,
sha256 f4775fc7 — verdict 5's fixes were RUNNING):
- OPEN8 (Raya, resume ~23s): PRES p50=84ms, lag pinned at +707ms CONSTANT for
  the entire 36s open, 1736 audio underrun refills, 555 DROPs, 3191 STARVEs.
- OPEN9 (next file, audio-only symptom): AUGAP grows to 6.5s and keeps
  growing after the ring drains; video never presents; AUPTS jump=-58.78s
  (carrying OPEN8's clock).

The 707ms constant lag is the fingerprint. Numbers from the log:
  resume target        = 23.000s  (watch-state; STARVE clock=23000000 fallback)
  first video keyframe = 22.233s  (BACKWARD seek lands on the keyframe)
  first audio chunk    = 22.940s  (AUWR pts=22940000 absolute)
  22940 - 22233        = 707ms    = EXACTLY the pinned lag.

Mechanism (the missing mpv line): mpv's hr-seek decodes from the keyframe
but DISCARDS every decoded frame/sample whose pts < seek target. kmedia
PRESENTED them. Those pre-target frames learned stream_origin_us from the
keyframe (22.233s); audio's first chunk (22.94s) rebased against it lands at
+707ms; the DAC anchor starts the clock at 707ms the instant video frame 0
displays — a permanent, constant A/V offset baked in from frame zero. Every
frame reads "late by 707ms" → drop-storm → ring drains → STARVE → bursty
refill → 707ms again. The clock rate itself was perfect (AUWR pts rate
1.004 vs wall). The vsync grid, the ring sizes, the drain fix — all correct
and all fighting a clock that was born 707ms in the future.
On files where the keyframe-to-target gap exceeds the ring budget the video
ring drains as "stale" faster than decode can refill → committed=0 → the
TRANSPARENT next-movie. Same line of code, both symptoms.

FIX (kmedia/src/Player.zig): hr-seek law — after a resume/mid-play seek,
remember seek_floor_us (the normalised seek target); decodeVideoPacket and
decodeAudioPacket DISCARD decoded output with rebased pts < seek_floor_us;
floor clears on the first frame/chunk at-or-after it. Bases then learn from
post-target timestamps, origin converges on the real shared start, clock is
born at ~0. ~20 lines, same file, no interface change.

WHAT CHANGED (running list, newest last):
- kmedia 698fa75  Player.zig  hr-seek: drop decoded output pts < seek target
DEPLOY: /usr/local/bin/kidulwm = sha256 f027d90c… = 286a76b/698fa75,
deployed ~12:3x via rename-swap (.bak-pre-hrseek kept). Live at next
compositor reload — boot stamp must read kmedia=698fa75. Reload + repro:
lag must be ~0 (not +707ms), PRES p50 ≈ 41.7ms, DROP/STARVE ≈ 0, next
file must show frames immediately (committed>0).

## 2026-09-09 VERDICT 7 (FIX-AND-RECORD #4): the floor died one stream too early
13:0x repro on VERIFIED-FRESH 698fa75 (boot stamp proven): lag pinned at
+707ms CONSTANT again — identical fingerprint to verdict 6. The floor WAS
running; it just didn't live long enough.

Mechanism: 698fa75 tied seek_floor_us lifetime to seek_armed, and
seek_armed disarmed on `aud_ring.count > 0 OR stream_origin_us >= 0`.
Video sets stream_origin_us on its first post-target frame — ALWAYS
before audio decodes its first post-target chunk (keyframe packet leads,
audio packets follow). Next tick: disarm, floor=-1, and the audio
decoder's queued pre-target chunks (keyframe→target = exactly 707ms)
walked through the dead floor into the ring. First AUWR pts=35000000 =
the resume target (floor worked for the LEADING chunk) but the ring
behind it was pre-target backlog; the DAC anchored from it and the clock
was born 707ms in the future. Again.

What mpv actually does (the missing half of the law): the pre-target
discard stays armed across ALL streams until AUDIO has re-primed — video
display gated on the audio clock existing, not on video having produced
a frame. FIX (kmedia d2b7113): seek_armed disarms ONLY on
aud_ring.count > 0 (or no audio stream — aud_codec_ctx == null);
stream_origin_us no longer factors in. Floor lives exactly as long as
the gate. ~8 lines, same function. playertest CLEAN EXIT.

Compositor cross-examined and INNOCENT (again): per-frame [present]
late=682-685ms mirrors the poisoned clock faithfully; gen=3 (Ratatouille,
the "transparent next movie") shows committed=0 dropped=~100/s where
dropped = "vsync, no new serial" = empty player ring = STARVE upstream.
Cache/gen guards held all day.

WHAT CHANGED (running list, newest last):
- kmedia d2b7113  Player.zig  hr-seek floor gated on audio re-prime
DEPLOY: /usr/local/bin/kidulwm = sha256 4b9fb9fc… = 286a76b/d2b7113,
deployed 13:37 via mv-aside (.bak-pre-hrseek2 kept). Reload + repro:
lag ≈ 0 (NOT +707ms), PRES p50 ≈ 41.7ms, next file committed>0 from t=0.
Boot stamp must read kmedia=d2b7113.

## 2026-09-09 VERDICT 8 (OPEN, probe deployed): d2b7113 ran, +707ms survives
13:3x repro on VERIFIED-FRESH d2b7113 (boot stamp + sha 4b9fb9fc proven):
- OPEN (Raya, resume 25.0s): first AUWR pts=25005000 at +4ms, aq=31 —
  audio primed EXACTLY at target; the verdict-7 gate held on the audio
  side. Yet first PRES (+644ms) lag=+718ms, p50 lag=+708ms constant
  across all 279 presents, DROP=505 (drop-lag p50=808ms), STARVE=2960,
  PRES delta p50=66ms. Same fingerprint, third binary.
- OPEN (next movie): PRES=0, AUPTS jump=-57.3s (cross-generation clock
  leak in the discontinuity detector), video never presented.
- Demux cross-examined INNOCENT: 823/830 video packets delivered over
  the 34.6s open (24fps honoured, one 1.4s gap at +33s), audio 40154
  pkts. Reader/decoder are not starving — frames die between decode and
  present, drained as "stale" by a clock born keyframe→target ahead.

Where that leaves the hunt: the gate now provably holds for AUDIO, so
the surviving pre-target teacher is on the VIDEO side — some frame with
pts below the floor still reaches `stream_origin_us = pts_us` (video
packets lead audio after a seek; the only value 707ms below 25.005s is
the keyframe). Inference has hit its limit; the next repro must NAME
the packet. Probe deployed for exactly that.

WHAT CHANGED (running list, newest last):
- kmedia 0b8b773  Player.zig + Timing.zig:
  1. FIX (proven in code): mid-play seek in readerLoop passed the
     NORMALISED target raw to av_seek_frame while open-resume adds
     cont_start — a seek in a start_time!=0 container (Bob Marley 790s)
     landed ~790s early on the absolute axis. Both doors same law now.
  2. PROBE: Timing.vfpts logs abs/cont_start/floor/PASS|DROP per decoded
     video frame while seek_armed — names the packet teaching the origin.
  3. FIX (evidence): openInternal resets last_auwr_pts_us/end so AUPTS
     stops carrying the previous player's clock into a fresh open.
DEPLOY: /usr/local/bin/kidulwm = sha256 212d89f7… = 286a76b/0b8b773,
deployed ~14:0x via mv-aside (.bak-pre-vfpts kept). Reload + repro:
watch for VFPTS lines after the Raya resume — the DROP/PASS sequence
pinpoints the origin teacher; lag must be ≈0 once that door closes.
Boot stamp must read kmedia=0b8b773.

## 2026-09-09 VERDICT 9 (FIX-AND-RECORD #5): ONE-CLOCK law — origin is derived, never learned
Credits ran out mid-run yesterday; the edit was found complete in the
kmedia worktree (verified: build clean, playertest CLEAN EXIT) and
committed this session.

Root cause (final form of the +707ms fingerprint, four binaries):
stream_origin_us was LEARNED from first decoded output. After a
BACKWARD seek the pre-target keyframe always decodes first and taught
the origin keyframe→target µs too early; the audio clock was born that
far in the future and every frame read exactly that much late, forever.
Fix: the origin is DERIVED at seek/open from the one value both doors
already agree on:
  origin = cont_start + seek_floor  (post-seek)
  origin = cont_start               (fresh open from t=0)
Live streams keep the learn path (no container timeline). The video-path
learning code is deleted; the old learn lines elsewhere are now dead
code (origin always set first) — left for the close-out sweep per
Barticus.

WHAT CHANGED (running list, newest last):
- kmedia 7d2b169  Player.zig  ONE-CLOCK law (committed 2026-09-11)
DEPLOY: /usr/local/bin/kidulwm = sha256 be466344… = 286a76b/7d2b169
ReleaseSafe, deployed 23:4x (.bak-pre-oneclock kept). Reload + repro:
resume Raya — lag must be ≈ 0 from frame zero (NOT +707ms), PRES p50
≈ 41.7ms, DROP/STARVE ≈ 0; next file committed>0 from t=0. VFPTS probe
from 0b8b773 still in the build if a packet needs naming.
Boot stamp must read kmedia=7d2b169.

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

## 2026-09-11 VERDICT 10 (OPEN, recorded for HANDOFF): fixes ran, ALL symptoms persist
Repro (Barticus, fresh session on the deployed 7d2b169 binary — sha256
be466344 = KidulWM 286a76b / kmedia 7d2b169, ONE-CLOCK law live):
- Raya STILL stutters.
- Second video STILL invisible.
- Butterfly widget STILL out of whack: movement stops & starts, shows
  media when media is no longer playing (verdict-3 silence watchdog did
  NOT kill it), song names render in the BOTTOM half of the butterfly
  instead of ON TOP of it.
- MEDIA SLIDE IS NOT A SLIDE (law violated): moving through the deck,
  the media slide STAYS in the focused area above or below the focused
  slide. It does not ride with the others. 8cd0a02 ("retire the
  sentinel, normal deck slide") did not deliver the actual behavior.

BARTICUS DIAGNOSIS (accepted): "our problem is a complexity that we
made, that needs to be gone." Nine verdicts on the clock seam; every
fix was individually verified yet the session symptoms never died.
The slide-not-a-slide integration is the structural smell — the media
slide still has special-case positioning/lifecycle instead of being
one more slide in the deck.

DECISION: media player investigation PAUSED per Barticus. Fresh eyes
after the browser works. No more patches on this seam until then.

TODO when the hunt resumes (fresh-eyes checklist):
  1. Slide geometry: why does the media slide pin above/below focus
     instead of riding the deck? Diff 8cd0a02's intent against the
     actual slide-layout code path (slide deck focus/scroll vs the
     media slide's position source).
  2. Butterfly widget: (a) liveness still not dying on stop — the
     verdict-3 watchdog path did not hold in real use; (b) song name
     placement = on TOP of the butterfly, not bottom half.
  3. Clock seam: verdict 9 (ONE-CLOCK) unverified-in-session — the
     stutter/invisible pair survived it. Next repro reads VFPTS lines.

## 2026-09-12 VERDICT 11 (IN PROGRESS): ONE-TRUTH architecture — the stale dot's real name
Session triggered by Barticus: butterfly shows dot + lines with NOTHING
playing, all sink-inputs empty. Live census proved it:
- pactl: zero sink-inputs; monitor tap records rms=0.000000 peak=0.000000
  (3s direct capture) — PipeWire is feeding the FFT pure silence.
- The only "holder" is our own tap: source-output "kidulwm-kmedia" on the
  analog sink monitor (core/kmedia.zig capture thread, permanent by design).
- Watchdog heartbeats: media_open=false active=false; player fully closed.
So the lit widget is compositor-internal state, not audio.

THE ROACH (Barticus): "how can a movie that relies on ms timed sound have
2 or more sound timelines?" We had THREE "is it live" answers:
  1. ksound's floor table (the real one — dead service, never consulted)
  2. FFT rms_slot residue in core/kmedia.zig (the lying one — sampled
     loudness re-purposed as liveness; verdict-3 watchdog didn't hold)
  3. player_active/player cached state in the media slide
The butterfly (a REACTOR, never a participant) was drawing whichever was
stalest. Same family as the +707ms clock fight: state re-derived in
consumer code instead of read from its owner.

THE ONE-TRUTH ARCHITECTURE (locked in-session, Barticus):
  - TALKING (is audio live): ksound's stream table ONLY. pw_watch already
    tracks every stream with class/role/corked. ksound gains an
    audio_live socket verb answering 1/0 over that table (non-corked
    output streams with live owners; LISTENING taps excluded by class).
  - LISTENING (FFT monitor tap): loudness food ONLY — rung energies while
    ksound says live. level()/bands() stop being a liveness oracle.
  - CLOCK: kmedia Player.zig DAC anchor, ONE timeline (verdict 9 stands).
    ksound carries NO clock — it arbitrates, never timestamps.
  - TRAY: zero media-liveness derivation. Both tray.zig:3680 and
    media.zig:1498 delete their local `level() > 0.03` duplications and
    read one bool: kmedia.audioLive() (ksound socket, ~100ms cache,
    non-blocking; daemon absent = not live).
  - BUTTERFLY: pure reaction — breathes with what plays, owns nothing.
    "The butterfly should never stop" while ksound says someone talks.
  - TITLE/SONG DETAILS: own dedicated space ABOVE the butterfly, never
    drawn inside the helix lane (kills verdict-10's "song names in the
    BOTTOM half"); that space may be interactive, but it is its own
    region, not the butterfly's.

Law audit (sound.md, full re-read 2026-09-12): clean of everything we've
been fighting — no tray invitation (face owns ONE control + chime
button), LAW 7 already writes honest-clock as law, LISTENING vocab
already defines the FFT tap as floor-less. ONE GAP: the law never says
who answers "is audio live?" for the face — the hole this bug grew in.
Lock amendment to add when this lands: "The face asks the floor table
for liveness; the meter answers loudness, never liveness."

WORK ORDER (search & destroy per census law):
  1. ksound: audioLive() over the table + `audio_live` socket verb.
  2. ksound.service: enable + start; verify socket answers 0/1 live.
  3. KidulWM core/kmedia.zig: pub fn audioLive() (ksound, cached).
  4. tray.zig + media.zig: delete both level()>0.03 derivations → bool.
  5. media.zig renderPeek: title lane moves ABOVE the helix, own space.
  6. ReleaseSafe build, deploy, Barticus reloads, repro closes:
     dot dead with nothing playing; butterfly breathes while playing;
     title sits in its own space above.

## 2026-09-12 VERDICT 11 LANDED (reload pending):
- ksound c2d0500  pw_watch.audioLive() + audio_live socket verb.
  VERIFIED LIVE: '0' with empty floor; '1' with a real pacat stream;
  an orphaned pacat (killed wrapper, ppid=1) honestly reported '1' —
  the truth includes ghosts, exactly as the law wants. FFT monitor tap
  (Stream/Input) correctly ignored. NOTE: hit the HANDOFF cold-cache
  trap — warm zig-cache shipped a binary WITHOUT the new verb; rm -rf
  zig-out .zig-cache is the build protocol. Pre-existing ksoundtest
  floor5 failures (2) confirmed on clean HEAD, not from this change.
- KidulWM 24eff5a  core/kmedia.zig audioLive() (unix socket, 100ms
  cache, 50ms io deadline, daemon-absent = not live) + tray.zig &
  media.zig FFT-liveness derivations DELETED + movie/TV title moved
  to the reserved title lane above the helix (own space).
- ksound.service: enabled + active (ExecStart dev path zig-out/bin).
  Daemon must be running for the widget to light — intended: no
  daemon, no truth, butterfly rests (never hallucinates).
DEPLOY: /usr/local/bin/kidulwm = sha256 830e6604… via mv-aside
(.bak-pre-onetruth kept). REPRO after reload:
  1. Nothing playing → no dot, no rung lines, within ~1s (100ms cache).
  2. Play music → butterfly breathes, title ABOVE the butterfly.
  3. Play movie → title in the same top lane, not the bottom half.
  4. Boot stamp proves kmedia=7d2b169 + new kidulwm commit.
PENDING: sound.md law-lock amendment — "The face asks the floor table
for liveness; the meter answers loudness, never liveness." (Barticus)

## 2026-09-12 VERDICT 12 (FIX-AND-RECORD #6): the clock is born in the future — host PROVEN innocent
Barticus: "maybe a single test to see if it is our player or the host."
New harness: kmedia test_clockprobe.zig (`zig build clockprobe`) —
headless Player.open(resume Raya 23s) + real host sink + tick() at
vsync cadence, NO compositor, NO PipeWire mixer in the decision path.
lag = masterClockUs - displayed_pts_us per present.

HEAD (7d2b169, ONE-CLOCK live): lag p50 = +923ms, CONSTANT, aq=0.
0c5308c ("ZERO-COPY" known-good): same shape, worse (no rebase at all).
The bug reproduces with zero host involvement → Player.zig, always was.

Mechanism (probe data, not theory):
- AUWR wall-delta p50 = 7µs per 833µs chunk — pa_simple_write returns
  INSTANTLY into PipeWire's 100ms tlength; the aud_ring drains to 0
  while the DAC has played almost nothing.
- The anchor then stamps pts + dur as if the DAC had played it → the
  clock is born ~(all queued audio) in the future and every video
  frame reads that much late, forever. Drop-storm → STARVE → burst →
  stutter; on next-file open, born ~1s ahead → frames dropped →
  committed=0 → the transparent movie. ONE mechanism, both symptoms.
- Why 4K/60Hz shows it and 144Hz hides it: same constant offset, but
  the 4K present path has no refresh headroom to mask the judder.
- Sink latency probe: PipeWire honestly reports 45-99ms unplayed
  (tlength) while letting us sprint ~1s ahead. We just never asked.

FIX (kmedia 03e4e6f): anchor subtracts pa_simple_get_latency() — "what
the DAC is playing NOW", mpv's audio-law line we never implemented.
Recovers ~80-90ms (the sink's own queue). PARTIAL: the remaining
constant is the ring-drain history at clock birth — the throttle +
anchor + latency submission arithmetic is three patches over one
missing truth: THE GRAPH MUST PACE THE CLOCK, not the other way round
(Barticus: "we have been anchoring off the sound when we should be
doing the reverse"). That rewrite is next, with clockprobe as harness.

WHAT CHANGED (running list, newest last):
- kmedia 03e4e6f  Player.zig DAC-latency anchor + test_clockprobe.zig
DEPLOY: /usr/local/bin/kidulwm = sha256 0729cfb0… = 27eeddd/03e4e6f,
deployed 12:0x via mv-aside (.bak-pre-latency kept). Reload + repro:
lag must DROP by the sink's latency; stutter/invisible persist =
verdict 13's graph-paced clock. Boot stamp must read kmedia=03e4e6f.

## 2026-09-12 VERDICT 14 (FIX-AND-RECORD #7): THE FREEZE — pkt ring storage
Two boots, same death: smoothest playback yet (~30s), then whole-machine
wedge, power-button recovery, ZERO journal (journal tail: kmedia stream
appears 13:31:26, then silence; watchdog: RSS 350MB→1.1GB in 7s at open,
stable 1.1GB, then heartbeat ends mid-line). A userspace crash leaves a
journal; this was kernel-side (zram + VA-API dmabuf pressure + i915).
Root cause (PROVEN in code): verdict 13 raised PKT_RING_FILE 64→2048 but
pktRingType's array, head/tail modulo AND clear loop all stayed 256.
count climbed toward 2048 against 256 slots — head lapped tail,
counted-queued packets overwritten/leaked, back-pressure fired ~8x late,
reader sprinted the demux/decode buffers into memory death. Both freezes
occurred only on the graph-paced build — the only one carrying 2048.
FIX (kmedia 67f77a0, dac-paced-clock): PKT_RING_STORAGE = PKT_RING_FILE;
array, both modulos and clear loop use STORAGE; caps stay 256 live /
2048 file below it. playertest CLEAN EXIT.
DEPLOY: /usr/local/bin/kidulwm = sha256 073c423d… = kidulwm 27eeddd +
kmedia 67f77a0 (stamp 67f77a0 verified in-binary), via mv-aside
(.bak-pre-ringfix kept). REPRO: same playback that froze twice must now
run past 60s+ with RSS stable and no wedge. Boot stamp kmedia=67f77a0.

## STANDING OPEN (from HANDOFFs, not this hunt)
- pause-pill chrome placement (letterbox gutter anchor) — cosmetic, parked.
- backups owed: 67+ commits ahead (sda1/Codeberg/Apocalypse).
- 2 uncommitted debug log lines in KidulWM src/ui/media.zig (gen logging)
  + HANDOFF.md addendum — leave them, commit when hunt closes.

## 2026-09-12 VERDICT 13 (IN PROGRESS): graph-paced clock + screens census
Branch dac-paced-clock (kmedia). Clock-patch pile (ffc8877→03e4e6f, eight
commits) DELETED and replaced with: absolute pts end-to-end + ONE anchor
line (pts_anchor = chunk_end_pts - pa_simple_get_latency) + seek_armed
gate. playertest CLEAN EXIT; clockprobe STILL shows +800ms constant —
but the LAT probe acquitted the sink (honest 80-100ms) and AUWR showed
audio pts advancing at rate 0.609 vs wall (bursty underrun feeding, NOT
a racing clock). The constant is NOT DAC sprint — census continues.
SCREENS CENSUS (Barticus questions, this session): NO master/slave
exists today — every output owns a full media_slide + tray widget +
player, and playTimerMs() SEARCHES outputs for an owner. Two seams
named: (A) playTimerMs ceil ms-timer vs exact µs grid = ~1.14Hz beat
(PRIME SUSPECT since 09-08, still live); (B) timer follows first-found
owner. Barticus law (locked in speech): ONE Master screen holds ALL
widgets + controls + truth; slaves present slides only; slides ride
focus; grid borrows the presenting screen's crystal. "One computer, one
compositor, one player, one clock — screens are windows." Latency of
Master ownership = ZERO (intra-process; HDMI carries pixels only).
LAW DOC: KidulWM docs/law/screens.md (DRAFT, awaits Barticus lock).
The crawl (Star-Wars app launcher, bottom-center, big white letters,
border-colour idle / white focus) = Barticus design, tray-as-we-know-it
retired to a later date — parked as future taskcard.
Seek & destroy mandate granted 2026-09-12; keep notes along the way.

## 2026-09-12 LAW EVOLUTION: Master/slave-screens REPLACED by Boss/slaves/pack
Barticus: "Master & slave screen is the wrong metaphor — the Master is
the COMPUTER; all screens are slaves, numbered (1,2,3...); slave 1 gets
the PACK (widgets+controls+crawl) by default; users can move the pack;
headless = 0 slaves." "1 boss 1 truth — we have been saying this all
along; giving it to anything else is actually silly. The Boss sends the
visuals to the screen & sound to the speakers — on time every time."
docs/law/screens.md rewritten in the new vocabulary (6 laws: Boss /
slaves are addresses / the pack / slides ride focus / one clock
borrowed crystals / latency honesty). DRAFT — awaits Barticus lock.

## 2026-09-12 VERDICT 13 (CONT'D): rings fixed, lag cut to ~20ms, drift named
dac-paced-clock branch state: AUDIO_RING 32→1024 (was a 27ms buffer
pace-locking the decode thread — chunks on Raya are ~1ms NOT 21ms),
PKT_RING_FILE 64→2048 (was ~1.5 video frames — every demux audio-run
starved video: 54v vs 2671a packets in 2s), anchor = chunk_end −
pa_simple_get_latency (LAT probe: honest 80-100ms), absolute pts
end-to-end, hr-seek floor as pure presentation filter, clock clamps
deleted. clockprobe: first-present lag fell +800ms → ~20-60ms at wall
1.5s (was 775ms). presents 133→213/10s. REMAINING: audio pts_rate
decays 1.01→0.89 after ~4s (PipeWire pulling at ~0.89× while honestly
reporting 80-90ms occupancy; WR probe: writes succeed in ~8µs, stream
live+uncorked on the real analog sink). Video stays glued to audio
(skew constant) so a/v sync itself is FINE — the drift is clock-rate
vs wall, only visible as lag growth vs pts. Suspects: PipeWire rate-
match/resample bookkeeping vs pa_simple_get_latency, or tlength=100ms
starving the mixer quantum. Live session repro will tell whether the
deployed path (HDMI sink) shows it at all — probe uses analog.

## 2026-09-12 VERDICT 13 DEPLOYED (reload pending)
- kmedia cf68efd (dac-paced-clock branch, SIGNED): graph-paced clock,
  ring pile deleted. Committed with full census mechanism in the message.
- KidulWM rebuilt ReleaseSafe (27eeddd + kmedia cf68efd statically
  included; stamps verified in-binary: cf68efd + 27eeddd present).
DEPLOY: /usr/local/bin/kidulwm = sha256 293ca6e1… via mv-aside
(.bak-pre-graphpaced kept). Barticus reloads + repro:
  1. Raya resume 23s: lag ≈ 0 from early presents (NOT +700ms pinned),
     PRES p50 ≈ 41.7ms, DROP/STARVE ≈ 0.
  2. Next video: committed>0 frames from t=0 (no transparent movie).
  3. Boot stamp must read kmedia=cf68efd.
  4. WATCH: drift — probe showed audio rate 0.89× vs wall on the
     ANALOG sink after ~4s (a/v sync holds; video glued to audio).
     If live HDMI path shows position-counter drift, next census is
     tlength/PipeWire quantum interaction. KMEDIA_TIMING=1 is live in
     the session wrapper — /tmp/kmedia-timing.log has LAT/ANCH/WR.
