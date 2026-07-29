# KidulWM / KidulDM — known-good commands

Live reference. Verified commands only. If a command is here, it worked.

## Quick paths

| Thing | Path |
|---|---|
| Source repo | `/home/dad/dev/KidulWM` |
| Build out | `zig-out/bin/kidulwm`, `zig-out/bin/kidulwm-control` |
| Installed system | `/usr/bin/kidulwm`, `/usr/bin/kidulwm-control` |
| Service log | `/tmp/kidulwm-service.log` |
| System config | `/etc/kidulwm/` |
| User config | `~/.config/kidulwm/` |
| Runtime | `/run/user/1000/` |

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

## SSH into a VM

`fresh-one`: `kidul@127.0.0.1:2260`
`cachyos-kidulwm`: setup depends on hostfwd below.

Use the existing key:

```bash
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1
```

If a VM does not have SSH forwarding yet, add one after it starts:

```bash
# for fresh-one, port 2260 -> guest 22
virsh -c qemu:///system qemu-monitor-command fresh-one --hmp 'hostfwd_add tcp::2260-:22'

# for cachyos-kidulwm, port 2222 -> guest 22
virsh -c qemu:///system qemu-monitor-command cachyos-kidulwm --hmp 'hostfwd_add tcp::2222-:22'
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519_kidulwm -C 'kidulwm@dotrix.org'
ssh -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1
```

If the VM rejects the key, inject it via guest agent — but first the agent must be running:

```bash
virsh -c qemu:///system qemu-agent-command fresh-one --cmd '{"execute":"guest-ssh-add-authorized-keys","arguments":{"username":"kidul","keys":["$(cat ~/.ssh/id_ed25519_kidulwm.pub)"]}}'
```

If guest agent is not responsive, use the SPICE console or the serial console instead.

## Deploy KidulWM to a VM

```bash
cd /home/dad/dev/KidulWM
zig build

scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm \
  zig-out/bin/kidulwm zig-out/bin/kidulwm-control \
  kidul@127.0.0.1:/tmp/

ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm /tmp/kidulwm-control /usr/bin/ && sudo systemctl start kidulwm'
```

Then verify:

```bash
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 'systemctl status kidulwm --no-pager'
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 'journalctl -u kidulwm -n 40 --no-pager'
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 'tail -n 40 /tmp/kidulwm-service.log'
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

## Commands that fail

| Command | Why |
|---|---|
| `virsh start fresh-one` | Uses `qemu:///session`; VMs are on `qemu:///system`. |
| `virsh qemu-agent-command ...` | Agent may not be ready; try again or use SPICE/SSH. |
| `pkill -9 qemu` | Blocked by Hermes safety guard; use `virsh -c qemu:///system destroy`. |
| `zig build` inside VM guest | Toolchain not set up there; build on host and deploy. |

## Verified on

- Host: CachyOS x86_64, Linux 7.1.3-1-cachyos
- Zig 0.15.0-dev-ish
- libvirt / qemu from pacman
