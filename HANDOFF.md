# KidulWM — Handoff

Single source of truth. Update `/home/dad/dev/KidulWM/HANDOFF.md` only.

## Project overview

- Language: Zig (not Rust/Niri — README/PLAN are stale and should not be trusted).
- Compositor base: wlroots 0.20.
- Repo: `/home/dad/dev/KidulWM`
- Branch: `pre-comms-dial`
- Last stable commit: `7afa0c7`
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

- `kidulwm.service` is enabled and running with real display output.
- Log confirms:
  ```
  KidulWM: renderer pixman=true gles2=false
  KidulWM: new output Virtual-1 1280x800
  KidulWM: output added to layout
  KidulWM: backend started
  ```
- Guest Wayland socket and IPC socket are both created at `/run/user/1000/`.
- Output frame listener added in `src/server.zig` calling `wlr_scene_output_commit` each frame; the `#222425` background renders.
- XDG toplevel crash fixed: initial configure is sent on first surface commit (`src/window.zig`), and `handleCommit` requests a layout pass.
- Hardcoded `Mod+Return` keybinding added in `src/input/keyboard.zig` that spawns `/usr/bin/ghostty` with the guest Wayland environment.
- `main.zig` ignores `SIGCHLD` so spawned terminals are auto-reaped.
- Host IPv4 loopback TCP fixed in `/etc/ufw/before.rules`; SPICE on `127.0.0.1:5900` now answers (`nc -zv 127.0.0.1 5900` succeeds).
- A ghostty terminal renders in the VM when launched, either by SPICE/`Mod+Return` or by guest-agent.

## Next steps

1. Verify `Mod+Return` from a real SPICE/virt-manager keyboard.
2. Wire `style.zig` tokens into layout/rendering paths.
3. Stub the chamfer/cut-corner SDF shader.

## Notes

- Barticus prefers terse, direct replies during fast UI iteration.
- Host IPv4 loopback TCP is now functional; SPICE viewers can connect to `127.0.0.1:5900`.
- README.md and PLAN.md in the repo are stale Rust/Niri drafts and should be ignored or rewritten separately.
- To remove headless fallback later, drop `WLR_RENDERER=pixman` once `wlr_renderer_autocreate()` is proven in the VM.
