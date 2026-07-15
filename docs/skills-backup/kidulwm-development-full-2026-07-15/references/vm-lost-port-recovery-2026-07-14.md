# VM deploy when SSH port forward is missing — 2026-07-14

## Scenario

The VM boots but the libvirt SSH port forward (e.g., `2222`, `2224`) is not present, so `scp`/`ssh` fails with `Connection refused`.

## QEMU guest agent alternative

Use `virsh -c qemu:///system qemu-agent-command <vm> '{"execute":"guest-network-get-interfaces"}'` to discover the guest IP (often `10.0.2.15` in QEMU user networking).

## HTTP fallback deploy

Instead of trying to base64 a large binary through `guest-exec` (argument list too long), serve the files over HTTP on the host and download them from inside the VM via the QEMU user gateway `10.0.2.2`.

### Host side

```bash
cd /home/dad/dev/KidulWM
python3 -m http.server 8765 --bind 127.0.0.1 --directory zig-out/bin
```

Place both `kidulwm` and `keybinds.conf` in the served directory.

### Guest side

```bash
systemctl stop kidulwm
curl -fsS -o /tmp/kidulwm.new http://10.0.2.2:8765/kidulwm
curl -fsS -o /tmp/keybinds.conf.new http://10.0.2.2:8765/keybinds.conf
cp /tmp/kidulwm.new /usr/bin/kidulwm
mkdir -p ~/.config/kidulwm
cp /tmp/keybinds.conf.new ~/.config/kidulwm/keybinds.conf
chmod +x /usr/bin/kidulwm
systemctl start kidulwm
```

## Checklist

- [ ] VM domain name includes `cachyos-kidulwm-rounded-fun` or the intended disposable clone.
- [ ] QEMU guest agent is running inside the VM.
- [ ] Host HTTP server is bound to `127.0.0.1` so QEMU user networking can reach it via `10.0.2.2`.
- [ ] Stop `kidulwm.service` before overwriting `/usr/bin/kidulwm` to avoid `Text file busy`.
- [ ] Verify with `systemctl is-active kidulwm` and `tail -n 20 /tmp/kidulwm-service.log`.
