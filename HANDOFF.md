# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (2026-11-10)

  KSD BOOT (docket #54) — real kboot->kushd->kidulwm on the 980 Pro. State:
    - kidulwm segfault FIXED + DEPLOYED today. Commits 07cbfc8 (backend unsetenv
      WAYLAND_DISPLAY — DRM not nested) + bafe895 (read env once before
      Server.init; use-after-free via setenv realloc). Built ReleaseSafe,
      deployed /mnt/ksd/usr/local/bin/kidulwm (stamp bafe895).
    - REBOOT-TEST PENDING (Barticus in the morning): boot nvme1, confirm kidulwm
      seats clean — kushd.log "seated kidulwm" with NO "died kidulwm" loop.
    - FORK FLAG: kboot (logdrain/devRules/log-path, 86 ins) + kushd (log-path
      /tmp->/var/log) are UNCOMMITTED in the tree but DOCKETS #54 describes them
      done. Commit+build+deploy them before the crash-survival guarantee holds.
      This is the "logs survive a crash for a service Bob" work.
    - OPEN (carried): VMD revert — host root is ALSO behind VMD, needs a plan not
      a flip. Trackpad loss was Fn+F2 EC toggle (BIOS-LOG 00:15), NOT VMD/security.

  kmedia lane: A/V drift wind-up fix COMMITTED (cf21d2f) + DEPLOYED (kplayd sha
  fbf7b926), UNVERIFIED by a real movie — next play is the check (~±6ms, no ramp).

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
