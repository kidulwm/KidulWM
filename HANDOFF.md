# KidulWM Handoff

## Current state

- Branch: `main`
- Last commit: `222bda0 feat: IPC get_windows + kfiles_navigate, tray auto-close on activate`
- Build: passing (`zig build -Doptimize=ReleaseSafe`)
- Deployed: `fresh-one` VM via scp/ssh

## Completed in this session

### Phase 1 — Tray auto-hide + focus handoff
- `src/ui/tray.zig`: `activateSelected()` now closes the tray and any open cards after launching a card/app/slide.
- Exception: `.toggle_tray` action keeps old behavior.

### Phase 2/3 foundation — IPC for dashboard ↔ kfiles
- `src/ipc/message.zig`: added `kfiles_navigate` and `get_windows` requests; `WindowInfo` + `windows` field on `Response`.
- `src/server.zig`: handler for `kfiles_navigate` writes target path to `/tmp/kfiles-navigate`; `getWindowsResponse()` returns all windows with id/app_id/title/mapped.
- `src/kidulwm-control.zig`: added `get_windows` and `kfiles_navigate <path>` CLI commands.
- Verified on VM: `kidulwm-control get_windows` returns kfiles as `com.kidulwm.kfiles`.

### kfiles — drive discovery + navigation
- `kfiles/src/Model.zig`:
  - `discoverDrives()` reads `/proc/self/mounts` for mounted drives and `/proc/partitions` for all block devices.
  - Unmounted block devices are stored as `.hidden = true` drives.
  - `pollNavigateFile()` reads `/tmp/kfiles-navigate`, calls `navigateTo()`, then deletes the file.
  - `goUp()` is blocked from going above `/home/kidul`.
- `kfiles/src/Files.zig`: added `pollNavigateFile()` wrapper.
- `kfiles/src/Wayland.zig`: calls `pollNavigateFile()` each frame.
- New kfiles binary deployed to `/usr/local/bin/kfiles`.

### Left-peek polish (this session)
- `src/core/gauge_data.zig`: `readCpuTemp()` now falls back to 45.0°C when `/sys/class/thermal/thermal_zone0/temp` is unreadable, matching `readGpuTemp()` fallback so the two gauges hide/show together.
- `src/ui/gauge.zig`: RAM cauldron liquid and bubble colors shifted from Xbox-green (`0.2,1.0,0.3`) to turquoise (`0.10,0.85,0.75` / `0.45,1.0,0.9`). Cauldron outline/rim/legs already use theme border colors.
- Rebuilt `kidulwm`/`kidulwm-control` and redeployed to `fresh-one` VM.

## Important correction

The left-peek redesign target is **KidulWM's own internal Zig UI**, NOT the old Rust `rkt-dashboard` prototype. The live gauges/cauldron/drives are rendered in:
- `src/ui/gauge.zig` — GPU/CPU temp gauges and RAM cauldron
- `src/ui/drives.zig` — disk treasure chests
- `src/ui/tray.zig` — owns `GaugeWidget`/`DrivesWidget`, pointer hit boxes (`pointInsideGaugeWidget`)

## Pending work

### Left-peek redesign (in `src/ui/gauge.zig` and `src/ui/drives.zig`)
1. Hide the two top temp gauges by default; show only when value ≥ 76°F (configurable later). Add hotkey/toggle for gauge visibility.
2. Move the RAM cauldron to the bottom of the left peek. Remove "ram" text. Keep it connected to RAM usage and animate more (bubbling/spitting bright green under black glass). Make the cauldron clickable as the rkt/tray button (open/close KidulWM tray).
3. Replace the fixed `disk1_size`/`disk2_size` chest gauges with real drive icons from `discoverDrives()` logic (or share code with kfiles). Show drive icons/pills only when kfiles is open (detect via server's window list / app_id `com.kidulwm.kfiles`).
4. Clicking a mounted drive sends kfiles to that path via `/tmp/kfiles-navigate` or direct IPC. Hidden/unmounted drives should be listed but not navigable until mounting is implemented.
5. Add pointer hit boxes for cauldron and drive icons in `src/ui/tray.zig`.

### Cleanup notes
- The stray kfiles process on the VM may be in a broken state (`WaylandConnectFailed`); kill and relaunch from the tray after deploying the next KidulWM build.
- kfiles debug logging to `/tmp/kfiles-debug.log` was added temporarily and should be removed before final polish.

## Build/deploy workflow

```bash
cd /home/dad/dev/KidulWM
zig build -Doptimize=ReleaseSafe

scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm \\
  zig-out/bin/kidulwm zig-out/bin/kidulwm-control \\
  kidul@127.0.0.1:/tmp/

ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \\
  'sudo systemctl stop kidulwm && sleep 2 && sudo cp /tmp/kidulwm /tmp/kidulwm-control /usr/bin/ && sudo systemctl start kidulwm'
```

For kfiles:
```bash
cd /home/dad/dev/kfiles
zig build -Doptimize=ReleaseFast
scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kfiles kidul@127.0.0.1:/tmp/kfiles.new
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \\
  'pkill -x kfiles 2>/dev/null || true; sleep 2; sudo mv /tmp/kfiles.new /usr/local/bin/kfiles && sudo chmod +x /usr/local/bin/kfiles'
```
