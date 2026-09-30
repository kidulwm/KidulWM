# KidulWM / KidulDM — known-good commands

Live reference. Verified commands only. If a command is here, it worked.

## Command slices — read only your lane's file

| Lane | File |
|---|---|
| Host build/deploy/control (this file) | KNOWN_CMDS.md |
| VM work — ksd-reset / fresh-one / libvirt | KNOWN_CMDS-vm.md |
| knetd — network daemon | KNOWN_CMDS-knetd.md |
| aig — Kidul Zig toolchain | KNOWN_CMDS-aig.md |
| Apocalypse backup — LaCie | KNOWN_CMDS-apocalypse.md |
| kmedia / PipeWire | KNOWN_CMDS-kmedia.md |

## Quick paths

| Thing | Path |
|---|---|
| Source repo | `/home/dad/dev/KidulWM` |
| Build out | `zig-out/bin/kidulwm`, `zig-out/bin/kidulwm-control` |
| Installed system | `/usr/local/bin/kidulwm`, `/usr/local/bin/kidulwm-control` |
| Service log | `/tmp/kidulwm-service.log` |
| System config | `/etc/kidulwm/` |
| User config | `~/.config/kidulwm/` |
| Runtime | `/run/user/1000/` |


## Host layout — where everything lives (workbench, 2026-09-04)

  Compositor:   /usr/local/bin/kidulwm  (spawned by SDDM session wrapper
                /usr/local/bin/kidulwm-session; desktop entry
                /usr/share/wayland-sessions/kidulwm.desktop)
  Satellites:   /usr/local/bin/ksignals, /usr/local/bin/kfiles,
                /usr/local/bin/launch-kfiles.sh
  knetd:        /usr/local/bin/knetd, knetd.service (SYSTEM unit,
                multi-user.target), state /tmp/knet/{state,cmd,flows,
                *.detail}, persistent /var/lib/knetd/{networks,whitelist},
                log /var/log/knetd.log
  ksignals:     reads /tmp/kidul-signals/*.detail
  brain-knet-watch: USER timer (~/.config/systemd/user/) — runs ONLY
                while dad's user session is up. Logged out = watcher
                asleep. Workbench-acceptable; product needs a system unit.


## TRIP WIRES (read before touching session/spawn code)

  1. Install path = /usr/local/bin, NOT /usr/bin. Spawn strings use
     absolute /usr/local/bin/... paths. (Earlier revisions of this file
     said /usr/bin — that was wrong; nothing was ever installed there.)
  2. uid-1000 assumption: ksd-reset runs as User=kidul (uid 1000), so
     XDG_RUNTIME_DIR=/run/user/1000 holds. The compositor now INHERITS its
     environment to children (Card 1.5) instead of hardcoding it — identity
     comes from the service unit's Environment= lines, never re-typed in
     spawn strings. A second user still breaks things; that's the Phase 1
     (supervisor) fix, not a mid-session patch.
  3. wayland-1 contract: the compositor's socket name comes from
     KIDULWM_WAYLAND_DISPLAY (main.zig), and Card 1.5 now seeds
     WAYLAND_DISPLAY into the compositor's own environ (server.zig start()),
     so spawned clients inherit it. The service unit must still export
     XDG_RUNTIME_DIR=/run/user/1000.
  4. Satellites must exist at their /usr/local/bin paths BEFORE the
     session is exercised — spawns fail silently otherwise.
  5. TERMINAL (Card 1.5): ONE terminal = ghostty via
     /usr/local/bin/launch-kidul-terminal.sh (Mod4+Return). alacritty is
     GONE, Mod4+w is PARKED/unbound. The wrapper carries ghostty-specific
     env (GHOSTTY_RESOURCES_DIR); identity is inherited, not re-typed.


## Build / test on host

```bash
cd /home/dad/dev/KidulWM
zig build
zig build test

# Nested Wayland smoke tests
WAYLAND_DISPLAY=wayland-1 bash scripts/nested-smoke.sh
bash scripts/nested-three-window.sh
bash scripts/nested-focus-stress.sh
```


## kidulwm-control

```bash
export XDG_RUNTIME_DIR=/run/user/1000

kidulwm-control focus_next
kidulwm-control focus_prev
kidulwm-control split_left
kidulwm-control split_right
kidulwm-control split_top
kidulwm-control split_bottom
kidulwm-control media_card_toggle
kidulwm-control media_play <path>
kidulwm-control quit
```


## Gauge visibility toggles (gauges.toml)

```bash
kidulwm-control set-show-temp on|off      # cpu/gpu temp gauges (default off)
kidulwm-control set-show-ram on|off       # reserved: ram gauge group
kidulwm-control set-temp-threshold <F>    # hide temp gauges below this (default 88)
```


## Commands that fail

| Command | Why |
|---|---|
| `virsh start fresh-one` | Uses `qemu:///session`; VMs are on `qemu:///system`. |
| `virsh qemu-agent-command ...` | Agent may not be ready; try again or use SPICE/SSH. |
| `pkill -9 qemu` | Blocked by Hermes safety guard; use `virsh -c qemu:///system destroy`. |
| `zig build` inside VM guest | Toolchain not set up there; build on host and deploy. |


## Verified on

- Host: CachyOS x86_64, Linux 7.1.8-1-cachyos
- Zig 0.16.0 (CachyOS package; aig fork stands at /home/dad/dev/aig)
- libvirt / qemu from pacman
