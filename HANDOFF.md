# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — latest verdict = current position
  4. DOCKETS.draft.md             open work — top non-DONE docket = next action

## Current attack (2026-11-23)

  STEP 4 — RE-SEAT + PRIVACY GUARD BUILT; CLAIM/CARVE SPEC LOCKED.

  PRIVACY GUARD: signed-in freeze now black-frosts. seat_signed_in (monotonic)
    set on any TRUSTED verdict on kidulwm's own gate connection; dimEnsure picks
    public=140 (~55% dim) vs signed-in=235 (~92% black frost, unreadable). No new
    kushd verb (the 0666 cue socket is NOT a trust boundary — a public tentacle
    could spoof "seated role=public" and defeat the guard; verdict-as-signal
    can't be injected into an established stream). BLACK frost (not white),
    shader-free, zero new per-frame cost; 255 blank stays the fail-safe floor.
    Spec: docs/design/privacy-guard.draft.md (Q A "verdict not verb" + Q B "black
    frost not shader", both RESOLVED).

  CLAIM/CARVE: spec LOCKED, BUILD AUTHORIZED (docs/design/claim-carve.draft.md,
    KidulWM 0a81af9). Spec-first: partitioning is FATAL. 7-step build order.
    Four rulings LOCKED (Barticus, GSI): A = letter pill-bar PRIMARY + keyboard
    PARALLEL (one name field, two surfaces; fold-out remote keyboard + separate
    keyboards drop in with zero rework); B = kushd owns claim, sign with proved
    owner key via gate (NEVER kalloc's TEST seed sign); C = TV -> 50% fill-bar
    default; D = carve KSD drive by LABEL (~771 GiB FREE POOL, partitions.md:120,
    fixed-config, no "biggest disk" probe).

  CARRIED THREADS (do not lose):
    - NOT deployed to KSD this cut — eyes-on the live freeze (public dim, then
      post-sign-in re-freeze frost) waits on the next deploy.
    - 2nd dongle still to order (real two-key cold SE050 ceremony deferred —
      current is a DISPOSABLE dev root, test-namespaced, TEST-ONLY).
    - Vault keyfile still 0 (no carve yet).

  NEXT SESSION: build claim/carve step 1 (claim detection — empty-roster = the
    ONLY unclaimed state) -> ceremony cues -> name+size input -> carve -> seed+
    sign -> defaultHome skeleton -> mount-on-proof. Then Homes provisioning UI.
    Handoff = CENSUS-NOTES top + claim-carve.draft.md (build order) + re-seat.md
    (law).

## Trip wires / commands / secrets

  KNOWN_CMDS.md   host build/deploy/control + slice router (VM/knetd/aig/Apocalypse/kmedia)
  AGENTS.md       secrets map + agent strategy + build gotchas + slice router
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
