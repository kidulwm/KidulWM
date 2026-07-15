# Deploy path mismatch pitfall

Session: 2026-07-14 (`kidulwm-glass` deploy after peek-glass build).

The KidulWM systemd service specified `ExecStart=/usr/bin/kidulwm`. I copied the new binary to `/usr/local/bin/kidulwm`, started the service, and it continued running the old `/usr/bin/kidulwm` binary. The new code was effectively not deployed.

## Rule

Always verify the service's `ExecStart=` path before copying a new binary:

```bash
ssh -p <port> -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 'cat /etc/systemd/system/kidulwm.service | grep ExecStart='
```

Copy to **that exact path** (on CachyOS KidulVM this is `/usr/bin/kidulwm`, not `/usr/local/bin/kidulwm`).

## Full deploy command

```bash
cd /home/dad/dev/KidulWM
zig build
scp -P 2225 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm.new
ssh -p 2225 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && \
   sudo cp /tmp/kidulwm.new /usr/bin/kidulwm && \
   sudo chmod 755 /usr/bin/kidulwm && \
   sudo systemctl start kidulwm && \
   systemctl is-active kidulwm'
```

## Why stop first

A running binary is memory-mapped. Copying over it while `kidulwm` is active gives `cp: cannot create regular file '/usr/bin/kidulwm': Text file busy` even with `sudo`. Stopping the service releases the mapping.
