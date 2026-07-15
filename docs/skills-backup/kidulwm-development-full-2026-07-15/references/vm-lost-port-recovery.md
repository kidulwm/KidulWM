# Recovering a lost host SSH port forward on a KidulWM VM

Date: 2026-07-14
Context: `cachyos-kidulwm-rounded-fun` had SSH-only access through host port 2224, but the forward disappeared after a reboot.

## What happened

The VM was originally opened on `qemu:///system`. Its SSH port forward was added dynamically via the QEMU monitor with `hostfwd_add tcp::2224-:22`. A later reboot or start from a different libvirt connection dropped that forward, so `ssh -p 2224` refused the connection even though the VM was running.

## How to tell

```bash
virsh -c qemu:///system list --all
cat /var/log/libvirt/libvirtd.log | tail -n 50
ss -ltn | grep 2224
```

If the VM is running on `qemu:///system` but the port is not listening, the forward is gone.

## Recovery options

### Option A: Re-add the monitor forward (if the VM is already running)

```bash
virsh -c qemu:///system qemu-monitor-command cachyos-kidulwm-rounded-fun \
  --hmp 'hostfwd_add tcp::2224-:22'
```

Then test:

```bash
ssh -p 2224 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1
```

This lasts only until the VM stops. If the forward must survive restarts, make it permanent in the libvirt XML network or the domain's QEMU command line.

### Option B: Use the guest IP directly

If `qemu-guest-agent` is running inside the VM, get the IP:

```bash
virsh -c qemu:///system qemu-agent-command cachyos-kidulwm-rounded-fun \
  '{"execute":"guest-network-get-interfaces"}'
```

Look for the first non-loopback IPv4 on the `192.168.122.0/24` range. Then:

```bash
ssh -i ~/.ssh/id_ed25519_kidulwm kidul@<ip>
```

### Option C: Rescue via guest agent

If you cannot re-add the forward and the guest IP is unreachable, use `guest-exec` to run commands directly. See `references/vm-qemu-guest-agent-ops.md`.

## Prevention

For a disposable clone used in day-to-day development, consider defining a libvirt domain with a static hostfwd XML snippet or a permanent `default` network DHCP reservation + static NAT rule, so the SSH port survives reboots. Keep the original Untouchable VMs shut off.
