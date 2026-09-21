# TASK CARD — CARD 2b slice 3: kvisd toplevel placement onto the video slide rect

**Repo**: /home/dad/dev/KidulWM (main, HEAD = 4b80e50)
**Date**: 2026-09-17
**Dispatcher**: bobDotrix (cold-verify + deploy after you)
**Predecessor commits**: 5b0aff3 (internal client), a065188 (slide lifecycle + kvis client), 198d057 (boot gate), 228abf6 (CHROME LAW)

## GOAL
Make kvisd's video surface actually appear ON the video slide. Today the
video slide is a black placeholder; kvisd renders in its own toplevel
somewhere else. Slice 3 = the compositor placement pass that pins kvisd's
toplevel to the slide rect every layout.

## CURRENT STATE (all on main, all deployed)
- Slice 1: internal Wayland client (src/ipc/internal_client.zig) —
  compositor's own client, HostSurface exported per video slide,
  app_id "com.kidul.video-slide-host".
- Slice 2: kvis.sock client (src/ipc/kvis_client.zig) + slide lifecycle —
  videoSlideSpawnRightOfPlayer spawns host toplevel, exports, connects
  kvis.sock, sends 'parent <handle>'. videoSlideCloseOn sends unparent +
  close, destroys host.
- kvisd side (17f45c8 in kmedia repo): binds zxdg_importer_v2, does
  import_toplevel + set_parent_of on 'parent <handle>'. kvisd surface
  app_id = "com.kidul.kvis" (set in kvisd_shell create).
- CHROME LAW (228abf6): fullscreen video = ZERO chrome. videoSlidePaint
  skips the ring when fullscreen. Windowed keeps it.

## WHAT'S MISSING (this slice)
1. TRACK kvisd's toplevel by app_id "com.kidul.kvis" in
   handleNewXdgToplevel (server.zig:3636). Today every toplevel becomes a
   Window; kvisd's toplevel needs to be recognised and its scene tree
   captured for placement. It is NOT a normal slide/window — do NOT give
   it deck treatment, chrome, or focus. Suggest: a dedicated
   `kvis_window: ?*Window` (or just the scene tree + output refs) on
   Server, matched in handleNewXdgToplevel via toplevel.app_id, cleared
   on its destroy.
2. PIN kvisd's scene tree over the video slide's rect every
   videoSlidePaint / applyLayout. The slide rect math already exists
   (videoSlidePaint: deck.targetForSlide(idx) + output box offset). The
   kvisd surface must be raised above the slide's black placeholder
   buffer, and sized/positioned to the same rect. kvisd letterboxes
   INSIDE its own surface (HANDOFF session 23: the §9a matte class dies
   structurally — kvisd owns its internal letterbox, we never paint matte).
3. FULLSCREEN LAW: when the video slide is fullscreen, kvisd surface =
   pixels edge-to-edge over the WHOLE output, zero chrome (already the
   slide's chrome law — extend to kvisd's placement: no offset for a ring
   that isn't there). When windowed (peek/parked), kvisd surface sits at
   the slide's windowed rect, UNDER the chrome ring.

## CONSTRAINTS / LAWS (do not relitigate)
- kvisd's surface STAYS a toplevel child of the host surface
  (xdg-foreign set_parent_of). It is NOT converted to a wl_subsurface.
- The host toplevel (com.kidul.video-slide-host) never paints — it exists
  to be exported and to carry the rect. kvisd is the pixel source.
- ONE video slide per session (video_slide_output latch) — placement only
  ever concerns one output.
- No blocking roundtrip on the internal client (pumpRoundtrip law). This
  slice shouldn't need new internal-client sync — placement is pure
  scene-tree work compositor-side.
- Hard stops / no wrap. Granny test arbitrates UI decisions.
- Fix & record is the law: note the verdict in CENSUS-NOTES.md.

## ACCEPTANCE (cold-verify by bobDotrix)
1. `zig build` Debug + ReleaseSafe clean (0 errors, 0 warnings).
2. Headless harness: nested compositor, spawn video slide, real kvisd
   opens a video → kvisd's toplevel is tracked, its scene tree is
   positioned at the slide rect, raised above the placeholder. (kvisd
   GL/shell probing vs pixman headless is a KNOWN host-only gap — CARD 2a
   note; the placement logic itself must be verifiable. If the shell won't
   spawn headless, verify the tracking + rect-math path with a stub/
   mock toplevel or by unit-testing the placement fn.)
3. No regression: existing video-slide lifecycle (spawn/close) still
   clean; unparent + close + host destroy still fire on quit.
4. CENSUS-NOTES.md gains a verdict entry.

## OUT OF SCOPE (next cards)
- Slice 4: deleting the embedded libkmedia module + media_video.zig
  present path from KidulWM (the old embedded player). Separate commit,
  verdict first.
- kvisd GL/shell-vs-pixman headless probing (host-only verdict).
- music-peek (CARD 3).

## HANDOVER
Commit signed (B&B, GPG 344B…A843) on main with a clear message.
Report: build results, harness evidence, files touched, any deviations.
bobDotrix cold-verifies, then deploys ReleaseSafe to /usr/local/bin/kidulwm
(rename-swap, .bak kept) and records the deployed hash.
