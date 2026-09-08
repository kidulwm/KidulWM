# TASKCARD — media collapse: the mediaPlayer becomes a normal deck slide

Card: 2026-09-07-collapse · Author: bobDotrix (orchestrator) · Executor: coderBob
(attended, stage-per-dispatch — ONE stage per dispatch, never two)
Repo: /home/dad/dev/KidulWM · Branch: media-collapse (from 8a43291)
B&B identity, sign everything (pre-commit hook armed).
Scope: HOST ONLY. Do NOT push. Do NOT touch the VM. Do NOT touch main —
today's playback.md patchwork commits (f197f7d, ba2f6fe, 7087802) stay on
main as history only.

## Rate-limit protocol (the three-headed monster)

- ONE stage per dispatch. A stage is: code + builds clean + verification
  bar met + SIGNED COMMIT. Nothing half-landed between stages.
- If the session dies mid-stage (API 402, rate limit, anything): STOP.
  Leave the tree exactly as it is and write a STAGE-INTERRUPTED note at
  the top of this card's stage section: what was attempted, what compiles,
  what doesn't. The next dispatch resumes from the note. Never resume by
  guessing from the diff alone.
- Orchestrator re-verifies every stage independently before the next stage
  is dispatched: read the diff, rebuild cold, trace the repro.
  Self-report is not proof.

## Reading list (READ FIRST, in order)

1. /home/dad/dev/kmedia/docs/law/playback.md — THE LAW this card implements.
   Locked 2026-09-07. The collapse: mediaPlayer is a normal deck slide.
   Fullscreen is a SIZE, not a mode. The peek is a VIEW, not a state.
   Audio stops ONLY on explicit Stop or end-of-track.
2. docs/law/daily-driver.md
3. HANDOFF.md
4. src/server.zig — everything grep finds under `media_slide|mediaSlide|
   play_timer` (~122 hits) is the machine being dismantled. Know it before
   touching it.
5. src/ui/media_slide.zig, src/ui/media.zig (the widget — SURVIVES),
   src/core/slidedeck.zig (EmptySlot, media_slide_open, openMediaSlide/
   closeMediaSlide/mediaSlideTarget ~lines 354-430),
   src/input/keyboard.zig (mediaSlideKey layer ~line 178),
   src/ui/overview_slide.zig — the sibling sentinel slide; its frame-callback
   driven life is the shape the media slide must adopt.

## Ground truth (orchestrator-verified 2026-09-07, do NOT re-litigate)

- The old pump (this branch, Output.handleFrame ~line 227-260): EVERY vsync
  while playing → player.tick(), copy pixels only when display_serial moves,
  then wlr_output.scheduleFrame() to self-perpetuate. This is the actual
  SUSPECT #1 stutter fix shape and it WORKS. The play_timer rewrite on main
  (cca4265) replaced it with a 16ms wl_event_loop timer that spins the
  compositor at ~90% CPU and can miss its reactive arm window → dead player.
  We do NOT port the play_timer. The vsync pump stays.
- The widget (ui/media.zig MediaWidget + kmedia_lib.Player) is NOT special-
  cased by this card. Decode, A/V sync, subtitles, watch-state: untouched.
- What dies per the law: media_slide.zig's sentinel scene tree machine,
  play_timer/armPlayTimer/handlePlayTimer/disarmPlayTimer (already absent
  on this branch — KEEP them absent), the mediaSlideKey input layer,
  mediaSlideOpenAnywhere, ctrl+Q special-case, the before_first sentinel
  slot semantics that make the slide "not a slide".
- What survives: one media slide per session (moves with the cursor),
  card browsing/expansion, peek widget (renders cached state, owns nothing),
  fullscreen letterbox + bar + two buttons, audio authority
  (close = view-only, playback survives), the RESTING FRAME is NOT
  ratified on host — no-stills reconcile (video_buffer != null → teardown)
  stays as-is.

## Stage 0 — baseline deploy (DONE by orchestrator)

- Branch media-collapse at 8a43291 builds clean: Debug + ReleaseSafe.
- kidulwm sha256 f420d9da7972f85f9172ad7bfe78afbdf8d3397900673a19407252c6535a571f
- kidulwm-control sha256 f434290ab9c540b42437a85879973e84aea45b7be15a0684662c87a1696d11d7
- Deployed to /usr/local/bin; Barticus restarts session and confirms:
  movies play, Enter/keys behave, no CPU spin (kidulwm < 5% at idle).

## Stage 0.5 — idle-desk frame storm (DONE 2026-09-07, commit 20af42a)

Symptom (orchestrator-verified on the deployed baseline, sha256 f420d9da…):
fresh login, NOTHING open, kidulwm spins at ~95% CPU. session.log FRAMES
counter shows BOTH outputs rendering 46-93 fps continuously since boot
(media_open=false ready=false active=false wallpaper_anim=false).
strace: ~6800 DRM ioctls + 1441 munmaps per 5s = buffer alloc/destroy
churn every frame.

Root cause (named condition): `drawMediaWidget` (src/ui/tray.zig:3616)
had an unconditional `const redraw = true;` — "the helix animates every
frame, so always redraw." Every `tray.update()` therefore allocated a
cairo surface + DataBuffer, dropped the old wlr.Buffer, destroyed and
recreated the wlr.SceneBuffer — per update, per output, regardless of
any state change. Any frame reaching handleFrame (client commits from
Barticus's session — visible as the handleCommit lines interleaved with
every FRAMES line in session.log) called tray.update(), which both
churned buffers (the munmap/DRM churn) and left the update loop hot at
46-102 fps. The `needs_redraw` conditions themselves (tray.zig:1351,
1436, 1439) all evaluate false at idle; the storm's *damage* was the
ungated widget draw block, with drawMediaWidget as the only widget that
forced redraw unconditionally.

What changed (src/ui/tray.zig, commit 20af42a):
- PerOutputMedia gains `last_peek_key: u64` (tray.zig:236).
- drawMediaWidget redraw gate (tray.zig:3616-3644): redraw only when
  the peek key changes — title hash, theme generation, scale, pill
  geometry, player_active, cached.playing, media_card_open, quantised
  audio level — or while audio is live AND playing (helix keeps
  breathing to music). Idle/paused: peek is a static cached render,
  ZERO buffer churn. The old `redraw = true` is gone.
- Rate-limited (1/s) TEMP DIAG log at the needs_redraw → request_frame
  site (tray.zig:1463-1498) naming each condition
  (first/tray_anim/bob/barry/underline/per_output/notify/signals_card/
  media) — marked for removal after live verification confirms ~0 fps.
- Clock/weather/gauge/drives/notification widgets were already
  state-gated (minute hash, geometry, theme generation) and untouched.

Build + verification trace:
- `zig build` (Debug, cold cache): CLEAN, exit 0.
- `zig build -Doptimize=ReleaseSafe` (cold cache): CLEAN, exit 0.
- Live FRAMES-counter verification deferred to Barticus on deploy
  (executor must not restart the host session; launching a second
  nested/headless instance was blocked in the dispatch environment).
  Code-trace: idle desk → kmedia.level() ≤ 0.03 → peek_key stable →
  redraw=false → no scene-buffer churn; all needs_redraw conditions
  false after boot settle → no request_frame → ~0 frames/s.
- Tray repaint paths preserved: hover/open (per_output condition),
  clock tick (drawWidget minute gate), weather (minute gate), gauges/
  drives (geometry/theme gates), media peek (peek_key + live-audio
  redraw).

Signed B&B commit: 20af42a436d3c14c0c1fc763094d1e565015b4c2
(GPG 344B8C86C2E835F1AF9766E40AE9A7E153BFA843, good signature).

## Stage 1 — fullscreen is a SIZE (port ba2f6fe, cleanly)

Port ONLY the good idea from main's ba2f6fe onto this branch:
mediaSlideTarget(fullscreen=true) returns the full output rect while
player_active; card size otherwise. CARD or FULLSCREEN, nothing between.
Do NOT port anything else from main's three commits.

Verification bar:
- zig build CLEAN (Debug + ReleaseSafe).
- Trace in commit message: open slide → play movie → slide fills output;
  exit fullscreen → slide returns to focused slot. No halfway states.
- Signed B&B commit.

## Stage 2 — audio authority: close is view-only (port the intent of 7087802)

mediaSlideClose stops calling ensureStopped(). Playback survives the card
closing; the vsync pump's isOpen() gate must NOT gate tick() — tick while
player_active, present pixels only while isOpen(). The slideless/tray music
pump already shows the pattern (~line 262-276). Peek mirror: while the slide
owns a playing player and the card is closed, tray.media.cached mirrors the
slide widget's cached state so the peek label lights (port from 7087802's
peek-mirror block, adapted to the vsync pump — do NOT introduce play_timer).

Verification bar:
- zig build CLEAN (Debug + ReleaseSafe).
- Trace in commit message: play music → close card → audio continues →
  peek label lit → reopen card → lands mid-track, controls live.
  Play movie → close card → video buffer torn down (no ghost), audio
  continues → reopen → video re-arms from currentFrame().
- isDone at end-of-track still tears down from handleFrame's guard.
- Signed B&B commit.

## Stage 3 — key routing: the slide obeys INPUT LAW like every slide

Remove the mediaSlideKey special layer and mediaSlideOpenAnywhere from
keyboard.zig; route keys through the deck's normal focused-slide path the
way overview does (overview keys: keyboard.zig routes when
deck.overview_slide_open — same shape for media). Ctrl+Q special-case dies
unless the normal path already covers it — if it does not, say so in the
commit message and keep the smallest possible guard.

Verification bar:
- zig build CLEAN (Debug + ReleaseSafe).
- Trace: with slide open — ↑↓=focus, ←→=move, Enter=apply/play, Esc=back.
  Unconsumed keys fall through. NO swallowed keys, no held Enter.
- Signed B&B commit.

## Stage 4 — the cut: media_slide.zig's sentinel machine dies

The slide stops being a special per-output scene tree managed by
mediaSlideOpen/Close/Refresh in server.zig and becomes a slide hosted by
the deck the way overview_slide is: deck owns open/closed state and slot;
render produces a buffer on demand; frame callbacks drive everything.
Delete: mediaSlideOpen/mediaSlideClose/mediaSlideRefresh/server-side
sentinel wiring, mediaSlideOpenAnywhere remnants, slidedeck.zig
openMediaSlide/closeMediaSlide special casing (fold into the normal
slide/sentinel mechanism overview uses). media_slide.zig may survive as a
thin render helper (like overview_slide.zig) or fold into media.zig —
executor's call, stated in the commit message.
The vsync pump in handleFrame stays but its guards read deck state, not
scene-tree presence.

Verification bar:
- zig build CLEAN (Debug + ReleaseSafe), zero warnings.
- grep: no mediaSlideOpenAnywhere, no play_timer anywhere in src/.
- Full user-path trace in commit message: open/browse/play/fullscreen/
  exit-fullscreen/close/reopen/quit — every step named.
- Signed B&B commit.

## Stage 5 — host verification + deploy (orchestrator)

- Cold-cache build both modes, record sha256.
- Deploy to /usr/local/bin. Barticus restarts, runs the full trace live.
- Only after Barticus' verdict: merge media-collapse → main (or rebase —
  orchestrator's call at the time), note VM-sync debt in HANDOFF.

## NOT this card

- Pushing to any remote. VM deploy/sync (notes only). kmedia repo changes.
  ksound/ksound-cork interaction. Karaoke/lyrics modes from playback.md
  (later card). Any unrelated compositor/widget edits. Upstream issues/PRs.
- Re-introducing play_timer or any compositor-level media timer. Advance is
  vsync-driven; that is settled ground.

## Verification bar (every stage)

Cold-cache build clean (Debug + ReleaseSafe), signed B&B commits, deviations
flagged in the stage report with reasons. Orchestrator re-verifies each
stage independently (read the diff, rebuild, trace the repro) before the
next stage is dispatched.
