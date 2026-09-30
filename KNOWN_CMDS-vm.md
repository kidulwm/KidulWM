# KidulWM — VM commands (slice)

Read only for VM work. Host core is KNOWN_CMDS.md.

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
