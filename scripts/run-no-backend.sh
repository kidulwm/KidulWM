#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

cd "$(dirname "$0")/.."
zig build

KIDULWM_NO_BACKEND=1 ./zig-out/bin/kidulwm &
WM_PID=$!

cleanup() {
    kill "$WM_PID" 2>/dev/null || true
}
trap cleanup EXIT

sleep 0.5
python3 scripts/test-splits.py
