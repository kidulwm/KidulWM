#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/zig-out/bin/kidulwm"
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id - u)}"
WAYLAND_SOCKET="kidulwm-repro"
IPC_SOCK="$RUNTIME/kidulwm-control.sock"
LOGFILE="$(mktemp "$RUNTIME/kidulwm-repro-XXXXXX.log")"

trap 'kill $(jobs -p) 2>/dev/null || true; rm -f "$IPC_SOCK" "${RUNTIME:?}/$WAYLAND_SOCKET" "$LOGFILE"' EXIT

echo "log: $LOGFILE"

rm -f "$IPC_SOCK" "${RUNTIME:?}/$WAYLAND_SOCKET"

WAYLAND_DISPLAY="wayland-1" \
WLR_BACKENDS=wayland \
KIDULWM_WAYLAND_DISPLAY="$WAYLAND_SOCKET" \
"$BIN" >"$LOGFILE" 2>&1 &
PID=$!

READY=0
for _ in $(seq 1 50); do
    if grep -q "KidulWM: Wayland socket $WAYLAND_SOCKET" "$LOGFILE" 2>/dev/null && [[ -S "$RUNTIME/$WAYLAND_SOCKET" ]]; then
        READY=1
        break
    fi
    sleep 0.1
done

if [[ $READY -ne 1 ]]; then
    echo "Compositor did not start"
    tail -n 40 "$LOGFILE"
    exit 1
fi

echo "Compositor up (pid=$PID)"

spawn_client() {
    WAYLAND_DISPLAY="$WAYLAND_SOCKET" alacritty -e sh -c 'echo client"$1" started; sleep 30' -- "$1" &
}

for i in 1 2 3; do
    spawn_client "$i"
    sleep 0.5
done

echo "Three clients spawned; waiting 8s for stability"
sleep 8

if kill -0 "$PID" 2>/dev/null; then
    echo "Compositor still alive, sending IPC quit"
    python3 - "$IPC_SOCK" <<'PY'
import json, socket, sys
sock = sys.argv[1]
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
    s.settimeout(2)
    s.connect(sock)
    s.sendall((json.dumps({'quit':{}})+'\n').encode())
    print(s.recv(4096).decode())
PY
else
    echo "Compositor exited before quit"
fi

for _ in $(seq 1 30); do
    if ! kill -0 "$PID" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

if [[ -e /proc/$PID ]] 2>/dev/null; then
    echo "Compositor still alive, killing"
    kill -9 "$PID" || true
fi

echo "--- log tail ---"
tail -n 80 "$LOGFILE"

if grep -q "Signal\|segfault\|assertion\|error: thread.*panic" "$LOGFILE"; then
    echo "REPRODUCED: crash signals found"
    exit 1
fi

echo "No crash observed"
