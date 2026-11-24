# DESIGN DRAFT — input trust, second order: the roamer's remote at a stranger TV

Status: SPEC DRAFT — the deep pass Barticus asked for (2026-11-23, GSI: "go as
deep as you need on the input of trust ... we don't trust, we verify ... quality
without compromising safety for ALL users"). This extends input-trust.md and
portable-homes.draft.md into the seam where they MEET: a portable home needs its
OWNER to carry an input device to a TV that has never met either of them.

## The one-line finding

The admission ladder is right in its spine — topology + identity + proof, never
arrival order. But TIER 2 "PROVEN" does DOUBLE DUTY: it is simultaneously (a) the
INPUT-TRUST tier (this device may fire harmful binds) and (b) the IDENTITY
resolution (this key-id has role X in the roster). Those are two different
questions and the ladder answers them with one verdict. That conflation is what
breaks the roamer — and the roamer is exactly the case that exposes it.

## The two questions (and why one tier is not enough)

  INPUT TRUST  "can this DEVICE type commands that hurt?" -> the tier ladder
               (Tier 0/1/2/3). Decided at enumeration from pairing + topology.
               Governs keybind power: which binds are live.

  IDENTITY     "who is the HOLDER, and may I mount their partition?" -> the
               roster (resident) or the drive manifest (roamer). Decided at
               PROOF (the tap). Governs WHAT mounts and WHO you are.

device-registry.md already wants these split (§Identity vs approval: "WHO
(identity) ... WHAT (approval) ... stay split"). But Tier 2 re-glués them:
PROVEN means BOTH "paired device" (input trust) and "roster role" (identity).
A resident never notices, because at home the two coincide — the paired remote
IS the rostered user. The roamer notices immediately.

## The roamer's actual problem, precisely

At their OWN TV, a user's remote is PAIRED (pubkey burned in) AND rostered. Both
questions answered. At a STRANGER TV, with their portable drive:

  INPUT  the remote is UNPAIRED here — no burned-in pubkey. The ladder cannot
         give it Tier 2, so it falls to Tier 1 (known VID:PID = usable) or
         Tier 3 (unknown). No harmful binds on the host.

  IDENTITY  the drive CARRIES the key-id in its KidulWorks-signed manifest, and
         the remote carries the seed. The tap (Ed25519 sign of a nonce) is
         verifiable against the manifest's key-id WITHOUT a prior pairing.

The two verdicts land at DIFFERENT tiers, and that is CORRECT — they were never
one question. The tap's proof and the input's binds are independent.

## The tap's cryptographic value is independent of the input tier

This is the fact that removes the panic. A Tier-1 device has a SPOOFABLE
identity (VID:PID), but it holds NO seed, so it CANNOT forge an Ed25519
signature. The tap's signature is valid or not regardless of the input tier that
carried it. Consequence:

  - a spoofed VID:PID device (Tier 1) can type usable binds, never harmful —
    contained by the tier.
  - a spoofed device CANNOT produce a valid tap — the seed is on-die. So the
    tap opens nothing for an impostor, no matter what tier it sits in.

Identity proof needs NO Tier 2. Input trust needs NO roster. The two should
never have shared a tier, and the roamer is the proof of it.

## The elegant answer: the drive's manifest IS the roamer's pairing

Pairing's one job is to make the gate KNOW the pubkey (burn it in). A roamer
cannot re-pair at every TV — pairing is the trust anchor; doing it casually
DEFEATS it. The fix is already in portable-homes: the drive carries the key-id
in a KidulWorks-root-signed manifest. So the gate's ground truth for the pubkey
has TWO legitimate sources:

  home    burned-in at pairing (the wire exchange)
  roam    read from the KidulWorks-signed manifest on the inserted drive

Both are root-anchored, so both are trustworthy. The challenge/response is
IDENTICAL (same nonce -> tap -> verify); only the pubkey's provenance changes.
And since the pubkey is public-not-secret (roster-format: keys are public), a
hostile drive presenting a bogus manifest pubkey gains nothing — the attacker
still needs the matching SEED to sign, and that is what is unforgeable.

So a roamer at a stranger TV:

  drive in -> manifest verified (KidulWorks root) -> key-id learned
  remote taps -> nonce signed -> verify against key-id (no pairing needed)
  home opens -> guest authority, Tier 1 input (usable binds only)

The remote rides in as a dumb USABLE keyboard; the DRIVE + the tap carry the
trust. Least privilege, zero new attack surface, no per-TV pairing.

## The residual question (flag for ruling, not decide here)

Tier 1 grants USABLE only — no harmful binds (spawn/close/reset/browser). For a
roamer on their OWN drive, is that enough? Two honest answers:

  A. YES — the deck/kidul-flow navigates apps within the mounted guest session
     without raw harmful keybinds; a guest needs no host-wide spawn/reset. Least
     privilege, clean, nothing new to build.

  B. NO — a roamer should be able to spawn a terminal/browser INSIDE their own
     seat; harmless to the HOST but blocked by the tier. Would need a new
     "guest-scoped harmful" grant: binds permitted with EFFECT scoped to the
     guest session, never the host.

This is a genuine ruling for Barticus, not a wave-through. A is the safe
default and costs nothing; B is more usable for the roamer and is DEFENSE BY
ARCHITECTURE (scope the bind's effect, not the whole tier) but is a real build.

## What this means for the ladder (a LAW refinement, not a rewrite)

The four tiers stay. What changes is the ANSWER Tier 2 gives:

  - Tier 2 UNGLUES: "PROVEN" answers INPUT trust (the paired device may fire
    harmful binds) — it does NOT resolve identity.
  - IDENTITY moves entirely to the resolution step: roster for residents,
    KidulWorks-manifest for roamers. The tap is where identity is decided, and
    the tap's validity is tier-independent.
  - The roamer's input is Tier 1 (usable) BY DESIGN, and that is correctness,
    not a downgrade: a guest gets usable binds on a host they do not own.

## Relationship to existing law

  input-trust.md      the ladder stays; Tier 2 stops double-dutying (identity
                      resolution out, device-trust stays).
  device-registry.md  §Identity vs approval ALREADY names the boundary — this
                      draft is the build consequence of it, finally enforced.
  device-proof.md     the tap (nonce -> sign -> verify) is unchanged and gains
                      a second pubkey provenance (manifest, not only burn-in).
  portable-homes.md   the manifest already carries key-id; this draft makes
                      that the roamer's pairing substitute.
  attestation.md      hostile-drive safety: a bogus manifest pubkey is useless
                      without the seed — no new trust gap.
  sign-in-tap-first   the Visitor door ("plug in your drive -> tap") rides this
                      exact path; the drive + tap ARE the sign-in.
