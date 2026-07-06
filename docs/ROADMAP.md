# KidulWM Build Roadmap

Maintained by the orchestrator. Check this file after restoring a session.

## Milestones

| # | Milestone | Status | Notes |
|---|-----------|--------|-------|
| 1 | Boot proof (Zig process, Wayland socket, no-backend IPC) | Done | `KIDULWM_NO_BACKEND=1 ./zig-out/bin/kidulwm` |
| 2 | Surface proof (display one XDG client, pointer/keyboard map) | In progress | Seat/input skeleton done; real client smoke test in flight |
| 3 | Layout proof (8%-94%-8% + gaps + side fade) | In progress | Geometry engine + vertical split implemented |
| 4 | Chamfer proof | Not started | SDF shader for content/border/shadow alignment |
| 5 | Input proof (edge gestures / floating button focus) | Not started | Basic click-to-focus implemented |
| 6 | Settings tray proof | Not started | GTK4 tray IPC controls layout/gaps/colours |
| 7 | Widget proof | Not started | Layer-shell panel + SDK example |
| 8 | Remote proof | Not started | QUIC chrome-sync → single-window tile diff |
| 9 | Daily-driver alpha | Not started | Replace Niri for one workflow |

## Recently Completed

- Real vertical/horizontal split geometry in `src/core/layout.zig`.
- Minimal `wlr.Seat` (`seat0`), pointer/keyboard skeleton.
- Seat capability updates when devices are hot-plugged.
- Click-to-focus via `wlr_scene_node_at` hit-testing.
- Safe focus-on-layout with empty-window guard.
- `zig build test` step + layout geometry tests.
- IPC smoke test script `scripts/test-splits.py`.

## In Flight

- Move `applyLayout()` from IPC thread to Wayland event loop.
- Add `quit` IPC command for clean shutdown.
- Support predictable nested Wayland socket (`KIDULWM_WAYLAND_DISPLAY`).
- Run first real-client smoke test under `WLR_BACKENDS=wayland`.

## Next Up

1. Implement `get_layout` IPC response that publishes live state so GTK4 tray can render.
2. Add keyboard shortcut / edge-zone commands for `FocusNext`/`FocusPrev`.
3. Smoke-test a real GTK4 settings tray / layer-shell panel.
4. Chamfered-corner SDF shader prototype. Border thickness/colours must ultimately consume `src/core/style.zig` as the single source of truth.
5. Widget protocol document + SDK example.
6. Remote-desktop protocol/schema phase.

## Developer Notes

- `zig build` — full compositor build.
- `zig build test` — layout geometry tests only.
- `KIDULWM_NO_BACKEND=1` — safe dev mode while Niri is running.
- Nested real-client test: `WLR_BACKENDS=wayland KIDULWM_WAYLAND_DISPLAY=kidulwm-nested ./zig-out/bin/kidulwm`.
- IPC control socket: `$XDG_RUNTIME_DIR/kidulwm-control.sock`.

## Critical Constraints

- Niri/Smithay code is reference only; KidulWM is Zig + wlroots + GTK4 widgets.
- Do not call wlroots functions from the IPC thread; route through the event loop.
- All risky compositor experiments use nested/headless backends first.
