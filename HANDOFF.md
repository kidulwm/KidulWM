# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (relog 2026-10-19)

  BOOT STATE (docket #8): boot-to-TV as a STANDARD SETTING, not a hardcoded
  behaviour. CLARIFICATION LOCKED 2026-10-19 (verbatim in docket): "NOT
  static-boot-to-TV. Boot-to-TV is a STANDARD SETTING we turn ON for our own
  TVs — flexible, never a hardcoded boot behaviour. The boot TARGET is a
  configurable autostart entry (TV / PC / remember-last / ANY app), so a
  hotel can autostart into its own menu and Granny lands on her channel."
  Done = cold boot restores last-known state; settings exposes a boot-target
  entry (TV / PC / remember-last / any autostart app). Klinks: kidulwm boot
  path (KIDULWM_BOOT_MEDIA gate, server.zig ~3800), kushd A5 boot ladder,
  settings surface, autostart/boot-target config.

  Also warm from last session (kmedia lane): the A/V drift wind-up fix is
  DEPLOYED (/usr/local/bin/kplayd sha fbf7b926) but UNVERIFIED by a real
  movie — next movie play is the check (should hold ~±6ms, not ramp).
  Source still uncommitted: Player.zig + Timing.zig + build.zig +
  test_driftprobe.zig. New sound.md law line added (cork freezes the clock =
  a contract; see ksound/docs/law/sound.md "The cork freezes the clock").

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
