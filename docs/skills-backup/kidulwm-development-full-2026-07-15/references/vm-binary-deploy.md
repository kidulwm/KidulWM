# Offline VM binary deployment for KidulWM

Use this when the VM is running KidulWM and you cannot SSH in while the compositor is active, or when you want a clean binary swap without starting a shell inside the VM.

## Preconditions

- Host has `qemu-nbd` and `nbd` kernel module support.
- VM disk is a qcow2 file at `/var/lib/libvirt/images/cachyos-kidulwm.qcow2`.
- The root filesystem is on the second partition of the image.
- Build is done on the host in `/home/dad/dev/KidulWM`.

## Steps

1. Shut down the VM cleanly.

```bash
virsh -c qemu:///system shutdown cachyos-kidulwm
for i in $(seq 1 20); do
  virsh -c qemu:///system list --all | grep -q 'shut off' && break
  sleep 1
done
```

2. Mount the VM root disk via qemu-nbd.

```bash
cd /home/dad/dev/KidulWM
sudo modprobe nbd max_part=8
sudo qemu-nbd --connect=/dev/nbd0 /var/lib/libvirt/images/cachyos-kidulwm.qcow2
sudo mkdir -p /mnt/vmroot
sudo mount /dev/nbd0p2 /mnt/vmroot
```

3. Copy the freshly built binary into the VM filesystem.

```bash
sudo cp zig-out/bin/kidulwm /mnt/vmroot/usr/bin/kidulwm
sudo chmod 755 /mnt/vmroot/usr/bin/kidulwm
sync
```

4. Unmount and disconnect the NBD device.

```bash
sudo umount /mnt/vmroot
sudo qemu-nbd --disconnect /dev/nbd0
```

5. Start the VM and forward the SSH port if needed.

```bash
virsh -c qemu:///system start cachyos-kidulwm
sleep 3
virsh -c qemu:///system qemu-monitor-command cachyos-kidulwm --hmp 'hostfwd_add tcp::2222-:22'
```

6. Spawn test clients (e.g. Ghostty) over SSH.

```bash
ssh -p 2222 -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
  -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'for i in 1 2; do WAYLAND_DISPLAY=wayland-1 ghostty & done; sleep 1; echo spawned'
```

## Pitfalls

- If the SSH host key for `[127.0.0.1]:2222` changes (common when redeploying VMs), use `StrictHostKeyChecking=accept-new` or remove the stale entry from `~/.ssh/known_hosts`.
- Do not leave the VM root filesystem mounted while the VM is running.
- The partition number (`/dev/nbd0p2`) may differ on other images; verify with `lsblk` after connecting.

## Related files

- `KNOWN_CMDS.md` in the KidulWM repo for project-specific commands.
