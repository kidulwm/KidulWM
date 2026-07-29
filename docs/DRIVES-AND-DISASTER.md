# Drives, Backup, and Disaster Recovery

Verified commands for handling disks, drives, and apocalypse recovery.
Format: **Linux/BSD only**. Windows and macOS are intentionally not supported.

## LaCie Apocalypse drive

| Property | Value |
|---|---|
| Device path | `/dev/sdb1` |
| UUID | `7672a543-bac2-4453-8c1f-b0e2bcae1392` |
| Filesystem | btrfs |
| Label | `LaCie-Apocalypse` |
| Mount point | `/mnt/lacie-apocalypse` |

## Remount the drive

```bash
sudo mkdir -p /mnt/lacie-apocalypse
sudo mount UUID=7672a543-bac2-4453-8c1f-b0e2bcae1392 /mnt/lacie-apocalypse
```

To mount automatically at boot:

```bash
echo 'UUID=7672a543-bac2-4453-8c1f-b0e2bcae1392 /mnt/lacie-apocalypse btrfs defaults,noatime,compress=zstd:1,nofail,x-gvfs-show 0 2' | sudo tee -a /etc/fstab
```

## Run the apocalypse backup now

```bash
bash /mnt/lacie-apocalypse/hermes-apocalypse/restore-scripts/backup-now.sh
```

This re-copies `~/.hermes`, `~/dev`, `~/bobsBrain`, `~/kidul-archives`, SSH/GPG keys, selected `~/.config`, package manifests, libvirt XMLs, NVRAM, local binaries, and both VMs.

## Recreate the drive from scratch

Only if the drive is corrupted or replaced.

```bash
# identify the device safely first
lsblk -f

# replace /dev/sdb1 with the actual device
sudo umount /mnt/lacie-apocalypse 2>/dev/null || true
sudo wipefs -af /dev/sdb1
sudo mkfs.btrfs -f -L "LaCie-Apocalypse" /dev/sdb1

UUID=$(sudo blkid -s UUID -o value /dev/sdb1)
echo "UUID=$UUID /mnt/lacie-apocalypse btrfs defaults,noatime,compress=zstd:1,nofail,x-gvfs-show 0 2"
```

Then replace the old UUID in `/etc/fstab` with the new one and run `backup-now.sh`.

## Inspect the archive

```bash
ls -la /mnt/lacie-apocalypse/hermes-apocalypse/
du -sh /mnt/lacie-apocalypse/hermes-apocalypse/*
df -h /mnt/lacie-apocalypse
```

## Verify VM backups are sparse and intact

```bash
for f in /mnt/lacie-apocalypse/hermes-apocalypse/virtual-machines/*.qcow2; do
  echo "=== $f ==="
  qemu-img info --force-share "$f" | grep -E 'virtual size|disk size|corrupt'
done
```

A healthy backup shows `disk size` around 5-6GB and `virtual size` around 64GB.

## Restore to a new machine

See the included recovery guide:

```bash
cat /mnt/lacie-apocalypse/hermes-apocalypse/APOCALYPSE-RESTORE-GUIDE.md
```

Copy that file and keep it somewhere readable without needing a backup.

## General drive inspection

```bash
# all block devices
lsblk -f

# partition UUIDs
sudo blkid

# mount status
df -h
findmnt

# btrfs health
sudo btrfs filesystem df /mnt/lacie-apocalypse
sudo btrfs device stats /mnt/lacie-apocalypse
```

## Important safety rules

1. Always use `UUID=` in `/etc/fstab`, never `sdX` letters.
2. Run `mkfs` manually, not through the agent.
3. Sparse files must be copied with `cp --sparse=always` or `rsync -S`.
4. VM `qcow2` images must never be copied while running unless using a live snapshot.
5. Keep one backup off-machine or at least unplug the drive after backing up.

## What's in the archive

| Path | Contents |
|---|---|
| `hermes/` | `~/.hermes` profiles, skills, memories, cron, plugins |
| `dev/` | `~/dev` projects (excludes build artifacts) |
| `bobsBrain/` | notes |
| `kidul-archives/` | archived KidulWM assets |
| `configs/` | selected `~/.config` folders and dotfiles |
| `ssh_gpg/` | SSH keys and GPG keyring |
| `system/` | package lists, fstab, libvirt XMLs, NVRAM, local bins |
| `virtual-machines/` | `fresh-one.qcow2`, `cachyos-kidulwm.qcow2` |
| `APOCALYPSE-RESTORE-GUIDE.md` | human restore instructions |
| `restore-scripts/backup-now.sh` | refresh script |
