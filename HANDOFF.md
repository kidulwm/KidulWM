# KidulWM Handoff

Updated 2026-07-31 (network widget landedit; taking a break). Source of truth for resuming.

## Current state

| Item | Value |
|------|-------|
| Branch | `main` |
| Last commit | `dbebf50` Tighten network icon: hollow sunburst, smaller, top-right above clock |
| Work VM | `fresh-one` (kidul@127.0.0.1:2260) |
| Service log | `/tmp/kidulwm-service.log` |
| Deployed WM binary | `/usr/bin/kidulwm` |
| Shorthands | `Bob` = top-left tray logo ; `Barry` = bottom-left pet |
| Notification bridge | Python D-Bus service (`scripts/notify-bridge.py`) owns `org.freedesktop.Notifications`, forwards to KidulWM IPC. |
| notify-send route | Works without manual env after adding `DBUS_SESSION_BUS_ADDRESS`, `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY` to service. |

## What this session changed

### 1. Network widget landed in top-right

- Added `src/ui/network.zig`:
  - Reads network connection state from `/sys/class/net` every 2 s.
  - Three states:
    - `.none` — no interface configured.
    - `.disconnected` — interface(s) configured but none connected.
    - `.connected` — at least one interface has a default-route/IPv4 and is up.
  - Render: hollow centre ring + 8 radiating beams (sunburst interpretation of the Kapitayan emblem).
  - Beam color = border-gold when connected, burnt-warn-orange when disconnected, muted when unconfigured.
  - Stub `renderCard` exists; card shows simple top and advanced bottom sections, not fully wired.
- Wired into `src/ui/tray.zig`:
  - `PerOutputNetwork` scene tree, lifecycle, and hit box.
  - `CardMode.network`, `toggleNetworkCard`, `closeAllCards`, `anyCardOpen` updates.
  - Render loop updates `/sys/class/net` state each frame and redraws on change.
  - Click on the icon opens the network card.
- Layout: icon sits in the right-peek area directly above the clock widget.
  - Widget size currently 32×32 px (logical), with `reserved_network_h = 4 px` for top offset.
- Brightness scroll behavior is **not yet routed** to the network icon (pointer axis in `src/input/pointer.zig` bypasses `Tray.scroll`).
- Fixed a `comptime_int` division compile error in the burnt-orange literal.

### 2. Previous sessions still in flight (carry-over)

- Notification stream cards, action card for security/usb/download, progress candy.
- Curtain renderer `src/render/curtain.zig` matching `/tmp/curtains9.png`.
- kidul-browser remains on hold.

## Visual references on disk

| File | Meaning |
|------|---------|
| `/tmp/kidulwm-network-14.png` | **Latest approved network icon** — hollow sunburst, 32 px, above clock (gap OK) |
| `/tmp/curtains9.png` | Target tied-back curtain silhouette |

## Next session work

1. Address remaining user feedback on the network icon (hollowness, beam count/layout, size if needed).
2. Route pointer-axis scrolling so hovering the network icon adjusts screen brightness.
3. Finish network card: simple top controls (toggle Wi-Fi / enable interface / connect), advanced bottom (`ip addr`, `/sys/class/net` details).
4. Make the network icon react cleanly to live network state changes.
5. Return to notification action cards and curtain work once network widget is locked.

## Files changed recently

- `src/ui/network.zig` (new)
- `src/ui/tray.zig`

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

Verify service is active, then capture screenshot and compare to `/tmp/kidulwm-network-14.png`.

For notifications, after the service is running run `notify-send "Test" "body"` and watch the tray stream.


## Codeberg remote workflow

Use this whenever you need to ensure the work is pushed or pulled from the canonical remote.

- Canonical repo: https://codeberg.org/kidulwm/KidulWM
- Default branch: `main`
- Local working copy: `/home/dad/dev/KidulWM`
- SSH key for pushes: `~/.ssh/id_ed25519_kidulwm` (registered on Codeberg as `dotrix-workstation`)
- Remotes:
  - `origin` points to Codeberg
  - `github-archive` points to the old GitHub mirror (kept for history only)

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

### Check remotes
```bash
cd /home/dad/dev/KidulWM
git remote -v
```

If authentication is refused, verify the SSH key is loaded:
```bash
ssh-add -l | grep id_ed25519_kidulwm
ssh -T git@codeberg.org
```

Do **not** commit credentials, tokens, or the private key itself. The key file stays in `~/.ssh/`; it is never added to the repo.
