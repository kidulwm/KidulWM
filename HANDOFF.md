# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (2026-11-26)

  C2 CLIENT-IFY — R1+R2+A DONE, R3 GATED ON RELOG.

  C2 makes the kmedia Wayland CLIENT the one media front-end (scanner →
  wall → kplay). R1 (env-roots + per-pill wiring + channel/music Enter)
  was already committed in kmedia repo. R2 (0cd0d0b) un-reverts the
  toggle → mediaCardToggle(), spawning the client instead of MediaWidget.
  Wire A (b520a78) sources ~/.config/kidulwm/media.env at login (git-ignored,
  personal bench paths only). Client deployed fresh to both host paths
  (was Oct 24 fossil). VM ksd-reset verified: client spawns, 3-pill shell
  renders, teardown (clean + kill -9) leaves compositor alive.

  LIVE ON HOST: NOT YET. Running kidulwm is pid 2854, Nov 18 fossil (no
  mediaCardToggle string). Session predates media.env source. A host RELOG
  picks up both — that is the parity gate: eyeball the client showing the
  86-item library (posters + expansion) BEFORE proceeding to R3. Relog
  kills this bobdotrix session; CENSUS-NOTES + HANDOFF updated first.

  R3 (NEXT SESSION, POST-RELOG PARITY EYEBALL): retire media.zig (2125L) +
  media_slide.zig (91L) + core/kmedia.zig (480L) + LibraryEntry bridge —
  106 ref sites in server.zig. Fullscreen-video machinery (kplay_window,
  placeKplayWindow, curtain) STAYS — client's video presentation path.
  The media.play door guards on o.media_slide.isOpen() → must re-point
  at client fullscreen request. build.zig drops kmedia_lib import.
  This is the one surgery that can kill the daily driver; fresh focused
  pass required.

  R4 after: landing shell re-cut v3 per law 4942892 (arc'd outline banner,
  identity-only, no 5-above row).

  CARRIED (claim/carve, frozen): carve-subvolume step 1 per
  docs/design/carve-subvolume.draft.md. Disk-guard law d25a228.
  Claim surface (613e280) + gate (c934fea) landed. Step 4 reconciliation
  (partition→subvolume) + step 5 (signed allocation) deferred.

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
