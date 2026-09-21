# TASKCARD 1 — tray-slide birth (stage 1: the slide renders)

Repo: /home/dad/dev/KidulWM  Branch: tray-slide (ALREADY CHECKED OUT — do not switch)
Git identity must be: B&B <bnb@ratukidultech.com>, signed commits (GPG key is configured repo-wide; verify `git config user.name` before first commit).

## Reading list (read BEFORE writing code)

1. docs/log/tray-slide-demolition-spec.md — THE LAW. Original spec + SESSION-2
   AMENDMENTS A1–A7. A-amendments win every conflict. Read all of it.
2. src/core/slidedeck.zig — SlideDeck; sentinel pattern at :72-78
   (`overview_slide_open`, `empty_slot`), `virtualFocus()` :147, addWindow :160,
   removeWindow :193.
3. src/ui/overview_slide.zig — compositor-owned scene tree shape (32 lines).
4. src/ui/media_slide.zig — "compositor-owned content in a deck slot" variant.
5. src/server.zig around :862 (tray init) — see how the overlay tray was wired;
   the home slide must NOT be wired as an overlay. Also server.zig :2665/:2729
   for updateChrome call pattern.
6. src/config/keybinds.zig (:8, :12, :45, :49) and src/input/keyboard.zig
   (:240-259) — the actions to repoint.
7. docs/law/ media-is-a-slide.md if present — the law this extends.

## Confirmed recon (build on this, do not redo it)

- `Slide` = `{ window_id: u32 }` (slidedeck.zig:43). slides.items holds ONLY
  real client windows — window-count invariants depend on it.
- Overview sentinel: `overview_slide_open: bool` flag + `empty_slot == .after_last`.
  NOT in slides.items.
- 59 `tray` touchpoints in server.zig (measured). Do NOT touch them this stage
  except the keybind path below.
- keyboard.zig:240 tray_toggle → server.tray.toggle(); :256 media_card_toggle →
  server.tray.toggleMediaCard(). Both repoint this stage.
- ui.Tray.init at server.zig:862 stays for now (demolition is stage 2+).

## What to build (stage 1 ONLY)

Amendment summary that governs this stage:
- A1 PROPER SLIDE: real border + background via the stock chrome path. NO
  borderless special. (Transparency is a future alpha constant, not now.)
- A2/A7 HOME SLIDE: compositor-owned, lives at index 0 of a row, AT MOST one
  per row, closable via the standard quit keybind, never auto-respawned.
- A3 no placeholders (nothing to build, just don't add any).

1. NEW FILE src/ui/tray_slide.zig — compositor-owned tray/home slide:
   - Scene tree owned by the compositor (per-output render like overview/media
     slides), content = CFC'd cairo text, centered both axes, sections stacked
     with house gap. v1 content: placeholder sections "MEDIA / WEATHER /
     SIGNALS / NOTIFICATIONS" as styled CFC text lines (real feeds wire in
     later stages — a static centered text card is enough to prove the slot).
   - Theme tokens: bg 0x0a0a0b, gold 0x948e7b (kfiles theme), border via the
     STOCK chrome renderer — this slide must get updateChrome like any other
     (A1). It must walk, peek, park, fullscreen with zero special input code.
2. slidedeck.zig — sentinel slot BEFORE_FIRST mirroring the overview pattern:
   - `home_slide_open: bool` + reuse `empty_slot == .before_first` mechanics,
     `openHomeSlide()/closeHomeSlide()/homeSlideOpen()` mirroring :321-354.
   - Window-count invariants MUST hold: home slide is NOT in slides.items.
   - At most one per row: openHomeSlide is a no-op when already open.
   - Standard quit on the sentinel slot closes it (A7) — wire the quit path
     so quitting while focus is on the home slot calls closeHomeSlide()
     instead of killing a client.
3. Keybinds repoint (keyboard.zig):
   - tray_toggle → "focus the home slide, or spawn it at before_first if this
     row has none" (openHomeSlide + focus jump).
   - media_card_toggle → same target for now (focus/spawn home slide). The
     real media readout section is a later stage.
   - tray_select_next/prev, tray_activate: DELETE the actions from the enum +
   parser + dispatch (redundant with Mod4+j/k per spec). If deletion cascades
   beyond keyboard/keybinds/ipc message tags, flag it in the report instead of
   ripping out half the tree — list every file that references them.
4. zig fmt on touched files.

## NOT this session (hard scope)

- NO demolition of src/ui/tray.zig or the 59 server.zig touchpoints (stage 2+,
  only after the slide renders on a real display).
- NO real widget feeds (weather/media/notifications data) — placeholder CFC
  text only.
- NO fullscreen-plays-ball (A4), NO boot ladder (A5), NO remote pads (A6).
- NO Barry assets. NO pointer hit-testing on the home slide.
- Do NOT touch spyglass.zig (locked & deployed).
- Do NOT touch LICENSE, src/input.zig, src/input/pointer.zig, src/ui/tray.zig —
  there is UNRELATED uncommitted work in the tree (licensing docs + KSD glyph
  paint + input tweaks). Leave the dirty files dirty; commit only YOUR files.
- No VM deploys. Host build only; deploy waits for Barticus.

## Verification bar (all required, report evidence)

1. `zig build` clean (watch: ArrayList is `.empty` + `appendSlice(allocator,…)`
   style; cairo optional pointers need `.?`; no std.math.pi.pi drift).
2. `zig build test` passes.
3. `zig build -Doptimize=ReleaseSafe` clean.
4. `bash scripts/nested-smoke.sh` if it exists and runs headless; report output.
5. Signed commit(s), message prefix "tray-slide:". Report commit ids.

## Deviations

Flag every deviation from this card in the report — never silent. If a design
question is not answered by the spec amendments, STOP and report the question
rather than guessing.
