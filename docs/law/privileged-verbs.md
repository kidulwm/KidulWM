# LAW — privileged verbs (root-only work lives in sealed one-shot verbs)

Status: LOCKED 2026-11-17, Barticus present (GSI).

## The one-line law

Anything only root can do, that must happen at RUNTIME (not boot), is a SEALED
ONE-SHOT VERB — a small binary in the immutable root carrying its own file
capability, kidulKey-signed, dm-verity + fs-verity verified. No resident
process holds the capability; kushd (the usher) CUES the verb; the verb
performs its one job and exits. The capability rides on the sealed CODE, not
on any process.

## The two mounts (never confused)

  PROCESS-mount (seating)  = kushd's own hand. fork + mintSession + setuid +
                             execve. Not mount(2) — the usher's core job.

  DRIVE-mount (mount(2)/luks) = the sealed doorman. kushd cues it; the verb's
                             own CAP_SYS_ADMIN does the work, then exits.

One orchestrator, two kinds of hand. kushd seats the process AND cues the
drive in the same cue chain — but the PERFORMANCE stays separate. kushd never
holds CAP_SYS_ADMIN for a drive mount; it holds a key to a door, not the thing
behind the door.

## Why (the trigger/performer split)

kushd must stay killable and respawnable (pure supervisor, kboot.md) and the
non-root seat must never mount. kboot is the boot floor, then radio silence
(the smallest immortal thing must not wake to do runtime work). So runtime
root work has no resident home — it lives in sealed verbs that carry their own
capability on the CODE. The non-root seat can't do it; kushd can't do it;
only the sealed verb can, and only its one job. Separation by architecture,
not by trusting kushd to be good.

Current state vs target (honest): kushd today drops caps only on its CHILDREN
(the seats, via applyClass bounding-set drop); kushd itself is still full-root
and "never mounts" is discipline. The target is a trimmed cap mask on kushd's
own bounding set so it literally cannot mount/reboot — then the "never
mounts/never reboots" law is enforced by the mask, not by discipline alone.
Step 4 builds the verbs first; the kushd self-trim is the enforcement pass.

## The catalog (root-only runtime verbs)

  mount(2) / umount(2)     user partition on proof; unmount on sign-out/lock
  luks open / close        key-wrapped partition; decrypt before mount
  partition carve          the People app carving per-user partitions from the
                           FREE POOL (block-device + mkfs)
  key-material read        roster / partition map from the cold vault (kvaultd)
  zeroize / klean          the exit-side scrub (runtime footprint, key bytes)
  kmodd                    module load (already one-shot)
  kidulkey-gate            proof (already one-shot)

## The Kleaner (the clean-exit verb)

The Kleaner is a one-shot VERB, not a resident daemon (less-running law). It
is armed at boot (part of the sealed base kboot verifies) and triggered by the
royalty presence transition: entry = clean-open (make the seat clean before
royalty walks in); exit = clean-close (unmount, zeroize, "fix the doors" so
nothing shows anyone came or went). Same pass at end-of-session and after any
passphrase/key is pushed through the system. "Leave the place cleaner than
when we found it."

Naming: "Kleaner" in code/docs; "KleanerMan" is Barticus<->Bob only, never
written into an artifact.

## Relationship to existing law

  partitions.md   the two-mounts rule + who performs the drive mount (this
                  law's companion section, added same day)
  kboot.md        kboot = boot floor only, then radio silence; kushd never
                  mounts/reboots (target: cap-mask enforced, not just said)
  verified-boot.md  dm-verity + fs-verity seal the verbs' integrity
  kidulkey.md     the gate proves the role; the roster maps role -> partition
  input-trust-gate.md  the proof verb (kidulkey-gate), first instance of the
                  pattern; kmodd the second
  cold-storage.md the vault stays cold; decrypt-on-read is a runtime sealed
                  verb, never a boot-time kboot mount
  machine-classes.md  axis G (golden/layered) is the immutability the verbs
                  ride on
