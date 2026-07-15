# Shrinking a KidulWM VM disk without breaking the bootloader

When you copy a running CachyOS/KidulVM image into a smaller qcow2 (e.g., to make a 16 GB `kidulwm-latest` untouchable), the guest may drop to emergency mode because the initramfs and/or bootloader still reference the **old root filesystem UUID**. This guide covers the safe conversion path and the recovery.

## What happened

- Source: `old-64gb-good.qcow2` (64 GiB virtual, ~8.4 GiB actual, root on `/dev/vda2`).
- Goal: a 16 GiB `kidulwm-latest.qcow2` clone with identical contents.
- Steps used:
  1. `resize2fs /dev/nbd0p2 14G` to shrink the filesystem.
  2. `sfdisk -N 2 ... ,15G` to shrink the partition to fit a 15–16 GiB disk.
  3. `qemu-img convert` to a new qcow2, then `qemu-img resize --shrink ... 15G` and later to 16 G.
- Result: the new image boots into emergency mode because the initramfs cannot find the root device by UUID. Converting does not preserve the disk UUID / partition UUID, and the initramfs fstab/cmdline still contain the old values.

## Recovery

1. Boot the broken VM from a Linux live ISO (e.g., Arch/CachyOS installer ISO) via libvirt.
2. Inside the live environment, mount the VM's root partition and ESP.
3. Update the root UUID references:
   - `/etc/fstab` on the root partition.
   - `/etc/kernel/cmdline` on the root partition (CachyOS/Arch kernel-install style).
   - `/boot/loader/entries/*.conf` if using systemd-boot.
   - `/etc/default/grub` plus `grub-mkconfig` if using GRUB.
4. Regenerate the initramfs from the chroot so it knows the new UUID, or switch the kernel command line to `root=/dev/vda2` as a resilient fallback.
5. Regenerate the bootloader config if needed.
6. Shut down, detach the ISO, and boot again.

Alternatively, before converting, boot the source VM and change the kernel command line to use `root=/dev/vda2` instead of UUID. Then clone/shrink; the new image will boot because the device path is stable across qcow2 conversions.

## Prevention checklist

- [ ] Before any image copy that will become a new VM, check `cat /etc/kernel/cmdline` and `/etc/fstab` for UUID-based root references.
- [ ] Prefer `root=/dev/vda2` for transient/dev VMs when the root disk is always `vda`.
- [ ] After creating a new VM from a cloned/shrunk image, always capture a QEMU monitor screendump on first boot (`screendump /tmp/<vm>-boot.ppm`) to verify it reached the login/desktop, not emergency mode.
- [ ] Do not assume SSH on a port forward means the VM booted successfully; verify visually if the compositor depends on display/SeatD.

## Preconditions

- Host can run `qemu-nbd`, `resize2fs`, `e2fsck`, and `sfdisk` or `parted`.
- VM uses CachyOS-style layout with a 512 MiB EFI partition and a root ext4 partition on `vda2`.

## Related

- `references/vm-binary-deploy.md` for offline binary swaps into a working VM.
- `references/vm-untouchables-discipline.md` for cloning policy and port assignment.
