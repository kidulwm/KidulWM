# KidulWM Session Recap / Standing Note

Last updated: 2026-07-06

## Current State

- KidulWM is a **from-scratch Wayland compositor in Zig**, on top of `wlroots` 0.20 via `zig-wlroots`.
- GTK4 will handle widgets/animations/settings tray.
- Niri is **UX reference only**; no Niri/Smithay code reuse.
- Remote desktop is a **first-class subsystem**; both endpoints can share layout/chrome to reduce bandwidth.

## Latest Changes (this session)

- Installed Zig 0.16.0, wlroots0.20, wayland-protocols, system deps.
- Created buildable skeleton; committed as `e324e95`.
- Added docs:
  - `DESIGN-INPUTS.md` — requirements incl. 8%-94%-8% layout, gaps, chamfers, GTK4 tray, dev widgets.
  - `WARGAME-ARCH.md` — architecture decisions and wargaming.
  - `WIDGET-PROTOCOL.md` — widget IPC spec.
  - `REMOTE-DESKTOP.md` — KidulWM-aware remote desktop strategy.
  - `AGENTS.md` — two-model agent strategy (kimi-k2.7-code + coderBob-Fable 5).
  - `RECAP.md` — this file.
- Started IPC module under `src/ipc/`; delegated Zig 0.16 API fixes to coderBob-Fable 5.

## Key Decisions

- wlroots backend; replace subsystems later if needed.
- Two-model workflow: orchestrator stays small, Fable 5 handles deep tasks, ≤4000-char output, file-on-disk deliverables.

## Active Work

- [in progress] `src/ipc/control.zig` — local control socket for widgets and settings tray.
- [pending] `src/core/layout.zig` — output/column/window model and 8%-94%-8% split.

## Useful Commands

```bash
cd /home/dad/dev/KidulWM
zig build
zig build run
git diff HEAD --stat
```

## Recovery Notes

If session is restored, read this file, `docs/AGENTS.md`, and do `git log --oneline -5`. Then run `zig build` before editing.
