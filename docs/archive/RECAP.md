# KidulWM Session Recap / Standing Note

Last updated: 2026-07-06

## Current State

- KidulWM is a **from-scratch Wayland compositor in Zig**, on top of `wlroots` 0.20 via `zig-wlroots`.
- GTK4 will handle widgets/animations/settings tray.
- Niri is **UX reference only**; no Niri/Smithay code reuse.
- Remote desktop is a **first-class subsystem**; both endpoints can share layout/chrome to reduce bandwidth.

## Latest Changes (this session)

- Branch `pre-comms-dial`, commit `e22258b` — seat capability updates, click-to-focus via scene hit-test, safe layout focus.
- Prior commits: real vertical split geometry + wlr seat/input skeleton (`2a388a8`), layout geometry tests + `zig build test` step (`8b71aaa`).
- coderBob-Fable 5 is moving `applyLayout()` to the Wayland main thread, adding a `quit` IPC command, supporting a predictable nested Wayland socket, and running the first real-client smoke test.

## Files of Note

- `src/core/layout.zig` — `Orientation`, three-column horizontal + top/bottom vertical bands, geometry tests.
- `src/server.zig` — `wlr.Seat`, input managers, `applyLayout`, `focusAtCursor`, seat focus.
- `src/window.zig` — `Window`, `Window.focus(seat)`, destroy clears focus.
- `src/input.zig` — `InputManager` attaches keyboards/pointers to seat and tracks device counts.
- `src/input/pointer.zig` — pointer event forwarding + click focuses at cursor.
- `src/input/keyboard.zig` — keyboard event forwarding.
- `scripts/test-splits.py` — smoke-tests IPC split/ping commands.

## Running the Dev Binary

```bash
cd /home/dad/dev/KidulWM
zig build
KIDULWM_NO_BACKEND=1 timeout 10 ./zig-out/bin/kidulwm &
python3 scripts/test-splits.py
```

The `KIDULWM_NO_BACKEND` flag is required while another compositor is running; it starts the IPC/display loop without calling `wlr_backend_start()`.

## Running Tests

```bash
zig build test       # layout geometry tests only, no backend/linking
```

## Key Decisions

- wlroots backend; replace subsystems later if needed.
- Two-model workflow: orchestrator stays small, Fable 5 handles deep tasks, ≤4000-char output, file-on-disk deliverables.
- IPC control plane: Unix socket at `$XGD_RUNTIME_DIR/kidulwm-control.sock`.
- `applyLayout()` is being moved to the Wayland event loop to avoid calling wlroots from the IPC thread.

## Open Work

1. coderBob in flight: main-thread applyLayout + quit IPC + nested smoke test.
2. Implement `get_layout` IPC response with live layout geometry.
3. Wire keyboard shortcuts / edge gestures for focus navigation.
4. Continue chamfered-corner renderer and settings-tray integration.

## Recovery Notes

If session is restored, read this file and `docs/AGENTS.md`, run `git log --oneline -5`, then run `zig build` before editing.
