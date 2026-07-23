# KidulWM Handoff

Updated 2026-07-23. Source of truth for resuming current work.

## Current state

| Item | Value |
|---|---|---|
| Branch | `clean-corners-02251c9` |
| Head | `ed9a6f2` |
| Last stable | `847d731` (`media card: search bar, keyboard/pointer focus, black-glass controls`) |
| Work VM | `fresh-one` |
| SSH port | `2260` |

## Current focus

Media widget is now a **search-first media finder card** in the bottom-right:
- Top search bar, category pills (movies/music/pictures), 5-column portrait grid.
- Focused result shows a zoomed overlay tile.
- Vertical slider scroller on the right, locked to the right edge.
- Keyboard nav: category/search/grid focus, Up/Down/Left/Right move selection, Enter/Space play.
- mpv external-process backend; `MediaWidget.play(path)` starts playback.
- `Mod4+m` toggles the media card. IPC `media_card_toggle` exists.

Outstanding from Barticus's 2026-07-23 direction:
1. Right-hand "signature" alphabet-letter scroller for jumping to media by first letter.
2. Wire actual library scan instead of placeholder/sample data.
3. When media starts, show a small now-playing bottom bar with scrubber + tiny controls (Disney style: back button prominent, settings on right).
4. mpv attribution before release.

## How to resume

1. `cd /home/dad/dev/KidulWM`
2. `git status` — should be clean after `ed9a6f2`.
3. `zig build`
4. Deploy to `fresh-one`:
   - `scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm zig-out/bin/kidulwm-control kidul@127.0.0.1:/tmp/`
   - `ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1`
   - `sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm /tmp/kidulwm-control /usr/bin/ && sudo systemctl start kidulwm`

## Relevant files

- `src/ui/media.zig` — media card renderer, focus state, mpv IPC.
- `src/ui/tray.zig` — media card ownership, pointer/keyboard routing.
- `src/ipc/message.zig`, `src/kidulwm-control.zig`, `src/input/keyboard.zig`, `src/config/keybinds.zig` — `media_card_toggle` wiring.
- `docs/log/2026-07-22-media-player-constraints.md` — size/position rules.

## Notes

- `src/ui/media.zig` currently uses `getLibrary(self.category)`/`sample_library`; real file scanning needs wiring.
- Placeholder tile art uses colored blocks; real artwork extraction not yet implemented.
- All cards must remain arrow-key + Enter + Esc navigable (TV/remote constraint).
