# TASKCARD: vsync-quantized video presentation (kill 24-on-60 judder)

Date: 2026-09-08, bobdotrix + Barticus ("still stuttery" on Raya, live-watched session).
Supersedes: nothing; sits on top of TASKCARD-slide-zero-copy.md (engine landed, deployed 91b2509).

## Symptom

Raya (and any 23.976/24 fps film) plays visibly stuttery in the media slide,
worst on pans, despite:

  - VA-API silicon decode ACTIVE
  - dmabuf zero-copy live (P010, separate layers)  [session.log, live capture]
  - compositor GAPS histogram: zero misses, longest gap 8-12ms
  - FRAMES 130-175/s, CPU fine

File: Raya.and.the.Last.Dragon.mkv = HEVC Main10 3840x1608 @ 24000/1001 fps
(ffprobe-verified on disk).

## Root cause (code-proven)

Player.advanceVideoFrame (kmedia/src/Player.zig:1047) decides "due" with:

    if (pts > now_us) break;  // masterClockUs() sampled at an arbitrary
                              // instant within the vsync interval

handleFrame (KidulWM/src/server.zig:341) calls tick() once per vsync, but
masterClockUs() advances on WALL time. So whether a film frame flips on this
vsync or the next one depends on where inside the 16.6ms interval the frame
callback happened to fire. For a 41.7ms film frame (2.5 vsyncs), the phase
drifts: the 2:3 hold pattern wanders instead of locking to an even
2,3,2,3,... cadence. That wandering IS the judder. Engine, decode, and
compositor are all clean — presentation PHASE is the bug.

Standalone kmedia looks smoother because the ALSA/PA write-block cadence
re-triggers advance near audio-chunk boundaries (a steadier effective phase),
not because it is vsync-correct.

## Fix (mpv video-sync=display-resample, steps 2+3; no audio resample yet)

Quantize presentation decisions to vsync boundaries:

1. Player.tick() gains the vsync interval: `pub fn tick(self: *Self,
   vsync_interval_us: i64)` — 0 or negative = legacy behaviour (music tray /
   headless tests keep working unchanged).
2. Inside advanceVideoFrame, when vsync_interval_us > 0, replace the raw
   `now_us = masterClockUs()` due-check with a vsync-quantized edge:

       edge_us = floor((now_us - phase_origin_us) / interval) * interval
                 + phase_origin_us

   A frame becomes due only when its PTS <= edge_us, i.e. the decision
   changes exactly once per vsync slot regardless of callback phase.
   phase_origin_us is captured once (first quantized tick) so the grid is
   stable for the whole playback.
3. Drop-late rule (lag > AV_DROP_LATE_US) is evaluated against the SAME
   quantized edge, so a frame held an extra vsync by the grid (max one
   interval, ~16.6ms < 40ms) is never a spurious drop.
4. Callers:
   - KidulWM server.zig handleFrame: pass interval from
     wlr_output.refresh (millihertz -> us; 0 refresh -> fall back to 16666).
   - Music-tray slideless pump and all test hooks: pass 0 (unchanged).
5. Optional later (mpv step 5): audio resample to display clock. NOT in this
   card — measure after the quantization lands.

## Verification

1. playertest/walltest/livetest green (kmedia repo).
2. ReleaseSafe build BOTH repos; deploy host /usr/local/bin (law: host).
3. Live watch: play Raya in the slide; session.log Timing PRES deltas should
   cluster at multiples of the vsync interval (16.6ms grid: ~33/50ms for
   23.976 content) instead of smearing. GAPS stays at zero misses.
4. Barticus eyes: pans smooth. Verdict word is his.

## Non-goals

- No display-resample audio pitch work.
- No changes to dmabuf doors, Gl.zig, mediaVideoRefresh.
- Not touching the drop threshold constant.
