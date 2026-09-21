# TASKCARD — slide zero-copy embed (session 19)

Mission: port the kmedia lab's zero-copy dmabuf path into the KidulWM media
slide. The slide currently copies every frame through a CPU pixel buffer
(server.zig mediaVideoRefresh @memcpy loop). The lab (kmedia standalone,
commit 5273cab) plays both codec families at ~2% CPU via VAAPI → dmabuf →
EGL import. Slide is the product; standalone was the lab.

## Reading list (in order)

1. /home/dad/dev/kmedia/HANDOFF.md — session 17+18 addenda (top of file).
2. /home/dad/dev/kmedia/src/Gl.zig:389-480 — importVaFrame, the THREE DOORS
   (per-plane R8+GR88 / R16+GR1616; whole-surface GL_TEXTURE_EXTERNAL
   separate layers; whole-surface composed layers). This door ORDER tamed
   iHD/P010 (GR1616 standalone = egl 0x3009; whole-P010 external sampler
   accepted). Do not reorder.
3. /home/dad/dev/kmedia/src/Player.zig:1096-1109 — zero-copy display edge:
   advanceVideoFrame holds the AV_PIX_FMT_VAAPI AVFrame in displayed_hw
   (data[3] = VASurfaceID, hw_frames_ctx chain → VADisplay) and bumps
   display_serial. Ownership: the Player owns displayed_hw; the embedder
   imports (fd duplication happens inside wlroots/mesa) and must NEVER
   av_frame_free it. Player.releaseDisplayedHw() exists for mode flips.
4. /home/dad/dev/KidulWM/src/server.zig:1705-1782 mediaVideoRefresh — the
   sw path being replaced; :300-345 handleFrame vsync/tick cadence (KEEP —
   the stutter-saga law); :1786-1801 mediaVideoTeardown.
5. wlroots zig bindings (zig-pkg/wlroots-0.20.2-dev-*/src):
   render/dmabuf.zig DmabufAttributes (fds, strides, offsets, modifier,
   n_planes); render/allocator.zig Allocator.createBuffer(w,h,DrmFormat);
   types/scene buffers. Server field: renderer_allocator: *wlr.Allocator
   (server.zig:387) is the compositor's dmabuf-capable allocator.
   DrmFormat type is in the wlroots package (render/drm_format_set.zig or
   similar — check).

## Stage 1 — kmedia: expose the display surface (small commit)

- Add to Player.zig, next to currentFrame() (~line 710):

      /// Zero-copy display surface for dmabuf embedders. Null unless
      /// zero_copy_ok and a hw frame is currently displayed. Borrowed
      /// ref — Player owns it; caller imports, never frees.
      pub fn currentVaFrame(self: *Self) ?*av.AVFrame {
          if (!self.zero_copy_ok) return null;
          return self.displayed_hw;
      }

- ALSO fix the MPV-LAW audit nit while in there: Player.zig:1534
  `if (self.sws_ctx == null or true)` recreates the sws context on EVERY
  decoded frame. Gate on actual src/dst format/dims change. This is the
  copyback path's dead weight; the fallback must stay cheap.
- Bar: `zig build` clean; walltest + playertest + livetest ALL PASS CLEAN
  EXIT. Signed commit in kmedia repo.

## Stage 2 — KidulWM: dmabuf scene path (the embed)

In server.zig mediaVideoRefresh, insert a dmabuf branch BEFORE the memcpy
path, active only when `widget.player.currentVaFrame() != null`:

Door A (preferred): export the VA surface
(vaExportSurfaceHandle, VA_SURFACE_ATTRIB_MEM_TYPE_DRM_PRIME_2,
VA_EXPORT_SURFACE_READ_ONLY | VA_EXPORT_SURFACE_SEPARATE_LAYERS), walk the
VADRMPRIMESurfaceDescriptor into wlr.DmabufAttributes (fourcc from
va_desc.fourcc, per-layer planes, offsets, pitches, per-object
drm_format_modifier, dup or borrow fds per wlroots semantics — VERIFY in
the C headers whether wlr_allocator_create_buffer dup's the fds; Gl.zig's
closeVaDesc pattern shows the lab's fd hygiene), then
renderer_allocator.createBuffer(w, h, drm_format) and
scene_buffer.setBuffer. On ANY failure: close fds, fall through to the
existing memcpy path silently (per-frame; next frame may succeed). A
failed frame redraws the last good image — black-with-sound is dead law.

Door B (fallback shape): if door A's import fails persistently (iHD GR1616
quirk may live inside mesa's EGL here too), retry export with the
whole-surface fourcc (NV12 0x3231564e / P010 0x30313050) and
VA_EXPORT_SURFACE_COMPOSED_LAYERS, mirroring Gl.zig doors 2-3.

- One-time per-stream log line on success: which door/fourcc went live
  (mirror the lab's "[gl] whole-surface import live" shape).
- Teardown (mediaVideoTeardown) must drop the dmabuf wlr buffer the same
  way; no fds leaked across stop. video_pixels path untouched as fallback.
- Do NOT touch handleFrame's vsync re-arm cadence. Do NOT touch the card
  buffer / chrome / z-order law (video below card, card raiseToTop).
- Renderer note: host renderer is gles2 (autocreate). If renderer is
  pixman (force_pixman), dmabuf import will fail — that IS the fallback
  path; make it quiet and correct, not an error.
- Bar: `zig build` clean in BOTH repos; kmedia harnesses still green.
  Signed commit in KidulWM repo.

## Stage 3 — verification (build + harness + headless smoke)

- Cold-cache `zig build` both repos, Debug AND ReleaseSafe.
- kmedia walltest/playertest/livetest green.
- Headless smoke is NOT possible for the dmabuf path (needs a real GPU +
  compositor) — say so in the report; the live host demo is parent's job.

## NOT this session

- Live host demo with Barticus (parent runs it after review).
- Deploy to /usr/local/bin/kidulwm (parent, after demo verdict).
- mpv-style display-sync projection; Escape/close UX; card-vs-played
  mismatch; any UI/visual change whatsoever.
- No refactors outside the named functions. No new dependencies.

## Rules

- Deviations flagged, never silent. Suspects are suspects — if recon above
  contradicts the tree, the tree wins and the card gets a note.
- Commits: B&B identity (pre-commit hook enforces), GPG signed, terse
  imperative one-liners.
