#!/usr/bin/env bash
set -euo pipefail

# nested-three-window.sh — verify KidulWM survives mapping three real XDG toplevels.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/zig-out/bin/kidulwm"
LOG_DIR="${TMPDIR:-/tmp}"
LOGFILE="$(mktemp "$LOG_DIR/kidulwm-3win-XXXXXX.log")"
trap 'rm -f "$LOGFILE"; rm -f "$RUNTIME/$WAYLAND_SOCKET" "$IPC_SOCK"' EXIT

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id - u)}"
WAYLAND_SOCKET="${KIDULWM_WAYLAND_DISPLAY:-kidulwm-3win}"
IPC_SOCK="$RUNTIME/kidulwm-control.sock"

say(){ printf '\n>>> %s\n' "$*"; }
fail(){ echo "FAIL: $1" >&2; echo "--- log tail ---"; tail -n 40 "$LOGFILE"; exit "${2:-1}"; }

[[ -x "$BIN" ]] || fail "$BIN not found"

# Kill stale
pkill -f "^$BIN" 2>/dev/null || true
sleep 0.2
rm -f "$IPC_SOCK" "$RUNTIME/$WAYLAND_SOCKET"

say "Launching KidulWM nested (socket=$WAYLAND_SOCKET)"
WAYLAND_DISPLAY="${HOST_WAYLAND_DISPLAY:-${WAYLAND_DISPLAY:-wayland-1}}" WLR_BACKENDS=headless KIDULWM_WAYLAND_DISPLAY="$WAYLAND_SOCKET" \
    "$BIN" >"$LOGFILE" 2>&1 &
PID=$!

READY=0
for _ in $(seq 1 80); do
    if grep -q "KidulWM: Wayland socket $WAYLAND_SOCKET" "$LOGFILE" 2>/dev/null && [[ -S "$RUNTIME/$WAYLAND_SOCKET" ]]; then
        READY=1
        break
    fi
    sleep 0.1
done
[[ $READY -eq 1 ]] || fail "startup timeout"

say "Compositor up (pid=$PID), spawning 3 alacritty windows..."

CLIENT_PIDS=()
for i in 1 2 3; do
    WAYLAND_DISPLAY="$WAYLAND_SOCKET" alacritty -e sh -c "echo 'window $i'; sleep 30" &
    CLIENT_PIDS+=($!)
    sleep 1
done

say "3 windows launched, waiting for settle..."
sleep 2

# Check compositor still alive
if ! kill -0 "$PID" 2>/dev/null; then
    wait "$PID" || true
    fail "compositor crashed after third window"
fi

# Ask compositor to quit cleanly via IPC
QUIT_RESP=""
if [[ -S "$IPC_SOCK" ]]; then
    QUIT_RESP=$(python3 - "$IPC_SOCK" <<'PY'
import json, socket, sys
sock = sys.argv[1]
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
    s.settimeout(2)
    try:
        s.connect(sock)
        s.sendall((json.dumps({'quit':{}})+'\n').encode())
        print(s.recv(4096).decode().strip())
    except Exception as e:
        print(f'ERROR: {e}')
PY
    )
fi

WAIT_OK=false
for _ in $(seq 1 50); do
    if ! kill -0 "$PID" 2>/dev/null; then
        WAIT_OK=true
        break
    fi
    sleep 0.1
done

for cpid in "${CLIENT_PIDS[@]}"; do
    kill "$cpid" 2>/dev/null || true
done

CRASHED=false
if [[ -s "$LOGFILE" ]] && grep -qiE 'segmentation fault|panic|aborted|core dumped' "$LOGFILE"; then
    CRASHED=true
fi

say "Results:"
echo "  IPC response:    ${QUIT_RESP:-<none>}"
echo "  clean exit:      $WAIT_OK"
echo "  crash in log:    $CRASHED"

if $CRASHED; then
    fail "crash indicators found in log"
fi
if ! $WAIT_OK; then
    fail "compositor did not exit after IPC quit"
fi
if [[ "$QUIT_RESP" != *'"ok":'*true* ]]; then
    fail "IPC quit failed"
fi

say "Three-window nested test PASSED"
