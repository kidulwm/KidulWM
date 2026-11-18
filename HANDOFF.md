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

  STEP 4 — RE-SEAT. MOUNT half DONE + LIVE-PROVEN (kushd b4ff2db; kcarve d20a9db).
    IDENTITY half SPEC'D (re-seat-entry.draft.md) + RULINGS A-D LOCKED +
    self-dismantling steer (re-seat.md v3). SLICES 1+2 BUILT + PROVEN:
    slice 1 socket convention (kushd 8680b58: /run/kushd/wayland 2770 root:seat
    SETGID + seat umask 0007, socket 0770 :seat + absolute WAYLAND_DISPLAY) +
    slice 2 conductor account (kushd 7ac1efe: kidulwm seats as data-blind uid
    990, groups {render video input seat tty} NO audio) + slice 3a freeze/thaw
    verb (kushd c0b9289: cue freeze/thaw SIGSTOP/SIGCONT the user/restricted
    tentacles; conductor + organs survive). Design FROZEN
    (re-seat.md 67202f5 + v3): FACE = CONDUCTOR uid (data-blind, never re-seats);
    sign-in re-mints only the USER identity (public 1001 -> owner 1002) via kushd
    mintSession. Owner PRE-PROVISIONED (uid 1002 = bee62e237cdd37a455eeafca).

  CARRIED THREADS (do not lose):
    - KSD NOT deployed: repos ahead of /mnt/ksd — deploy is still ahead.
    - kboot + kslide-template CLEAN (committed).
    - Conductor PROVISIONING (rootfs build): uid 990 needs its OWN primary group
      (not a device group — host gid 990 = "kvm"), home /nonexistent, binary at
      /usr/local/bin. Rides with the owner-1002 pre-provisioning.

  NEXT SESSION: SLICE 3 SURFACE = the entry slide's visible half (frozen-frame
    backdrop in kidulwm + Homes prompt freeze-on-focus in kbrain-ui + privacy
    guard). The freeze mechanism (kushd c0b9289) is done; this wires the surface
    to it. Then (4) key->home-hash resolution, (5) kmount mount-point
    correction, (6) the re-mint wiring. Full boot-tower assembly proof
    (kboot->kushd->kidulwm on ksd-boot) rides once the bill ships kidulwm as
    "conductor" — the kushd PID-1 tower, not ksd-reset (systemd). Handoff =
    CENSUS-NOTES top + re-seat.md (law) + re-seat-entry.draft.md (build order).

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
