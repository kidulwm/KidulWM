# KidulWM Handoff

Updated 2026-07-30 (notification bridge env fix proven). Source of truth for resuming.

## Current state

| Item | Value |
|------|-------|
| Branch | `full-tray-02251c9` |
| Work VM | `fresh-one` (kidul@127.0.0.1:2260) |
| Service log | `/tmp/kidulwm-service.log` |
| Deployed WM binary | `/usr/bin/kidulwm` |
| Shorthands | `Bob` = top-left tray logo ; `Barry` = bottom-left pet |
| Notification bridge | Python D-Bus service (`scripts/notify-bridge.py`) owns `org.freedesktop.Notifications`, forwards to KidulWM IPC. |
| notify-send route | Works without manual env after adding `DBUS_SESSION_BUS_ADDRESS`, `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY` to service. |

## What this session changed

### 1. Curtain overlay feature (active work)
- Added `src/render/curtain.zig` with `OutputCurtains` / `Panel` structures.
- Wired into `src/server.zig`: import, `Output.curtains` field, create/destroy/update calls in `handleNewOutput`, `Output.init`, `Output.deinit`, and `applyLayout`.
- Rendered below widgets/tray so widgets stay fully visible.
- Current implementation draws full-height side panels with black velvet folds and a border-color rope tie-back + small tassel.
- Temporary crash guard added in `handleNewToplevelDecoration` to skip `setMode(.server_side)` for uninitialized xdg surfaces; this kept the compositor alive during testing.

### 2. kidul-browser integration remains benched
- kidul-browser is on hold per user direction.
- Browser files unchanged this session.

### 3. Notification bridge — env fix + flicker fix + route proven
- Fixed notification stream flicker: `NotificationWidget.update()` no longer returns `true` forever when idle, and the widget buffer is destroyed when the queue is empty so the tray stops redrawing continuously.
- Verified empty board shows nothing; notifications still type out normally when added.
- The tray already renders a typewriter notification stream under the clock (`src/ui/notifications.zig` + `src/ui/tray.zig`).
- The KidulWM IPC already supports `notification_test` requests (`src/ipc/message.zig`, `src/server.zig`, `src/kidulwm-control.zig`).
- `scripts/notify-bridge.py` owns `org.freedesktop.Notifications` and forwards each `Notify` to KidulWM via `kidulwm-control notification_test`.
- Service changed from `Type=dbus` to `Type=simple` and now sets `DBUS_SESSION_BUS_ADDRESS`, `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY` so `notify-send` works from any app.
- Verified end-to-end: `notify-send "Test" "body"` reaches the typewriter stream without manual env setup.
- Broken Zig bridge remains in `src/notify-bridge/` as scaffold for a future native rewrite.

## Notification design direction (just decided)

- We accept mistakes and iterate; source-specific rules from the start, tuned over time.
- Categories with examples:
  - **Bob Brain / Files**: folder/file changes (favourite).
  - **System**: updates, backup status, low battery, network up/down.
  - **Security**: reuse data lines from rkt-dashboard (blocked IPs, failed SSH, bad downloads, USB guard pending/connected/blocked).
  - **Communications**: email, messages, calls.
  - **Media**: player state, track changes, errors.
  - **Calendar/Reminders**: appointments, timers.
- Downloads from the Files/browser require user approval (safety guard).
- Per-source formatting, prominence, and sound from day one; users can change them in Settings later.
- Sounds are per-source/category so you can identify importance by ear. Start with a small sound set and grow it.
- **Slide title/favicon band**: will live in the right peek between the bottom of the notification stream and the top of the media-player double-helix. We need to reserve that vertical space now.

## Critical design decisions locked in

- Curtains are **permanent tied-back** unless a peek exists on that side; when a peek exists the panel drops to full output height.
- No animations in this phase — static proof first.
- Colors: black velvet fabric (`tray_bg_color`), rope/tassel in user's mood/border color (`color_border_focused` / `color_border`).
- Rope must be the **thinnest** point of the curtain; fabric bulges outward above and below it.
- Rope sits ~1/5 from the top of the screen, just under top widgets and above future gauges.
- Curtain inner edge must stay ~5 px outside the focused slide so it never covers the main slide.

### Notifications (new decisions)
- Backend is proven — D-Bus bridge owns the standard bus name and any app can `notify-send` to it.
- Fixed idle-redraw bug that caused the whole tray/background to flicker every few seconds.
- Empty notification board renders nothing at all (no placeholder, no accent line).
- Under-clock typewriter stream remains the passive/ambient notification view.
- Clicking/tapping the stream opens a **peek card** displaying the full notification river.
- Peek is a temporary layer beside the focused slide; it does not replace or dim the focused app.
- River will group notifications by source/app with per-item dismiss and clear-all controls.
- Source-specific rules from the start: different formatting and sound per source/category.
- **Reusable security/USB lines**: rkt-dashboard already writes `security-state.json`, `usb-pending.jsonl`, and `usb-guard-state.json`; the notification watcher can read those same files.
- **Slide titles/favicons** will sit in the right peek between the notification stream and the media-player helix; reserve that space.
- Visual polish and sound mapping are after the functional rule/card layer.

## Visual references on disk

| File | Meaning |
|------|---------|
| `/tmp/curtains8.png` | User screenshot: how the tied-back curtain currently looks (wrong) |
| `/tmp/curtains9.png` | User screenshot: **target shape** for the tied-back curtain (pixel-level copy target) |
| `/tmp/curtains4.png` | Additional reference: black stage curtain tied back with gold rope/tassel |
| `/tmp/curtains5.png` | Additional reference: tall gathered curtain with tie near bottom |
| `/tmp/curtains6.png` | Additional reference: red velvet tied-back with small tassels |

Use `/tmp/curtains9.png` as the primary silhouette target.

## Notification bridge install & test

```bash
# On the target session (kidul/fresh-one), after deploying the current KidulWM binaries
sudo mkdir -p /usr/share/kidulwm/scripts
sudo cp /home/dad/dev/KidulWM/scripts/notify-bridge.py /usr/share/kidulwm/scripts/
sudo chmod 755 /usr/share/kidulwm /usr/share/kidulwm/scripts
sudo chmod 644 /usr/share/kidulwm/scripts/notify-bridge.py
mkdir -p ~/.config/systemd/user
cp /home/dad/dev/KidulWM/config/systemd/user/kidulwm-notify-bridge.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now kidulwm-notify-bridge

# Verify it owns the notification bus name
systemctl --user status kidulwm-notify-bridge
dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DB org.freedesktop.DBus.GetNameOwner string:org.freedesktop.Notifications

# Send a test notification
notify-send "Hello" "from the bridge"
```

Expect to see the text appear in the typewriter stream under the clock.

## Next session work

1. **System-event notification watcher** — write a small Python/systemd service that polls the same rkt-dashboard state files (security, USB) and emits `notify-send` into KidulWM. Use this to define the first source rules.
2. **Notification rule/config foundation** — add a config file that maps source/category → display treatment (colour, sound, persistence, approval-required).
3. **Implement notification peek/card** triggered by clicking/tapping the stream under the clock. Card shows full river grouped by app with dismiss per item and clear all.
4. **Reserve right-peek space** between notification stream and media helix for slide title/favicon band.
5. **Copy `/tmp/curtains9.png` silhouette pixel-for-pixel** into `src/render/curtain.zig` as the tied-back left panel, then mirror for the right panel.
3. Apply the curtain design rules above (thinnest at rope, bulge above/below, 5 px gap from focused slide, rope at 1/5 top, black velvet, border-color rope).
4. Build/deploy/screenshot until the static tied-back shape is approved.
5. Then implement the **dropped** curtain state: mostly straight vertical folds all the way to the bottom, still 5 px outside the slide.
6. Verify peek-trigger transitions and remove/replace the temporary `handleNewToplevelDecoration` guard.
7. (Future) Rewrite the bridge in pure Zig and remove the Python service once D-Bus service handling is solid.

## Files changed (uncommitted)

- `src/render/curtain.zig` — curtain renderer.
- `src/server.zig` — curtain import, `Output.curtains` field, init/deinit/update wiring, temporary decoration guard.
- `scripts/notify-bridge.py` — Python D-Bus notification bridge; keep `BusName` reference so name stays owned.
- `config/systemd/user/kidulwm-notify-bridge.service` — `Type=simple`, added required env vars.
- `src/ui/notifications.zig` — stop idle-redraw loop; destroy widget buffer when queue empty.
- `src/ui/tray.zig` — skip notification render entirely when queue is empty.
- `src/ipc/message.zig`, `src/server.zig`, `src/kidulwm-control.zig` — added `notification_clear` IPC command.
- `build.zig` — temporarily excluded the broken Zig bridge binary from the build (comment TODO).
- `HANDOFF.md` — this file.

## How to resume

```bash
cd /home/dad/dev/KidulWM
zig build
scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm \
  zig-out/bin/kidulwm \
  zig-out/bin/kidulwm-control \
  kidul@127.0.0.1:/tmp/
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1
sudo systemctl stop kidulwm
sudo cp /tmp/kidulwm /tmp/kidulwm-control /usr/bin/
sudo systemctl start kidulwm
```

Verify service is active, then capture screenshot and compare to `/tmp/curtains9.png`.

For notifications, after the service is running run `notify-send "Test" "body"` and watch the tray stream.
