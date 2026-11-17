# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (2026-11-18)

  STEP 4 — RE-SEAT. The MOUNT half was DONE + LIVE-PROVEN (kushd b4ff2db; kcarve
    d20a9db). The IDENTITY half is now SPEC'D: the build order lives in
    docs/design/re-seat-entry.draft.md (480b1c2, pushed) — sibling to
    re-seat-mount.draft.md. Design FROZEN (re-seat.md 67202f5): the FACE = a
    CONDUCTOR uid (data-blind, never a user, never re-seats); sign-in re-mints
    only the USER identity (public 1001 -> owner 1002) via kushd mintSession.
    Owner PRE-PROVISIONED (uid 1002 = bee62e237cdd37a455eeafca, home-hash).
    Reverses kid.md (home = random hash, not key-derived key-id).

  CARRIED THREADS (do not lose):
    - KSD NOT deployed: repos ahead of /mnt/ksd — /mnt/ksd mounted RO this session
      (owner account verified); deploy is still ahead.
    - kboot + kslide-template CLEAN (committed).

  NEXT SESSION: await Barticus's verdict on the spec's FOUR open questions, then
    build slice 1 of the re-seat build order. The Qs: A sequencing
    (foundation-first vs surface-first — rec foundation-first), B conductor uid
    number, C entry slide = Homes upgraded vs a new slide kind (rec upgraded),
    D socket dir path (rec /run/kushd/wayland). After the verdict, build in
    order: (1) socket convention -> (2) conductor account -> (3) entry slide
    freeze -> (4) key->home-hash resolution -> (5) kmount mount-point correction
    -> (6) the re-mint wiring. Fire 'next' -> docket #59 resolves to the socket
    convention. Handoff = CENSUS-NOTES top + re-seat.md (law) +
    re-seat-entry.draft.md (build order) + kidulkey skill (the seq + stderr gotcha).

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
