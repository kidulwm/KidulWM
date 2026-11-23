#!/usr/bin/env bash
# boot-watch.sh — read back the KSD tower boot trace from nvme1n1 (the m.2).
# Run from the HOST after a tower boot cycle (the tower boots on this same box,
# not a miniPC). READ-ONLY: mounts KSD-root ro, dumps the persisted logs, greps
# the verdict, and lists any EFI pstore panic dumps. No writes to the drive.
#
# House boot trail (all persistent on the m.2, none on tmpfs):
#   kernel.log        kboot drains /dev/kmsg -> /var/log/kernel.log
#   kboot.log         kboot's own log (forked logdrain / devrule / kushd spawn)
#   kushd.log         kushd seating + re-seat trail
#   kushd-<act>.log   per-act stdio (redirectStdio) — e.g. kushd-kidulwm.log
#
# Success markers (conductor-reconnect probe, Phase A):
#   "seated kidulwm" with class=conductor, uid 990; NO "died kidulwm",
#   NO "refused", NO "kernel panic".
#
# Usage:  sudo ./boot-watch.sh
set -uo pipefail

ROOT_DEV=/dev/disk/by-label/KSD-root
MNT=/mnt/ksd

if ! mountpoint -q "$MNT" 2>/dev/null; then
  sudo mount -o ro "$ROOT_DEV" "$MNT" || { echo "boot-watch: mount $ROOT_DEV failed" >&2; exit 1; }
fi

L="$MNT/var/log"
echo "===================== KSD BOOT WATCH $(date '+%F %T') ====================="

echo
echo "[1] kernel.log tail (boot up to kboot/kushd):"
sudo tail -45 "$L/kernel.log" 2>/dev/null || echo "   (no kernel.log)"

echo
echo "[2] kboot.log tail:"
sudo tail -30 "$L/kboot.log" 2>/dev/null || echo "   (no kboot.log)"

echo
echo "[3] kushd.log tail (seating + re-seat):"
sudo tail -50 "$L/kushd.log" 2>/dev/null || echo "   (no kushd.log)"

echo
echo "[4] kidulwm act log tail:"
sudo tail -30 "$L/kushd-kidulwm.log" 2>/dev/null || echo "   (no kushd-kidulwm.log)"
echo "   other act logs present:"; ls "$L"/kushd-*.log 2>/dev/null | sed 's#.*/##' || echo "   (none)"

echo
echo "===================== VERDICT ====================="
echo "-- CONDUCTOR SEATING (want: seated kidulwm / conductor; uid in /etc/kushd/conductor): --"
# kushd.log has NUL padding -> grep sees it as binary and suppresses matches. -a forces text.
sudo tr -d '\000' < "$L"/kushd.log 2>/dev/null | grep -niE 'conductor|seated kidulwm' | tail -25 \
  || echo "   (no conductor/seated lines — seating may have failed or log missing)"
echo "   conductor uid (want: 990): $(sudo cat "$MNT"/etc/kushd/conductor 2>/dev/null | tr -d '\n')"

echo
echo "-- CRASH / PANIC / REFUSED (want: NONE in the current boot): --"
# Only the LAST boot cycle matters (the current seat). History before the last
# "bill:" line is pre-conductor-flip respawn noise. Use awk to slice from the
# final boot-start line; NUL padding stripped so grep won't read it as binary.
if sudo tr -d '\000' < "$L"/kushd.log 2>/dev/null | awk '/bill: .* acts/{cur=""} {cur=cur $0 ORS} END{print cur}' \
     | grep -niE 'died kidulwm|kernel panic|not syncing|segfault|refused|crash-loop' | tail -25; then
  echo "   ^^^ crash/panic markers in the CURRENT boot (investigate)"
else
  echo "   (clean — current boot has no died/panic/refused; earlier cycles were pre-conductor-flip respawns)"
fi

echo
echo "===================== EFI PSTORE (panic dumps) ====================="
echo "dump-type efivars present:"
ls /sys/firmware/efi/efivars/ 2>/dev/null | grep -iE 'dump-type' | sort
echo "(17 old dumps = Nov 9 #54 VMD/VFS panics. Any NEW timestamp = fresh panic this boot.)"
echo "decode a dump:  cat /sys/firmware/efi/efivars/dump-type* | tr -d '\\000'   (or: mount -t pstore pstore /mnt/pstore)"

echo
echo "===================== DONE ====================="
echo "leave mounted ro or: sudo umount $MNT"
