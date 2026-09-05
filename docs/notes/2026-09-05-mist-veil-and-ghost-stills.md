# Mist veil + ghost video stills — fix & fallback (2026-09-05)

Symptoms: grey "mythical mist" over BOTH screens after boot's wallpaper
reveal (cursor stays bright — hardware plane above the scene); fans at
idle from kidulwm pinned ~96-100% CPU, samples inside libnvidia-eglcore
(eglMakeCurrent via wlr_egl_restore_context in scene commit). Separately,
the known "kept" bug: a movie's last frame lingering behind the WALL and
behind terminals after playback.

## Root causes (both in src/server.zig)

1. MIST = wallpaper z-order. `setupWallpaper()` creates a fresh
   `wlr.SceneBuffer` per output. New scene nodes land ON TOP of every
   sibling — windows included. Old code only re-raised the overlay tree,
   so any wallpaper (re)creation after clients mapped (HDMI-A-1 arriving
   after the wallpaper decoded) veiled the whole screen in the
   palette-tinted wallpaper image. Hence "above everything, under the
   cursor".

2. GHOST STILL = video teardown gap. `video_buffer` / `video_wlr_buf` /
   `video_pixels` were only destroyed in `mediaSlideClose`. All other stop
   paths leaked the last frame: playback-finished in handleFrame, player
   stop key, `MediaWidget.update()`, track switch in `play()`, widget
   `deinit()`, output hot-unplug.

## The fix (commit on top of 0843a24)

- `bg_rect` pinned to the stack floor at creation (`lowerToBottom`).
- Wallpaper node: `lowerToBottom()` then `placeAbove(bg_rect)`, overlay
  re-raised. `background.rect/node` no longer nulled at wallpaper arrival
  (latent bug: letterbox rect kept living but stopped resizing).
- New `mediaVideoTeardown(output)` — kills scene node, wlr buffer, pixel
  copy. Called from ALL stop paths + a reconcile branch in handleFrame
  (slide open + player inactive + video node alive → teardown).
  LAW: no stills.
- `mediaSlideClose` deduped through the helper and now also stops a
  still-running player.
- `Output.deinit` tears the video path down (hot-unplug).
- TEMP DIAG frame counter repaired for zig 0.16 (`std.time.milliTimestamp`
  gone → `animation.nowUs()`).
- Also in this commit (from the mist-hunt earlier the same evening):
  `kidulwm-control scene_dump` IPC verb (writes
  ~/.local/state/kidulwm/scene_dump.txt — every scene node: type, enabled,
  world coords, dest size, opacity, owning window id) + chrome
  create/destroy logging with `node.data` window tagging. Use scene_dump
  FIRST on any future "mystery layer over the screen" report.

## Verify after reload

1. Mist gone: both screens show windows directly, no veil; cursor normal.
2. `ps -o %cpu -C kidulwm` — should sit near 0 at idle (was 96-100).
   If it still spins, next suspect is the media-peek helix in
   ui/tray.zig drawMediaWidget (`redraw = true` + buffer destroy/create
   every frame) — throttle to ~30 Hz and skip when idle.
3. `kidulwm-control scene_dump` → wallpaper buffer nodes should sit
   directly above the bg rect, BELOW all window trees.
4. Play a movie in the media slide, stop/back-to-wall: no still behind
   the wall; close the slide: nothing left behind terminals.

## Fallback

If the new binary misbehaves:

    sudo mv /usr/local/bin/kidulwm.prev /usr/local/bin/kidulwm
    # (md5 abb2eae0d44023ac02d3d01bbb65782a, 2026-09-05 14:10 build)

then re-log. Git fallback: `git revert` the fix commit; the tree before
it is 0843a24 (plus the same uncommitted scene_dump/chrome-logging hunks,
which are inert).

Known-unrelated pre-existing issue spotted in passing: orphaned SDDM
greeter Xorg on tty2 survives session start (PID was 55447 that evening);
the "screens turn off, type into login screen" experience is SDDM greeter
+ panel DPMS, NOT a locker — KidulWM has zero lock/DPMS code.
