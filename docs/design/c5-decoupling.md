# C5 DECOUPLING — EXECUTION PLAN (DRAFT)

Status: DRAFT 2026-11-11 by bobdotrix, for Barticus to lock next session.
Laws this executes (already LOCKED, no new design): slide-process.md
(LOCKED 2026-10-14, the "mother roach"), kplay.md (LAW 2: one player, all media),
app-id-namespace.md (com.kidulworks.*), fullscreen.md (fullscreen is a MODE).

This is NOT a new freeze. It is the execution spec for C5 — the last migration
card of the mother-roach law — which deletes the embedded player and strips the
app_id special-casing so kidulwm / kmedia / kplayd become three independent
processes (conductor / client / player), seated by kushd.

---

## Goal (one sentence)

Finish C5: kidulwm stops knowing "kmedia" and "kplay" by NAME, and the embedded
media player (media.zig + media_slide.zig) is deleted so the media model lives in
exactly one process (kmedia) and playback in exactly one (kplayd).

## Current state (verified against code, 2026-11-11)

kplayd is ALREADY the resident daemon you described:
  - kplayd_main.zig listen()/bind()/accept() on $XDG_RUNTIME_DIR/kplay.sock,
    SOCK_SEQPACKET line protocol. kmedia kplay_client.zig connect()s on first
    play and keeps the fd. kplayd_main.zig line 5: "kfiles borrow it over
    kplay.sock." The "always at the ready for any app" seam is SHIPPED.
kmedia is ALREADY a Wayland client (Wall.zig 3-pill Movies/TV/Music, the
    category filter the FORBIDDEN LAYER gated on). mediaCardToggle spawns
    /usr/local/bin/kmedia; its toplevel auto-seats as an .app slide.
So the two "content" processes (kmedia, kplayd) are already independent. The
remaining entanglement is the CONDUCTOR still reaching inside them by name.

## The coupling inventory (what C5 must remove)

1. server.zig:2144  mediaCardToggle — exact-eql "com.kidulworks.kmedia"
     (focus-or-spawn). The WM knows the media app by NAME to find its slide.
2. server.zig:4049  handleNewXdgToplevel — exact-eql "com.kidulworks.kplay"
     (kplayd video surface → is_kplay, no deck/chrome/focus).
3. server.zig:4070  classifyKplay — exact-eql "com.kidulworks.kplay" again
     (re-classify on set_app_id, since app_id arrives after toplevel).
4. window.zig:62    is_kplay flag; :577 placeKplayWindow on commit; :627
     kplay_window null-out; :682 "kplay"/"ghostty" substring frametrace.
5. server.zig:54/56/135/439/1001/2182  media_slide.zig + media.zig MediaWidget
     still IMPORTED and INSTANTIATED — the embedded scene tree is compiled in,
     not just dead-on-disk.
6. server.zig:139   video_host_surface (ipc/internal_client.zig HostSurface,
     xdg-foreign) — the fullscreen-video machinery, still live.
7. media_slide.zig:6  imports media.zig; MediaSlide tree + renderToBuffer
     (33MB ARGB32 cairo buffer) still reachable.

## THE GATING QUESTION (must be answered before C5 executes)

Are BOTH media paths live on a real boot, or is one orphaned?

  Path A (new, C2): mediaCardToggle → spawns kmedia CLIENT → .app slide.
  Path B (old, embedded): mediaSlideKey (keyboard.zig:247) → mediaSlideOpen →
     out.media_slide.widget (media.zig MediaWidget: search, library, art,
     watch-state) — reachable whenever findKind(.media_player) matches a
     COMPOSITOR slide kind (a distinct kind from the .app kmedia client slide).

Both entry points are wired in keyboard.zig and server.zig. If a .media_player
compositor slide is ever seated on KSD today, Path B still owns the media keys
and still scans the drive — the exact roach slide-process.md named (WM scans,
WM holds the library globals). If nothing seats .media_player anymore, Path B is
orphaned and C5 is a clean delete.

RECOMMENDATION (Q-A): determine live-path by (a) grepping who calls
mediaSlideOpenAnywhere / mediaSlideOpen with a .media_player slide, and (b) a
one-boot census on the KSD VM (ksd-reset). Do NOT delete until the census says
Path B is unreachable. Deleting a live circuit is a regression, not a cleanup.

## Open questions for Barticus (lettered, with recommendations)

Q-A  Live-path determination (above). REC: census on VM before any delete.

Q-B  kplayd surface identification. Today: app_id "kplay". The law says kplayd
     is a daemon whose video surface is a CHILD of the host surface we exported
     via xdg-foreign. REC: identify the video surface STRUCTURALLY (the host
     surface already knows its imported child) and drop the app_id match — that
     is the true decoupling. No app_id string, no rename-lockstep ever again.

Q-C  kmedia focus-or-spawn. Today: mediaCardToggle matches app_id "kmedia" to
     find "is the client already seated?". REC: kushd tags the window at seat
     time (a SEATING FACT — kushd decides, kidulwm consumes, per vocabulary-law
     "owner class is a seating fact"). WM consumes the tag, never sniffs app_id.
     GATED on kushd growing a "seat kmedia" act (it currently seats body daemons
     only). Until then, the app_id match is a tolerated bridge.

Q-D  media.zig deletion gate. FORBIDDEN LAYER: "media.zig on main is FROZEN
     (bypassed) only until the kmedia client's Wall filters by category."
     VERIFIED CLEARED: Wall.zig filters Movies/TV/Music (3-pill) today. So the
     deletion gate is OPEN — C5 may proceed once Q-A confirms Path B is dead.

## Proposed cut sequence (prove in VM, per KSD doctrine)

  Step 0  Census on ksd-reset VM: is .media_player compositor slide ever seated?
          If yes → Path B is live, Q-A flips, re-plan. If no → proceed.
  Step 1  Delete Path B: media_slide.zig, media.zig, the .media_player
          compositor slide kind, mediaSlideKey/mediaSlideOpen/mediaSlideCloseOn
          and their callers. (C5 proper.)
  Step 2  Strip kplayd app_id match → structural (xdg-foreign child of
          video_host_surface). Removes server.zig:4049/4070 + window.zig is_kplay
          + "kplay" substring. (Q-B.)
  Step 3  Strip kmedia app_id match → seating tag (kushd). Remove server.zig:2144.
          (Q-C.) If kushd "seat kmedia" is not ready, keep this as the LAST step
          and mark the bridge explicitly.
  Step 4  Rebuild + redeploy lockstep (kidulwm + kmedia + kplayd) to /mnt/ksd,
          cp->mv atomic, strings-verify no com.kidulworks.kmedia/kplay eql
          matchers remain in kidulwm. Remount ro.

## Verification (acceptance)

  - `strings kidulwm | grep -c 'com.kidulworks.kmedia\|com.kidulworks.kplay'` == 0
    (the WM no longer names either app).
  - kidulwm builds and boots on ksd-reset VM; kmedia seats as a plain client;
    kplayd still answers on kplay.sock; playback + fullscreen still work.
  - media.zig / media_slide.zig gone from src/ (git rm), no dangling @import.

## Risks

  - Deleting Path B while it's live (Q-A) = media keys + library silently die.
    The census in Step 0 is the guard.
  - Stripping the kplayd app_id match before the structural path is proven = the
    video surface falls back into the deck as a normal window (chrome + focus).
    Step 2 must land the structural identification in the SAME cut as the strip.

## Not in scope (separate axes, do not blur)

  - kushd growing a "seat kmedia" act (Q-C dependency) — a kushd task, not C5.
  - Product branding (KSD / StarShipKidul face) — unrelated to app_id or process.
  - Host keybinds.conf cleanup (stale ghostty / ~/.local/bin/kmedia lines) — host
    side, cosmetic, separate.
