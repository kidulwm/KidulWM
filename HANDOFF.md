# KidulWM Handoff

## Current state

- Branch: `main`
- Last commit: `a0b001b files card: full-featured file manager with click/key routing and shared card frame`
- Working tree: clean
- Build: passing (`zig build -Doptimize=ReleaseSafe`)
- Deployed: `fresh-one` VM via scp/ssh

## Direction change: standalone Kidul Files client

The in-process files card has reached the limits of what an overlay card can do cleanly. The flagship file manager will become a standalone Wayland client (`kidul-files`), launched from the tray, mirroring the architecture of `kidul-browser`.

Goals:
- Own Wayland surface / event loop (no more card overlay)
- GPU-friendly rendering for large directories and smooth scrolling
- Async directory enumeration with caching
- Fast-scroll preview deferral (preview only when scrolling is slow/stable)
- Browser-pill shape for drive/category pills with file-manager colors
- Same KidulWM visual language (dark glass, gold borders, Fantasque Sans Mono)

## Files card GUI (legacy in-process card)

`src/ui/files_card.zig` provides a full-featured Cairo file manager card:
- Two-pane layout: left file list (~55%), right preview pane (~45%).
- Drive pills at top from `/proc/self/mounts`.
- Breadcrumb path bar, folder/file glyphs, dotfile dimming, selected-row highlight.
- Scrollbar when list overflows.
- Click inside the list selects/activates entries; clicks inside the preview pane are consumed.
- Inner panels follow system `corner_style` (round/chamfer/square).
- Outer card uses the shared `card_frame` mat with system border/corners.

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

All cards support `Left` arrow to return to the tray from the card's leftmost focus.

## Build/deploy workflow

```bash
cd /home/dad/dev/KidulWM
zig build -Doptimize=ReleaseSafe

scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm \\
  zig-out/bin/kidulwm zig-out/bin/kidulwm-control \\
  kidul@127.0.0.1:/tmp/

ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \\
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm /tmp/kidulwm-control /usr/bin/ && sudo systemctl start kidulwm'
```
