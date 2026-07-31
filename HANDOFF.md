# KidulWM Handoff

Updated 2026-07-31 (session wrap-up). Source of truth for resuming.

## Current state

| Item | Value |
|------|-------|
| Branch | `main` |
| Last commit | `3ffe272` replace bottom-left tray toggle with Kidul circular goddess icon |
| Work VM | `fresh-one` (kidul@127.0.0.1:2260) |
| Service log | `/tmp/kidulwm-service.log` |
| Deployed WM binary | `/usr/bin/kidulwm` |
| Shorthand history | `Bob` = legacy top-left tray logo ; `Barry` = legacy bottom-left pet (both now parked/hidden) |
| Notification bridge | Python D-Bus service (`scripts/notify-bridge.py`) owns `org.freedesktop.Notifications`, forwards to KidulWM IPC. |
| notify-send route | Works without manual env after adding `DBUS_SESSION_BUS_ADDRESS`, `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY` to service. |

## What this session changed

### 1. Network icon merged into clock widget

- `src/ui/network.zig`:
  - Removed brightness icon; network icon size increased to 16×scale.
  - VPN icon sits left of network; battery icon sits right.
- `src/ui/tray.zig`:
  - Dedicated network widget tree is now hidden; `drawNetworkWidget` only polls state.
  - Network icon is rendered into the clock widget buffer at the top (status band = 34 px).
  - Clock widget moved up to the top of the right-peek box, then lowered 18 px for final vertical position.
  - Gap between network icon and clock digits tightened to ~1 px.
  - Click zone: top ~52 px of the right-peek box = network/brightness; below = calendar.

### 2. Bottom-left tray toggle replaced with Kidul circular goddess icon

- New logo asset: `src/ui/assets/bob/emblem_mask.png` (flipped horizontally from `~/Pictures/KidulIcon.png`, black made transparent).
- Top-of-tray Barry lozenge is hidden; the single bottom button is now the tray toggle.
- Icon is rotated 9° anti-clockwise from the committed state (`3ffe272`).
  - **In-flight tweak at session end:** user wants -17° anti-clockwise and a small vertical raise, but the working tree got corrupted by repeated patches and had to be restored to `3ffe272`. A small loop occurred during the final rotation adjustment.
- Button is rendered as a glass disc with soft shadow, theme-colored rim, and a 3 px inner shading ring.

### 3. Pending / next session

- **Finish the bottom-left logo tweak:** rotation should be `-17°` (cairo negative) and icon raised ~6 px from the bottom (`raise_up = 6.0 * s`). The current committed code is at `9.0` (clockwise), so it needs to be flipped negative.
- **Rename refactor:** settle on `drawKidulButton` / `drawKidulIcon` names once the visual result is locked. The `Barry`/`Pet` names in `tray.zig` are now misleading.
- Brightness scroll behavior is **not yet routed** to the network icon (pointer axis in `src/input/pointer.zig` bypasses `Tray.scroll`).
- Network card (`renderCard`) is still mostly stub.
- Notification action cards and curtain renderer still parked.

## Visual references on disk

| File | Meaning |
|------|---------|
| `/tmp/kidul_status_on_clock.png` | Latest network-icon-on-clock layout (do not analyze unless requested) |
| `/tmp/curtains9.png` | Target tied-back curtain silhouette |

## Next session work

1. Apply the final bottom-icon rotation/raise cleanly (and possibly rename `drawPet` → `drawKidulButton`).
2. Verify the icon follows theme border colors under accent changes.
3. Route pointer-axis scrolling so hovering the network icon adjusts screen brightness.
4. Finish network card UI.
5. Return to notification action cards and curtain work.

## Files touched this session

- `src/ui/network.zig`
- `src/ui/tray.zig`
- `src/ui/assets/bob/emblem_mask.png`
- `src/ui/assets/bob/logo.png` (reverted to original text logo)

## How to resume

```bash
cd /home/dad/dev/KidulWM
git log --oneline -5
zig build
scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm \
  zig-out/bin/kidulwm \
  kidul@127.0.0.1:/tmp/
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1
sudo systemctl stop kidulwm
sudo cp /tmp/kidulwm /usr/bin/kidulwm
sudo systemctl start kidulwm
```

Verify service is active, then proceed with the pending tweak.

## Codeberg remote workflow

- Canonical repo: https://codeberg.org/kidulwm/KidulWM
- Default branch: `main`
- Local working copy: `/home/dad/dev/KidulWM`
- SSH key for pushes: `~/.ssh/id_ed25519_kidulwm` (registered on Codeberg as `dotrix-workstation`)

### Push current branch
```bash
cd /home/dad/dev/KidulWM
git push origin main
```

### Pull latest from Codeberg
```bash
cd /home/dad/dev/KidulWM
git pull origin main
```

Do **not** commit credentials, tokens, or the private key itself.
