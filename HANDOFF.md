# KidulWM — Handoff

Single source of truth. Update `/home/dad/dev/KidulWM/HANDOFF.md` only.

## Project overview

- Language: Zig (not Rust/Niri — README/PLAN are stale and should not be trusted).
- Compositor base: wlroots 0.20.
- Repo: `/home/dad/dev/KidulWM`
- Branch: `pre-comms-dial`
- Last stable commit: `7afa0c7`
- Build health: `zig build` pass, `zig build test` pass, `scripts/nested-smoke.sh` pass.

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
- Dark default chrome and plain GTK4 tray default.
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

## Key files

- `/home/dad/dev/KidulWM/src/server.zig` — main compositor init/output handling.
- `/home/dad/dev/KidulWM/src/input.zig` — input manager listener setup.
- `/home/dad/dev/KidulWM/src/core/style.zig` — style tokens.
- `/home/dad/dev/KidulWM/src/core/layout.zig` — layout engine.
- `/home/dad/dev/KidulWM/HANDOFF.md` — this file.

## How to resume

1. `cd /home/dad/dev/KidulWM`
2. `git status` — confirm branch, review uncommitted diff.
3. `zig build && zig build test && bash scripts/nested-smoke.sh`
4. For VM work: use the live status windows or `virsh console cachyos-kidulwm` / QEMU guest agent.

## Current status (tonight's result)

- `kidulwm.service` is enabled and has been running with real display output for ~10 minutes.
- Log confirms:
  ```
  KidulWM: renderer pixman=true gles2=false
  KidulWM: new output Virtual-1 1280x800
  KidulWM: output added to layout
  KidulWM: backend started
  ```
- Guest Wayland socket and IPC socket are both created at `/run/user/1000/`.
- A `KidulVM console` serial console window remains open on the host.
- The live Ghostty status window keeps closing in this environment even though the Python monitor runs fine when launched directly; the console window is the reliable visual fallback.

## Next steps

1. Fix host IPv4 loopback TCP so SPICE can connect and we can actually see the display.
2. Try `wlr_renderer_autocreate()` inside the VM instead of forcing pixman (once loopback/display is reachable).
3. Wire `style.zig` tokens into layout/rendering paths.
4. Stub the chamfer/cut-corner SDF shader.

## Notes

- Barticus prefers terse, direct replies during fast UI iteration.
- Host IPv4 loopback (`127.0.0.1`) is currently broken for TCP, so SPICE viewers cannot connect. Use serial/guest-agent or fix loopback first.
- README.md and PLAN.md in the repo are stale Rust/Niri drafts and should be ignored or rewritten separately.
- To remove headless fallback later, drop `WLR_RENDERER=pixman` once `wlr_renderer_autocreate()` is proven in the VM.
