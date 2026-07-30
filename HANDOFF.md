# KidulWM Handoff

Updated 2026-07-30 (notification stream cards content-sized and layout-tested). Source of truth for resuming.

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

### 1. Notification priority card system (just locked)

### 1b. Notification stream card layout / sizing (in progress)
- Cards now size to their content height rather than filling the whole right-peek panel.
- Layout per card:
  1. Priority label line (`CRITICAL`, `HIGH`, etc.).
  2. Source label line (`Download`, `Security`, `USB`, `Files`, `System`, `Media`).
  3. Title/detail line (file type/size for downloads, event summary for security/system).
  4. Body/state/progress line:
     - progress bodies draw a thin gold bar when `%` token is present;
     - non-progress bodies draw wrapped text (`pending approval` normalizes to `Pending`).
- Critical actionable cards (`security`, `usb`, `download`) get a subtle dark backing + burnt-orange rounded border.
- Added `download` source rule and action hook.
- Refactored `src/ui/notifications.zig` from a simple queue into a `NotificationCard` unit.
  - Title and body/panel are now one card; `display_mode` selects the skin to draw it with.
  - Day-one skins: `.typewriter` (active); `.scroll`, `.banner`, `.river` stubbed for later.
  - `Priority`: `.critical`, `.high`, `.normal`, `.low`.
- Priority behaviour:
  - `critical` interrupts the current card immediately and pauses the normal stream.
  - `high` waits for the current card to finish, then cuts ahead of normal/low.
  - normal/low rotate one-at-a-time; low only shows when nothing else is queued.
  - After an urgent card clears, the stream takes a 1.5 s "curtain down" break before resuming normal cards.
  - Burnt-orange `CRITICAL` label; smaller priority label sits above source/title line.
- Burst grouping: multiple same-source critical events within 2 s collapse into one card with a count (e.g. `USB (3)`).
- Action-card hooks: `security` and `usb` notifications carry `action_id` metadata so a future click can open a Block/Allow/Details card.
- `src/ipc/message.zig`, `src/server.zig`, `src/kidulwm-control.zig`: `notification_test` now accepts optional `priority`, `action_id`, `display_mode` fields.
- `scripts/notify-bridge.py` and `scripts/system-watcher.py` forward priority hints and action IDs.
- `config/notifications.yaml` remains the rule reference; the in-code `defaultRule` table matches it.

### 2. Curtain overlay feature (active work)
- Added `src/render/curtain.zig` with `OutputCurtains` / `Panel` structures.
- Wired into `src/server.zig`: import, `Output.curtains` field, create/destroy/update calls in `handleNewOutput`, `Output.init`, `Output.deinit`, and `applyLayout`.
- Rendered below widgets/tray so widgets stay fully visible.
- Current implementation draws full-height side panels with black velvet folds and a border-color rope tie-back + small tassel.
- Temporary crash guard added in `handleNewToplevelDecoration` to skip `setMode(.server_side)` for uninitialized xdg surfaces; this kept the compositor alive during testing.

### 3. kidul-browser integration remains benched
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

## IMAP email watcher install & test

```bash
# Copy the watcher and example config to the target system
sudo mkdir -p /usr/share/kidulwm/scripts
sudo cp /home/dad/dev/KidulWM/scripts/imap-watcher.py /usr/share/kidulwm/scripts/
sudo chmod 755 /usr/share/kidulwm /usr/share/kidulwm/scripts
sudo chmod 644 /usr/share/kidulwm/scripts/imap-watcher.py

# Create your private config; never commit this file
cp /home/dad/dev/KidulWM/config/imap.conf.example ~/.config/kidulwm/imap.conf
# edit ~/.config/kidulwm/imap.conf with Proton Bridge credentials

# Install and start the user service
mkdir -p ~/.config/systemd/user
cp /home/dad/dev/KidulWM/config/systemd/user/kidulwm-imap-watcher.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now kidulwm-imap-watcher
systemctl --user status kidulwm-imap-watcher
```

With one new unread message you'll see `Sender Name` / `Subject`; with multiple you'll see `Email` / `N new`.

## Next session work

1. **FINISH notification stream body visibility** — confirm short body text appears under the title line; adjust contrast/backing if still missing on live wallpaper.
2. **Implement the action card** for `security`, `usb`, and `download` notifications: Block / Allow / Details buttons, rendered in KidulWM card style.
3. **Add progress-bar candy** — live current/total size count and optional ETA inside the body string.
4. **Implement notification peek/card** triggered by clicking/tapping the stream under the clock.
5. **Reserve right-peek space** between notification stream and media helix for slide title/favicon band.
6. **Copy `/tmp/curtains9.png` silhouette pixel-for-pixel** into `src/render/curtain.zig`.
7. Apply curtain design rules and build/deploy/screenshot until approved.
8. Then implement the **dropped** curtain state.
9. Verify peek-trigger transitions and remove/replace the temporary `handleNewToplevelDecoration` guard.


## Files changed (uncommitted)

- `src/render/curtain.zig` — curtain renderer.
- `src/server.zig` — curtain import, `Output.curtains` field, init/deinit/update wiring, temporary decoration guard.
- `scripts/notify-bridge.py` — Python D-Bus notification bridge; keep `BusName` reference so name stays owned.
- `config/systemd/user/kidulwm-notify-bridge.service` — `Type=simple`, added required env vars.
- `src/ui/notifications.zig` — `NotificationCard` unit with priority, display_mode, action_id, burst grouping, priority interrupts, resume-after-break.
- `src/ui/tray.zig` — updated `notificationAdd` to accept optional priority/action/display args; still skips render when queue empty.
- `src/ipc/message.zig`, `src/server.zig`, `src/kidulwm-control.zig` — added optional `priority`, `action_id`, `display_mode` to `notification_test`; `notification_clear` still present.
- `scripts/notify-bridge.py` — forwards urgency hints and `kidulwm-action` hints; maps numeric urgency levels to priority names.
- `scripts/system-watcher.py` — sends per-event priority hints (`critical` for security, USB pending/blocked; `high` for connected/other).
- `scripts/imap-watcher.py` — new Python IMAP email watcher; polls INBOX and sends `email` source notifications.
- `config/imap.conf.example` — example config for the IMAP watcher.
- `config/systemd/user/kidulwm-imap-watcher.service` — user service to run the IMAP watcher.
- `config/notifications.yaml` — added `email` source rule.
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
