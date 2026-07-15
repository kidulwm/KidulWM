# 2026-07-15 Tray: icons, "All The Things" -> Hide toggle

## Commit
- `75872af` — `tray: icons and hide-toggle logic`
- Tag: `tray-icon-toggle`, also tagged `greatest-yet`

## Why
The bottom-left tray label was flipping to "Hide" as soon as hover opened the tray, giving no chance to click/activate "All The Things" to pin the tray open.

## What changed
- Added optional `.icon` to `TrayItem` for PNG logos; cached per tray instance.
- Added `tray_icon_size` and `tray_icon_gap` style tokens.
- Bottom button label is now dynamic:
  - Closed/hover-only: **All The Things**
  - After activation: **Hide**
- Removed the redundant static "Hide" tray item.
- `bottom_activated` flag tracks whether the bottom button has been explicitly activated while the tray is closing. The flag resets when the tray fully closes.

## Keybinds (existing)
- `Mod4+t` — toggle tray
- `Mod4+Down` — select next tray button (auto-opens if closed)
- `Mod4+Up` — select previous tray button (auto-opens if closed)
- `Mod4+Return` — activate selected tray button (auto-opens if closed)

## Files
- `src/ui/tray.zig`
- `src/core/style.zig`

## Follow-up ideas
- JPEG/other image formats via a small decoder (currently PNG only).
- Config-driven tray items instead of hard-coded defaults.
