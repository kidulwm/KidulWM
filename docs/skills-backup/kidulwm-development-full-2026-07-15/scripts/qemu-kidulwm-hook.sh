#!/bin/bash
# /etc/libvirt/hooks/qemu
# Auto-forward SSH for KidulWM test clones.
# Name clone domains like "kidulwm-test-<PORT>", e.g. "kidulwm-test-2223".

DOMAIN="$1"
ACTION="$2"
PORT="${DOMAIN##*-}"

[[ "$DOMAIN" == kidulwm-test-* ]] || exit 0
[[ "$PORT" =~ ^[0-9]+$ ]] || exit 0

LOG=/var/log/kidulwm-hook.log

case "$ACTION" in
  start|started)
    echo "$(date +%Y-%m-%dT%H:%M:%S) forward $DOMAIN -> $PORT" >> "$LOG"
    virsh --connect qemu:///system qemu-monitor-command "$DOMAIN" --hmp "hostfwd_add tcp::${PORT}-:22" >> "$LOG" 2>&1 || true
    ;;
  stop|stopped)
    echo "$(date +%Y-%m-%dT%H:%M:%S) remove $DOMAIN -> $PORT" >> "$LOG"
    virsh --connect qemu:///system qemu-monitor-command "$DOMAIN" --hmp "hostfwd_remove tcp::${PORT}" >> "$LOG" 2>&1 || true
    ;;
esac
exit 0
