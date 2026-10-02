#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# nested-focus-stress.sh — exercise focus/split IPC under animation load,
# then shut down cleanly.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/zig-out/bin/kidulwm"
CTL="$ROOT/zig-out/bin/kidulwm-control"
LOG_DIR="${TMPDIR:-/tmp}"
LOGFILE="$(mktemp "$LOG_DIR/kidulwm-stress-XXXXXX.log")"
trap 'rm -f "$LOGFILE"' EXIT

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id - u)}"
WAYLAND_SOCKET="${KIDULWM_WAYLAND_DISPLAY:-kidulwm-stress}"
IPC_SOCK="$RUNTIME/kidulwm-control.sock"

say(){ printf '\n>>> %s\n' "$*"; }
fail(){ echo "FAIL: $1" >&2; exit "${2:-1}"; }

[[ -x "$BIN" ]] || fail "$BIN not found (run zig build first)"
[[ -x "$CTL" ]] || fail "$CTL not found (run zig build first)"

pkill -f '^./zig-out/bin/kidulwm' 2>/dev/null || true
pkill -f "^$BIN" 2>/dev/null || true
sleep 0.2

say "Launching KidulWM nested (socket=$WAYLAND_SOCKET, log=$LOGFILE)"
rm -f "$IPC_SOCK" "${RUNTIME:?}/$WAYLAND_SOCKET"
WLR_BACKENDS="${WLR_BACKENDS:-headless}" KIDULWM_WAYLAND_DISPLAY="$WAYLAND_SOCKET" \
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
[[ $READY -eq 1 ]] || fail "startup timeout; log tail below:\n$(tail -n 30 "$LOGFILE")"

start_client() {
    WAYLAND_DISPLAY="$WAYLAND_SOCKET" "$@" &
}

say "Spawning three alacritty windows"
for _ in 1 2 3; do
    start_client alacritty -e sh -c 'echo stress; sleep 60'
done
sleep 2

say "Rapid focus/split stress"
export XDG_RUNTIME_DIR="$RUNTIME"
for _ in $(seq 1 50); do
    "$CTL" focus_next >/dev/null
    "$CTL" focus_prev >/dev/null
done
for _ in $(seq 1 20); do
    "$CTL" split_left  >/dev/null
    "$CTL" split_right >/dev/null
    "$CTL" split_top   >/dev/null
    "$CTL" split_bottom >/dev/null
    "$CTL" focus_next >/dev/null
done

say "Sending quit"
RESP="$("$CTL" quit)"
if [[ "$RESP" != *'"ok":'*true* ]]; then
    fail "quit failed: $RESP"
fi

declare -i WAIT_OK=0
for _ in $(seq 1 30); do
    if ! kill -0 "$PID" 2>/dev/null; then
        WAIT_OK=1
        break
    fi
    sleep 0.1
done
[[ $WAIT_OK -eq 1 ]] || fail "compositor did not exit"

# Ignore historical cores from other paths; count new cores for the just-run build.
CORE_COUNT=$(coredumpctl list --no-pager "$BIN" 2>/dev/null | grep "$(date '+%a %Y-%m-%d')" | wc -l || echo 0)

say "Stress PASSED"
echo "  cores today: $CORE_COUNT"
