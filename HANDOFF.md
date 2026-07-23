# KidulWM Handoff — Dynamic Index

Auto-regenerate friendly. Manually update only the **Current focus** and **Runtime** sections.

## Current state

| Item | Value |
|---|---|
| Branch | `clean-corners-02251c9` |
| Head | `02251c9` |
| Last stable tag | `greatest-yet` (`75872af`) |
| Work VM | `fresh-one` |
| SSH port | `2260` |
| Active skills | `kidulwm-v2` (sub-skills: chrome, layout, debug-vm, input, wayland) |

## Quick links

- `docs/KIDULWM_CHROME_LAYERS.md` — chrome overlay layering lesson.
- `docs/AGENTS.md` — agent strategy pointers.
- `docs/sessions/DumpFile.md` — append-only raw project brain.
- `docs/sessions/` — per-session distilled summaries.
- `docs/log/` — per-feature/milestone notes.
- `KNOWN_CMDS.md` — command reference.
- `docs/log/2026-07-22-media-player-constraints.md` — media widget size/position rules.

## Current focus

- Media widget: bottom-right peek + card with mpv IPC backend.
- Music card renders prev/play/next controls and "now playing" label under the slider.
- mpv installed on `fresh-one`; FLAC playback confirmed.
- Next: dual-purpose search/now-playing line, keyboard-navigable finder overlay, tabs for video/slideshow, spectrum-driven double-helix, mpv attribution.

## How to resume

1. `cd /home/dad/dev/KidulWM`
2. `git status`
3. `zig build`
4. Deploy to `fresh-one`:
   - `scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm zig-out/bin/kidulwm-control kidul@127.0.0.1:/tmp/`
   - `ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1`
   - `sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm /tmp/kidulwm-control /usr/bin/ && sudo systemctl start kidulwm`

## Recent log entries

- `docs/log/2026-07-22-media-player-constraints.md`
- `docs/log/2026-07-15-peek-glass-final.md`
- `docs/log/2026-07-15-skill-split.md`
- `docs/log/2026-07-15-dynamic-handoff.md`

## History

Raw chronological dump: `docs/sessions/DumpFile.md`
