# KidulWM Handoff

Updated 2026-07-24. Source of truth for resuming current work.

## Current state

| Item | Value |
|------|-------|
| Branch | `clean-corners-02251c9` |
| Head | `5d6c735` |
| Work VM | `fresh-one` (kidul@127.0.0.1:2260) |
| Service log | `/tmp/kidulwm-service.log` |

## What works

- Media card opens via `Mod4+m` or `kidulwm-control media_card_toggle`.
- Slider is right-aligned inside the card; letters are centered in the scroller channel, size-tapered toward the focused letter.
- Letters hide unless the slider is hovered or keyboard-focused.
- Cards fully capture keyboard while open (no key events leak to clients).
- Arrow navigation routes: Up/Down/Left/Right move between category/search/result/slider.
- Result grid uses `selected_result` and shows a gold border highlight.
- Real file scanning runs for `/home/kidul/{Music,Movies,Pictures}` (hard-coded for VM testing).
- `kidulwm-control media_play <path>` starts mpv. Playback confirmed with `/home/kidul/Movies/S03E02.mkv`.

## What is broken / needs finishing

1. **In-card keyboard movement has no visible effect**
   - The key handler is called and `selected_result` updates in the log.
   - Likely causes: highlight not visible against art, category switches away from a populated grid, 1-item categories blocking movement, or the requestUpdate path not redrawing the card.
2. **Media scanner only logs Music:9 on first open; Movies/Pictures counts unverified**
   - Hard-coded `/home/kidul` paths may not be desired for non-VM installs.
3. **Card opening focused on search makes arrow-down land in result grid**
   - This is intentional but may confuse; Barticus may want category row focused first.
4. **Play command launches mpv with `--no-video --force-window=no`**, i.e. audio-only
   - For movie playback it needs a video window or compositor-level mpv integration.
5. **Now-playing bottom bar / Disney-style transport controls** are not implemented.

## How to resume

1. `cd /home/dad/dev/KidulWM`
2. `git status` should be clean at `5d6c735`.
3. `zig build`
4. Deploy to `fresh-one`:
   - `scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm zig-out/bin/kidulwm-control kidul@127.0.0.1:/tmp/`
   - `ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1`
   - `sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm /tmp/kidulwm-control /usr/bin/ && sudo systemctl start kidulwm`
5. Toggle card and test: `kidulwm-control media_card_toggle`

## Relevant files

- `src/ui/media.zig` — media card render, focus state, scanning, mpv IPC, A-Z slider.
- `src/ui/tray.zig` — card ownership, keyboard/pointer routing, `handleMediaCardKey`/`handleMediaCardClick`.
- `src/input/keyboard.zig` — global key interception while any card is open.
- `src/ipc/message.zig`, `src/kidulwm-control.zig` — IPC commands including `media_play`.

## Notes

- Keep cards fully keyboard-navigable (TV/remote constraint).
- All visual state must be clearly visible against the dark-glass card.
