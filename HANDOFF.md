# KidulWM Handoff

## Current state

- Branch: `main`
- Last commit: `a0b001b files card: full-featured file manager with click/key routing and shared card frame`
- Working tree: clean
- Build: passing (`zig build -Doptimize=ReleaseSafe`)
- Deployed: `fresh-one` VM via scp/ssh

## Files card GUI

`src/ui/files_card.zig` now provides a full-featured Cairo file manager card:
- Two-pane layout: left file list (~55%), right preview pane (~45%).
- Drive pills at top from `/proc/self/mounts`.
- Breadcrumb path bar, folder/file glyphs, dotfile dimming, selected-row highlight.
- Scrollbar when list overflows.
- Preview pane shows filename and text-file preview.
- Click inside the list selects/activates entries; clicks inside the preview pane are consumed.
- Inner panels follow system `corner_style` (round/chamfer/square).
- Outer card now uses the shared `card_frame` mat with system border/corners.

`src/ui/tray.zig` wiring:
- `files_card_open` flag and `files.card.open` kept in sync.
- `toggleFilesCard()` opens/closes the card and refreshes state.
- `handleFilesCardClick()` routes clicks to the card.
- `handleFilesCardKey()` maps Up/Down/Return/BackSpace/Escape/Left.
- `backToTray()` closes any card and returns focus to the tray.

Keyboard routing (`src/input/keyboard.zig`):
- Card key block dispatches to the active card.
- Fixed inverted `tray_select_next`/`tray_select_prev` mapping in `handleAction`.

## Back-to-tray behavior

All cards now support `Left` arrow to return to the tray from the card's leftmost focus:
- Calendar, Weather, Files: `Left` → `backToTray()`.
- Media card: `Left` while focused on the category pills → `backToTray()`.

## Known issues / next steps

1. Files card key navigation updated: Up/Down move selection, Right/Return activate, BackSpace goes up, Escape closes. Left now returns to tray when tray is open, or closes the card when tray is closed.
2. Click inside the card should no longer close it (any click inside card bounds is consumed).
3. Card outer border/corners now follow the system `corner_style`; inner panes also follow it.
4. Polish: drive pill interaction, directory history, larger click targets, sorting options, etc.

## Build/deploy workflow

```bash
cd /home/dad/dev/KidulWM
zig build -Doptimize=ReleaseSafe

scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm \
  zig-out/bin/kidulwm zig-out/bin/kidulwm-control \
  kidul@127.0.0.1:/tmp/

ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm /tmp/kidulwm-control /usr/bin/ && sudo systemctl start kidulwm'
```
