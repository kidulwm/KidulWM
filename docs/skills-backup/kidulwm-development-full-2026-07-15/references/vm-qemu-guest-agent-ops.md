# VM diagnostics via QEMU guest agent

Date: 2026-07-14
Context: Host SSH port forward lost; used `qemu-guest-agent` to read VM state and logs.

## When to use this

- The VM is running and reachable by libvirt (`qemu:///system`) but the usual host SSH port is refused.
- A graphical console is not available and you still need to inspect logs, service state, or files.

## Basic ping

```bash
virsh -c qemu:///system qemu-agent-command cachyos-kidulwm-rounded-fun '{"execute":"guest-ping"}'
```

## Run a command and collect output

`guest-exec` returns a PID immediately. Poll it with `guest-exec-status`:

```bash
virsh -c qemu:///system qemu-agent-command cachyos-kidulwm-rounded-fun \
  '{"execute":"guest-exec","arguments":{"path":"/bin/sh","arg":["-c","systemctl is-active kidulwm"],"capture-output":true}}'
# -> {"return":{"pid":NNN}}

sleep 1

virsh -c qemu:///system qemu-agent-command cachyos-kidulwm-rounded-fun \
  '{"execute":"guest-exec-status","arguments":{"pid":NNN}}'
# -> {"return":{"exitcode":0,"out-data":"YWN0aXZ...","exited":true}}
```

Decode `out-data` with `base64 -d`. Do not pass `timeout` to `guest-exec`; it is rejected.

## Get VM IP for scp

```bash
virsh -c qemu:///system qemu-agent-command cachyos-kidulwm-rounded-fun \
  '{"execute":"guest-network-get-interfaces"}'
```

Look for the first non-loopback IPv4 address. If the address is reachable from the host (e.g., `192.168.122.x` on the libvirt default network), you can scp/ssh directly to it.

## Watch the size limit

`guest-exec` arguments are passed as a single JSON string to `virsh qemu-agent-command`. A large payload (for example base64-encoding an 18 MiB binary in the JSON command) will hit the kernel argument limit:

```
OSError: [Errno 7] Argument list too long: 'virsh'
```

For big file transfers, prefer scp to the guest IP or `guest-file-*` primitives, not `guest-exec` with inlined base64.

## Useful one-liners

Service status and latest log tail:

```bash
journalctl -u kidulwm -n 50 --no-pager; echo '---'; tail -n 50 /tmp/kidulwm-service.log
```

Input devices:

```bash
ls -l /dev/input/by-id/; ls -l /dev/input/event*
```
