# TASKCARD — media slide: location-aware toggle + one audio-clocked playloop

Card: 2026-09-07 · Author: bobDotrix (orchestrator) · Executor: coderBob (attended, stage-per-dispatch)
Repo: /home/dad/dev/KidulWM · B&B identity (pre-commit hook armed — non-B&B commits refuse).
Scope: HOST ONLY. We are ahead of the VM "main commits" on purpose. Everything
lands on the host and is NOTEd so the VM can be brought up to the same state
later. Do NOT push. Do NOT touch the VM.

## Reading list (READ FIRST, in order)

1. docs/law/media-slide-location.md  (the new law — this card implements it)
2. docs/law/daily-driver.md
3. HANDOFF.md (current state)
4. src/server.zig:
   - mediaSlideToggle()  ~line 1509   (THE BUG)
   - mediaSlideOpen()    ~line 1546
   - mediaSlideClose()   ~line 1693
   - mediaSlideOpenAnywhere() ~line 1719 (the find-open iterator — reuse this pattern)
   - mediaSlideKey()     ~line 1742   (already scans outputs for the open slide)
   - currentDeck()       ~line 1273
   - focusFollowsCursor()~line 2176
   - the player tick pump in Output frame handler ~line 227-276 (Stage 2)
5. src/core/slidedeck.zig: openMediaSlide/closeMediaSlide/mediaSlideTarget ~line 354-408

## Ground truth (verified by orchestrator 2026-09-07, do NOT re-litigate)

- The media slide opens on the KEYBOARD-FOCUS output (currentDeck), but the
  cursor is the focus the user can see. Cursor moves re-point focused_output
  via focusFollowsCursor on every pointer motion (pointer.zig:91).
- Symptom 1 (wrong output / "only opens on Kogan"): boot parks cursor+focus on
  Kogan; open lands there; moving cursor to laptop and toggling opens a SECOND
  slide on the laptop because the reconcile only inspects the laptop output.
- Symptom 2 (stuck open): close resolves to the focus deck, so it never reaches
  a slide left open on the other output. That slide is orphaned.
- VSYNC IS EXONERATED. Standalone kmedia runs a poll-timer heartbeat; the
  compositor self-perpetuates its own frame (server.zig:234). The residual
  "vsync-y" stutter is the per-output tick cadence — Stage 2.
- Other slides (overview) are a deck MODE, no per-output sentinel tree, so they
  can't split. Only the media slide has the tree-on-output-A + flag-on-deck-B
  split.

## Stage 1 — Location-aware media slide toggle/close (THE BUG FIX)

Make mediaSlideToggle obey docs/law/media-slide-location.md:

- On toggle: first scan ALL outputs for `media_slide.isOpen()`.
  - If found on output X: close THAT one — mediaSlideClose(X) AND clear the
    media_slide_open flag on X's OWN deck (which may differ from currentDeck()).
    Never reference the focus deck for the close decision.
  - If found nowhere: proceed with open on the current focus deck as today.
- On open: never open if any output already has it open (mediaSlideOpenAnywhere
  guard) — toggle when one is already open means CLOSE it, not open a second.
- The deck flag and the output tree must always be cleared/set on the SAME
  output. Add a brief comment citing the law file.
- Do NOT change mediaSlideOpen/mediaSlideClose internals beyond what's needed;
  the fix is in the toggle's targeting + flag ownership.

Verification bar (Stage 1):
- `zig build` CLEAN (Debug and ReleaseSafe).
- Trace the exact repro in a comment in the commit message: boot→Kogan→open→
  cursor-to-laptop→toggle (must close, not open-a-second)→toggle (opens on
  laptop)→toggle (closes).
- Signed B&B commit, message per repo convention.

## Stage 2 — One audio-clocked playloop; outputs only PRESENT (the stutter)

Goal: the player playloop advance must NOT be married to a single output's
frame callback. mpv shape: ONE playloop on the audio clock; each output just
presents the due frame when its own vsync arrives.

- Read the player tick pump (server.zig ~227-276): today tick() is driven from
  a specific output's frame handler, and re-arms that output's scheduleFrame.
- Refactor so the playloop tick is driven by the AUDIO clock / a single
  compositor-level timer, independent of which output the slide is on. Outputs
  only call the present/blit for the due frame on their own frame; they do not
  own advance.
- Preserve: slideless music tick pump (server.zig:262-276), the LAW no-stills
  reconcile (media_slide.video_buffer != null branch), and the isDone teardown.
- Do NOT regress the "VSYNC SELF-PERPETUATION" fix — if nothing schedules
  frames during steady playback the loop must still run; the change is WHERE
  advance is clocked from, not whether it runs.
- If full audio-clock decoupling is larger than a stage, land the smallest
  correct increment and FLAG the remainder explicitly in the stage report.

Verification bar (Stage 2):
- `zig build` CLEAN (Debug and ReleaseSafe).
- posprobe-style advance check if the repo has one (`zig build posprobe`) or a
  clear statement of how advance-without-render was verified.
- Signed B&B commit.

## Stage 3 — Host build + deploy (orchestrator verifies)

- Cold-cache build both Debug and ReleaseSafe.
- Report zig-out/bin/kidulwm (+ kidulwm-control) sha256 + build time.
- Orchestrator deploys to /usr/local/bin and records hashes. Barticus restarts
  the session to pick it up; fallbacks (niri/limine) are in place.

## NOT this card

- Pushing to any remote. - VM deploy / VM sync (notes only). - Changing the
  standalone kmedia player's already-correct poll-timer heartbeat. - Any
  unrelated compositor/widget/media-widget edits. - Upstream issues/PRs.

## Verification bar (every stage)

Cold-cache build clean, signed B&B commits (hook enforced), deviations flagged
in the stage report with reasons. Self-report is not proof — orchestrator
re-verifies each stage independently (read the diff, rebuild, trace the repro).
