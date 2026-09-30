# KidulWM — Apocalypse backup (slice)

Read only for backup work. Host core is KNOWN_CMDS.md.

## Apocalypse drive backup (LaCie)

The LaCie-Apocalypse drive mounts at `/mnt/lacie-apocalypse`.
Backup = full-history git bundle + rsync'd source tree:

```bash
cd /home/dad/dev/KidulWM
git bundle create /tmp/kidulwm-apocalypse-$(date +%Y%m%d_%H%M).bundle --all
cp /tmp/kidulwm-apocalypse-*.bundle /mnt/lacie-apocalypse/
rsync -a /home/dad/dev/KidulWM/ /mnt/lacie-apocalypse/KidulWM-src/ \
  --exclude=.zig-cache --exclude=zig-out
```

Restore: `git clone kidulwm-apocalypse-<date>.bundle` gives the full repo.
