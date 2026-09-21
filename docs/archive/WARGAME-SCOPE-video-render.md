# WARGAME-SCOPE: kmedia video render-path restructure (VM stutter fix)

## Mission
Make in-slide video playback smooth on the ksd-work VM (4 vCPU, virtio-vga,
pixman software rendering, SPICE). Currently plays but stutters — "constantly
trying to load", not smooth. Root cause identified: per-frame render path is
too heavy for software rendering.

## The design (LOCKED — implement this shape, cribbed from mpv)
mpv (player/video.c, video/out/vo.c) architecture we are copying:
1. Decode thread fills a small frame queue stamped with PTS. Never renders.
2. A per-vsync "playloop" decides which frame is DUE (PTS vs audio clock),
   drops late ones, advances the queue. Runs every refresh, cheap, no render.
3. The video output receives only the DUE frame's pixels, uploads once, and
   the compositor/scene-graph scales+presents. UI/chrome is a SEPARATE
   overlay layer; the video layer is never re-rendered to draw chrome.
4. Only changed regions are pushed.

KEY INSIGHT that fixed our deadlock: advance logic (step 2) is DECOUPLED from
rendering (step 3). mpv runs advance every vsync regardless of redraw.

## Current state (partially implemented, builds clean on both repos)

### kmedia/src/Player.zig (repo: /home/dad/dev/kmedia)
Already added:
- `frame_serial: std.atomic.Value(u64)` — bumped at DECODE edge when a frame
  is pushed into vid_ring (availability stamp).
- `display_serial: u64` — bumped at DISPLAY edge when vid_surf actually
  receives new pixels in advanceVideoFrame(). THE GATE USES THIS.
- `embedder_owns_video: bool = false` — when true, render() skips its cairo
  video scale/paint block (the embedder draws video itself).
- `currentFrame() ?struct{data:[*]u8, w:i32, h:i32, stride:i32}` — returns
  the vid_surf BGRA pixels for the embedder to copy. Valid until next advance.
- `pub fn tick(self: *Self) void` — calls advanceVideoFrame() WITHOUT drawing.
  This is the mpv playloop step 2. MUST be called every vsync by the embedder.
render() still calls advanceVideoFrame() then (if !embedder_owns_video) does
the old cairo letterbox blit — the standalone kmedia app path, KEEP IT WORKING.

### KidulWM (repo: /home/dad/dev/KidulWM)
Already added:
- src/render/buffer.zig: `DataBuffer.createRef(pixels: []u8, w, h, stride)` —
  zero-copy variant (new `owned: bool` field; destroy() only frees when
  owned). Use this for the video buffer so the scene graph reads our memory.
- src/ui/media_slide.zig: MediaSlide gained `video_buffer: ?*wlr.SceneBuffer`,
  `video_wlr_buf: ?*wlr.Buffer`, `video_pixels: []u8`, `last_frame_serial: u64`.
- src/ui/media.zig: MediaWidget.play() sets `self.player.embedder_owns_video = true`.
- src/server.zig: `mediaVideoRefresh(output)` — copies Player.currentFrame()
  pixels into video_pixels (row-wise, respects stride), wraps in a
  DataBuffer.createRef, puts it in a SceneBuffer child of the slide tree,
  setDestSize+setPosition to the letterboxed rect inside deck.mediaSlideTarget().

## WHAT IS LEFT (your job)
1. Fix server.zig frame handler (`Output.handleFrame`, ~line 96-113). It
   currently gates on frame_serial and calls mediaVideoRefresh. CHANGE to the
   mpv shape:
     - EVERY frame tick, while player_active: call
       `output.media_slide.widget.player.tick()` (the cheap playloop advance).
     - Then compare `player.display_serial` against a new
       `output.media_slide.last_display_serial: u64` field (ADD this field to
       MediaSlide; keep last_frame_serial only if still used, else remove).
     - Only when display_serial changed: store it and call mediaVideoRefresh().
   This is the critical fix: tick() must run every vsync or the ring
   back-pressures and playback freezes (the earlier regression).
2. In mediaSlideClose (server.zig ~line 1130): also destroy video_buffer node,
   drop video_wlr_buf, free video_pixels. Currently leaks / leaves stale frame.
3. The card buffer (mediaSlideRefresh) still calls renderToBuffer →
   renderCard → player.render() which (embedder_owns_video=true) draws ONLY
   chrome (black bg + UI bar + subtitles + signal-lost). Verify the black
   matte is still painted behind where video goes (embedder_owns_video path
   in Player.render should still fill black background so the letterbox bars
   are black, not transparent). If it doesn't, make the chrome render fill
   black over the whole rect when player_active.
4. Z-order: video_buffer node must be ABOVE the card buffer's black matte but
   the chrome (progress bar, buttons) is part of the card buffer... PROBLEM:
   chrome lives in the card buffer BELOW the video buffer, so the video would
   COVER the progress bar/buttons. Resolve: either (a) draw chrome in the
   card buffer and put video buffer BELOW card buffer with the video area of
   the card left transparent, or (b) simplest: keep video below card buffer
   and have Player.render with embedder_owns_video draw the black matte +
   chrome but leave the central video rectangle unpainted/transparent so the
   video shows through. Pick the approach that keeps chrome visible over the
   video's letterbox bars and the video visible in the middle. Document the
   choice. (mpv uses a separate OSD overlay ABOVE video; mirroring that means
   chrome should be its own buffer above the video buffer. Prefer that:
   split chrome into an overlay buffer above video if tractable, else the
   transparent-window approach. State which you did.)
5. Build both repos clean (zig build). Run kmedia harnesses:
   `zig build walltest`, `zig build playertest`, `zig build livetest` — all
   must CLEAN EXIT. The standalone kmedia app path (embedder_owns_video=false)
   must still render video via cairo.

## Constraints
- Zig 0.16 on host. Target must compile with it. (Gotchas already handled in
  existing code: pthread mutexes, av.* C shims, no std.Thread.Mutex.)
- Do NOT change the watch-state, decode, M3U, or live-TV logic. Only the
  render/display path.
- KidulWM imports kmedia by RELATIVE PATH ../kmedia/src (see build.zig), so
  Player.zig changes are picked up directly. No submodule.
- pixman software rendering on the VM; WLR_RENDERER=pixman, WLR_ALLOCATOR=shm.

## Verification (orchestrator does the VM deploy; you do build+harness)
- zig build clean in BOTH /home/dad/dev/kmedia and /home/dad/dev/KidulWM.
- kmedia: walltest, playertest, livetest all CLEAN EXIT.
- Report: `git diff --stat` for both repos.

## Output rules
Return ≤ 3500 chars. Write all files to disk. Give only: paths changed per
repo, the z-order choice you made (4 above), build+harness results, and any
deviations. Do NOT paste full file contents.
