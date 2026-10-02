#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Phase 2 step 1 host repro sampler — captures RSS + CPU + FRAMETRACE deltas
# during video playback so we can name the wedge owner (kidulwm vs kplayd)
# and watch the render loop under load.
#
# Run BEFORE firing media_play (it logs for 3 min at 2s cadence), then trigger
# playback with:  /usr/local/bin/kidulwm-control media_play <path>
# Output appends to playback-repro.log; each line = FRAMETRACE counters +
# per-process RSS/CPU + the watchdog line (includes i915_irqs). Verified
# 2026-09-20: proved the wedge is RETENTION (kidulwm plateaus ~1160MB, never
# releases ~880MB), not runaway growth.
OUT=/home/dad/dev/KidulWM/playback-repro.log
LOG=/home/dad/.local/state/kidulwm/session.log
WLOG=/var/log/kmedia-watchdog.log

# snapshot FRAMETRACE counter line
fr() { grep FRAMETRACE "$LOG" | tail -1 | sed 's/.*FRAMETRACE //'; }
# snapshot watchdog line
wd() { tail -1 "$WLOG"; }
# per-proc RSS/CPU
ps_snap() {
  local kp kw
  kw=$(ps -o rss=,pcpu= -p "$(pgrep -x kidulwm | head -1)" 2>/dev/null | awk '{print $1/1024, $2}')
  kp=$(ps -o rss=,pcpu= -p "$(pgrep -x kplayd | head -1)" 2>/dev/null | awk '{print $1/1024, $2}')
  echo "kidulwm_mb_cpu=$kw kplayd_mb_cpu=$kp"
}

echo "=== repro start $(date '+%H:%M:%S') ===" >> "$OUT"
prev=$(fr)
for i in $(seq 1 180); do
  cur=$(fr)
  stamp=$(date '+%H:%M:%S')
  echo "$stamp FRAMETRACE $cur | $(ps_snap) | $(wd)" >> "$OUT"
  prev="$cur"
  sleep 2
done
echo "=== repro end $(date '+%H:%M:%S') ===" >> "$OUT"
