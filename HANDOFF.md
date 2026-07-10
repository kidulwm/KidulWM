# KidulWM — Handoff

Single source of truth. Update `/home/dad/dev/KidulWM/HANDOFF.md` only.

## Project overview

- Language: Zig (not Rust/Niri — README/PLAN are stale and should not be trusted).
- Compositor base: wlroots 0.20.
- Repo: `/home/dad/dev/KidulWM`
- Branch: `chrome-2x`
- Last stable commit: `eb50be0`
- Build health: `zig build` pass, `zig build test` pass, `scripts/nested-smoke.sh` pass, `scripts/nested-three-window.sh` pass.

## Barticus' design rules

1. Window matrix performance first; no window tabbing.
2. Default compositor background: Hermes CLI dark `#222425`.
3. Plain GTK4 tray by default; layer-shell opt-in only (`KIDUL_TRAY_USE_LAYER=1`).
4. Border/colour/chamfer/gap tokens live exclusively in `src/core/style.zig`.
5. Chamfer SDF shader refinement comes after core window path is fast and stable.

## What's already landed

- Heap-allocated `Server`, init every `wl.Listener.link` before `signal.add()`, arm timers with `timerUpdate()`.
- Event-driven layout via self-pipe + `wl.EventLoop.addFd` wakeup.
- Cached `LayoutModel` in `src/core/layout.zig`; allocation-free geometry updates after first output sync.
- Dark default chrome. Compositor-side tray removed; GTK4 tray/shell will be added later once the core window path is solid.
- Real `get_layout` IPC response.
- Explicit pixman renderer path when `WLR_RENDERER=pixman` is set.
- `handleNewOutput()` now calls `wlr_output_init_render()` and commits state before adding to layout/scene.

## VM / runtime environment

- VM name: `cachyos-kidulwm`
- Hypervisor: `qemu:///system`
- Network: QEMU user-mode SLIRP (`<interface type='user'/>`), guest IP `10.0.2.15/24`.
- Display: SPICE on `127.0.0.1:5900`, video model `virtio-vga`.
- Guest disk: GPT with 512 MiB ESP (`/dev/vda1`) and ext4 root (`/dev/vda2`).
- Guest user: `kidul` (autologin on tty1), groups: `wheel`, `video`, `input`, `seat`.
- Guest seat backend: `seatd` running; `LIBSEAT_BACKEND=seatd` set in service.

## Current service config (guest)

File: `/etc/systemd/system/kidulwm.service`

Real display now works:
- `WLR_RENDERER=pixman`
- `WLR_NO_HARDWARE_CURSORS=1`
- `LIBSEAT_BACKEND=seatd`
- `XDG_RUNTIME_DIR=/run/user/1000`
- `XDG_SESSION_TYPE=wayland`

This boots cleanly, creates `wayland-1` + `kidulwm-control.sock`, adds output `Virtual-1 1280x800`, and reports `KidulWM: backend started`.

## Recent fixes

### LayoutModel overwrite in `applyLayout`

**Symptom:** KidulWM died on the third mapped XDG toplevel.  The crash path pointed
at `wl_signal_emit` / `libwlroots-0.20.so+0x5f121` with a stale listener.

**Root cause:** `Server.applyLayout()` reassigned the whole struct with
`self.layout = layout.LayoutModel.init(...)`.  The `LayoutModel` created in
`Server.init()` already owned an allocated `outputs` ArrayList.  Reassigning the
struct leaked the old array and cached pointers; the next layout pass iterated
freed memory.

**Fix:** In `src/server.zig`, call `self.layout.deinit()` before reassigning when
outputs are empty.  `zig build`, `zig build test`, and `scripts/nested-smoke.sh`
pass; VM verification is next.

### Input manager listener lifetime bug

Root cause of the VM crash inside `wlr_backend_start` / `handle_device_added`:
`InputManager.init()` returned the struct by value *after* calling `backend.events.new_input.add(&manager.new_input)`. The added listener's address was a stack temporary, so the signal list ended up pointing at freed stack memory.

Fix:
- `InputManager.init()` now takes `self: *InputManager`.
- `Server.init()` heap-allocates `input_manager` and calls `InputManager.init(server.input_manager, server)` at its final address.

### Output initialization

`handleNewOutput()` now:
1. Calls `wlr_output.initRender(allocator, renderer)`.
2. Builds an `Output.State`, enables, chooses preferred mode or a 1024×768 fallback, commits.
3. Logs output name/size.
4. Adds to `output_layout` and scene.

### Renderer selection

`Server.init()` takes a `force_pixman` flag plumbed from `main()`. When `WLR_RENDERER=pixman`, it creates `wlr_pixman_renderer_create()` instead of `wlr_renderer_autocreate()`, and logs renderer type.

### Compositor-side tray removal

`TrayManager` / `SettingsTray` were removed from `src/server.zig` and `src/tray.zig` deleted.
GTK4 will own panels and tray once core window management is stable.

### VM boot failure (NO BOOTABLE DISK)

After copying the fixed binary into the VM, the next boot failed with "NO BOOTABLE DISK".

- The ESP only contained `EFI/KIDUL/grubx64.efi`; there was no UEFI fallback `EFI/BOOT/BOOTX64.EFI`.
- The OVMF_VARS fd was stale/corrupt.

Fix (with VM shut off):
1. Mount `/dev/vda1` (ESP) and copy `EFI/KIDUL/grubx64.efi` to `EFI/BOOT/BOOTX64.EFI`.
2. Recreate `/var/lib/libvirt/qemu/nvram/cachyos-kidulwm_VARS.fd` from `/usr/share/edk2/x64/OVMF_VARS.4m.fd`, owner `libvirt-qemu:libvirt-qemu`, mode `660`.

The VM then booted cleanly and the KidulWM service started normally.

### Layout stability across map/unmap

- `Server.applyLayout()` reserves the column slot for unmapped windows so geometry does not shift when a client unmaps/remaps.
- `focusAtCursor()` and focus selection in `applyLayout()` only consider mapped windows.

### Window focus lifecycle

- `Window.handleMap()` now calls `Server.focusWindow(window)` so new windows receive keyboard focus.
- `Window.handleUnmap()` clears focus from that window if it was focused.
- `Window.handleDestroy()` clears focus and removes all listeners safely.
- `Server.focusWindow()` refuses unmapped surfaces and syncs the integer `state.focused_window` index.
- `Server.focusWindowByIndex()` implements IPC `set_focus`.
- `Server.clearFocus()` uses `seat.keyboardNotifyClearFocus()`.

Result: mapped windows are focus-aware, IPC `set_focus` works, and shutdown no longer asserts on outstanding toplevel listeners.

### VM deployment and access workflow

- Service binary lives at `/usr/bin/kidulwm` (FHS path) and is used by `/etc/systemd/system/kidulwm.service`.
- Guest agent is functional and was used to inject an SSH key for `kidul`.
- Host SSH access uses libvirt hostfwd: `hostfwd_add tcp::2222-:22`, then `ssh -p 2222 kidul@127.0.0.1`.
- Verified in VM: three Ghostty toplevels map without crash; `systemctl restart kidulwm` restarts cleanly with no new coredump.

### Shutdown cleanup (host nested tests)

After fixing the third-map crash, host nested tests still aborted during IPC quit.

- **PointerManager / KeyboardManager by-value initialization bug**: `.init()` returned the struct by value, so the `wl.list.Head` sentinel ended up pointing at the stack temporary. Fixed by making both managers in-place init (`self: *Manager`) and calling `.init()` at the final field address.
- **Input manager free**: `Server.deinit()` de-inited `input_manager` but never called `allocator.destroy()` on it. Added.
- **Display teardown**: `wl_display_destroy` asserted because clients were still connected. Added `self.wl_server.destroyClients()` at the start of `Server.deinit()`.
- **Listener teardown**: `PointerDevice.destroy()` and `KeyboardDevice.destroy()` were double-removing listeners attached to signals already cleared by wlroots. Removed listener `.link.remove()` calls from these destroy paths; detaching from the manager list and freeing the struct is enough because the signals themselves are being destroyed.

Result: host nested smoke and 3-window tests now exit cleanly with no new kidulwm coredumps.

## Key files

- `/home/dad/dev/KidulWM/src/server.zig` — main compositor init/output handling.
- `/home/dad/dev/KidulWM/src/input.zig` — input manager listener setup.
- `/home/dad/dev/KidulWM/src/core/style.zig` — style tokens.
- `/home/dad/dev/KidulWM/src/core/layout.zig` — layout engine.
- `/home/dad/dev/KidulWM/src/dm/render.zig` — DM splash/auth card rendering.
- `/home/dad/dev/KidulWM/KNOWN_CMDS.md` — command reference.
- `/home/dad/dev/KidulWM/HANDOFF.md` — this file.

## Linux file-management conventions

To stay generic for end-user systems, KidulWM/DM follow standard FHS placement:

- Binaries: `/usr/bin/kidulwm`, `/usr/bin/kiduldm`
- System config: `/etc/kidulwm/`
- Static assets: `/usr/share/kidulwm/`
- User config: `~/.config/kidulwm/`
- Runtime sockets: `/run/user/1000/`
- Logs: `journalctl -u kidulwm`

The repo builds to `zig-out/bin/*`; install into `/usr/bin` with `install` or a
package script.  Avoid custom `/opt/kidul` or user-only `/usr/local` conventions
so future installers match distro expectations.

## How to resume

1. `cd /home/dad/dev/KidulWM`
2. `git status` — confirm branch, review uncommitted diff.
3. `zig build && zig build test && bash scripts/nested-smoke.sh`
4. For VM work: use the live status windows or `virsh console cachyos-kidulwm` / QEMU guest agent.

## Current status (tonight's result)

- Branch: `chrome-2x`
- Head commit: `eb50be0` (`chrome: parallel-offset chamfer ring, edge-aware mask, hidden-seam square corners`)
- Fallback commit: `c628157` (`chrome: background-corner mask + variable chamfer ring (sides=3, chamfers=3.5)`)
- `zig build` and `zig build test` pass.
- VM test binary deployed; live visual confirmed:
  - grey client-corner bleed past chamfers is masked out,
  - fine aliasing/halo line inside the focused border is gone,
  - straight side borders and diagonal chamfer legs read as equally thick.

### Chrome / border geometry

- `src/core/style.zig` now defines two independent border tokens:
  - `border_width` -- perpendicular thickness of straight top/bottom/left/right edges.
  - `chamfer_border_width` -- perpendicular thickness of the diagonal chamfer legs on `.cut` corners.
- `src/render/chrome.zig` builds the frame as a variable-thickness ring for `.cut` style:
  - each outer edge is offset inward by its own thickness;
  - inner vertices are recomputed by intersecting adjacent offset edges.
  - `.classic` (rounded) and `.none` remain on the previous uniform path.
- `src/render/chrome.zig` now masks the area outside the inner content shape with `color_background` before drawing the border ring. This hides client-surface rounded corners / shadows that extend beyond the chamfered content region.
- `src/server.zig` handles `border_width` and `chamfer_border_width` theme keys at runtime, increments `chrome_style_generation`, and triggers a layout pass.
- `src/kidulwm-control.zig` exposes `set_theme <key> <value>`.
- Default values in `src/core/style.zig`:
  - `border_width = 3.0`
  - `chamfer_border_width = 3.5`
- The small chamfer surplus (0.5 px) is a visual compensation trick; on a 1:1 display it reads as equal-thickness to the human eye.

### VM deployment (current workflow)

- VM: `cachyos-kidulwm` via `virsh -c qemu:///system`.
- Host SSH forward: `hostfwd_add tcp::2222-:22`.
- Service binary target: `/usr/bin/kidulwm`.
- Guest user `kidul@127.0.0.1:2222` has passwordless `sudo`.
- `nbd` mount is currently broken on host kernel `7.1.3-1-cachyos` (`modprobe nbd` fails). Use live SSH deploy instead:
  1. `scp -P 2222 zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm.new`
  2. `ssh -p 2222 kidul@127.0.0.1 'sudo systemctl stop kidulwm; sudo -S -p '' cp /tmp/kidulwm.new /usr/bin/kidulwm; sudo -S -p '' systemctl start kidulwm'`
  3. Re-add port forward if the VM was rebooted: `virsh -c qemu:///system qemu-monitor-command cachyos-kidulwm --hmp 'hostfwd_add tcp::2222-:22'`

## Next steps

1. Investigate / verify right-peek top/bottom border reach under different focus states.
2. Verify `Mod+Return` from a real SPICE/virt-manager keyboard.
3. Stub the chamfer/cut-corner SDF shader.

## Notes

- Barticus prefers terse, direct replies during fast UI iteration.
- Host IPv4 loopback TCP is now functional; SPICE viewers can connect to `127.0.0.1:5900`.
- README.md and PLAN.md in the repo are stale Rust/Niri drafts and should be ignored or rewritten separately.
- To remove headless fallback later, drop `WLR_RENDERER=pixman` once `wlr_renderer_autocreate()` is proven in the VM.

### Window motion / animation

- Added `src/core/animation.zig`: spring-based interpolation tuned for fast, crisp motion.
- Each `Window` now carries a `WindowAnimation`; `server.zig` sets layout targets in `applyLayout()` instead of snapping geometry.
- `Output.handleFrame()` ticks animations before `scene_output.commit()`; configure/resize requests are sent only when targets change, not every frame.
- New `kidulwm-control` CLI sends IPC commands (focus_next, focus_prev, split_left/right/top/bottom, quit).
- `scripts/nested-focus-stress.sh` spawns three clients and rapid-fires focus/split commands to exercise the motion layer.

### IPC hardening

- Fixed `src/ipc/control.zig` read path to use `linux.errno(rc)` instead of a broken unsigned `n < 0` check that caused buffer underflow crashes.
- Added bounds/defensive handling for EAGAIN/EINTR, empty lines, and handleLine errors.

### SlideDeck grid matrix

- Replaced 3-column LayoutModel with SlideDeck in src/core/slidedeck.zig.
- Each Slide is a full-screen page on an output. Focused Slide gets central focus rect; neighbours peek from edges.
- New windows insert near deck centre; focus_next/prev cycle slides with spring motion.
- Window lifecycle (map/unmap/destroy) inserts/removes slides; deck preserves ordering across unmap.
- Per-output decks planned: current code has one Deck per Server; move field into Output when multi-output window assignment is wired.

### Window dimming

- Unfocused Slides get a semi-transparent black overlay (18% alpha).
- Focused window hides the overlay.
- dim_rect stored on Window; recreated/ resized each layout pass using surface current size.

### Per-output SlideDecks

- Each Output now owns its own SlideDeck (src/server.zig).
- Server has focused_output; new windows assign to the active output.
- applyLayout iterates every output, resizes each deck to the output geometry, sets window targets.
- IPC split/gap/orientation live on Server and apply to all outputs (per-output overrides later).
- get_layout reports slide_count (deck size) and window_count (global list).

### Lag / Slide-from-behind fixes

- Output.scheduleFrame() called on every requestLayout so motion starts immediately.
- Focused window scene node raised to top of scene tree each layout pass.
- XDG toplevel only reconfigured after the spring settles; no buffer churn while sliding.
- Animation uses variable dt from CLOCK_MONOTONIC, capped at 50 ms. Spring tuned stiffer + more damping.

### VM 1/4-screen fix

- KidulDM is not the cause; KidulWM drives the display directly.
- QEMU virtual outputs advertise 1280x800 as "preferred" even when larger modes exist.
- For outputs named Virtual-* KidulWM now selects the largest available mode up to 4K.
- Verified in VM: Virtual-1 now commits at 3840x2160.

### Animation disabled (temporary)

- Window motion animation removed to reduce VM lag/pixelation.
- setLayoutTarget snaps current geometry to the target immediately.
- Per-frame spring stepping replaced by direct target application in tickAnimation.
- Can be re-enabled once rendering budget is understood.

### Renderer experiment log

| Setting | Visual quality | Speed | Notes |
|---|---|---|---|
| `WLR_RENDERER=pixman` + 3840x2160 | pixelated/blurry | poor | Pixman nearest-neighbor upscaling; avoid. |
| `WLR_RENDERER=gles2` (kms_swrast) + 3840x2160 | crisp | slow | Better than Pixman, but 4K software raster swamps VM CPU. |
| `WLR_RENDERER=gles2` (kms_swrast) + 1920x1080 | crisp | acceptable for testing | Current sweet spot for VM testing. |
| `virtio-vga-gl` + SPICE GL | blocked | blocked | Host SPICE/QEMU build rejects gstreamer video encoder; not viable without fixing host encoder. |
| `virtio-vga-gl` + `egl-headless` | blocked | blocked | QEMU fails to open `/dev/dri/renderD128` or `renderD129`; likely permission or host EGL setup. |

**Current VM config for testing:**
- Video device: `virtio-vga` (no 3D).
- Service drop-in `/etc/systemd/system/kidulwm.service.d/gles2.conf`: `WLR_RENDERER=gles2`.
- Output mode: capped at 1920x1080 in `src/server.zig`.
- Binary deployed to `/usr/bin/kidulwm`.
