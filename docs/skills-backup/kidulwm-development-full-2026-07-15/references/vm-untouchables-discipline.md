# Untouchable VM discipline for KidulWM development

## Principle

Some VMs hold known-good states that must never be touched by experimental deployments. Treat them as **Untouchables**: they stay shut off or read-only while risky work happens in disposable clones.

## Current Untouchables

| VM name | Role | SSH port | SPICE port | Why untouchable |
|---------|------|----------|------------|-----------------|
| `cachyos-kidulwm` | rounded-best (default CachyOS rounded build) | 2222 | auto/5900 | Last known-good rounded-corner binary; Barticus' reference screen. |
| `cachyos-kidulwm-chamfer` | chamfer-best (final archived CachyOS chamfer) | 2223 | auto/5902 | Best archived chamfer state; clip fix did not land here, so this is the snapshot before abandonment. |

Both should normally be **shut off** while experimenting. Power on only to copy from them or to do a final visual regression check.

## Archived artifact

The last good chamfer binary is saved on the host at:

```
/home/dad/kidul-archives/kidulwm-chamfer-best
md5: 2ff051af9fbc9cf76c4acf01d6a482bb
```

Restoring it to the chamfer VM:

```bash
scp -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -P 2223 -i ~/.ssh/id_ed25519_kidulwm \
  /home/dad/kidul-archives/kidulwm-chamfer-best \
  kidul@127.0.0.1:/tmp/kidulwm.restore

ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -p 2223 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm.restore /usr/bin/kidulwm && sudo chmod 755 /usr/bin/kidulwm && sudo systemctl start kidulwm && systemctl is-active kidulwm'
```

## Creating an experimental rounded clone

1. Shut off originals so they cannot be confused.
2. Use `virt-clone` from the rounded-best VM.
3. Start the clone and add a unique SSH port forward via QEMU monitor.

```bash
virsh -c qemu:///system shutdown cachyos-kidulwm
virsh -c qemu:///system shutdown cachyos-kidulwm-chamfer
virt-clone --connect qemu:///system \
  --original cachyos-kidulwm \
  --name cachyos-kidulwm-rounded-fun \
  --file /var/lib/libvirt/images/cachyos-kidulwm-rounded-fun.qcow2
virsh -c qemu:///system start cachyos-kidulwm-rounded-fun
sleep 15
virsh -c qemu:///system qemu-monitor-command cachyos-kidulwm-rounded-fun --hmp 'hostfwd_add tcp::2224-:22'
```

Use port 2224 for the rounded-fun clone. Verify the IP and forward exist with:

```bash
virsh -c qemu:///system qemu-agent-command cachyos-kidulwm-rounded-fun '{"execute":"guest-network-get-interfaces"}'
virsh -c qemu:///system qemu-monitor-command cachyos-kidulwm-rounded-fun --hmp 'info hostfwd'
```

## Pre-deploy checklist

Before every binary copy, confirm all three:

1. **VM name** matches the intended target.
2. **SSH port** matches the VM name from the table above.
3. **Build** matches the intended branch/variant.

If any doubt, stop and ask. A wrong-port deploy can overwrite the wrong Untouchable.

## Naming convention for future clones

- `cachyos-kidulwm` — base good rounded. Untouchable.
- `cachyos-kidulwm-chamfer` — base archived chamfer. Untouchable.
- `cachyos-kidulwm-rounded-<experiment>` — disposable clone for rounded experiments.
- `cachyos-kidulwm-chamfer-<experiment>` — disposable clone for chamfer/Gentoo experiments.
- `<experiment>` should be short and memorable, e.g. `rounded-bg`, `rounded-opaque`, `rounded-anim`.
