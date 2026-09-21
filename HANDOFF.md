# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — verdict 53 = current position + next test

## Current position (2026-09-21)

  - GodCodeMode LOCKED — docs/law/godcodemode.md (slide protocol + kslate +
    scanout-by-default; fork = chamfer-only patchset, not a fork).
  - Card A inc1 DEPLOYED (9fe3b374) — scanout overlay toggle. RELOG + Raya owed.
  - NVIDIA blacklisted; WLR_DRM_DEVICES=/dev/dri/card1. REBOOT owed.
  - Verdict 53 in CENSUS holds the exact post-reboot/post-relog test steps.
  - 7 commits ahead of Codeberg — push waits for the reset (standing policy).

## Next action

  Relog + reboot → media_play Raya fullscreen → grep "scanout candidate" in
  ~/.local/state/kidulwm/session.log → watch kidulwm CPU (~2-5% = scanout
  engaged). Details in CENSUS verdict 53.

## Trip wires / commands / secrets

  KNOWN_CMDS.md   build, deploy, VM (ksd-reset 192.168.122.87 / fresh-one FROZEN), SSH
  AGENTS.md       secrets map + agent strategy + build gotchas