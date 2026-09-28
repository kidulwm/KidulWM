# KSD RESET LEDGER — live state (bobdotrix, migrated from media census 2026-09-20)

Read THIS FILE first in any reset session. It is the live state of the Great
Reset (SYSTEM.md is the arbiter; this file is the running ledger). Update it
after every verdict. The old MEDIA CENSUS (embedded-player hunt, verdicts 1-28)
is retired — those verdicts live in git history and their laws survive in the
kmedia + ksd-input-claim-law skills.

# (relog handoff 2026-09-21 resolved: hub WORKED — TV on Intel DP-3. See verdict 53.)
# (relog handoff 2026-09-28 RESOLVED — VERDICT 66 RELOG VERIFY PASSED. Border
#  visible (square, thin — the verdict 66 shape), RSS FLAT 1812700kB over 90s on
#  a 5h19m compositor (the 27.14MB/layout leak is dead by construction: no raster
#  buffer exists). See verdict 66 block.)

# VERDICT 66 (2026-09-28): CHROME LAW AMENDED — THIN BORDER RESTORED. Borders
#   are back, but as thin scene-rect strokes (createSceneRect x4, O(perimeter)),
#   NOT the leaky full-window cairo/DataBuffer path. The 27.14MB/layout leak is
#   dead BY CONSTRUCTION (no raster buffer at all) — not by disabling chrome.
#   Law: docs/law/chrome.md amended — thin border only; no full-window buffer;
#   border colour = color_border_focused theme token, syncs on
#   chrome_style_generation bump (widgets + borders change together). window.zig
#   updateChrome rewritten (scene rects; TEMP DIAG cache-miss/create/destroy
#   logs removed). renderChrome + surfacePixels now dead (renderMiniRing lives).
#   Design (Barticus): user apps keep this thin border; KSD apps drop the
#   compositor border and self-frame (fade-to-black, 96% opacity) — client-side.
#   DEPLOYED /usr/local/bin/kidulwm (.bak-95be9e9 = verdict 65 no-chrome).
#   RELOG OWED — verify border + RSS flat.

# GREAT RESET — REMAINING WORK (prioritized, 2026-09-28)

#   1. RELOG VERIFY — DONE (2026-09-28): border visible + RSS flat.
#   2. KPLAYD VA-DEVICE LEAK root. PINNED (session 37): the surviving renderD
#      fd is the VA DECODE DEVICE (drm-engine-video, client-id 137), NOT the
#      EGL shell. Zero-copy export/import leaves one extra ref that
#      avcodec_free_context/vaTerminate can't release. FIX candidates (in
#      order): vaExportSurfaceHandle DRM_PRIME_2 ref released only by
#      vaDestroySurfaces, held past close; OR eglDestroyImage/releaseImage
#      not running in zero-copy close order. See kmedia HANDOFF session 37.
#      exit(1) put-to-bed band-aid still holds. DIAG dump (dumpRenderFds in
#      kplayd_main.zig) is temporary — remove once the fix lands.
#   3. TV ~10min CUT + 7/9 channel fail (verdict 59) — confirm if still live.
#   4. xdg-decoration .client_side flip + GTK_CSD un-flip (applyTitleBarEnv).
#      Feeds item 5.
#   5. CORNER BLEED on foreign apps (browsers/proton). Client "factory round
#      corners" still bleed against the compositor frame — SSD/CSD corner
#      mismatch. OBSERVE this reload first (thin square border may shift it).
#   6. GRAND DESIGN framing (chamfer). DEFERRED — see ksd-design-language
#      skill. Sub-order: fix DataBuffer free -> chamfer.frag.glsl frame ->
#      tune depth on TV -> scallop upgrade.
#   7. KSD apps fade-to-black self-framing (96% black, no compositor border) —
#      client-side, the "one system" look. DEFERRED.

# VERDICT 65 (2026-09-28): LEAK PINNED + CHROME LAW. The 27.14MB/layout-event
#   leak is updateChrome -> DataBuffer.create (window.zig:574), the full-window
#   ARGB chrome buffer for the rounded-corner border — NOT the media slide, NOT
#   dmabuf (import 18x == close 18x, exonerated). Pin via perf uprobe
#   (heap.PageAllocator.alloc, --call-graph fp — dwarf/LBR both fail; see skill
#   zig-allocation-leak-pinning).
#   Law: docs/law/chrome.md (compositor draws no window chrome — no border, no
#   corner mask, no full-window buffer; fullscreen = bare pass-through; windowed
#   = client-side). fullscreen.md rulings 7-8 added. updateChrome disabled via
#   chrome_enabled=false toggle (body retained, renderChrome/surfacePixels DCE'd).
#   DEPLOYED /usr/local/bin/kidulwm 95be9e9 (.bak-8cb8d52 = verdict 64). RELOG
#   OWED — verify compositor RSS stops climbing. Follow-on: xdg fullscreen
#   handler + client-side decorations flip (see HANDOFF "Next action").

# KNOWN-GOOD + FALLBACK (Barticus, 2026-09-28): verdict 64 (8cb8d52, kept as
#   /usr/local/bin/kidulwm.bak-8cb8d52) runs helium with ZERO screen tearing
#   and very smooth playback, and its matching rounded corners looked really
#   good. If a later verdict regresses smoothness or visuals, FALL BACK to
#   kidulwm.bak-8cb8d52.
#   CAVEAT: 8cb8d52 is the leaky one (27.14MB/layout event, the RSS wedge) —
#   the smoothness + corners come with the leak. Reconcile by keeping the
#   windowed corners but killing the full-window buffer (thin border / proper
#   free), NOT nuking all chrome (verdict 65 did the latter).

# (relog handoff 2026-09-27 — SYSTEM FIXES + FULL REBOOT, bobdotrix)
# System admin session (NOT a KSD code verdict); detail in sda1 change journal.
#   - kernel split-brain FIXED: linux-cachyos 7.2.8 rebuilt to /boot + limine.conf
#     (pacman bumped 7.2.6->7.2.8 and deleted the 7.2.6 modules but never rebuilt
#     /boot — stale 7.2.6 vmlinuz, empty /etc/mkinitcpio.d -> SDDM dead on cachyos).
#   - fstab FIXED: /mnt/lacie-apocalypse listed twice -> fstab-generator + /boot
#     mount failure. Removed one line.
#   - NVIDIA -> COMPUTE-ONLY (SUPERSEDES verdict 53's FULL blacklist): the full
#     4-module blacklist made ollama model-load HANG (CUDA needs nvidia_uvm).
#     Now blacklist nvidia_drm + nvidia_modeset ONLY; nvidia + nvidia_uvm stay
#     loadable. Toggle /usr/local/bin/nvidia-profile (off|gaming: prime-run).
#     Intel iGPU still drives all screens. verdict 53's POST-REBOOT VERIFY
#     (nvidia-smi gone / D3cold / no card0) is VOID — nvidia SHOULD be present
#     but with NO display output.
#   - bobdotrix approvals.mode -> smart.
#
# FULL REBOOT resolves the REBOOT/RELOG OWED markers (53-62) + reaps the leaked
# GEM. Post-reboot: resume verdict 63's RSS checks fresh.

# VERDICT 64 (bobdotrix 2026-09-28, end of night) — COMPOSITOR IS THE LEAK (CORRECTS 63's "did NOT reproduce"); TWO FIXES DEPLOYED, ALLOCATOR PIN OWED TOMORROW
#
# LEAK (live host, Barticus open/close testing over ~1h): kidulwm anon 325MB
#   -> 3.45GB, RSS 3.6GB, STILL climbing, NO drop on close. kplayd CLEAN every
#   cycle (respawns 27MB / 0 renderD / 0 GEM — put-to-bed holds). smaps =
#   verdict-57 fingerprint: ~27.8MB anon rw- chunks coalescing into
#   83/111/166/250/278MB slabs ("one 4K P010 frame each"). Renderer gles2
#   (pixman=false), outputs DP-3 (Kogan 4K scale 2) + eDP-1 (1080p scale 1).
# WHY 63 MISSED IT: tested over RAW kplay.sock (open->close) which never enters
#   the fullscreen present path. Barticus's Mod4+m flow DOES — host surface +
#   curtain + scanout + per-frame video import. REPRO-DOOR LAW (video-playback-
#   architecture skill) named this exact false negative; I stepped on it.
#   Corrections to 63: the "compositor does NOT retain" + "did NOT reproduce"
#   lines are VOID for the fullscreen path. kplayd verdict 63 itself stands.
#
# FIXES DEPLOYED (src/server.zig, ReleaseSafe hash 39193e2d -> /usr/local/bin/
#   kidulwm; running pid NOT restarted — relog picks it up):
#   1. FULLSCREEN CHROME REMOVAL: applyLayout called updateChrome(true, .all)
#      unconditionally on the focused slide, ignoring slide.fullscreen (the peek
#      already hid itself via focused_fullscreen; the window chrome had no
#      matching check). Now clearChrome() when slide.fullscreen, in BOTH the
#      normal and headless branches. Fullscreen slide = edge-to-edge, zero
#      chrome, every app (shared focused-slide branch).
#   2. MEDIA PLAYER SPAWN DIRECTION: was addCompositorSlide(.media_player, 0)
#      = index 0 (far LEFT, pushed everything RIGHT — backwards vs addWindow).
#      Barticus: new slide becomes focused + pushes former focus LEFT; home is
#      the ONLY far-left (index 0) resident. Now spawns at focused_index+1.
#
# OWED TOMORROW — "2 SUSPECT REVIEW" (pin the allocator, then fix). Both fire
#   on fullscreen enter/exit layout events:
#   A. media-slide 33MB ARGB32 re-render (mediaSlideRefresh -> renderToBuffer,
#      server.zig ~2072; card_dirty guard exists but re-fires on fullscreen
#      layout events).
#   B. chrome border regen (updateChrome create/destroy churn, window.zig ~472;
#      TEMP DIAG "CHROME cache-miss" log still in place).
#   Plus (skill-documented): per-frame dmabuf import churn — cache per
#   VASurfaceID (~8 slots), scene node ONCE, setBuffer the cached entry.
#   Sampler trace: ~/.hermes/profiles/bobdotrix/cache/scratch/ramsample-*.log
#   (ts kplayd_pid rss fds gem kidulwm_pid rss fds gem anon memavail).
#   METHOD: relog first (deploys live), re-test, re-run sampler while Barticus
#   cycles fullscreen, correlate anon delta vs CHROME cache-miss +
#   mediaSlideRefresh log lines. Don't guess — the log distinguishes A vs B.

# VERDICT 63 VERIFIED LIVE (bobdotrix 2026-09-27, post-reboot) — RAM FLAT, NO LEAK
#
# Fresh-boot 3-cycle open->play->close over kplay.sock (Bob.Marley 1080p NV12):
#   - kplayd DURING: RSS 209-212MB, 5 renderD128 fds, ~180MB GEM. AFTER close:
#     pid CHANGES every cycle (1761->28743->29095->29407), new proc 0 renderD,
#     0 GEM, 27MB RSS. The close reply is EMPTY (no "ok") — exit(1) fires BEFORE
#     reply("ok"), confirming the put-to-bed path runs on EVERY video close (the
#     VA device still survives close; process death reaps it). By design.
#   - kidulwm: RSS 262->269->262MB (returns to baseline), GEM 1.111->1.193->1.111GB
#     (transient +82MB during play, released on close). NO retention. Verdict 62's
#     "2.5GB compositor climb" CONFIRMED dead post-reboot (was the wedged driver).
#   - MemAvailable oscillates 61.8-62.1GB, NO downward trend. Final = baseline.
# VERDICT 63 STILL-OPEN items both RESOLVED: (1) compositor does NOT retain;
# (2) root fix (avcodec_free_context releasing the zero-copy pool) stays deferred —
# the exit(1) kill covers it. NOTE for future clients: the `close` verb's "ok"
# reply is LOST (exit(1) preempts it); kplay client is fire-and-forget so it's
# harmless, but any future synchronous close waiter will time out.

# VERDICT 63 (bobdotrix 2026-09-25) — KPLAYD VA-DEVICE LEAK = THE RAM CLIMB, FIXED (exit(1)); COMPOSITOR "2.5GB" DID NOT REPRODUCE
#
# PIN (live, clean post-reboot): kplayd leaks ~1 VA decode device (renderD128,
# distinct client-id) + ~440MB GEM per video (4K; ~121MB @1080p). 6 open/close
# cycles → kidulwm RSS FLAT, kplayd +1 fd + ~440MB GEM per cycle. GEM is SYSTEM
# RAM on the iGPU → this IS the "5GB climb", NOT the compositor. Verdict 62's
# "kidulwm 2.5GB dominant" = misattributed (or tied to the since-rebooted
# wedged-driver state); clean kidulwm does NOT retain buffers.
#
# ROOT CAUSE (instrumented, live): avcodec_free_context fails to free the VA
# device + surface pool in the ZERO-COPY path. dev_ref=2 (normal), frames_ref=81,
# hw_live=1 (our av_frame_ref/free balanced) — ~79 dangling refs are the DECODER's
# internal pool, kept alive by the zero-copy export/import path. Plain decode (C
# probe) frees clean; vaExportSurfaceHandle alone = clean; the successful EGL
# import is the trigger. Per Barticus: pool count is codec-fixed, pool BYTES scale
# resolution × bit-depth — the fix must be per-stream-agnostic.
#
# FIX (kmedia 31c5c9f, DEPLOYED /usr/local/bin/kplayd): PUT-TO-BED LAW — after
# dropShell + close, if any renderD fd survives, exit(1) (PROCESS-DEATH IS THE
# KILL). systemd respawns clean; fd + GEM + pool reaped in one syscall. VERIFIED:
# 3 open/close cycles → fresh kplayd 0 renderD fds each, RAM flat.
#
# STILL OPEN: (1) compositor retention (verdict 62 step 3) did NOT reproduce
# cleanly — re-examine only if kidulwm RSS ITSELF climbs (not kplayd GEM).
# (2) root fix (make avcodec_free_context release the pool) deferred — doctrine:
# don't patch teardown to survive its own bugs.

# VERDICT 62 (bobdotrix 2026-09-25) — RAM CLIMB = TWO LEAKS (compositor dmabuf churn 2.5GB DOMINANT + kplayd VA device 224MB); VAAPI possibly wedged — REBOOT OWED
#
# SYMPTOM (Barticus): play-close-play now works (verdict 61 DONE), but RAM
#   climbs to ~5GB and does not release per video/channel.
# FINDINGS (live host, measured):
#   - kidulwm (compositor, pid 210902) RSS 2.5GB = THE "5GB". smaps: 33 x
#     ~27.8MB anon rw- MAP_PRIVATE chunks = EXACT verdict-57 fingerprint (one
#     4K P010 frame each). Verdict 56 deleted the .video slide, but retention
#     returned via the ZERO-COPY present path: kplayd exports a fresh VA
#     surface each frame, wlroots re-imports + recreates the texture per
#     setBuffer, texture-destroy path leaks the GEM (skill "setBuffer import
#     churn" / PER-FRAME DRIVER-CALL CHURN). Total anon rw- = 2.59GB.
#   - kplayd RSS 224MB: session-30 VA-device leak — 5 leaked renderD128 fds
#     (drm-engine-video, distinct client-ids 94/98/102/106/110), ~72-133MB GEM
#     each, one per video. Held by the zero-copy import path (importVaFrame).
#   - VAAPI symptom: since ~16:19 "hwaccel initialisation returned error"
#     (h264 VAAPI decode falls back to software) in BOTH kplayd AND a fresh C
#     probe (/tmp/vadevice_probe.c). At 15:43 VAAPI was ACTIVE. Suspect the
#     leaked iHD contexts wedged the driver; REBOOT to confirm.
# VERDICT: two known leaks (verdict 57 + session 30), now both alive through
#   the zero-copy present path. NOT a regression from verdict 61 (wedge fix is
#   DONE + confirmed working).
# NEXT (post-reboot, in order):
#   1. [DONE 2026-09-25 ~16:30] REBOOT/relog — driver wedge cleared + both
#      leaks reaped (kplayd 27MB RSS / 1 thread / 0 renderD128 fds; kidulwm
#      fresh). Confirmed live post-relog.
#   2. [DONE 2026-09-25 ~16:31] VERIFY VAAPI returns — ffmpeg vaapi decode
#      probe on renderD128 (Intel iGPU, PCI 00:02.0) decodes h264 clean,
#      NO "hwaccel init error". iHD wedge CONFIRMED CLEARED by the reboot.
#   3. PIN + FIX compositor retention (THE 2.5GB fish): per-frame setBuffer ->
#      texture recreate -> GEM leak. Likely fix = cache imported buffer per
#      VASurfaceID (~8 slots), create the scene node ONCE, setBuffer the cached
#      entry; or destroy+recreate the node on surface CHANGE (not per frame).
#      See verdict 52 Card A + video-playback-architecture skill.
#   4. THEN kplayd VA-device leak (session 30): pin the import-path ref
#      (vaExportSurfaceHandle + eglCreateImage holds the device) before any
#      unref — no UAF guess.
#
# VERDICT 61 (bobdotrix 2026-09-25) — "SECOND MOVIE WON'T PLAY" = SESSION-32 POLL-LOOP WEDGE, FIXED + DEPLOYED (eye-test owed)
#
# SYMPTOM (Barticus TV test, post-relog, ~15:00): the FIRST movie/TV channel
#   plays; close it; the SECOND will not play. RAM still climbs.
# CONFIRMED (live host, frozen-process forensics matches session 32 exactly):
#   kplayd pid 190444 (verdict-59 binary a64ef0c3, live since 14:37) holds
#   28 THREADS (16 av:h264:df* frame threads + threaded-ml demuxer + reader
#   STILL ALIVE) and 5 renderD128 fds — fd 12 = leaked VA decode device,
#   fds 19-22 = shell render engine. RSS 233MB vs 27MB clean restart. A player
#   was opened and NEVER torn down (closePlayer never ran dropShell).
#   kidulwm RSS 973MB (at the ~900MB verdict-57 bar, near/over).
#   DOOR (a) PINNED (live thread dump + socket): main thread 190444 parked in
#   __x64_sys_ppoll.cold (wl_display_read_events' NO-TIMEOUT read on the wayland
#   fd), threaded-ml demuxer alive in __x64_sys_poll.cold (av_read_frame),
#   16 av:h264:df* frame threads futex_wait. kplay.sock is SOCK_SEQPACKET and
#   connect() now returns EAGAIN (listen backlog full — the loop is NOT calling
#   accept4). Journal silent since 14:55:36. This is door (a): the poll loop
#   blocked in the Wayland read after the slide closed and the compositor
#   stopped sending events, so the close verb was never read, closePlayer never
#   ran, dropShell never ran. NOT door (b) (main thread is in ppoll, not a
#   futex join).
# VERDICT: NOT a regression from verdict 59/60 (live-reconnect + idle-blank —
#   both remain fixed/live). This is the SESSION-32 kplayd poll-loop wedge
#   (card docs/cards/2026-09-25-kplayd-close-wedge.md, then "DIAGNOSED, FIX
#   SPEC'D, NOT CODED"). Barticus's test REPRODUCED it — confirming the
#   diagnosis. The fix landed later this session — see FIXED + DEPLOYED below.
#   RAM climb = unreaped VA-device GEM + shell (72-133MB each) the wedged
#   close never releases, PLUS the session-30 clean-close VA import-path leak
#   (separate, still open).
# FIXED + DEPLOYED (bobdotrix 2026-09-25, kmedia b55fda1 + 51817f9 signed):
#   CORRECTION (gdb backtrace of the live wedge, 2nd repro): the real block was
#   NOT the read path — it was the PRESENT path. render() -> eglSwapBuffers ->
#   wl_display_dispatch_queue -> ppoll(infinite). eglSwapInterval(1) made
#   eglSwapBuffers block waiting for the compositor's refresh; when the slide
#   closed and the compositor stopped presenting, that block was forever. The
#   read-path fix (door a) removed a real but SEPARATE latent wedge.
#   REAL FIX (51817f9): eglSwapInterval(0) — eglSwapBuffers never blocks; vsync
#   pacing is already the shell's frame-callback gate (cb_fresh) in tick().
#   door (b) = threads_alive + 2s bounded join + exit(1) on wedge (unchanged).
#   playertest PASS + socket open->close PASS (shell live -> threads joined
#   bounded, 0 renderD128 fds after close).
#   kplayd deployed c8b2d9da (.bak-6909a72a = read-path-only; .bak-a64ef0c3 =
#   verdict 59), service restarted clean (1 task, 27MB RSS, 0 renderD128).
#   EYE-TEST OWED (Barticus, TV): play->close->play x3 (no wedge, no
#   play-until-reboot); live cut -> close -> play; after close
#   `ls /proc/$(pgrep -x kplayd)/fd | grep renderD128` = empty; simulated
#   wedge (kill -STOP reader + close) -> systemd respawns <3s.
#   FOLLOW-ON (session 30, separate deploy): pin the third ref in Gl.zig
#   importVaFrame (vaExportSurfaceHandle + eglCreateImage) — clean-close VA
#   leak; needs the import-path repro before any unref (no UAF guess).
#
# VERDICT 60 (bobdotrix 2026-09-25) — IDLE-BLANK CUT THE MOVIE/TV EVERY 10min: playbackInhibitsBlank() never saw fullscreen video [KidulWM a1b2928, DEPLOYED kidulwm 03d9f15d, RELOG OWED]
#
# SYMPTOM (Barticus): a screenBlank fires at the 10 min mark and cuts the
#   movie or TV — should NOT happen while fullscreen is in play.
# ROOT CAUSE: smartLock idle-blank (keybinds.blank.timeout_s=600 = 10min,
#   inhibit_visual=true) calls playbackInhibitsBlank() to decide whether to
#   skip blanking. That fn only read the MUSIC mirror (media_player.cached,
#   set by setMusicNowPlaying) — the video path (kplayOpen + videoFullscreenEnter)
#   never sets cached, so fullscreen video (movies / LIVE TV) returned false and
#   the blank fired mid-watch. SEPARATE from verdict 59 (kmedia reconnect): the
#   "10min cut" was the BLANK, not the feed.
# FIX (KidulWM a1b2928, signed): playbackInhibitsBlank() returns inhibit_visual
#   when video_fullscreen is true (fullscreen-is-a-mode signal, verdict 56).
# DEPLOYED /usr/local/bin/kidulwm 03d9f15d (.bak-b729ded2 = verdict 58).
#   RELOG OWED to pick it up (kidulwm is the compositor — never restarted for
#   the user). bobdotrix dies on relog; this ledger is the bridge.
#   POST-RELOG TEST: play a movie/TV, no input >10min -> screen stays ON.
#   Music still does NOT inhibit (inhibit_audio=false; screen may blank while
#   music plays, per design). Manual Mod4+x blank still works.
# NOTE (architectural, deferred): TV channels play via kplayOpen -> kplayd
#   'open' verb (is_live=false), NOT 'open_live' — the compositor's KplayClient
#   has no open_live method. So the live signal-lost/reconnect path (verdict 59)
#   is NOT yet exercised by the TV rail; a dead feed ends playback like EOF
#   instead of reconnecting. The live rail (open_live verb + IPTV rail) is the
#   deferred follow-on, not this session.

# VERDICT 59 (bobdotrix 2026-09-25) — LIVE-TV RECONNECT/CLOSE WEDGE: hung reopen blocked close(), froze kplayd ("play 10min → cut → no other channel until reboot") [kmedia 5e1cb13, DEPLOYED kplayd a64ef0c3]
#
# SYMPTOM (Barticus): play a live channel ~10 min → it cuts; then can't play
#   ANY other channel until reboot. Channels 7 & 9 (Seven/Nine) also take a
#   LONG time to start now and still cut out. Most channels fail to (re)play.
# ROOT CAUSE (code-proven): kmedia Player.reconnectLive() reopened the dead
#   stream with avformat_open_input(url, null, null) — NO rw_timeout, NO
#   timeout, and the avio interrupt callback is wired only AFTER open returns.
#   A hung reopen (stalled mjh.nz `.r` redirect / TLS / DNS) blocked the
#   READER thread indefinitely. closeInternal() then t.join()s that thread,
#   so close() wedged kplayd's SINGLE poll loop — no further open_live/close/
#   status verb was ever serviced. The initial open (openInternal) already
#   passed rw_timeout=5s/timeout=5s; the reconnect open was the asymmetry.
#   This is the CLOSE-MUST-NOT-BLOCK-THE-LOOP law (video-playback-arch skill).
# FIX (kmedia 5e1cb13, signed): reconnect open now passes the SAME live dict
#   as openInternal (rw_timeout, timeout, buffer_size, probesize,
#   analyzeduration). A dead reopen fails in ~5s; the reader loop stays
#   responsive to stop_flag, close() joins bounded. livetest PASS: backoff
#   retry still recovers (signal-lost -> recovered, clean exit).
# DEPLOYED /usr/local/bin/kplayd a64ef0c3 (ReleaseSafe, mv-over swap, .bak-
#   403639f9 kept), service restarted, daemon responsive (status verb clean).
# OWED (eye-test, TV): play a channel past the ~10min death -> it should
#   freeze-on-last-frame then recover (or at minimum NOT wedge the daemon);
#   Escape/switch channel must work without reboot.
# STILL OPEN (next, "2" of the plan): the ~10min CUT trigger + the 7/9
#   SLOW-START are UNPINNED — need a live repro (mpv control + KMEDIA_TIMING=1
#   on 7 & 9) to separate our clock/reconnect from the mjh.nz feed. Lead:
#   Seven now returns a Yospace CSM playlist (ppId session, #CSM, ad-stitched)
#   — the skill flags SSAI as a known HLS-demux breaker at ad breaks (~10min
#   cadence on commercial TV). Nine is a clean master. Indonesian/Java test
#   channels are parked (test feeds; curation is a later stage, not reset).

# VERDICT 58 (bobdotrix 2026-09-22) — PIPEWIRE "HAMMERING" = ALWAYS-ON FFT MONITOR CAPTURE; NOW CORKED WHEN SILENT [DEPLOYED b729ded2, commit 917e826]
#
# SYMPTOM (Barticus): PipeWire hammering on htop with nothing playing.
# ROOT CAUSE: the "kidulwm-kmedia" sink-monitor LISTENING tap (kmedia.zig
#   capture thread, kmedia_shim.c pw_stream_new_simple) connects ONCE at boot
#   (main.zig:38 kmedia.start()) and is never deactivated. As a live
#   Stream/Input monitor it pins the ALSA sink (graph driver node 57) awake
#   at full quantum 24/7 — data-loop thread never sleeps (1:51 CPU accumulated
#   over 5.5h, ~0.6% steady), sink never suspends. LISTENING is legal
#   (sound.md: "needs no floor") but must not force the graph awake when the
#   room is silent.
# FIX (917e826): gate the capture stream's active state on ksound's floor table
#   — audioLive() (verdict 11 ONE truth; excludes Stream/Input by class so it
#   cannot self-sustain). The existing silence-watchdog thread now also, every
#   ~300ms, calls pw_stream_set_active(stream, audioLive()): cork when silent
#   (sink+graph suspend), uncork the instant a playback stream holds the floor.
#   Our OWN stream -> native set_active, NOT link-teardown (that is for foreign
#   streams, ksound HANDOFF). +1 extern fn, +19 lines, src/core/kmedia.zig.
# DEPLOYED b729ded2 (.bak-5438118f = verdict 56). Build+test clean, signed.
#   bobdotrix does NOT survive relog — handoff recorded here.
# POST-RELOG VERIFY (Barticus): nothing playing -> `pw-cli info 48` (or pw-top)
#   shows kidulwm-kmedia = paused/inactive, and pipewire data-loop CPU ~0 idle;
#   play a video -> stream uncorks, visualizer live; stop -> re-corks within
#   ~300ms. If the graph STILL runs idle, the sink is held by something else.

# VERDICT 57 (bobdotrix 2026-09-22) — IDLE-RAM WEDGE RELOCATED: THE .VIDEO SLIDE (same-GPU, NOT fixed by re-cable); verdict 56 DEPLOYED
#
# Barticus: "800MB extra at idle" after watching videos — each video adds
# RAM and never lets it go. Host live hunt:
#   - kidulwm RSS: ~742MB boot steady-state -> +625MB (13:34:06-14, ~78MB/s)
#     -> +195MB (13:36:55-57), held ~1.6GB after close. Never released.
#   - smaps: 28 x ~27-30MB rw- MAP_PRIVATE ANON chunks (19x27 8x30 1x31MB)
#     = ~800MB retained. EXACT verdict-51 "cross-GPU staging" signature —
#     but ON SAME-GPU now: NVIDIA runtime-suspended, WLR_DRM_DEVICES=
#     /dev/dri/card1 live, TV on Intel DP-3, kidulwm + kplayd BOTH on
#     renderD128. Cross-vendor staging is impossible here -> verdict 53's
#     "cross-GPU, structurally closed" was wrong/incomplete. The retainer is
#     the .video slide, not the GPU boundary.
#   - Running binary was 1afc2343 = verdict 55, which STILL carried the
#     .video slide (renderBlackToBuffer ~33MB black card + chrome_buffer +
#     host surface, videoSlideSpawnRightOfPlayer). Verdict 56 deletes ALL of
#     it (fullscreen = a mode the card enters/leaves, teardown kills
#     host+curtain+kplay on exit).
#
# DEPLOYED this session: verdict 56 -> /usr/local/bin/kidulwm = 5438118f,
#   .bak-1afc2343 kept (drop-back). Build + zig build test clean.
# ALSO FOUND (kmedia, separate, NOT fixed): kplayd leaks its VA-API device
#   per video (~1 renderD128 fd + ~72-133MB GEM each). A plain decode probe
#   (create+decode+avcodec_free_context) closes the fd clean -> the leak is
#   the zero-copy export/import path's extra ref, NOT the device lifecycle.
#   Needs the import-path repro to pin before fixing (no UAF guess). The GEM
#   feeds the SAME 'idle RAM' the compositor retention does.
#
# POST-RELOAD VERIFY (Barticus): play 2-3 videos to natural end + quit.
#   Expect kidulwm RSS ~900MB FLAT after warmup (the bar); and when idle
#   `ls /proc/$(pgrep -x kplayd)/fd | grep renderD128` = 0 (proves the
#   kplayd VA leak out too — if >0 the kplayd leak is still open).

# VERDICT 56 (bobdotrix 2026-09-22) — THE .VIDEO SLIDE IS DELETED; FULLSCREEN = MODE + PRESENT CHOREOGRAPHY [DEPLOYED 5438118f 2026-09-22]
#
# Barticus's call: "the mediaPlayer slide should just be a normal slide." The
# .video deck slide (spawn-right-of-player, focus-walk, player-slip-to-peek,
# black placeholder, chrome ring, rect-chase) is GONE. Fullscreen video is now
# a MODE the card enters and leaves — the card never moves, never parks, never
# peeks. Net code: -36 lines (318 in, 354 out).
#
# THE PRESENT CHOREOGRAPHY (docs/law/fullscreen.md "the kidul way", LOCKED):
#   ENTER: black curtain 0->1 (~180ms) -> hold black, zero energy, until
#          kplayd maps -> video fades ITS OWN pixels 0->1 over black -> at rest
#          curtain stays at opacity 1 behind the video (invisible, free — the
#          black the exit fade reveals), scanout. Controlled present: NEVER
#          pop-on-receive.
#   EXIT:  video 1->0 (reveals curtain) -> teardown kplayd+host -> curtain
#          1->0 -> deck back in. Card still focused, never moved.
#   z-order: deck < overlay(peeks) < curtain < kplayd, re-asserted every tick
#   (applyLayout would strand peeks above the curtain). Same t*t*(3-2t)
#   smoothstep as the boot reveal — one easing language.
#
# DELETED: SlideKind.video, addCompositorSlideRightOf, videoSlideSpawnRightOf
# Player, videoSlidePaint, videoSlideClose/CloseOn, Output.video_slide, the
# black placeholder + chrome ring, pause-on-aside (video_focused +
# kplayPauseForAside/kplayResumeForFocus — fullscreen owns the output, there
# is no "aside"), renderBlackToBuffer, the slidedeck .video test.
# KEPT/REWIRED: kplay_window tracking + placeKplayWindow (now pins edge-to-edge
# over the full output, no rect chase), host surface + xdg-foreign parent
# handshake (videoHostSpawn), syncScanoutOverlay (gate = fullscreen AND idle
# phase, re-fires from the tick's phase edges), nav retire (focusNext/Prev +
# overview + mediaSlideClose + keyboard quit all -> videoFullscreenExit).
#
# State machine: FullscreenPhase enum (idle/fade_to_black/wait_video/
# fade_video_in/fade_video_out/fade_from_black) + curtain_anim struct +
# video_fullscreen/video_fullscreen_output. Driven per-frame from handleFrame
# (tickFullscreen) alongside tickWallpaperReveal.
#
# DEPLOYED 5438118f (bobdotrix 2026-09-22, after verdict 57 RSS hunt). EYE-TEST
# STILL OWED on the TV (host). DROP-BACK = 1edcea7 (verdict 55, binary
# 1afc2343, kept as /usr/local/bin/kidulwm.bak-1afc2343).
#   POST-RELOG TEST: play a movie -> card fades to black -> video fades in
#   edge-to-edge. Quit/nav -> video fades to black -> card fades back in,
#   still focused. No card-to-peek slip, no focus deadlock, no pop-on-receive.

# VERDICT 55 (bobdotrix 2026-09-22) — FULLSCREEN IS A MODE, NOT A DECK POSITION (law 8626a03 + 599a6c8, DEPLOYED 1afc2343)
#
# LAW LOCKED (docs/law/fullscreen.md, 8626a03): the screen is CFC for the eyes
# (sound.md applied to pixels). Fullscreen video owns the output and yields the
# instant deck navigation takes over. Corrects media-is-a-slide.md ruling 6
# ("fullscreen is a size") + kplay.md LAW 4 ("slide moves, video rides").
#
# CODE (599a6c8, 11 lines): focusNext / focusPrev / overviewToggle now RETIRE a
# playing video first (videoSlideClose -> teardown kplayd + .video slide, deck
# settles on the player card) then move. Never navigate with the video slide up.
# Barticus: quit-to-WALL is the wanted shape — card drops to browsing, position
# saved to watch-state, re-select the title resumes. NO retire-paused increment.
#
# OVERRIDES verdict 54's pause-on-aside for the NAVIGATION case (retire wins;
# pause-on-aside now only fires on a cursor-walk across outputs — moot on the
# single-TV appliance). Expected to kill: video riding the deck, the parked
# .video-slide focus deadlock (verdict 51), placeKplayWindow pin-chasing, the
# z-order burial (black placeholder over kplayd).
#
# EYE-TEST OWED (compile-verified only): play fullscreen -> Mod4+Left/Right ->
# video quits to the WALL card, deck settles, no crash, no parked slide. Also
# Mod4+Tab (overview) from fullscreen. DROP-BACK if it fails = b83da5e2
# (verdict 54, kept as /usr/local/bin/kidulwm.bak-b83da5e2).
#
# CROSS-REPO (same session, kmedia): renderD128/shm leak FIXED — the natural
# end-of-stream path (isDone) freed the player inline and left the EGL/GLES2
# shell alive (renderD128 fd + shm/cairo leak + use-after-free). Now routes
# through closePlayer (dropShell first). kplayd deployed 403639f9. Also removed
# the dead Player.hw_device_ctx field (avcodec_free_context already frees it —
# a false lead from the prior session). kmedia commits 70606b7 + 704a4d6.
#
# NOTE: prior kplayd was a 13.6MB Debug build (plain `zig build` defaults to
# Debug). Correct deploy is ReleaseSafe (~4.1MB). `zig build -Doptimize=ReleaseSafe`.

# VERDICT 54 (bobdotrix 2026-09-21) — SLIDE ROUTING + PAUSE-ON-ASIDE (bddc1c5, DEPLOYED b83da5e2)
#
# SYMPTOM (Barticus): opening a media card spawns the fullscreen video but
# pushes the media player to the OTHER screen — the two outputs' decks were
# meeting. "Each screen is its own slideDeck; the two never meet."
#
# ROOT CAUSE: spawn routing used the single global focused_output via
# currentDeck(). media_play already iterated outputs to find the player (correct),
# but media_card_toggle / homeSlideFocusOrSpawn / assignOutput resolved the
# target stage from GLOBAL focus, not the pointer. focusFollowsCursor flapping
# at the eDP-1/DP-3 seam (cursor x ~1920, the old side-by-side auto-placement)
# flipped focused_output every twitch, so the card/video landed on whichever
# stage focus last touched.
#
# FIX (bddc1c5): cursorOutput() / spawnDeck() — a NEW slide (media card, home
# launcher, fresh app window) routes by the POINTER's output (CFC law: the
# cursor is the focus you can see); focus-follow stays on currentDeck.
# assignOutput is cursor-first too. The global focused_output is now a
# focus-follow hint only, never a spawn authority.
#
# PAUSE-ON-ASIDE (same commit, Barticus ruling): the .video slide FREEZES
# playback when walked off-focus (pause verb) and RESUMES when walked back
# (resume verb). Edge-triggered via the new video_focused field in applyLayout.
# OVERRIDES the old "A4 rides at windowed rect" (session-and-deck-spec §2).
# LIVE catch-up-to-edge (seek_abs to live) = follow-on when the IPTV rail
# lands (deferred; resume already lands near the edge since a paused live
# stream stops advancing).
#
# outputs.toml CORRECTED (~/.config/kidulwm): dead HDMI-A-1 (NVIDIA) -> DP-3
# {0,0} above eDP-1 {0,1080}; both 1920 logical wide = laptop centred under
# the TV. No more side-by-side auto-placement (that was the flapping seam).
#
# DEPLOYED /usr/local/bin/kidulwm b83da5e2 (.bak-9fe3b374). RELOG OWED.
# POST-RELOG TEST (Barticus):
#   1. Outputs: TV (DP-3) ABOVE, laptop (eDP-1) BELOW, centred, no side-by-side.
#   2. media_play on the TV -> fullscreen video IN the TV slide; player peeks
#      left ON THE TV. Laptop deck untouched.
#   3. Walk off the video (Mod4+j/l): PAUSES (log "walked aside — pause").
#      Walk back: RESUMES ("refocused — resume").
#   4. media_card_toggle with cursor on the laptop -> card opens on the LAPTOP.
#   5. Watch the return z-order ("comes back under the widgets"): pause-on-aside
#      means the video is frozen, not playing under the bands; the fullscreen
#      return is handled by syncScanoutOverlay (Card A inc1). Flag if it still
#      renders under the bands on return.

# VERDICT 53 (bobdotrix 2026-09-21) — HUB WORKED + GOD CODE LOCKED + CARD A inc1 DEPLOYED
#
# HUB WORKED (post-relog check done): TV on Intel card1 DP-3 (3840x2160 scale=2),
# eDP-1 also card1; NVIDIA card0 HDMI-A-1 + DP-5 BOTH disconnected. Cross-GPU
# staging wedge STRUCTURALLY CLOSED (decode+present both Intel). NVIDIA still
# awake (P0 23W, runtime_status=active, kidulwm+Xorg hold refs) — PARK OWED
# (blacklist nvidia modules, or runtime-PM hard suspend). nvidia-smi shows
# kidulwm 2MiB (WLR_DRM_DEVICES still lists card0) + Xorg 4MiB.
#
# GOD CODE = the name everything converges on; NOT a new phase/refactor. LOCKED
# as docs/law/godcodemode.md. Recon SHRANK the fork: ONLY the CHAMFER corner-clip
# needs a wlroots patch (0.20.2 has no corner primitive at all). Scanout is
# already native (wire it); present-mode = OUR four-axis derivation; slide
# protocol = OUR extension. So slide-protocol + shared-painter "kslate" +
# scanout-by-default = pure KidulWM, zero fork. The sole patch (chamfer) is the
# generic piece to hand back AFTER kidulStyle is recognisable. Patchset-not-fork
# against pinned 0.20.2. Four axes = KIND/GEOMETRY/FOCUS/MOTION; present-mode is
# a DERIVED function, never stored.
#
# CARD A increment 1 DEPLOYED (9fe3b374, .bak-c360c8cc): syncScanoutOverlay() at
# end of applyLayout disables overlay_tree when the video slide is focused AND
# fullscreen, so kplayd's buffer is the sole visible node and wlroots scans out
# directly. Gate = fullscreen AND focused (FULLSCREEN-FOCUS LAW). Log marker:
# "scanout candidate — disabling overlay_tree".
#   POST-RELOG TEST (bobdotrix dies on relog):
#     1. media_play Raya -> fullscreen video slide on TV.
#     2. grep "scanout candidate" ~/.local/state/kidulwm/session.log == present.
#     3. kidulwm CPU during playback: ~2-5% = scanout ENGAGED (win). ~15-33% =
#        overlay disabled but wlroots didn't scan -> next inc targets kplayd's
#        buffer shape (xdg subtree -> bare SceneBuffer).
#     4. Walk video off-focus: peek + chrome MUST return (overlay re-enabled).
#     5. Close video: peek + chrome normal both outputs.
#   KNOWN LIMIT (inc1): fullscreen video also hides peek/chrome on the second
#   output (overlay_tree is global). Fine for the single-TV product; per-output
#   scanout state lands with the slide protocol (Card D). niri = escape hatch.
#   SPRING CLEAN NOTE: ~65 .bak-* binaries now (parked item said "20+" — stale).
#
# NVIDIA BLACKLIST DEPLOYED (2026-09-21, bobdotrix): /etc/modprobe.d/
#   blacklist-nvidia.conf (nvidia/nvidia_drm/nvidia_modeset/nvidia_uvm) +
#   kidulwm-session WLR_DRM_DEVICES=/dev/dri/card1 (card0 dropped). No initramfs
#   regen needed (MODULES=() empty, nvidia loads from rootfs via udev).
#   REBOOT OWED to take effect; POST-REBOOT VERIFY: `lsmod | grep -c nvidia`
#   == 0, `ls /sys/class/drm/` has no card0, `nvidia-smi` gone, dGPU D3cold.
#   Reversible: delete the conf + regen initramfs.

# VERDICT 52 (bobdotrix 2026-09-21) — SCANOUT RECON DONE: present path has ONE seam, direct scanout is wlroots-native but unwired
#
# THE PRESENT PATH (confirmed in tree, wlroots 0.20.1):
#   Output.handleFrame (server.zig:310) -> scene_output.commit(null) (341) ->
#   sendFrameDone. Every frame walks the WHOLE scene graph and re-composites
#   through the GPU renderer. No direct-scanout attempt, no frame gating.
#   That one seam is the root of BOTH live symptoms: fullscreen video jitter
#   (no zero-copy passthrough) + idle 36% CPU (ghostty GTK4 commit ~14/s
#   wakes the loop, every wake = full re-composite of both outputs).
#
# WLROOTS 0.20.1 ALREADY EXPOSES EVERYTHING (bindings present, zero use):
#   wlr_output_is_direct_scanout_allowed, SceneBuffer.OutputSample.
#   direct_scanout, SceneOutput.buildState/commitState, StateOptions. We link
#   these and call none. The fix is wiring, not invention.
#
# THE STRUCTURAL BLOCKER TO SCANOUT TODAY (why fullscreen video can't scan):
#   kplayd's video surface is a SceneXdgSurface inside a per-window
#   scene_tree, raised to top but left BELOW overlay_tree. overlay_tree
#   (peek + chrome rings) is always enabled and raiseToTop()'d — peek hides
#   its child trees on fullscreen but the overlay_tree node itself stays up.
#   wlroots direct scanout requires a SINGLE buffer covering the output with
#   NOTHING above it, no scale transform. So today: fullscreen video =
#   wallpaper + layer strata + slide card + kplayd surface + overlay_tree all
#   composited. Scanout needs the fullscreen path to collapse to: kplayd
#   buffer alone, overlay_tree (and slide card + wallpaper) disabled/hidden,
#   opaque, exact-cover.
#
# NEXT CARD (render-path law, LOCKED docs/law/render-path.md): scanout first,
#   then gating. Card A = fullscreen-video scanout reachability: on focused
#   fullscreen video slide, disable overlay_tree + hide wallpaper/card so
#   kplayd's buffer is the sole cover, then verify wlroots engages direct
#   scanout (log evidence + CPU ~2-5%). Card B = frame gating: handleFrame
#   skips commit when no scene damage + no active animation + no pending
#   layout (kills the idle 36%). Slow path (thin tentacles) unchanged.
#   GHOSTTY FORK + slide-protocol/"GodCodeMode" = separate spec, wargamed
#   after this law lands. Cross-GPU re-cable (verdict 51) still deferred.

# WEDGE ROOT-CAUSED + FOCUS DEADLOCK (bobdotrix 2026-09-20 ~22:30) — VERDICT 51 (LOCKED 2026-09-21)
#
# WEDGE = cross-GPU staging retention (I4). Live repro (Raya, ACTIVE playback,
# kplay committing ~4754 frames, kplayd healthy 400MB): kidulwm 288MB -> 1003MB.
# smaps classifies the +722MB as PRIVATE ANONYMOUS mmap: ~22 chunks of ~27-30MB,
# rw- MAP_PRIVATE, RETAINED (kidulwm stays ~989MB after `close` verb to kplayd).
# Root = hybrid GPU: kplayd decodes on INTEL iGPU (renderD128, VAAPI); the 4K TV
# (HDMI-A-1) is on the NVIDIA dGPU (sysfs card0=0x10de RTX3060 owns HDMI-A-1;
# card1=0x8086 Intel owns eDP-1). Cross-vendor dmabuf import (Intel decode ->
# NVIDIA present) CANNOT zero-copy -> each frame = ~27MB CPU staging buffer,
# wlroots/GL retains them. Phase-2 "zero-copy ~2% CPU" bar is STRUCTURALLY
# unattainable while decode+present sit on different GPUs.
# DECISION (Barticus 2026-09-21, LOCKED): forget the NVIDIA side — drive the TV
# from the INTERNAL Intel GPU (fork b). Decode is already Intel VAAPI; presenting
# on Intel removes the vendor boundary that forced the ~27MB CPU staging buffers.
# No NVDEC, no PRIME offload. wlroots releasing the staging buffers on the
# copy path stays as defense-in-depth (land it regardless of the GPU fix).
# MECHANICS RESOLVED (bobdotrix 2026-09-21): HDMI-A-1 is hardwired to the NVIDIA
# dGPU (card0) — muxless laptop, no mux, no software routing. The Intel iGPU's
# only external outputs are DP-1/DP-2 = the Thunderbolt 4 / USB-C port. So the
# fix is a RE-CABLE: TV -> USB-C hub -> TB4 port, then park NVIDIA.
# DEFERRED ("later thing" — Barticus has a USB-C hub ready for it):
#   BARTICUS does: plug the TV into the USB-C hub / TB4 port (USB-C->HDMI).
#   BOBDOTRIX does, when re-cabled: (1) verify TV lights on Intel DP-1/DP-2;
#   (2) park/disable NVIDIA (runtime PM or BIOS); (3) re-run the wedge repro —
#   kidulwm RSS flat, no staging growth; (4) confirm audio still Intel HDA
#   analog (default sink already is); (5) close verdict 51, retire the
#   cross-GPU staging root-cause.
#
# FOCUS DEADLOCK (separate bug, found live): a .video slide that loses focus
# (focus-follows-cursor / walk) becomes PARKED; focusNext/focusPrev SKIP parked
# slides -> unreachable (no re-focus, no Ctrl+q quit). videoSlideSpawnRightOfPlayer
# guards `findKind(.video) != null` -> no re-spawn either. Net = stuck slide,
# recover only via overview/relog. Fix: focus walk must land on a parked .video
# slide, or the slide must unpark on quit.

# WORKBENCH (READJUSTED 2026-09-19): Phase 2 (RSS wedge) is GPU-only, so the
# workbench moves BACK TO THE HOST for this phase — kidulwm runs on the host's
# real i915/VAAPI/dmabuf (GL, NOT pixman). ksd-reset stays the software/pixman
# workbench for everything else. fresh-one FROZEN, never touch. Host deploy =
# ReleaseSafe build on host -> /usr/local/bin/kidulwm (mv-over swap + .bak).
# bobdotrix does NOT survive an sddm login — document handoff here first.
#
# CURRENT POSITION (2026-09-20 ~20:50): verdict 50 + tracer DEPLOYED 869c68a9
# (commits 57dab29 + f5b4beb signed B&B) AND RELOG DONE — running pid 830305 ==
# /usr/local/bin/kidulwm == 869c68a9 byte-identical, live since 20:39. Git HEAD =
# 3f381ff (2 doc-only CENSUS commits past the deployed code; nothing undelivered).
# 15 commits UNPUSHED to Codeberg (ledger earlier said 3 — stale; list below).
# FRAMETRACE live 10s idle sample: rendered 14.2/s, commit 9.4/s = ghostty 9.4/s
# (100% of commits), all 6 scheduleFrame sites flat, kplay=0 other=0. Idle
# committer NAMED = ghostty. NEW GAP: rendered 14.2 vs 9.4 commit = ~4.8 wakes/s
# with NO named source (not commit, not any scheduleFrame site) — next question.
# Phase 2 step 1 DONE (wedge owner = kidulwm), step 2 IN PROGRESS. Raya = video.
#
# SURGERY DEPLOYED (2026-09-20 ~22:00): per-output render counter. The global
# ft_rendered folded a 144Hz+60Hz two-output rig into one number, so the
# "rendered 14.2 vs commit 9.4" gap was un-attributable. handleFrame now bumps
# per-Output ft_rendered AND emits FRAMETRACE-OUT {s} rendered={d} per output.
#   Deployed c360c8cc (.bak-869c68a9), build+test clean, signed. RELOG OWED.
#   POST-RELOG (bobdotrix dies on relog): grep FRAMETRACE-OUT, compute per-output
#   rate deltas. Expect ghostty's 9.4/s pinned to one output and ~4.8/s of
#   self-wake on the other (eDP 144Hz prime suspect) — names the idle waster.
#
# POST-RELOG READ DONE (bobdotrix, ~22:07) — idle waster NAMED, eDP hypothesis FALSIFIED:
#   Relog done: running kidulwm pid 1691 (started 22:04) == /usr/local/bin/kidulwm
#   == c360c8cc (no "(deleted)" on exe -> per-output tracer LIVE). FRAMETRACE-OUT:
#   eDP-1 rendered FLAT at 425 (never climbs); HDMI-A-1 rendered climbs ~14/s.
#   => idle render is 100% on the 4K HDMI output; eDP 144Hz is NOT the waster.
#   Global: commit ~14/s, ghostty=100% (kplay=0 other=0); rendered~=commit~=14/s
#   now — verdict-50 chrome fix closed the old "rendered 14.2 vs commit 9.4" gap
#   (the mystery ~4.8/s self-wake WAS the chrome regen loop). Idle cost: kidulwm
#   31% CPU, RSS 273MB FLAT (no idle wedge), i915_irqs ~86-100/s; kplayd 27MB/0.1%
#   healthy. ghostty (stock GTK4, pid 2502) is the SOLE committer, mapped on
#   HDMI-A-1 (CHROME create output=HDMI-A-1). 17 KidulWM commits UNPUSHED; kmedia
#   still NO git remote.
#   NEXT (step 2 close, ONE probe): is each ghostty commit a tiny-damage 4K redraw
#   (-> compositor commit-path cost, fix THERE) or a full-surface repaint (-> GTK4
#   frame-clock/client misconfig, fix the CLIENT)? Check ghostty GTK env/config for
#   the ~14/s driver FIRST (no relog); else add damage-rect to commit path + relog.
#
# KEY FINDING THIS SESSION (Barticus caught it): the "thick tentacle" committing
# ~8/s at idle is a STOCK ghostty — CachyOS package ghostty 1.3.1-2.2, a full
# GTK4 + libadwaita + gtk4-layer-shell app (ldd confirms libgtk-4/libadwaita-1/
# gtk4-layer-shell). The stripped-back ghostty fork is the END GAME and is NOT
# built yet. So the idle commit rate is GTK4 frame-clock + libadwaita + GSK
# machinery, NOT a light terminal. kidulwm itself links NO GTK (pure Zig/wlroots/
# cairo; only transitive libglib). The Zig-GTK4 plan has NOT leaked into the
# compositor — it is a separate tentacle (rkt-dashboard/gauge shells).
# VERDICT 50 also killed a stale premise: "damage-clipped commit" is a NON-FIX
# on wlroots 0.20.1 (commit() takes StateOptions, damage is internal).
#
# NEXT SESSION (post-relog): read FRAMETRACE's ghostty=/kplay=/other= split to
# NAME the idle committer by rate. Then answer: is each ghostty commit a cheap
# damage-clipped redraw or an expensive one? Dig the GTK4 frame-clock driver.
#
# LOG-GATE DEPLOYED (verdict 46, commit 8f85879): dev-trace (handleCommit /
# setSurfaceOffsetForFocus / BTN-NOTIFY / PTR-ENTER / pointer-diag) demoted
# info->debug. /usr/local/bin/kidulwm = 4544249f (stamp 8f85879, kmedia 1db5571),
# .bak-37fcf59. TAKES EFFECT ON RELOG. Watchdog now logs kplayd RSS too.
# Commit NOT yet pushed to Codeberg (owes post-relog verify + push).
#
# FINDING (verdict 46): idle CPU ~30-55% is NOT the watchdog (0.2%) and NOT the
# logging (16 lines/s is cheap). i915_irqs climbs ~28/s while idle = continuous
# frame scheduling -> the RENDER LOOP is the suspect, not the commit path (the
# no-op guards already kill the commit->damage->redraw loop). This IS the
# Phase 2 compositor-side suspect (verdict 45), not scope creep.
#
# NEXT SESSION STARTS HERE (2026-09-20):
#   POST-RELOG STATE VERIFIED (bobdotrix 2026-09-20 ~15:52): relog ALREADY DONE
#   (kidulwm pid 465925, started 15:39:58). Running binary == deployed == HEAD:
#   kidulwm 4544249f (8f85879), kplayd 6b6b040b. Log gate LIVE + verified SILENT
#   (dev-trace grep = 0). RESULT: idle CPU STILL ~40% (kidulwm), i915_irqs still
#   ~100/s. Log gate is CONFIRMED not-the-fix — verdict 46 was right that logging
#   was never the cause. The render loop / damage source IS the target.
#   NEW DATA: eDP-1 = 1920x1080 @144Hz + HDMI-A-1 = 3840x2160 @60Hz (2 outputs
#   live). A 144Hz panel amplifies any residual idle damage into 144 commits/s.
#   Live windows: ghostty mapped (the 8 commits/s thick tentacle); video-slide-
#   host unmapped; kplayd toplevel NOT mapped (no video playing). kidulwm RSS
#   flat 528MB / kplayd 429MB — no wedge at idle, as expected.
#   BAR/BUTTONS HYPOTHESIS (Barticus) CHECKED: transport bar + 2 buttons are GONE
#   from the compositor (verdict 33 deleted media_video.zig; media.zig has zero
#   transport/seek/scrub/button code). mediaSlideRefresh is verdict-17 guarded
#   (not a hot loop). kplayd 0.2% CPU = not looping. So no compositor code is
#   "searching for" the absent bar/buttons. Idle wake = damage-driven render-loop
#   churn, NOT an orphaned bar/button poll.
#
#   NEXT (Phase 2 step 2, compositor side): instrument WHO schedules frames /
#   damages at idle — render loop is event-driven (no free-running loop;
#   scheduleFrame sites all bounded: peek minute-timer 1029, requestLayout 1164,
#   scale change 3623, one-shot wallpaper reveal 3872/3911/3942). Prime suspects:
#   ghostty commit damage (thick tentacle) and/or a requestLayout storm. THEN
#   Phase 2 step 1 HOST repro (media_play Raya, watch BOTH RSS in
#   /var/log/kmedia-watchdog.log) to name the wedge owner.
#   Raya: /mnt/sda_backup/Jelly/Kids Movies/Raya.and.the.Last.Dragon.mkv.
#   3 KidulWM commits UNPUSHED (8f85879, 34c129f, 38bc43a) — push owed. kmedia
#   checkout has NO git remote configured (flag).
#
# PARKED (at Phase-2 base):
#   - CONSOLIDATE kidulwm-development skill (100KB god-file at size cap).
#   - Prune 20+ /usr/local/bin/kidulwm.bak-* binaries.
#   - Weather widget redo (new design, not clamps — see verdict 27 below).
#   - Peek-unit law (%-of-peek sizing) — deferred polish pass.
#   - Screens law (Boss/slaves/pack) — docs/law/screens.md, locked.
#
# NEW CARD (2026-09-20, Barticus) — HOUSE TEXT-SIZE TOKEN + remote scroll wheel:
#   TBD date. NOT discussed before tonight. The idea: a smooth scroll wheel on
#   the remote adjusts text size on the focused slide, so Granny sets the right
#   size from the lounge chair, and ALL our apps come ready with the same sized
#   CFC text. The CFC payoff: one token, every app follows.
#   SHAPE (agreed in conversation): do NOT build per-slide "remote -> focused
#   slide -> that slide's font size" as a hack. Build ONE house text-size token
#   (per-output, integer-scaled, like the existing CFC scale law) that every
#   THIN-tentacle app reads through the one shared painter (kpaint — see the
#   thin/thick + kpaint discussion, also new this session). Remote scroll wheel
#   just nudges that single token; all CFC text follows. This is the typography
#   half of the renderer-unification decision, and it supersedes the parked
#   "kfiles font ramp (typography law)" crumb in HANDOFF.
#   PRE-EXISTING HOOKS: theme.toml [typography] font_size_s/m/l=13/16/22, loaded
#   once in core/theme.zig (fixed, not runtime). output_layout_config.zig:24
#   already tags "text size" as the future per-output setting shape. Integer
#   scale from pixel density (CFC scale law, server.zig ~3470) is the model.
#   Frontier: token must live per-OUTPUT (two outputs, different scales) and be
#   integer-scaled, never fractional, to stay crisp (CFC law).

# ─────────────────────────────────────────────────────────────────────
# PROCESS LAWS (load-bearing for all reset work)
# ─────────────────────────────────────────────────────────────────────
# FIX-AND-RECORD (Barticus 2026-09-09): when a verdict is PROVEN (root cause
#   named, mechanism shown in code/logs, not theory) and the fix is small
#   (same file, no interface change), fix immediately — don't wait for approval.
#   Still: repro closes the symptom; early fix != skip verification.
# CENSUS-FIRST, NO PATCHES ON THEORY. Name the boundary, THEN fix.
# ONE CHANGE PER DEPLOY. Commit immediately when something works.
# SESSION HANDOFF (Barticus 2026-09-19): bobdotrix dies on an sddm login —
#   do all host-prep that needs no login cycle, record exact next commands,
#   hand off. This ledger IS the bridge.
# Dmabuf cache-key law: never key a dmabuf cache on surface id alone (pools
#   reuse ids across decoders -> stale hit renders freed GPU surfaces).


