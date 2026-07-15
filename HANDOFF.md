# KidulWM Handoff — Dynamic Index

Auto-regenerate friendly. Manually update only the **Current focus** and **Runtime** sections.

## Current state

| Item | Value |
|---|---|
| Branch | `corner-bg-fix` |
| Head | `6604ee7` |
| Last stable tag | `greatest-yet` (`b6ff45d`) |
| Work VM | `bob-is-a-douche` |
| SSH port | `2228` |
| Active skills | `kidulwm-v2` (sub-skills: chrome, layout, debug-vm, input, wayland) |
| Legacy fallback | `kidulwm-development` (untouched) |

## Quick links

- `docs/KIDULWM_CHROME_LAYERS.md` — chrome overlay layering lesson.
- `docs/AGENTS.md` — agent strategy pointers.
- `docs/sessions/DumpFile.md` — append-only raw project brain.
- `docs/sessions/` — per-session distilled summaries.
- `docs/log/` — per-feature/milestone notes.
- `KNOWN_CMDS.md` — command reference.

## Current focus

- Peek chrome: full dark glass + 2 px `color_border` rim, overlay-tree rendering.
- Granular KidulWM skill split + DumpFile dynamic-handoff refactor.

## How to resume

1. `cd /home/dad/dev/KidulWM`
2. `git status`
3. `zig build`
4. For VM deploy, see `kidulwm-debug-vm` skill or `KNOWN_CMDS.md`.

## Recent log entries

- `docs/log/2026-07-15-peek-glass-final.md`
- `docs/log/2026-07-15-skill-split.md`
- `docs/log/2026-07-15-dynamic-handoff.md`

## History

Raw chronological dump: `docs/sessions/DumpFile.md`
