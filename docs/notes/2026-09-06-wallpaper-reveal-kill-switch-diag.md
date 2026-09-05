# 2026-09-06 — Mist hunt: wallpaper-reveal kill switch (diag)

## Context

After f877a73 (fade master-pixel restore + setPosition no-op guard) the mist
veil and the ~95% CPU / fan spin were still present on the host. Hash-verified
the running compositor WAS f877a73 (/proc/<pid>/exe == zig-out == /usr/local/bin),
so not a stale binary. Nvidia GPU at 45% util, kidulwm pinned in libnvidia-eglcore,
ghostty still committing — the commit-storm guard did not break the loop.

Hypothesis tree:
  1. The reveal animation never completes (fade path), keeping both the tinted
     veil on screen AND a per-frame scheduleFrame storm alive.
  2. The veil is a scene-node stacking problem, not the animation at all.
  3. Nvidia driver amplifies whatever per-frame damage the compositor emits
     (libnvidia-eglcore makes each pass expensive) — amplifier, not root cause.

## What was done (diag commit)

src/server.zig, in the wallpaper-arrival handler:
  - Buffer now starts on MASTER pixels (`start_px = result.pixels`), not tinted.
  - The boot reveal is never armed; logs "wallpaper reveal DISABLED (diag kill switch)".
  - tickWallpaperReveal() early-returns on active==false, so no other call
    sites needed changes.

This is a DIAGNOSTIC, not a fix. Revert/rework once the verdict is in.

## How to read the result

  - Mist gone + CPU calm after restart  -> animation path was the culprit.
    Next: find why fade completion never fires (or why its scheduleFrame loop
    persists), then re-enable effects with a guaranteed-complete path.
  - Mist persists                       -> stacking/veil node problem.
    Next: use the `scene_dump` IPC verb (added in 59b1db9) to inspect the node
    stack; check wallpaper_scene_buffer placement vs overlay/background.rect.

## Verify steps after compositor restart

    sha256sum /proc/$(pgrep -x kidulwm)/exe /usr/local/bin/kidulwm   # must match
    ps -o %cpu -p $(pgrep -x kidulwm)                                # expect low single digits
    journalctl --user -b | grep 'wallpaper reveal'                   # expect DISABLED line

## Pitfalls learned

  - "Nothing changed" reports: hash the RUNNING exe before trusting that a
    deploy happened. Timestamps lie; /proc/pid/exe doesn't.
  - The fade effect writes NO pixels (opacity only) — any pixel-level fix must
    run for every effect, and any pixel-level diag must start from master.
  - setSurfaceOffset no-op guard guards ONE caller. scheduleFrame storms can
    come from the animation tick itself re-arming every frame.
