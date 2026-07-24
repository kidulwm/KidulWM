# KidulWM Handoff

Updated 2026-07-25. Source of truth for resuming current work.

## Current state

| Item | Value |
|------|-------|
| Branch | `clean-corners-02251c9` |
| Head | `ba55267` |
| Work VM | `fresh-one` (kidul@127.0.0.1:2260) |
| Service log | `/tmp/kidulwm-service.log` |
| Shorthands | `Bob` = top-left tray logo ; `Barry` = bottom-left pet |

## What works

- Media card opens via `Mod4+m` or `kidulwm-control media_card_toggle`.
- Cards fully capture keyboard while open (no key events leak to clients).
- Clamped linear pill carousel: opens on Music, Left/Right move without wrapping, ends stop at center.
- Category order: Shop | Movies | Music | Pictures | TV.
- Pills use user-configurable theme border color, focused/selected uses "Bobs Candy Shading" (subtle alpha fill + soft stroke).
- Focused pill matches searchbar height; outer pills smaller/dimmer.
- Search bar supports text entry, caret movement, Backspace, Escape clears.
- Return in search jumps to first result matching typed prefix.
- Secret 2-letter category easter egg on Return: `MU` `MO` `PI` `SH` `TV` instantly switch categories.
- Result grid uses `selected_result` with gold border highlight and dark 3D shadow lift.
- Placeholder grid evenly distributed across full card width; edge gaps equal inter-tile gaps.
- Plain scrollbar slider (track + knob) on the right; Up/Down scroll one row; Page_Up/Page_Down page through list.
- Slider slides in and out smoothly and never overlaps placeholders.
- Empty category result grid is skipped in Tab/Down navigation.
- Tile art is cached per path; category switching no longer re-loads all PNGs.
- Card open and slider reveal are near-instant.
- Subcategory pop-out row shell: Return on a category pill opens a second pill row; Left/Right/Up/Return/click work. Lists are placeholder data.
- Real file scanning runs for `/home/kidul/{Music,Movies,Pictures}` (hard-coded for VM testing).
- `kidulwm-control media_play <path>` starts mpv. Playback confirmed with `/home/kidul/Movies/S03E02.mkv`.

## What still needs finishing

1. **Subcategory content is placeholder only.**
   - Fill `MediaWidget.subcategoryNames()` in `src/ui/media.zig` with real genres/tags and wire to backend filtering.
2. **Media scanner only logs Music:9 on first open; Movies/Pictures counts unverified.**
   - Hard-coded `/home/kidul` paths may not be desired for non-VM installs.
3. **Play command launches mpv with `--no-video --force-window=no`**, i.e. audio-only.
   - For movie playback it needs a video window or compositor-level mpv integration.
4. **Now-playing bottom bar / Disney-style transport controls** are not implemented.
5. **No mouse cursor theme is loaded** — pointer is invisible/flying blind.
6. **Held arrow key acceleration** for slider scrolling not implemented; currently one row per Wayland repeat event.

## Useful keys while media card is open

| Key | Action |
|-----|--------|
| Left / Right | move main category pill |
| Return (on pill) | open subcategory row |
| Left / Right (subcategory) | move sub-pill |
| Up / Return (subcategory) | close subcategory row |
| Down (subcategory) | focus search |
| Up (search) | focus main category pills |
| Down (search) | focus result grid (or slider if empty) |
| Tab | cycle category → search → result/slider |
| Left (result) | previous tile; wraps to previous row |
| Right (result, last column) | focus slider |
| Up (result top row) | focus search |
| Down (result bottom row) | wrap to top |
| Up / Down (slider) | scroll one row |
| Page Up / Page Down | scroll one page |
| Escape | close card |

## How to resume

1. `cd /home/dad/dev/KidulWM`
2. `git status` should be clean at `ba55267`.
3. `zig build`
4. Deploy to `fresh-one`:
   - `scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm zig-out/bin/kidulwm-control kidul@127.0.0.1:/tmp/`
   - `ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1`
   - `sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm /tmp/kidulwm-control /usr/bin/ && sudo systemctl start kidulwm`
5. Toggle card and test: `kidulwm-control media_card_toggle`

## Relevant files

- `src/ui/media.zig` — media card render, focus state, scanning, mpv IPC, slider, tile cache, subcategory shell.
- `src/ui/tray.zig` — card ownership, keyboard/pointer routing, `handleMediaCardKey`/`handleMediaCardClick`.
- `src/core/animation.zig` — card open/close animation preset.
- `src/input/keyboard.zig` — global key interception while any card is open.
- `src/ipc/message.zig`, `src/kidulwm-control.zig` — IPC commands.

## Notes

- Keep cards fully keyboard-navigable (TV/remote constraint).
- All visual state must be clearly visible against the dark-glass card.
- "Bobs Candy Shading" recipe is saved in the `kidulwm-ui` skill.
- Deployed binary path on live VM is `/usr/bin/kidulwm`.

## Kidul Browser side quest (2026-07-25)

- Project: `kidul-browser` at `/home/dad/dev/kidul-browser`.
- Branch `main`, head `c6a4ad2`.
- Keyboard nav fixed: Tab and arrow keys cycle slider / address bar / favorites.
- Theme switched to muted black-gold candy; borders read from shared `border` / `border_focus` tokens.
- Corner style is configurable (round default) — no hard-coded chamfers.
- Centered top pill slider; default mode is `Isolate`; `Safe` and `Browse` extend to the left.
- Address bar at 1/3 canvas height; favorites below with generous spacing, laid out for 3 future rows.
- Window hints request a 1920×1080 slide (double-d of earlier 1024×768); small configs ignored in code.
- Still deferred: real web engine, tray IPC, Kidul Files, Mullvad top-right slot.
- Next test: relaunch and screenshot to verify slide size and proportions.
