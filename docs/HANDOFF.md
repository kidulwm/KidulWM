# KidulWM Big Build — Handoff

Trigger word: **"KWM Kidul build — next step"**

## Current state

- Branch: `pre-comms-dial`
- Last stable commit: `7afa0c7`
- Build health: `zig build` pass, `zig build test` pass, no-backend IPC pass, `scripts/nested-smoke.sh` pass
- Working directory: `/home/dad/dev/KidulWM`

## Barticus' current priorities

1. **Window matrix performance first**: smooth, fast placement/movement of windows; no window tabbing (browser/terminal apps handle their own tabs).
2. **Dark default chrome**: default compositor background should be the Hermes CLI dark `#222425` to avoid bright flashes during lag or startup.
3. **Plain GTK4 tray**: `scripts/kidul-tray.py` should remain a plain GTK4 toplevel by default. Layer-shell is opt-in only (`KIDUL_TRAY_USE_LAYER=1`) while the compositor's layer-shell dispatch path is unstable.
4. **Chamfer/cut-corner SDF shader** will be refined after the core window path is fast and stable.

## What just landed

- Default compositor background changed to Hermes CLI dark `#222425` (`src/core/style.zig` `color_background` and `src/server.zig` full-output `SceneRect` background).
- `scripts/kidul-tray.py` now defaults to a plain GTK4 toplevel, with layer-shell mode opt-in only via `KIDUL_TRAY_USE_LAYER=1`.
- GTK4 tray includes minimal dark CSS to match the `#222425` chrome.
- Core window matrix performance: `src/core/layout.zig` now caches a long-lived `LayoutModel`, and `src/server.zig` reuses it in `applyLayout()`. Per-layout-tick heap allocation eliminated; geometry updates are allocation-free after the first output sync.
- Event-driven layout: the 8 ms timer poll in `src/server.zig` has been replaced with a self-pipe + `wl.EventLoop.addFd` wakeup. Layout now runs immediately when any thread calls `requestLayout()`, with duplicate requests coalesced.

## What just landed (commit `7afa0c7`)

- Fixed nested/headless backend crash by heap-allocating `Server` so intrusive `wl.list`/`wl.Listener` link pointers do not dangle after struct return-by-value.
- Added `wl.Listener(...).link.init()` before every `signal.add()` (`zig-wayland` `Listener.init()` only sets `notify`, leaving `link` undefined).
- Armed every `wl.EventLoop.addTimer()` source with `timerUpdate()` so timers actually fire in a live backend.
- Implemented real `get_layout` IPC response returning:
  ```json
  {"ok":true,"layout":{"orientation":"...","gap":8,"left_peek":0.5,"focus":0.5,"right_peek":0,"focused_window":1,"window_count":0}}
  ```

## Design rules in force

- Border thickness, colours, chamfer style/depth, glow values live exclusively in `src/core/style.zig`.
- All rendering paths (shaders, focus rings, widgets, settings tray) read from that module.
- `docs/ROADMAP.md` already references this constraint.

## Next priorities

1. **Core window-placing/movement performance**  
   Cached `LayoutModel` and event-driven layout are landed. Next micro-optimizations: avoid repeated `windows.length()` calls, batch `toplevel.setSize()` where possible, and profile real window movement under `WLR_BACKENDS=wayland` nested mode once it is stable.

2. **GTK4 settings tray protocol skeleton**  
   Skeleton is in place (`src/tray.zig`, `scripts/kidul-tray.py`). Plain GTK4 mode works; layer-shell path is opt-in while the compositor's layer-shell dispatch crash is debugged.

3. **Wire style.zig tokens into remaining layout/rendering paths**  
   Replace any remaining hard-coded gap/border/colour values throughout `src` with imports from `style.zig`.

## How to resume

1. `cd /home/dad/dev/KidulWM`
2. `git status` — confirm on `pre-comms-dial`, no stray uncommitted work.
3. `zig build && zig build test`
4. Run `bash scripts/nested-smoke.sh` to verify the baseline.
5. Pick the next priority and keep building.

## Notes

- No-backend dev mode still works via `KIDULWM_NO_BACKEND=1`.
- Nested/headless real-client smoke test works via `WLR_BACKENDS=headless` fallback in `scripts/nested-smoke.sh`.
- Real `WLR_BACKENDS=wayland` nested path remains flaky inside Niri and is intentionally left as a later target.
- Barticus prefers terse, direct replies during fast UI iteration and wants risky work to have fallback branches; pause on demand is fine.
