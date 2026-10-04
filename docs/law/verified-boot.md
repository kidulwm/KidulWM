# LAW — verified boot & the fallback policy (LOCKED 2026-10-04, Barticus present)

The boot-time trust floor: what the box verifies about itself before it runs,
and — the part that is easy to get wrong — what it does when verification
fails. One floor, three failures, three DIFFERENT responses. The three must
never be collapsed into one policy.

## The floor (what is sealed, and by what)

  BASE (the immutable golden image)   dm-verity — one hash tree over the whole
                                      device, read-only by design. This is the
                                      appliance; a mismatched base either
                                      matches or it does not.
  EXECUTABLES (on the writable layer) fs-verity (Merkle tree per file) + IMA
                                      appraisal (signature checked against the
                                      kidulKey keyring before exec).

"dm-verity ALL folders that execute" is the wrong unit — dm-verity is
block-level, not per-folder. The two jobs live in two places: dm-verity seals
the base, fs-verity + IMA seals what rides on top.

## Three failures, three responses

  1. INTEGRITY fail — bit-rot, torn write, dying disk. The bytes changed;
     nobody attacked. Response: AUTO-FALLBACK to last-known-good, warn, restore
     the base. No alarm.

  2. AUTHENTICITY fail — not signed by kidulKey. The attack signal. Response:
     FAIL-CLOSED. No auto-boot, no auto-rollback, gate on the human with the
     key. Auto-rollback here is the WRONG reflex: silently rolling back and
     booting "clean" hands a live attacker a warm box and a clean log. Stop,
     tell the human, wait.

  3. AUTHORIZATION fail — signed by us, in the wrong slot (a restricted-class
     binary in a system-class slot). Not corruption, not forgery — a policy
     breach. Response: fail-closed; it is a policy check, not a hash check.

Integrity fails benign, authenticity fails hostile, authorization fails
structural. The user's original "fallback + warn + remove the file" is correct
for (1) and dangerous for (2).

## The fallback lives BELOW the thing it recovers

The warning surface and the rollback are not part of the normal boot graph —
the normal graph is exactly what just failed. The warning rides the MOUTH
(getty) or a stub in kboot itself, independent of kidulwm. Same law as
power-states.md: the recovery path must never be corrupted by the boot it is
there to rescue.

## "Remove the file before it boots" — writable layer only

On the verity base there is nothing to remove: a mismatched base is restored
or its hash rotated, never "delete x from /usr." The remove-and-retry gate
applies ONLY to the writable/overlay execute path (downloaded content, user
config that picked up a stray executable). Two different recoveries; never one
UI pretending they are the same.

## The warning flag is tamper-evident

"Warn once you boot back in" needs a persistent flag, and that flag must not
be clearable by the thing that triggered it — a resident attacker must not be
able to clear the "warn me" bit and vanish. The flag rides the same signed,
verity-sealed storage as the base, not the writable layer.

## What this floor is, and is NOT

It is a STRUCTURAL INTEGRITY FLOOR: it kills bit-rot and userspace tampering.
It is NOT a kernel boundary. dm-verity, fs-verity, IMA, the fallback, the
warning — all enforced by the kernel. The brig remains the only kernel
boundary (crypto.md, verdict 89). "Verified boot everything" is the locks on
the interior doors, not a wall around the house.

## The admission gate (crypto.md) rides on this floor

This floor answers "is the code what we shipped, and is it allowed here."
The admission gate answers "is this process allowed to talk to that one."
Two rungs, one ladder: the floor seals what RUNS, the gate seals what TALKS.
Both stand on the kernel. Both fail-closed on authenticity.
