# KidulWM / KidulDM — known-good commands

Live reference.  Check here first instead of guessing.

## Standard paths (FHS)

- Source repo: `/home/dad/dev/KidulWM`
- Build artifacts: `zig-out/bin/kidulwm`, `zig-out/bin/kiduldm`
- Installed binaries: `/usr/bin/kidulwm`, `/usr/bin/kiduldm`
- System config: `/etc/kidulwm/`
- Static assets: `/usr/share/kidulwm/`
- User config: `~/.config/kidulwm/`
- Runtime sockets: `/run/user/1000/`
- Logs: `journalctl -u kidulwm`

## Build / test on host

```bash
cd /home/dad/dev/KidulWM
zig build
zig build test
WAYLAND_DISPLAY=wayland-1 bash scripts/nested-smoke.sh
bash scripts/nested-three-window.sh
```

## VM lifecycle — always use qemu:///system

Default `virsh` connects to `qemu:///session` and will fail for this VM.

```bash
virsh -c qemu:///system list --all
virsh -c qemu:///system start cachyos-kidulwm
virsh -c qemu:///system shutdown cachyos-kidulwm
virsh -c qemu:///system destroy cachyos-kidulwm
```

## VM display / console access

SPICE check:
```bash
nc -zv 127.0.0.1 5900
remote-viewer spice://127.0.0.1:5900
```

Serial console (interactive, needs pty):
```bash
virsh -c qemu:///system console cachyos-kidulwm
```

## SSH into the VM

The VM uses QEMU user-mode networking (SLIRP). Add a host port forward once after start.
If no key is injected, use guest agent to add one (the `kidul` account has no password):

```bash
virsh -c qemu:///system qemu-monitor-command cachyos-kidulwm --hmp 'hostfwd_add tcp::2222-:22'
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519_kidulwm -C 'kidulwm@dotrix.org'
virsh -c qemu:///system qemu-agent-command cachyos-kidulwm --cmd '{"execute":"guest-ssh-add-authorized-keys","arguments":{"username":"kidul","keys":["$(cat ~/.ssh/id_ed25519_kidulwm.pub)"]}}'
ssh -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1
```

## Deploy a new KidulWM binary

Offline copy is more reliable because the running guest is hard to reach:

```bash
cd /home/dad/dev/KidulWM
zig build
virsh -c qemu:///system shutdown cachyos-kidulwm
# wait for "shut off"; destroy if it hangs
sudo modprobe nbd max_part=8
sudo qemu-nbd --connect=/dev/nbd0 /var/lib/libvirt/images/cachyos-kidulwm.qcow2
sudo mkdir -p /mnt/vmroot && sudo mount /dev/nbd0p2 /mnt/vmroot
sudo cp zig-out/bin/kidulwm /mnt/vmroot/usr/bin/kidulwm
sudo chmod 755 /mnt/vmroot/usr/bin/kidulwm
sudo umount /mnt/vmroot && sudo qemu-nbd --disconnect /dev/nbd0
virsh -c qemu:///system start cachyos-kidulwm
```

Verify:
```bash
ssh -p 2222 kidul@127.0.0.1 'systemctl status kidulwm --no-pager'
ssh -p 2222 kidul@127.0.0.1 'journalctl -u kidulwm -n 40 --no-pager'
```

## Open windows in the VM

- Via SPICE keyboard: `Mod+Return` spawns `/usr/bin/ghostty`.
- Via SSH: `ssh -p 2222 kidul@127.0.0.1 'WAYLAND_DISPLAY=wayland-1 ghostty'`

## Compositor-side tray status

`src/tray.zig` has been removed. GTK4 dashboard will own the tray/panels once the core window path is solid; remove this note when `TrayManager` work resumes.

## Boot recovery (NO BOOTABLE DISK)

If the OVMF GUI reports "NO BOOTABLE DISK":

```bash
# 1. Shut off the VM and mount its ESP
sudo modprobe nbd max_part=8
sudo qemu-nbd --connect=/dev/nbd0 /var/lib/libvirt/images/cachyos-kidulwm.qcow2
sudo mkdir -p /mnt/vmesp && sudo mount /dev/nbd0p1 /mnt/vmesp
sudo mkdir -p /mnt/vmesp/EFI/BOOT
sudo cp /mnt/vmesp/EFI/KIDUL/grubx64.efi /mnt/vmesp/EFI/BOOT/BOOTX64.EFI
sudo umount /mnt/vmesp && sudo qemu-nbd --disconnect /dev/nbd0

# 2. Recreate NVRAM
sudo rm -f /var/lib/libvirt/qemu/nvram/cachyos-kidulwm_VARS.fd
sudo cp /usr/share/edk2/x64/OVMF_VARS.4m.fd /var/lib/libvirt/qemu/nvram/cachyos-kidulwm_VARS.fd
sudo chown libvirt-qemu:libvirt-qemu /var/lib/libvirt/qemu/nvram/cachyos-kidulwm_VARS.fd
sudo chmod 660 /var/lib/libvirt/qemu/nvram/cachyos-kidulwm_VARS.fd

virsh -c qemu:///system start cachyos-kidulwm
```

## NVRAM recovery

If start fails with `Could not open ... VARS.fd: Permission denied`:

```bash
sudo rm -f /var/lib/libvirt/qemu/nvram/cachyos-kidulwm_VARS.fd
sudo cp /usr/share/edk2/x64/OVMF_VARS.4m.fd /var/lib/libvirt/qemu/nvram/cachyos-kidulwm_VARS.fd
sudo chown libvirt-qemu:libvirt-qemu /var/lib/libvirt/qemu/nvram/cachyos-kidulwm_VARS.fd
sudo chmod 660 /var/lib/libvirt/qemu/nvram/cachyos-kidulwm_VARS.fd
```

## Commands that fail

| Command | Why |
|---|---|
| `virsh start cachyos-kidulwm` | Uses `qemu:///session`; VM is on `qemu:///system`. |
| `virsh qemu-agent-command cachyos-kidulwm ...` | Guest agent is not currently responsive; use SSH via hostfwd. |
| `pkill -9 qemu` | Blocked by Hermes safety guard; use `virsh -c qemu:///system destroy`. |
| `zig build` inside the VM guest | Toolchain not set up there; build on host and deploy. |
