#!/bin/bash
# rkt-dashboard wrapper: spawns one instance per monitor.
# Uses gtk4-layer-shell's set_monitor() via RKT_MONITOR env var.
set -e
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

# Wait for niri to be ready
while [ ! -S "/run/user/1000/${WAYLAND_DISPLAY}" ]; do
    sleep 0.5
done

# Give niri a moment to settle
sleep 1

# Get monitor list from niri (both built-in and external)
# niri msg outputs prints "Output \"...\" (CONNECTOR)" — extract the connector in parentheses.
MONITORS=$(WAYLAND_DISPLAY=$WAYLAND_DISPLAY niri msg outputs 2>/dev/null \
  | grep -oP '\([A-Za-z0-9-]+\)' \
  | tr -d '()' \
  | tr '\n' ' ')
echo "rkt-dashboard: monitors detected: $MONITORS"

# Kill any existing rkt-dashboard instances
pkill -f 'rkt-dashboard' 2>/dev/null || true
sleep 0.5

# Spawn one instance per monitor
for mon in $MONITORS; do
    echo "rkt-dashboard: starting instance for $mon"
    RKT_MONITOR=$mon /home/dad/dev/KidulWM/rkt-dashboard/target/release/rkt-dashboard &
    sleep 0.2
done

echo "rkt-dashboard: all instances spawned"
wait
