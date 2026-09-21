# TASKCARD 2 — tray-slide stage 2: DEMOLITION (tray.zig dies)

Repo: /home/dad/dev/KidulWM  Branch: tray-slide (ALREADY CHECKED OUT — do not switch)
Git identity must be: B&B <bnb@ratukidultech.com>, signed commits (GPG key is
configured repo-wide; verify `git config user.name` before first commit).
You are coderBob, a Zig/wlroots specialist working on KidulWM (Zig, wlroots 0.20).

## Reading list (read BEFORE writing code)

1. docs/log/tray-slide-demolition-spec.md — THE LAW. Amendments A1–A7 win
   every conflict. Hard NOs apply (no pointer hit-testing on the tray slide,
   do not touch spyglass.zig, no Barry port).
2. HANDOFF.md top addendum (Sep 16, stage 1) — what stage 1 built.
3. src/ui/tray_slide.zig — the stage-1 home slide (compositor-owned, sentinel
   at before_first, CFC placeholder text). It EXISTS. Do not rewrite it;
   extend it only where a severed feed needs a minimal home (see §3).
4. src/core/slidedeck.zig — sentinel pattern (home_slide_open, before_first).
5. src/server.zig — 102 `tray` touchpoints. Each is DELETE or REDIRECT.
6. src/input/keyboard.zig :191-222 tray capture block, :240-259 repoint path
   from stage 1.
7. src/ipc/message.zig :19-23, :69-73 and src/kidulwm-control.zig :72-76 —
   IPC tray tags.

## Confirmed recon (build on this, do not redo it)

- Stage 1 is committed (c083b95 + follow-ups). Keybinds tray_toggle (Mod4+t)
  and media_card_toggle (Mod4+m) ALREADY repoint to homeSlideFocusOrSpawn —
  see keyboard.zig:240ff. Verify, don't redo.
- `ui.Tray.init` at server.zig ~:862 still runs — the overlay tray is alive
  and wired. Killing it is THIS stage.
- Notification ingress lives at server.zig:582/:651/:655
  (`self.tray.notificationAdd`, `self.tray.notifications.clear`). These are
  the feed the home slide must NOT lose.
- style.zig tokens `tray_text_color` / `tray_bg_color` are used OUTSIDE
  tray.zig (ui/notifications.zig:590, render/curtain.zig:290) — KEEP those
  tokens; only delete tray-exclusive theme/style entries if truly unreferenced
  after demolition. grep before deleting any token.
- core/animation.zig has a `tray` Preset used as default (:104
  `preset = &presets.tray`). Do NOT delete the preset if anything still
  defaults to it; check references first. Renaming is out of scope.
- core/kmedia.zig:133/:350 and ui/media.zig comments MENTION tray.zig —
  comments only; update wording only if it becomes actively wrong, else leave.
- There are pre-existing uncommitted changes in the repo? NO — tree was clean
  at taskcard writing. If you find dirty files at start, STOP and report; do
  not commit anything pre-existing.

## What to build (stage 2 ONLY — demolition)

1. DELETE src/ui/tray.zig (4323 lines) and the `ui.Tray` instance + init at
   server.zig ~:862. Every one of the 102 server.zig touchpoints is either
   deleted (z-dance, overlay raise/lower, host wiring, card plumbing) or
   redirected to the home slide.
2. keyboard.zig: DELETE the tray capture block at :191-222 (calendar/weather/
   files/media card key routing + tray isOpen selectPrev/Next/activate).
   tray_select_next/prev/activate actions die with it (remove from
   config/keybinds.zig enum + :292 parser). tray_toggle survives ONLY as the
   already-repointed focus-home-slide action.
3. IPC: DELETE tray_select_next/prev/activate/tray_toggle_card from
   ipc/message.zig (both enum sites) and kidulwm-control.zig :73-76.
   tray_toggle IPC → redirect to the same homeSlideFocusOrSpawn path (remote
   depends on it; A6).
4. Notification feed REDIRECT (the one real wiring job):
   - server.zig:582/:651/:655 currently call tray.notificationAdd /
     tray.notifications.clear. Redirect these to a minimal notification store
     owned by the home slide path (e.g. a small list on Server or in
     tray_slide.zig, whatever is least invasive — your call, keep it simple:
     title/body/source strings, append + clear).
   - ui/notifications.zig popover: if it is independent of tray.zig, leave it;
     if it depends on tray state, cut the dependency. The spec wants the
     notification FEED as a CFC section eventually, but stage 2 requires only
     that ingress doesn't crash and data isn't silently lost.
5. tray_slide.zig CFC sections: replace the "NOTIFICATIONS" placeholder line
   with the real notification feed (last N entries, gold CFC text, centered
   per existing style). MEDIA/WEATHER/SIGNALS stay placeholders — real feeds
   are a LATER stage, out of scope here.
6. weather/media card toggles that routed into tray cards
   (weather_toggle_card etc.) — follow the stage-1 pattern: redirect to
   homeSlideFocusOrSpawn or delete if redundant. Mod4+m already done.
7. DO NOT: touch spyglass.zig; touch overview_slide.zig; port Barry; add
   pointer hit-testing to the home slide; implement A4 fullscreen dwell;
   implement A5 boot ladder; delete style tokens still in use; rename
   animation presets.

## Verification gate (ALL must pass before you return)

1. `zig fmt` on every file you touched.
2. `zig build` clean.
3. `zig build test` clean.
4. `zig build -Doptimize=ReleaseSafe` clean.
5. `grep -rn "ui/tray.zig\|@import(\"ui/tray" src/` returns NOTHING.
6. `grep -c "tray" src/server.zig` — only legitimate home-slide references
   (tray_slide) or none; report the count.
7. `bash scripts/nested-smoke.sh` PASSES. NOTE: a pre-existing
   'Aborted (core dumped)' AFTER the accepted IPC quit in smoke was present
   BEFORE this work — if you see exactly that after a pass, it's not yours.
8. Report `git diff --stat` summary.

## Output rules

Return <= 3000 chars. Write all code to disk. Give: files changed/deleted,
the grep counts from the gate, smoke result, one-paragraph summary of any
touchpoint you redirected instead of deleted and why. Do NOT paste file
contents. Do NOT commit — bobDotrix reviews, builds, and commits signed.
