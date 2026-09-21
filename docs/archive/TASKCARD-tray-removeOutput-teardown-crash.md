# TASKCARD — tray.removeOutput teardown crash

Status: OPEN — pre-existing on 6d6455f, reproduced 2026-09-05.
Priority: MEDIUM — every compositor quit crashes instead of exiting
cleanly; nested-smoke.sh fails its "compositor exited" check because of
this, masking real regressions.

## Symptom

On IPC quit / shutdown, `server.deinit()` → `output.deinit()` →
`self.server.tray.removeOutput(self)` crashes (segfault trace points at
tray.zig:726 removeOutput). Reproduced identically on pristine 6d6455f
and on cd3bf52 — NOT caused by the output-drop fix.

## Repro

  cd /home/dad/dev/KidulWM
  bash scripts/nested-smoke.sh
  # compositor accepted quit: true / compositor exited: false

## Suspected shape

Teardown order: tray holds per-output widget state keyed to Output;
either removeOutput runs after something it needs is already freed, or
the outputs list is being mutated while iterated during deinit. Check
what tray.zig:726 dereferences and whether tray.deinit vs output.deinit
ordering in server.deinit (server.zig ~850-870) frees shared state first.

## Done-when

- nested-smoke.sh "compositor exited: true", exit code 0.
- No new coredumps from kidulwm on quit.
