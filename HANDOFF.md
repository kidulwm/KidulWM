# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — verdict 53 = current position + next test

## Current position (2026-09-21)

  - Verdict 54 DEPLOYED (bddc1c5, /usr/local/bin/kidulwm b83da5e2, .bak-9fe3b374):
    slide routing (cursor owns new slides — media card / home launcher / app
    window) + pause-on-aside (video freezes when walked off-focus, resumes on
    return). outputs.toml corrected: DP-3 {0,0} above eDP-1 {0,1080}.
  - RELOG OWED to pick up b83da5e2 + the new outputs.toml. Test steps in
    CENSUS verdict 54.
  - GodCodeMode LOCKED; Card A inc1 scanout overlay toggle still live (verdict 53).
  - NVIDIA blacklisted; WLR_DRM_DEVICES=/dev/dri/card1. REBOOT still owed.

## Next action

  Relog + reboot → media_play Raya fullscreen → grep "scanout candidate" in
  ~/.local/state/kidulwm/session.log → watch kidulwm CPU (~2-5% = scanout
  engaged). Details in CENSUS verdict 53.

## Trip wires / commands / secrets

  KNOWN_CMDS.md   build, deploy, VM (ksd-reset 192.168.122.87 / fresh-one FROZEN), SSH
  AGENTS.md       secrets map + agent strategy + build gotchas