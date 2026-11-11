# C5 DECOUPLING — EXECUTION PLAN (DRAFT, v2 re-cut after Barticus's steer)

Status: DRAFT v2 2026-11-11 by bobdotrix. v1 was the app_id strip only;
Barticus added TWO more targets (media card → zero; test media → zero on KSD).
This is the full C5 scope. For Barticus to lock next session.

Laws this executes (already LOCKED, no new design): slide-process.md
(LOCKED 2026-10-14, "mother roach"), kplay.md (LAW 2: one player, all media),
app-id-namespace.md (com.kidulworks.*), fullscreen.md (fullscreen is a MODE).

---

## The three targets (Barticus 2026-11-11, verbatim intent)

  1. THE CARD IS DEAD. "There should be NO card at all any more — only the
     slide." The old media CARD became the media SLIDE (the placement, holding
     the kmedia client). The compositor-owned card scene tree (MediaCard /
     MediaWidget / media_slide.zig) must be ZERO. "Card" survives ONLY for the
     overview mini-grid and the dm login card — never media.
  2. TEST MEDIA STAYS ON THE HOST, ZERO ON KSD. "The test player stays on here
     for now, but the KSD on the other m.2 should have zero media 'test' and
     zero media 'card' references or code anywhere."
  3. THE APP_ID SPECIAL-CASING (v1 scope) — kidulwm must stop naming kmedia /
     kplay by string. (This is "half the issue"; the card+test are the other
     half.)

## Goal (one sentence)

KSD ships with NO media card, NO test media, and NO app_id special-casing:
kidulwm is a pure conductor, kmedia is a plain client seated in a slide,
kplayd is the resident player on kplay.sock.

---

## Target 1 — the media CARD is dead (only the slide remains)

Verified footprint (all inside kidulwm/src, must go to zero):

  ui/media.zig        MediaCard struct (:22), MediaWidget.card (:520),
                      toggleCard/setCardOpen/isCardOpen (:581/:594/:612),
                      CardClick (:1321), renderCard (:1486) — the embedded
                      scene tree: scanCategory, g_* library globals,
                      ArtPipeline, watch-state. This is the roach's live body.
  ui/media_slide.zig  imports media.zig; MediaSlide tree + renderToBuffer
                      (33MB ARGB32 cairo) — the render-to-buffer path.
  server.zig          mediaSlideToggle/Open/Close/CloseOn/OpenAnywhere/Key/
                      FocusOrSpawn; .media_player compositor slide kind.
  keyboard.zig        mediaSlideKey routing (the .media_player slide owns keys).
  slidedeck.zig       .media_player compositor slide kind (:43-45).

  SURVIVES (do NOT touch — "card" is a live concept here):
  core/slidedeck.zig  overview slide's mini-grid "card" (:482)
  dm/render.zig       drawCard, the dm login card (:157/:238)
  core/animation.zig  animation.card preset (generic popup motion)
  core/style.zig / core/theme.zig  card_mat / card_border / CardMatStyle
                      (the visual mat language, media-agnostic)

  Delete sequence (prove in VM first):
  D1  census on ksd-reset VM: is .media_player ever seated on a real boot?
      If yes → Path B is live (see Q-A), re-plan before deleting. If no → D2.
  D2  git rm ui/media.zig ui/media_slide.zig; strip the .media_player
      compositor slide kind from slidedeck.zig; delete mediaSlide* from
      server.zig + keyboard.zig + the media_card_toggle IPC/keybind plumbing.
  D3  confirm zero: grep -riE 'MediaCard|MediaWidget|media_slide|mediaSlide|
      mediaCard|\.media_player' kidulwm/src/ == empty.

## Target 2 — test media: host-only, ZERO on KSD

Verified (2026-11-11):

  a. test-media.mp4  the ffmpeg 12s H.264+AAC clip (CENSUS "injected to
     /home/kidul/test-media.mp4"). VERIFIED ABSENT from the current /mnt/ksd
     image. It must NEVER be injected again; no test clip ships.
  b. Player.zig      the "old test player" — ALREADY DELETED from kmedia/src/
     (file absent). Only comment references remain (Gl.zig:472, Timing.zig:163,
     Wayland.zig:160, Wall.zig:12). Those comments may stay (history) or be
     tidied — cosmetic, not a blocker.
  c. 12 test/probe harness binaries still built by kmedia/build.zig via
     installArtifact: bench_decode, clockprobe, displaysync, driftprobe,
     eofprobe, liveavoff, livetest, modeltest, playertest, posprobe, walltest,
     tvpacktest. PLUS kmedia-test built by KidulWM/build.zig (src/test_kmedia.zig)
     and ksoundtest (ksound). These are DEV harnesses — they live in zig-out on
     the HOST, and MUST NOT be deployed to /mnt/ksd/usr/local/bin.

  The KSD deploy rule (make it law): only the named production binaries are
  ever installed to /mnt/ksd (kidulwm, kmedia, kplayd, ktty, kfiles, kbrain,
  kbrain-ui, kweather, ksignals, kslide-template, kidul-browser, kushd, ksound,
  knetd, kboot). Test/probe harnesses stay in zig-out, never deployed. A
  deploy-list (not a glob) guards this.

  Delete sequence:
  T1  sweep kmedia/src for test-only code still compiled into kmedia proper:
      test_scanner.zig, the libkmedia test hooks (*ForTest comment at :31-32),
      test_wall.zig. Decide per file: harness (keep, host-only) vs dead code in
      the shipped binary (remove or gate behind a build flag).
  T2  confirm the deploy is a WHITELIST (explicit binary list), never
      `cp zig-out/bin/*`.

## Target 3 — app_id special-casing (v1 scope, unchanged)

  server.zig:2144  mediaCardToggle exact-eql "com.kidulworks.kmedia"
  server.zig:4049  handleNewXdgToplevel exact-eql "com.kidulworks.kplay"
  server.zig:4070  classifyKplay exact-eql "com.kidulworks.kplay"
  window.zig:62/577/627  is_kplay flag + placeKplayWindow
  window.zig:682  "kplay"/"ghostty" substring frametrace

  Replacement (see Q-B / Q-C): identify kplayd's surface STRUCTURALLY (xdg-
  foreign child of video_host_surface), drop the string; kmedia focus-or-spawn
  via a kushd seating tag, not app_id. These are the rename-lockstep sites —
  removing them is what frees kidulwm from ever naming its apps again.

---

## Open questions for Barticus (lettered, with recommendations)

Q-A  (v1, still open) is Path B — the .media_player compositor slide — ever
     seated on a real boot? REC: census on ksd-reset VM before D2. Deleting a
     live circuit is a regression, not a cleanup.

Q-B  (v1) kplayd surface identification. REC: structural (xdg-foreign child),
     drop the app_id string. No rename-lockstep ever again.

Q-C  (v1) kmedia focus-or-spawn. REC: kushd seating tag (kushd decides,
     kidulwm consumes). GATED on kushd growing a "seat kmedia" act. Until then
     the app_id match is a tolerated bridge — but it dies WITH Target 1 (the
     mediaCardToggle is part of the card plumbing).

Q-D  (v1) media.zig deletion gate — VERIFIED CLEARED (Wall.zig 3-pill filter
     ships). C5 may proceed once Q-A confirms Path B dead.

Q-E  (NEW) do the test/probe harness binaries get (a) deleted from build.zig
     entirely, (b) gated behind a `-Dharness` flag, or (c) kept built but
     excluded by the deploy whitelist? REC: (c) now (cheapest, keeps dev
     harnesses), fold (b) into a later build-hygiene pass. No harness code is
     in the shipped kmedia/kidulwm binaries today (strings-verified).

Q-F  (NEW) the Player.zig comment references and the "test player" wording in
     HANDOFF.md / c2-client-ify.md — tidy now or leave as history? REC: leave
     (history records the fork incident; never rewrite history, per
     ksd-vocabulary-law).

## Proposed cut order (prove in VM, per KSD doctrine)

  Step 0  census: is .media_player seated on a real boot? (Q-A)
  Step 1  Target 2 first (it's a whitelist + sweep, zero VM risk): T1 + T2.
  Step 2  Target 1 (the card) — D2 + D3, after Step 0 clears.
  Step 3  Target 3 (app_id) — structural identification lands in the SAME cut
          as the strip (Q-B), then the kmedia seating tag (Q-C).
  Step 4  rebuild + redeploy lockstep (kidulwm + kmedia + kplayd) to /mnt/ksd,
          cp->mv atomic, strings-verify, remount ro.

## Verification (acceptance, all must pass)

  - grep -riE 'MediaCard|MediaWidget|media_slide|mediaSlide|mediaCard|
    \.media_player' kidulwm/src/ == 0 hits.
  - strings /mnt/ksd/usr/local/bin/kidulwm | grep -iE 'mediaCard|MediaCard|
    renderCard' == empty.
  - strings /mnt/ksd/usr/local/bin/kidulwm | grep -cE 'com.kidulworks.kmedia|
    com.kidulworks.kplay' == 0 (no name special-casing).
  - no test/probe binary in /mnt/ksd/usr/local/bin (ls whitelist check).
  - no test-media.mp4 anywhere under /mnt/ksd (find check).
  - kidulwm boots on ksd-reset VM; kmedia seats as a plain client in a slide;
    kplayd answers on kplay.sock; playback + fullscreen still work.

## Risks

  - Deleting the card while Path B is live (Q-A) = media keys + library die.
    Step 0 is the guard.
  - Stripping the kplayd app_id match before the structural path lands = the
    video surface falls back into the deck as a normal window. Step 3 must
    land structural identification in the SAME cut.
  - Over-deleting "card": the overview mini-grid and dm login card are NOT
    media and stay. The grep in D3 is scoped to media symbols only.

## Not in scope (separate axes, do not blur)

  - kushd "seat kmedia" act (Q-C dependency) — a kushd task, not C5.
  - Product branding (KSD / StarShipKidul face) — unrelated to app_id/process.
  - Host keybinds.conf cleanup (stale ghostty / ~/.local/bin/kmedia lines).
