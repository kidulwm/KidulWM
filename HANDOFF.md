# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (2026-11-17)

  STEP 4 — RE-SEAT DESIGN FROZEN TO LAW (re-seat.md, 67202f5, pushed). The MOUNT half
    was already DONE + LIVE-PROVEN (kushd b4ff2db; kcarve d20a9db). Now the IDENTITY
    half is specced: the FACE = a CONDUCTOR uid (data-blind, never a user, never
    re-seats); sign-in re-mints only the USER identity (public 1001 -> owner 1002)
    via kushd mintSession. Owner PRE-PROVISIONED (uid 1002 = bee62e237cdd37a455eeafca,
    home-hash). Reverses kid.md (home = random hash, not key-derived key-id).

  CARRIED THREADS (do not lose):
    - KSD NOT deployed: repos ahead of /mnt/ksd — /mnt/ksd mounted RO this session
      (owner account verified); deploy is still ahead.
    - kboot + kslide-template CLEAN (committed).

  NEXT SESSION: step 5a = the ENTRY SLIDE + the SOCKET CONVENTION (spec-first).
    (i) the entry slide: sign-in as a deck slide; on focus, FREEZE the data
    tentacles (SIGSTOP — only {face,audio} survive) and hold their last frame as
    a dimmed backdrop with the tap prompt overlaid (privacy guard: blank/blur on
    lock/re-auth). (ii) the socket convention: ONE shared socket dir (0770,
    group "seat") + one seat group all session uids join + absolute socket paths
    (WAYLAND_DISPLAY=/run/kushd/wayland/wayland-1), across Wayland + ksound +
    kplayd. Then (5b) key->home-hash resolution, (5c) kmount mount-point
    correction (/home/<key-id> -> /home/<home-hash>), (5d) conductor account +
    bill.kush act. Fire 'next' -> docket #59 resolves to the entry slide +
    socket convention. Handoff = CENSUS-NOTES top + re-seat.md (law) + kidulkey
    skill (the seq + stderr gotcha).

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
