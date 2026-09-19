# KidulWM / KidulDM — known-good commands

Live reference. Verified commands only. If a command is here, it worked.

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

## VM lifecycle — always use qemu:///system

Default `virsh` connects to `qemu:///session` and fails for this VM.

```bash
virsh -c qemu:///system list --all
virsh -c qemu:///system start fresh-one
virsh -c qemu:///system shutdown fresh-one
virsh -c qemu:///system destroy fresh-one

# The original server-in-waiting VM
virsh -c qemu:///system start cachyos-kidulwm
```

## VM console access

```bash
# check SPICE port
nc -zv 127.0.0.1 5900

# GUI viewer
remote-viewer spice://127.0.0.1:5900

# serial console (interactive, exit with Ctrl+] )
virsh -c qemu:///system console fresh-one
```

## SSH into a VM (CURRENT, 2026-09-19)

Work VM (reset bench): `ksd-reset` — `kidul@192.168.122.87` (plain NAT, port 22)
Frozen reference (widget sizes): `fresh-one` — `kidul@192.168.122.96` (DO NOT TOUCH — old code, pre-tray-demolition)
`cachyos-kidulwm` and the rest: shut off / stale.

Real IPs come from `virsh -c qemu:///system domifaddr <vm>` (or the guest agent).
The old `127.0.0.1:2260` (fresh-one) and `127.0.0.1:2222` (cachyos) hostfwd
mappings are STALE — do not use them.

Use the existing key:

```bash
ssh -i ~/.ssh/id_ed25519_kidulwm kidul@192.168.122.87   # ksd-reset (work)
ssh -i ~/.ssh/id_ed25519_kidulwm kidul@192.168.122.96   # fresh-one (frozen)
```

VM sudo password is `kidul` (the `echo kidul | sudo -S ...` pattern below).

If a VM rejects the key, inject it via guest agent — but first the agent must be running:

```bash
virsh -c qemu:///system qemu-agent-command ksd-reset --cmd '{"execute":"guest-ssh-add-authorized-keys","arguments":{"username":"kidul","keys":["$(cat ~/.ssh/id_ed25519_kidulwm.pub)"]}}'
```

If guest agent is not responsive, use the SPICE console or the serial console instead.

## Deploy KidulWM — workbench is PHASE-DEPENDENT (2026-09-19)

SYSTEM.md is the arbiter ("1 file to rule"). Phase 2 (RSS wedge) is GPU-only
→ HOST: kidulwm runs on the host's i915 (GL, NOT pixman) via an sddm login.
Everything else (software/pixman) stays in ksd-reset. Build ReleaseSafe on
host; deploy to the active target (mv-over swap + .bak, never cp on running
binary).

ksd-reset runs kidulwm as a SYSTEM service on tty1 (not a user session):
`/etc/systemd/system/kidulwm.service`, `User=kidul`, `WLR_RENDERER=pixman`
(software renderer — it's a headless VM). Deploy = install to
`/usr/local/bin/kidulwm` + `systemctl restart kidulwm`.

```bash
cd /home/dad/dev/KidulWM
zig build -Doptimize=ReleaseSafe

scp -i ~/.ssh/id_ed25519_kidulwm \
  zig-out/bin/kidulwm zig-out/bin/kidulwm-control scripts/launch-kidul-terminal.sh \
  kidul@192.168.122.87:/tmp/

ssh -i ~/.ssh/id_ed25519_kidulwm kidul@192.168.122.87 \
  'echo kidul | sudo -S install -m 755 /tmp/kidulwm /usr/local/bin/kidulwm.new && \
   echo kidul | sudo -S mv /usr/local/bin/kidulwm.new /usr/local/bin/kidulwm && \
   echo kidul | sudo -S cp /tmp/launch-kidul-terminal.sh /usr/local/bin/ && \
   echo kidul | sudo -S chmod 755 /usr/local/bin/launch-kidul-terminal.sh && \
   echo kidul | sudo -S systemctl restart kidulwm'
# install + rename-swap, not plain cp: cp on a running binary = ETXTBSY.
```

Then verify:

```bash
ssh -i ~/.ssh/id_ed25519_kidulwm kidul@192.168.122.87 'systemctl is-active kidulwm'
ssh -i ~/.ssh/id_ed25519_kidulwm kidul@192.168.122.87 'echo kidul | sudo -S journalctl -u kidulwm -n 40 --no-pager'
```

## Offline binary patch (if VM is unreachable)

```bash
cd /home/dad/dev/KidulWM
zig build
sudo modprobe nbd max_part=8
sudo qemu-nbd --connect=/dev/nbd0 /var/lib/libvirt/images/cachyos-kidulwm.qcow2
sudo mkdir -p /mnt/vmroot && sudo mount /dev/nbd0p2 /mnt/vmroot
sudo cp zig-out/bin/kidulwm /mnt/vmroot/usr/bin/kidulwm
sudo chmod 755 /mnt/vmroot/usr/bin/kidulwm
sudo umount /mnt/vmroot && sudo qemu-nbd --disconnect /dev/nbd0
```

## Boot recovery (NO BOOTABLE DISK)

```bash
sudo modprobe nbd max_part=8
sudo qemu-nbd --connect=/dev/nbd0 /var/lib/libvirt/images/cachyos-kidulwm.qcow2
sudo mkdir -p /mnt/vmesp && sudo mount /dev/nbd0p1 /mnt/vmesp
sudo mkdir -p /mnt/vmesp/EFI/BOOT
sudo cp /mnt/vmesp/EFI/KIDUL/grubx64.efi /mnt/vmesp/EFI/BOOT/BOOTX64.EFI
sudo umount /mnt/vmesp && sudo qemu-nbd --disconnect /dev/nbd0

# recreate NVRAM
sudo rm -f /var/lib/libvirt/qemu/nvram/cachyos-kidulwm_VARS.fd
sudo cp /usr/share/edk2/x64/OVMF_VARS.4m.fd /var/lib/libvirt/qemu/nvram/cachyos-kidulwm_VARS.fd
sudo chown libvirt-qemu:libvirt-qemu /var/lib/libvirt/qemu/nvram/cachyos-kidulwm_VARS.fd
sudo chmod 660 /var/lib/libvirt/qemu/nvram/cachyos-kidulwm_VARS.fd

virsh -c qemu:///system start cachyos-kidulwm
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

## aig — the Kidul Zig toolchain (NEW DIRECTION, Aug 28 2026)

Repo: `https://codeberg.org/kidulwm/aig` (public, GPLv3 layer over upstream MIT).
Local: `/home/dad/dev/aig`. Docs: `README-AIG.md`, `BUILD-AIG.md`.

What it is: pinned fork of zig 0.16.0 RELEASE source + `a/` stdlib
extensions (`a.fs`, `a.img`, ...). Patch discipline in `patches/` —
nothing edits the tree without a patch file. No syntax changes in 0.x.

Why: the compiler was the last outside dependency deciding whether our
tree builds on any given morning (`std.fs` → `std.Io.Dir` mid-release,
an evening gone). Upstream roulette stops here. Updates to the toolchain
happen when WE pull, deliberately, never by surprise.

Status: bootstrap proven — aig builds from host zig and KidulWM built
with it is byte-identical to the in-service binary (sha 780eef98...).
Known gap: C compilation needs LLVM backend (milestone aig 0.1.1 —
cmake + clang21 at /usr/lib/llvm21 + `-Denable-llvm`). Until that lands,
host zig builds C-shim targets; aig already builds pure-Zig targets.

RULES (locked):
- No syntax changes in aig 0.x. Parser untouched.
- `a/` namespace for our additions; import `const a = @import("a");`
- Host zig is bootstrap seed exactly once; then aig builds aig.
- Resolved (Aug 29): the kidulwm-under-aig Sema panic was an upstream
  0.16.0 assert vs `[*c]` element-pointer routing, triggered by ONE
  line in files_card.zig (`&entry.*.d_name[0]` → array-decay form).
  kidulwm builds under aig now. Details: HANDOFF session 15. Policy:
  not reported upstream (in-house knowledge).
- Never track upstream master. We pull, we decide, we pin.

## Apocalypse drive backup (LaCie)

The LaCie-Apocalypse drive mounts at `/mnt/lacie-apocalypse`.
Backup = full-history git bundle + rsync'd source tree:

```bash
cd /home/dad/dev/KidulWM
git bundle create /tmp/kidulwm-apocalypse-$(date +%Y%m%d_%H%M).bundle --all
cp /tmp/kidulwm-apocalypse-*.bundle /mnt/lacie-apocalypse/
rsync -a /home/dad/dev/KidulWM/ /mnt/lacie-apocalypse/KidulWM-src/ \
  --exclude=.zig-cache --exclude=zig-out
```

Restore: `git clone kidulwm-apocalypse-<date>.bundle` gives the full repo.

## kmedia / PipeWire notes (fresh-one)

- The VM has no audio hardware. A null sink lives at
  `~/.config/pipewire/pipewire.conf.d/kidul-sink.conf` (adapter factory
  `support.null-audio-sink`, media.class `Audio/Sink`, monitor.passthrough).
  Do NOT use `libpipewire-module-null-sink` — not shipped on this setup.
- `pipewire-audio` package is required (pw-cat, SPA audio factories).
- wireplumber is the session manager (installed + enabled as user service).
- `kmedia-test` binary prints live band levels for debugging:
  `XDG_RUNTIME_DIR=/run/user/1000 /tmp/kmedia-test`

## knetd (network daemon — replaces NM/wpa_supplicant/dhcpcd)

Repo `/home/dad/dev/knetd`, binary `zig-out/bin/knetd`, installed
`/usr/local/bin/knetd`, unit `knetd.service`, log `/var/log/knetd.log`.

Control file is `/tmp/knet/cmd` — write a verb line, knetd picks it up
within 5s, truncates the file after processing. State is readable at
`/tmp/knet/state` and `/tmp/kidul-signals/network.detail`.

```bash
echo 'spoof wlan0 random'          > /tmp/knet/cmd   # or xx:xx:xx:xx:xx:xx
echo 'up wlan0'                    > /tmp/knet/cmd
echo 'down wlan0'                  > /tmp/knet/cmd
echo 'dhcp enp1s0'                 > /tmp/knet/cmd   # full DISCOVER flow
echo 'scan wlan0'                  > /tmp/knet/cmd   # results land in network.detail
echo 'connect wlan0 MySSID'        > /tmp/knet/cmd   # psk from store, else open
echo 'connect wlan0 MySSID secret' > /tmp/knet/cmd   # typed psk (dev loop)
echo 'save MySSID secret'          > /tmp/knet/cmd   # store, 0600 root:root
echo 'forget MySSID'               > /tmp/knet/cmd
echo 'reload'                      > /tmp/knet/cmd   # re-parse the store
```

Deploy to fresh-one (VM on qemu:///system, NAT 192.168.122.96):

```bash
export LIBVIRT_DEFAULT_URI=qemu:///system
cd /home/dad/dev/knetd && zig build
scp -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/knetd kidul@192.168.122.96:/tmp/knetd
ssh -i ~/.ssh/id_ed25519_kidulwm kidul@192.168.122.96 \
  'echo kidul | sudo -S systemctl stop knetd; echo kidul | sudo -S cp /tmp/knetd /usr/local/bin/knetd; echo kidul | sudo -S systemctl start knetd'
```

Flap test without losing SSH (guest-agent, no network needed):

```bash
virsh -c qemu:///system qemu-agent-command fresh-one \
  '{"execute":"guest-exec","arguments":{"path":"/usr/bin/ip","arg":["link","set","enp1s0","down"],"capture-output":true}}'
# poll the returned pid with guest-exec-status, then bring it back up the same way
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
