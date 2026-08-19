# SlideDeck Overview + Parked Slides (wargame)

> **For Hermes:** Use subagent-driven-development discipline. Implement task-by-task, build after each task, deploy to fresh-one, verify with Barticus between tasks. No visual polish until the state machine is proven.

**Goal:** Two features sharing one mechanism: (a) an end-of-row SlideDeck View showing every slide as a mini place card, click-to-focus; (b) a per-slide "parked" flag (Ctrl+B) that keeps the client alive but invisible in normal navigation, visible in the overview.

**Architecture:** `slidedeck.zig` gains a `view_mode: enum { normal, overview }` and `Slide.parked: bool`. Overview is a mode, not a sentinel slide — `deck.slides` stays a clean list of real windows. When `.overview`, `targetForSlide` returns grid positions (minis) instead of row positions. Parked slides stay in `deck.slides` with `parked=true`; normal layout skips them entirely, overview includes them in a dimmer row/section. No transparency/animation/place-card styling in pass one — plain rectangles and positions only.

**Tech Stack:** Zig, wlroots 0.20 scene graph, existing `Window.setLayoutTarget` / `startTransition` machinery.

**Prerequisites:** close-window crash fix (`a62efa0`) must bake overnight with normal use before starting. If any SIGABRT appears in `journalctl -u kidulwm` before this work begins, STOP and fix that first.

---

## PIVOT RULING (2026-08-19 ~23:30, Barticus): overview = end-of-row sentinel slide, NOT a lens mode

Two days of lens debugging (deck identity, recency inversion, ring coordinate
space, per-output ownership) proved the parallel-universe mode fights the
compositor at every layer. New shape:

- The overview is a real deck entry at the end (a compositor-owned
  "place-card grid" slide), rendered like media-card placeholders: ONE
  Cairo-drawn object with live minis composited inside.
- Mod4+Tab = focus the overview slide (occupies the existing empty slot).
- Click a tile = focus that slide (existing pointer/focus paths).
- Esc/Mod4+Tab = return to the slide you came from.
- Parked minis on the bottom row of the card.
- Ring/swallow/cursor apparatus DELETED. Grid math + recency walk +
  mini surface-scaling survive (pure functions + window.zig paths).

Implementation order: (1) deck gains `overview_slide` sentinel at the end,
(2) compositor renders the card grid into it, (3) keybind routes,
(4) click-through, (5) delete the lens machinery.

---

## Open decisions (resolve BEFORE Task 1)

RULED 2026-08-19 ~19:40 by Barticus:

1. **Overview keybind → Mod4+Tab.** Lens, not focus change — Alt+Tab muscle memory, WM-owned.
2. **Ctrl+B with one slide → refuse with a log line.** Empty-slot-on-purpose is a separate feature.
3. **Unpark position → old index, clamped to slides.len.** "Where I left it" mental model.
4. **Overview scope → per-output.** Matches existing deck ownership.
5. **Direct parked access → nothing in pass one.** Overview is the only door.
6. **Mini-render source → live scene buffer.** Nodes already exist; reposition + setDestSize. Freeze-on-park deferred to pass two if motion distracts.

---

## State machine

```
view_mode: .normal | .overview      (per deck)
slide.parked: bool                  (per slide)

Transitions:
  normal --[Mod4+grave]--> overview          (any slides present)
  normal --[Ctrl+B]--> normal                (focused slide becomes parked, focus moves to next unparked)
  overview --[Mod4+grave | Esc]--> normal    (return to previously focused)
  overview --[click mini | Enter]--> normal  (focus that slide; if parked, unpark first)
  overview --[Ctrl+B on mini]--> overview    (toggle parked on that mini, stay in overview)

Invariants:
  - deck.slides.len is ALWAYS the real window count (parked included)
  - deck.focused_index always points at an UNPARKED slide in normal mode
  - If all slides become parked, forced transition to empty-slot state (existing)
  - view_mode == .overview does NOT change focused_index — it's a lens, not a focus change
```

---

## Task 1: `parked` flag + Ctrl+B keybind (normal mode only)

**Objective:** Park/unpark mechanics work in normal mode. No overview yet. Parked slides render as zero-width (fully hidden, no peek sliver).

**Files:**
- Modify: `src/core/slidedeck.zig` — add `parked: bool = false` to `Slide`; add `parkFocused()`, `unparkIndex()`, `nextUnparked(from:)`, `unparkedCount()` helpers; `targetForSlide` skips parked slides in horizontal/vertical target math (they get x=-width, zero-width rect, scene_tree disabled).
- Modify: `src/input/keybinds.zig` — add `park_toggle` action.
- Modify: `src/server.zig` — wire `park_toggle` to `deck.parkFocused()` + `requestLayout()`.
- Modify: `config/keybinds.conf` — add `Ctrl+b = park_toggle` line (commented in default until proven).
- Test: `src/core/slidedeck.zig` test block.

**Steps:**
1. Add `parked` field and helpers. Unit test: `parkFocused` on a 3-slide deck marks the right slide, focus moves to next unparked.
2. Update `targetForSlide` to treat parked slides as off-screen zero-width. Unit test: parked slide at index 1 of 3 → `targetForSlide(1)` returns zero-width rect, others unchanged relative to new focus.
3. Wire keybind. Build. Deploy.
4. Manual test on fresh-one: open 3 ghosttys, Ctrl+B on middle one, verify it's gone from view, other two still navigate normally. Ctrl+B does nothing while focused slide is the only one.

**Verification:**
- `zig build test` passes new slidedeck tests.
- `kidulwm-control get_windows` still lists parked windows (they're alive).
- `journalctl -u kidulwm` shows no asserts.
- Commit: `feat: slide parking mechanics (Ctrl+B), no UI yet`.

---

## Task 2: Overview mode — lens switch, grid positions

**Objective:** `Mod4+grave` toggles `view_mode`. In overview, `targetForSlide` returns mini grid positions for ALL slides (parked included, in a separate bottom row).

**Files:**
- Modify: `src/core/slidedeck.zig` — add `view_mode` field, `overviewTargetForSlide(idx)` returning a grid rect (e.g., 4 columns, slide minis at 25% scale), `enterOverview()`, `exitOverview()`.
- Modify: `src/server.zig` — keybind wiring; `applyLayout` branches on `view_mode` to call the right target fn; parked slides get `scene_tree.node.setEnabled(true)` in overview (they're disabled in normal).
- Modify: `src/input/keybinds.zig` — add `overview_toggle` action.
- Test: `src/core/slidedeck.zig` test block.

**Steps:**
1. Add `view_mode` and grid math. Mini size: `target.width / 4` wide, aspect-preserved height, 16px padding between minis. Unit test: 3 unparked + 1 parked → 3 minis in top row, 1 in bottom row.
2. Wire the mode switch in `applyLayout`. Parked slides' scene trees re-enable on overview entry, disable on exit.
3. Wire keybind. Build. Deploy.
4. Manual test: 3 ghosttys + 1 parked, Mod4+grave shows 4 minis in expected layout, Mod4+grave again returns to normal with focus unchanged.

**Verification:**
- Focused index is unchanged across overview toggle (log it).
- Parked mini is visually distinguishable in pass one only by position (bottom row), not styling.
- Commit: `feat: overview mode grid layout (Mod4+grave), no interaction yet`.

---

## Task 3: Overview interaction — click-to-focus, Esc to exit

**Objective:** Minis are clickable; clicking focuses that slide and exits overview. Esc exits without changing focus.

**Files:**
- Modify: `src/server.zig` — `handlePointerMove` / `handlePointerClick` in overview mode hit-tests mini rects; keyboard handler routes Esc and Enter.
- Modify: `src/core/slidedeck.zig` — `miniAtPoint(x, y) ?usize` helper.

**Steps:**
1. `miniAtPoint` with the same grid math as Task 2. Unit test with known rects.
2. Pointer click in overview → if mini hit, set focus to that slide (unpark if parked), exit overview, requestLayout. If empty space, just exit.
3. Esc exits overview. Enter focuses the mini under a virtual "overview cursor" (default: previously focused slide's mini). Pass one: Enter = same as clicking the previously focused mini.
4. Build, deploy, manual test: open 4 windows, park 1, overview, click each mini in turn, verify focus + unpark behavior.

**Verification:**
- Click hit-test matches visual mini position (log both).
- No way to get stuck in overview (Esc always works, even with zero slides).
- Commit: `feat: overview click-to-focus and Esc exit`.

---

## Task 4: Edge cases + hardening

**Objective:** The weird cases behave sanely.

**Cases to handle:**
- Last unparked slide gets parked → forced empty-slot state (existing behavior, verify).
- Parked slide's client exits (kill -9) → `handleToplevelDestroy` already removes from deck; verify no dangling `parked` state or focus index corruption.
- Overview open when a new window maps → overview stays open, new slide appears as a mini at the end of the top row.
- Overview open when focused window closes → overview stays open, minis reflow.
- Rapid Ctrl+B toggles → no layout thrash (layout requests are already coalesced by `requestLayout`).

**Files:**
- Modify: `src/server.zig`, `src/core/slidedeck.zig` as needed.
- Test: add unit tests for each case in slidedeck test block.

**Verification:** each case exercised on fresh-one via SSH script. No asserts, no stuck modes, `get_windows` always consistent.
- Commit: `fix: overview/park edge cases`.

---

## Task 5: Documentation + HANDOFF

**Objective:** Future sessions know what exists.

**Files:**
- Modify: `HANDOFF.md` — new section for overview/park state.
- Modify: `KNOWN_CMDS.md` — new keybinds.
- Modify: kidulwm-development skill — add a pointer section for the state machine.

---

## Explicitly NOT in pass one

- Transparency / glass styling on the overview background
- Place-card rendering (titles, app icons, borders)
- Animations between normal and overview
- Freeze-on-park buffer snapshots
- Parked-slide-specific styling in overview (beyond the bottom-row position)
- Direct park/unpark cycling keybind (Alt+Tab-style)
- Multi-output global overview

These are the "just right" pass, after the mechanics are proven boring.

---

## Test plan summary

1. Unit: `zig build test` — slidedeck park/unpark/grid/hit-test math.
2. Smoke: fresh-one, 4 ghosttys, park 1, overview in/out, click each mini.
3. Stress: 10x park/unpark cycles + overview toggles, no asserts in journal.
4. Hostile: kill -9 on a parked client while overview open — deck stays consistent.
5. Bake: one full day of normal use before any visual pass.
