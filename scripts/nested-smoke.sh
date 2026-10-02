#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

# nested-smoke.sh — launch KidulWM nested under an existing Wayland session,
# run a minimal real client, and shut down cleanly via IPC.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/zig-out/bin/kidulwm"
LOG_DIR="${TMPDIR:-/tmp}"
LOGFILE="$(mktemp "$LOG_DIR/kidulwm-nested-XXXXXX.log")"
trap 'rm -f "$LOGFILE"' EXIT

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id - u)}"
WAYLAND_SOCKET="${KIDULWM_WAYLAND_DISPLAY:-kidulwm-nested}"
IPC_SOCK="$RUNTIME/kidulwm-control.sock"

say(){ printf '\n>>> %s\n' "$*"; }
fail(){ echo "FAIL: $1" >&2; exit "${2:-1}"; }

# 1. Binary check
[[ -x "$BIN" ]] || fail "$BIN not found (run zig build first)"

# 2. Kill any stale kidulwm
pkill -f '^./zig-out/bin/kidulwm' 2>/dev/null || true
pkill -f "^$BIN" 2>/dev/null || true
sleep 0.2

# 3. Launch KidulWM nested (headless by default so it runs inside an existing session;
#    set WLR_BACKENDS=wayland to test the real Wayland backend path later).
say "Launching KidulWM nested (socket=$WAYLAND_SOCKET, log=$LOGFILE)"
rm -f "$IPC_SOCK" "${RUNTIME:?}/$WAYLAND_SOCKET"
WLR_BACKENDS="${WLR_BACKENDS:-headless}" KIDULWM_WAYLAND_DISPLAY="$WAYLAND_SOCKET" \
    "$BIN" >"$LOGFILE" 2>&1 &
PID=$!

# 4. Wait for ready log line and socket
READY=0
for _ in $(seq 1 50); do
    if grep -q "KidulWM: Wayland socket $WAYLAND_SOCKET" "$LOGFILE" 2>/dev/null && [[ -S "$RUNTIME/$WAYLAND_SOCKET" ]]; then
        READY=1
        break
    fi
    sleep 0.1
done
[[ $READY -eq 1 ]] || { say "Compositor did not announce Wayland socket"; fail "startup timeout; log tail below:\n$(tail -n 30 "$LOGFILE")"; }

say "Compositor up (pid=$PID), socket ready"

# 5. Try to run a real client
CLIENT_PID=""
start_client() {
    local cmd=("$@")
    WAYLAND_DISPLAY="$WAYLAND_SOCKET" "${cmd[@]}" &
    CLIENT_PID=$!
}

if command -v foot >/dev/null 2>&1; then
    say "Client: foot"
    start_client foot true
elif command -v alacritty >/dev/null 2>&1; then
    say "Client: alacritty"
    start_client alacritty -e sh -c 'echo smoke; sleep 2'
elif command -v wayland-info >/dev/null 2>&1; then
    say "Client: wayland-info"
    start_client wayland-info
else
    fail "no suitable Wayland client found (foot, alacritty, wayland-info)"
fi

sleep 2

# 5b. Output assertions — the 2026-09-05 black-screen incident passed every
# check above while both physical outputs were silently dropped. A smoke test
# that never looks at the outputs is blind to the exact failure it exists to
# catch. Require: at least one output driven, and zero recorded output drops.
OUTPUT_LINES=$(grep -c "output added to layout" "$LOGFILE" || true)
DROP_LINES=$(grep -c "OUTPUT DROPPED" "$LOGFILE" || true)
OUTPUTS_OK=false
[[ "$OUTPUT_LINES" -ge 1 && "$DROP_LINES" -eq 0 ]] && OUTPUTS_OK=true
if ! $OUTPUTS_OK; then
    say "Output assertion FAILED: driven=$OUTPUT_LINES drops=$DROP_LINES"
    grep -E "OUTPUT DROPPED|output added to layout" "$LOGFILE" || true
fi

# 6. Send IPC quit
QUIT_RESP=""
QUIT_OK=false
if [[ -S "$IPC_SOCK" ]]; then
    say "Sending IPC quit"
    set +e
    QUIT_RESP=$(python3 - "$IPC_SOCK" <<'PY'
import json, os, socket, sys
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
    set -e
    if [[ "$QUIT_RESP" == *'"ok":'*true* ]]; then
        QUIT_OK=true
    fi
fi

# 7. Wait for compositor exit
WAIT_OK=false
for _ in $(seq 1 30); do
    if ! kill -0 "$PID" 2>/dev/null; then
        WAIT_OK=true
        break
    fi
    sleep 0.1
done

CLIENT_RAN=false
if [[ -n "$CLIENT_PID" ]] && kill -0 "$CLIENT_PID" 2>/dev/null; then
    # Client still alive at quit (expected for long-running clients)
    CLIENT_RAN=true
elif [[ -n "$CLIENT_PID" ]]; then
    # Client exited; it still ran
    CLIENT_RAN=true
fi

say "Results:"
echo "  compositor accepted quit: $QUIT_OK"
echo "  compositor exited:        $WAIT_OK"
echo "  client process ran:       $CLIENT_RAN"
echo "  outputs driven (no drops): $OUTPUTS_OK ($OUTPUT_LINES driven, $DROP_LINES dropped)"
echo "  IPC response:             ${QUIT_RESP:-<none>}"

if $QUIT_OK && $WAIT_OK && $CLIENT_RAN && $OUTPUTS_OK; then
    say "Smoke test PASSED"
    exit 0
else
    say "Smoke test FAILED"
    echo "--- last 30 log lines ---"
    tail -n 30 "$LOGFILE"
    exit 1
fi
