#!/usr/bin/env bash
set -euo pipefail
# close-never-crashes evidence (CARD 2b slice 4): open media slide, send
# media_play (kvis open logged), close the slide, repeat — compositor must
# survive every close; kvis.sock open evidence must appear in the log.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/zig-out/bin/kidulwm"
LOGFILE="$(mktemp /tmp/kidulwm-close-evidence-XXXXXX.log)"
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
WAYLAND_SOCKET="kidulwm-close-evidence"
IPC_SOCK="$RUNTIME/kidulwm-control.sock"

pkill -f "^$BIN" 2>/dev/null || true
sleep 0.2
rm -f "$IPC_SOCK" "${RUNTIME:?}/$WAYLAND_SOCKET"

# Real kvis.sock evidence: run kvisd (out-of-process player) if the binary
# is available; the open verb then lands for real and the compositor logs
# "[kvis] open sent".
KVISD="${KVISD:-/home/dad/dev/kmedia/zig-out/bin/kvisd}"
KVIS_PID=""
if [[ -x "$KVISD" ]]; then
    rm -f "$RUNTIME/kvis.sock"
    WLR_BACKENDS=headless "$KVISD" >>"$LOGFILE" 2>&1 &
    KVIS_PID=$!
fi

WLR_BACKENDS=headless KIDULWM_WAYLAND_DISPLAY="$WAYLAND_SOCKET" "$BIN" >"$LOGFILE" 2>&1 &
PID=$!
cleanup(){ kill "$PID" 2>/dev/null || true; [[ -n "$KVIS_PID" ]] && kill "$KVIS_PID" 2>/dev/null || true; }
trap cleanup EXIT

for _ in $(seq 1 50); do
    grep -q "KidulWM: Wayland socket $WAYLAND_SOCKET" "$LOGFILE" 2>/dev/null && break
    sleep 0.1
done

ipc() {
    python3 - "$IPC_SOCK" "$1" <<'PY'
import json, socket, sys
sock, payload = sys.argv[1], sys.argv[2]
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
    s.settimeout(3)
    s.connect(sock)
    s.sendall((payload + '\n').encode())
    try:
        print(s.recv(4096).decode().strip())
    except Exception:
        print("(no reply)")
PY
}

alive(){ kill -0 "$PID" 2>/dev/null; }

say(){ printf '>>> %s\n' "$*"; }
fail(){ echo "EVIDENCE FAIL: $*" >&2; exit 1; }

# Round 1: open the media slide, play (music path → kvis open), close slide.
say "open media slide";   ipc '{"media_card_toggle":{}}' >/dev/null; sleep 0.3
say "media_play (music)"; ipc '{"media_play":{"path":"/tmp/evidence-tune.mp3"}}' >/dev/null; sleep 0.3
alive || fail "compositor died after media_play"
say "close media slide";  ipc '{"media_card_toggle":{}}' >/dev/null; sleep 0.3
alive || fail "compositor died on media slide close (round 1)"

# Round 2: open + close again immediately (reopen-lands-on-card path).
say "reopen media slide"; ipc '{"media_card_toggle":{}}' >/dev/null; sleep 0.3
alive || fail "compositor died on reopen"
say "close again";        ipc '{"media_card_toggle":{}}' >/dev/null; sleep 0.3
alive || fail "compositor died on media slide close (round 2)"

# Round 3: play video path then close without video slide present (kvisd
# is not running nested — open fails gracefully, close must still work).
say "media_play (video)"; ipc '{"media_play":{"path":"/tmp/evidence-film.mkv"}}' >/dev/null; sleep 0.3
alive || fail "compositor died after video media_play"
say "close media slide";  ipc '{"media_card_toggle":{}}' >/dev/null; sleep 0.3
alive || fail "compositor died on media slide close (round 3)"

# kvis.sock open evidence: kvisd is not running nested, so the WARN connect
# line is the proof the verb path fired (no in-process player touched).
grep -q "\[kvis\]" "$LOGFILE" || fail "no [kvis] evidence line in log"
say "kvis evidence lines:"; grep "\[kvis\]" "$LOGFILE" | head -5

# Clean quit.
ipc '{"quit":{}}' >/dev/null || true
for _ in $(seq 1 30); do alive || break; sleep 0.1; done
alive && fail "compositor did not exit on quit"

if grep -qE "Segmentation|protection exception|Assertion" "$LOGFILE"; then
    fail "crash signature in log"
fi
say "close-never-crashes evidence: PASS (3 close rounds, session survived, clean quit)"
