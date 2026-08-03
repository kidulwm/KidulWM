# KidulWM Handoff

## Current state

- Branch: `main`
- Last commit: `c81e813 kidul-files: text background good!`
- Working tree: `src/ui/files_card.zig` (new), `src/ui/tray.zig` (modified)
- Build: not yet tested with files card wiring

## Files card GUI (in progress)

New module `src/ui/files_card.zig` created:
- `FilesWidget` with `renderCard()` for Cairo-based three-pane file manager.
- Drive pills auto-detected from `/proc/self/mounts`.
- 20/60/20 three-pane layout, focus-follow vertical centering, preview centering.
- Font size 27.

`src/ui/tray.zig` partially wired:
- Imports `FilesWidget`.
- Adds `files: FilesWidget` field, init/deinit.
- Adds `files_card_open` flag.
- Adds `.files` to `CardMode` enum.
- Updates `closeAllCards`, `anyCardOpen`, `activeCardMode`.
- Adds `.files => self.files.renderCard(...)` to card render switch.

## Still needed

1. Add `files_card` variant to `TrayItem.Action` enum.
2. Change Files tray item action from `.spawn` to `.files_card`.
3. Add `toggleFilesCard()` method and handle `.files_card` in tray activation.
4. Replace `launchKidulFiles()` disk-gauge spawn with opening the files card.
5. Fix `src/ui/files_card.zig` compilation issues (check Zig syntax, `std.mem.splitAny` usage, `c.cairo_text_extents_t`, etc.).
6. Build `zig build -Doptimize=ReleaseSafe`.
7. Deploy to VM `fresh-one` and test.

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
