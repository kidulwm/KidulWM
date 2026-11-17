# DESIGN DRAFT — step 4: RE-SEAT + MOUNT (the plug-and-play wiring)

Status: DRAFT (bobdotrix 2026-11-17). NOT law yet — but the architecture is
RESOLVED into privileged-verbs.md (LOCKED 2026-11-17) + partitions.md "who
performs the mount". This file is the build order; the law is the contract.

## The locked architecture (already frozen)

  - Two mounts, never confused:
      PROCESS-mount = kushd seats (fork + mintSession + setuid + execve).
      DRIVE-mount   = a sealed one-shot verb (kidulKey-signed, dm-verity +
                      fs-verity verified, file-capped CAP_SYS_ADMIN). kushd
                      CUES it; it mounts and exits.
  - kboot = boot floor only (sealed root + verify + read class + spawn kushd),
    then radio silence. No runtime mount, no mid-session wake.
  - The mounter mounts what the key's roster says (role -> partition), never
    what it is told. Gate proves role (step 3, DONE), roster maps role to
    partition, mounter mounts exactly that.
  - The Kleaner = the clean-exit verb: armed at boot, triggered by royalty
    presence. entry = clean-open, exit = clean-close (unmount + zeroize +
    "fix the doors").

## Build order (what step 4 actually is)

  1. The roster resolution. Gate already returns TRUSTED role=<role>. Extend
     the gate verdict to carry the PARTITION the role is allowed to cast, or
     have kushd look it up from the signed roster (ROSTER_PATH). The role ->
     partition map is the missing link between step 3 and the mount.

  2. The sealed mounter verb. One-shot binary, file-capped CAP_SYS_ADMIN,
     kidulKey-signed, in the immutable root. Input: the partition. Does
     luks open + mount(2) + verify fs-verity, then exits. Fail-closed.

  3. The Kleaner verb. One-shot, same sealing. Unmount + luks close + zeroize
     runtime footprint + key bytes. Fired on the presence exit (sign-out /
     unplug) and end-of-session.

  4. kushd cue plumbing. On proof: cue the mounter (after resolving the
     partition from the roster). On sign-out/unplug: cue the Kleaner. Both are
     verbs on the existing cue socket pattern (homes-gate set the precedent).

  5. kushd self-trim (the enforcement pass). Trim kushd's own bounding set so
     it cannot mount/reboot even by accident — "never mounts" becomes a cap
     mask, not discipline. After the verbs exist.

## What this does NOT touch

  - The slide (Homes) stays a cue, nothing more (step 3 contract holds).
  - kboot stays untouched: ~100 lines, sleeps after boot.
  - No new resident daemons. Mounter and Kleaner are one-shot verbs.

## Open (non-blocking, for later)

  - Where the partition map lives: extend roster, or a separate signed map.
  - Co-owned drives (second key) — internal separation on one partition.
  - Kleaner zeroize scope: runtime-only now; at-rest metadata scrub later.
