#!/bin/bash
# rkt-dashboard wrapper: spawns one instance per monitor.
# Each instance uses RKT_MONITOR=connector to filter which monitor it handles.
# If an instance dies, only that monitor's instance is restarted.
set -e
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

# Wait for niri socket
while [ ! -S "/run/user/1000/${WAYLAND_DISPLAY}" ]; do
    sleep 0.5
done
sleep 1

# Get monitor list from niri
# niri msg outputs format: 'Output "..." (CONNECTOR)'
MONITORS=$(WAYLAND_DISPLAY=$WAYLAND_DISPLAY niri msg outputs 2>/dev/null \
  | grep '^Output' \
  | grep -oP '\([A-Za-z0-9-]+\)' \
  | tr -d '()' \
  | tr '\n' ' ')
echo "rkt-dashboard: monitors detected: $MONITORS"

# Kill stale instances (but not this wrapper)
pkill -f 'rkt-dashboard.*RKT_MONITOR' 2>/dev/null || true
sleep 0.5

# Spawn one instance per monitor; track PIDs in an associative array (bash 4+).
# We use a simple approach: store "monitor:pid" pairs in a flat file + supervise loop.
PIDFILE="/tmp/rkt-dashboard-pids.txt"
> "$PIDFILE"

for mon in $MONITORS; do
    echo "rkt-dashboard: starting instance for $mon"
    RKT_MONITOR=$mon /home/dad/dev/KidulWM/rkt-dashboard/target/release/rkt-dashboard &
    PID=$!
    echo "$mon:$PID" >> "$PIDFILE"
    echo "rkt-dashboard: started $mon (PID $PID)"
    sleep 0.2
done

echo "rkt-dashboard: all instances spawned"

# Supervise loop: restart any dead instance for its specific monitor only.
while true; do
    declare -A NEW_PIDS
    while IFS=: read -r mon pid; do
        [ -z "$mon" ] && continue
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "rkt-dashboard: instance for $mon (PID $pid) died, restarting..."
            RKT_MONITOR=$mon /home/dad/dev/KidulWM/rkt-dashboard/target/release/rkt-dashboard &
            NEW_PID=$!
            NEW_PIDS["$mon"]=$NEW_PID
            echo "rkt-dashboard: restarted $mon (PID $NEW_PID)"
        fi
    done < "$PIDFILE"

    # Rewrite PID file with any updated PIDs
    if [ ${#NEW_PIDS[@]} -gt 0 ]; then
        > "$PIDFILE"
        while IFS=: read -r mon pid; do
            [ -z "$mon" ] && continue
            if [ -n "${NEW_PIDS[$mon]}" ]; then
                echo "$mon:${NEW_PIDS[$mon]}" >> "$PIDFILE"
            else
                echo "$mon:$pid" >> "$PIDFILE"
            fi
        done < <(cat "$PIDFILE")
        # Also append any brand-new monitors that weren't in the original file
        for mon in "${!NEW_PIDS[@]}"; do
            if ! grep -q "^$mon:" "$PIDFILE" 2>/dev/null; then
                echo "$mon:${NEW_PIDS[$mon]}" >> "$PIDFILE"
            fi
        done
    fi

    sleep 5
done
