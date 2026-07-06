# KidulWM Session Recap / Standing Note

Last updated: 2026-07-06

## Current State

- KidulWM is a **from-scratch Wayland compositor in Zig**, on top of `wlroots` 0.20 via `zig-wlroots`.
- GTK4 will handle widgets/animations/settings tray.
- Niri is **UX reference only**; no Niri/Smithay code reuse.
- Remote desktop is a **first-class subsystem**; both endpoints can share layout/chrome to reduce bandwidth.

## Latest Changes (this session)

- Branch `pre-comms-dial`, last commit `ee0048a` — split left/right/top/bottom IPC commands verified over Unix socket.
- coderBob-Fable 5 delivered real vertical split geometry and a `wlr.Seat` + pointer/keyboard skeleton.
- Fixed Zig 0.16 timestamp mismatch (`std.time.milliTimestamp` → `clock_gettime`) in `src/input/pointer.zig`.
- `zig build` passes and the no-backend dev binary responds to `ping`/`split_*` IPC tests.

## Files of Note

- `src/core/layout.zig` — `Orientation`, three-column horizontal + top/bottom vertical bands.
- `src/server.zig` — `wlr.Seat`, input managers, `applyLayout` with focus.
- `src/window.zig` — `Window.focus(seat)` helper.
- `src/input.zig` — `InputManager` attaches keyboards/pointers to seat.
- `src/input/pointer.zig` — pointer event forwarding skeleton.
- `src/input/keyboard.zig` — keyboard event forwarding skeleton.
- `scripts/test-splits.py` — smoke-tests the IPC split commands.

## Running the Dev Binary

```bash
cd /home/dad/dev/KidulWM
zig build
KIDULWM_NO_BACKEND=1 timeout 10 ./zig-out/bin/kidulwm
# In another terminal:
python3 scripts/test-splits.py
```

The `KIDULWM_NO_BACKEND` flag is required while another Wayland compositor is running; it starts the IPC/display loop without calling `wlr_backend_start()`.

## Key Decisions

- wlroots backend; replace subsystems later if needed.
- Two-model workflow: orchestrator stays small, Fable 5 handles deep tasks, ≤4000-char output, file-on-disk deliverables.
- IPC control plane: Unix socket at `$XDG_RUNTIME_DIR/kidulwm-control.sock`.
- No-backend dev mode for safe IPC/layout iteration.

## Open Work

1. Wire pointer motion to actual cursor focus / window hit-testing.
2. Add seat capability updates when devices are added/removed.
3. Implement real `get_layout` IPC response so GTK4 tray can render live state.
4. Run a real-client smoke test (TTY or `WLR_BACKENDS=wayland`).
5. Continue chamfered-corner renderer and settings-tray integration.

## Recovery Notes

If session is restored, read this file, `docs/AGENTS.md`, and run `git log --oneline -5`. Then run `zig build` before editing.
