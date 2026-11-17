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

  1. The roster resolution. [DONE] — allocation map (kalloc): { attested-key ->
     partition } signed map, a SEPARATE artifact from the roster (WHO vs WHAT).
     Module + CLI + tests proven. Law: allocation-map.md. Gate now emits the
     proven key-id ('TRUSTED role=<r> key=<k>') so the mounter can resolve it.
     kidulkey commits eaf8be6 + b32ada8.

  2. The sealed mounter verb. [DONE] — kmount: one-shot, verifies kalloc,
     resolves key-id -> token -> device (by-partuuid/by-uuid), mount(2)
     nosuid+nodev, fstype=NULL autoprobe, fail-closed with strerror. mount(2)
     ONLY — luks open/close is a SEPARATE verb (one job per verb). Proven:
     sig-BAD/unknown-key/malformed-key/absent-partition all fail-closed; mount
     reached with correct marshalling. Success path still needs an auto-probe-
     able rw fs (mkfs, hardline-blocked); its gate — the luks decrypt — is now
     built (2b).

  2b. The luks verbs. [DONE] — kopen/kclose: one-shot verbs linking
      libcryptsetup (never reimplement LUKS). kopen <device> <name> <keyfile>
      = crypt_activate_by_keyfile (LUKS1/2 auto-detect, keyfile = passphrase
      bytes); kclose <name> = crypt_init_by_name + crypt_deactivate. Live-
      proven on a loop LUKS2 (aes-xts-plain64): open + wrong-key fail-closed +
      close + unknown-name fail-closed (tools/test-luks.sh). The Kleaner (3)
      cues kclose on exit.

  3. The clean-close verbs. [DONE] — kumount + kclean (the Kleaner), completing
     the exit sequence (kumount -> kclose[2b] -> kclean). kumount <mountpoint>
     = umount2(flags 0, NO MNT_DETACH — EBUSY fail-closes, no lazy half-tear).
     kclean <path...> = the Kleaner scrub: open O_WRONLY, refuse non-regular
     (S_ISREG), overwrite full length with zeros, fsync, unlink; idempotent
     (ENOENT = clean). Live-proven (tools/test-klean.sh): umount success +
     bare-dir fail-closed; zeroize proven via hard-link alias reading all-zeros
     (overwrite-before-unlink, not just unlink); missing-path idempotent;
     directory refused. kclean serves BOTH clean-open (entry) and clean-close
     (exit) — one idempotent scrub, one job.

  4. kushd cue plumbing. [TODO] — on proof: cue kopen -> kmount (after kalloc
     resolve); on sign-out/unplug/end-of-session: cue kumount -> kclose ->
     kclean. All verbs on the existing cue-socket pattern.

  5. kushd self-trim (the enforcement pass). [TODO] — trim kushd's own bounding
     set so it cannot mount/reboot even by accident.

## What this does NOT touch

  - The slide (Homes) stays a cue, nothing more (step 3 contract holds).
  - kboot stays untouched: ~100 lines, sleeps after boot.
  - No new resident daemons. Mounter and Kleaner are one-shot verbs.

## Open (non-blocking, for later)

  - Where the partition map lives: extend roster, or a separate signed map.
  - Co-owned drives (second key) — internal separation on one partition.
  - Kleaner zeroize scope: runtime-only now; at-rest metadata scrub later.
