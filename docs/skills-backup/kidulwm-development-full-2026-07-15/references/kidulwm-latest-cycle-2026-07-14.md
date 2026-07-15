# KidulWM untouchable-latest cycle: 2026-07-14

This reference records the concrete VM names, disk sizes, ports, and commands used to rotate the KidulWM untouchable master and spin up a disposable work clone on 2026-07-14. Use it as a template for future cycles.

## Naming convention used

- Outgoing clone/source: `old-64gb-good` (copy of `cachyos-kidulwm-rounded-fun`, 64 GiB virtual disk)
- New promoted untouchable: `kidulwm-latest`
- Disposable work clone: `kidulwm-glass` — one per experiment, destroyed when the feature lands or fails

Target disk size for `kidulwm-latest`: 15 GiB usable, so the qcow2 was given 16 GiB virtual size to fit the 512 MiB ESP plus 15 GiB root partition. Actual qcow2 usage remained sparse (`~8.5 GiB` at rest after first boot) because the root filesystem was already only ~8 GiB used.

## What we tried and why

### First attempt: in-place fs + partition shrink of `old-64gb-good`

```bash
sudo qemu-nbd --connect=/dev/nbd0 /var/lib/libvirt/images/old-64gb-good.qcow2
sleep 1
sudo e2fsck -f -p /dev/nbd0p2
sudo resize2fs /dev/nbd0p2 14G
echo ',15G' | sudo sfdisk --no-reread -N 2 /dev/nbd0
sudo qemu-nbd --disconnect /dev/nbd0
```

Then `qemu-img convert` to a new qcow2 and resize it to 16 GiB. Result: the new VM dropped to emergency mode because CachyOS initramfs references the root filesystem by UUID, and the converted qcow2 changed the disk/partition UUID seen by the bootloader. This is the UUID drift pitfall described in `references/vm-shrink-and-uuid-drift.md`.

### Fallback: fresh install from ISO (abandoned)

A 2.85 GiB CachyOS ISO existed at `/home/dad/iso's/cachyos-desktop-linux-260426.iso`. Installing interactively from ISO is accurate but slow; it was not needed because the disposable-clone path below got us back to a runnable system faster.

### Working path: disposable clone for the experiment

Since `old-64gb-good` was itself a fresh copy of the known-good `-fun` VM, we abandoned the resize/promotion for this session and created a thin-provisioned, writable overlay clone for the peek-glass work.

```bash
# Create a COW clone
sudo qemu-img create -f qcow2 -F qcow2 -b /var/lib/libvirt/images/cachyos-kidulwm-rounded-fun.qcow2 \
  /var/lib/libvirt/images/kidulwm-glass.qcow2
sudo chown libvirt-qemu:libvirt-qemu /var/lib/libvirt/images/kidulwm-glass.qcow2
```

```xml
<domain type='kvm'>
  <name>kidulwm-glass</name>
  <uuid>eefaf8bd-4325-4759-887c-171e7c08f8ca</uuid>
  <!-- clone of cachyos-kidulwm-rounded-fun XML, disk pointed at kidulwm-glass.qcow2, backingStore removed, unique MAC 52:54:00:63:84:08 -->
</domain>
```

```bash
virsh -c qemu:///system define /tmp/kidulwm-glass.xml
virsh -c qemu:///system start kidulwm-glass
virsh -c qemu:///system qemu-monitor-command kidulwm-glass --hmp 'hostfwd_add tcp::2225-:22'
```

Work port for `kidulwm-glass`: `2225`. Build, deploy, and connect on that port only until the peek-glass feature is verified.

## Port allocation used this cycle

| VM | SSH port | Status |
|----|----------|--------|
| `cachyos-kidulwm` | 2222 | Untouchable rounded-best |
| `cachyos-kidulwm-chamfer` | 2223 | Untouchable archived chamfer-best |
| `cachyos-kidulwm-rounded-fun` | — | Source/good copy (can be running or shut off) |
| `old-64gb-good` | — | Source of truth while resize was attempted; kept intact |
| `kidulwm-glass` | 2225 | Active work clone for peek-glass tray experiment |

## Resume recipe

When returning to this branch:
1. Verify which VM is currently the promoted untouchable (`kidulwm-latest` or `cachyos-kidulwm-rounded-fun`).
2. If no `kidulwm-latest` exists yet, either retry the resize+UUID fix from `old-64gb-good`, or recreate it from the current good VM.
3. Create a fresh disposable clone for the next experiment; do not reuse `kidulwm-glass` across features.

## Related

- `references/vm-untouchables-discipline.md` — why we clone before touching.
- `references/vm-shrink-and-uuid-drift.md` — the UUID-drift pitfall encountered during the resize attempt.
- `references/live-vm-clone-side-by-side.md` — for true side-by-side comparison of two builds.
