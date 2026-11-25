# design — the signer (ksign) — one SOURCE, never a raw key — the signing boundary

LOCKED 2026-11-25, Barticus present (GSI) — "yes to your recs" on A-D. The
SIGNER SEAM is frozen: one verb ksign, two sources (dev-root + se050), the
se050 backend stubbed fail-closed until silicon is on the bench, attestation out
of this cut, kseed takes `<source>` with no raw-seed back door.
Draft 2026-11-25 (bobdotrix, GSI). Spec-first freeze BEFORE code. Answers the
"test key vs production key" fork for good by making the SIGNATURE PRODUCER a
single seam with two backends, so the ceremony code never again holds OR knows
where a key's private half lives.

Authority referenced: kidulkey.md (LOCKED — the ROOT is cold silicon, private
half lives NOWHERE but silicon), claim-carve.draft.md ruling B (LOCKED — sign
with the proved owner key, never the kalloc TEST seed; if owner-key signing is
unreachable, STOP).

## The problem, one sentence

kseed today signs HOST-SIDE by deriving an Ed25519 key from an on-disk seed
(RFC 8032 generateDeterministic). Production destroys that model: the ROOT's
private key is BORN ON-DIE in the SE050 and never leaves — "sign" becomes an
APDU to cold silicon, and the host only ever sees the public half + an
attestation certificate. The seam that hides this difference is the signer.

## The abstraction — ksign, one verb, one SOURCE

  ksign <source> <canonical-file> [sig-out]

One job, per the sealed-verb law: produce a detached Ed25519 signature over the
canonical bytes of <canonical-file>, and emit the signer's public half + key-id.
Nothing else. No parse, no resolve, no append — that stays in kpax/kalloc/kseed.

  ksign dev-root:<seed-file> <canon> [sig]   -> SIG dev-root key=<key-id>
  ksign se050:<device-or-slot> <canon> [sig] -> SIG se050 key=<key-id>

The <source> names WHERE the key lives. ksign never sees a raw key; it sees a
SOURCE. That is the entire point: the caller (kushd, the ceremony) can say "sign
this" without ever being able to say "here is the key".

## The two SOURCES (and ONLY these two)

  dev-root   a DISPOSABLE on-disk seed (0600, test-namespaced, marked never-ship).
             Exists SOLELY to drive rigs and the disposable dev root so the claim
             ceremony is provable end-to-end today. It signs RFC 8032 in software.
             It is the thing ruling B warns against ever leaking into production.

  se050      production. The signature is an APDU to the SE050 over I2C
             (T=1-over-I2C). The key is generated on-die at provisioning and never
             exported; the host reads the public half + the NXP attestation chain
             only. sign(canon) returns the detached sig; the private half never
             appears anywhere a host can reach.

No third source. Nothing transparently "fall-back"s from se050 to dev-root — a
missing SE050 is a STOP, not a silent downgrade to the test seed (ruling B).

## The interface contract every SOURCE must satisfy

  1. identity()      -> public half (64-hex) + key-id (43-char b64url of pub)
                       + the name of the source. Never the private half.
  2. sign(canon)     -> a detached Ed25519 signature over the canonical bytes,
                       RFC 8032 raw (NOT Ed25519ph), byte-interoperable with the
                       existing kpax/kalloc `verify` path. Fail-closed on any
                       unreachable/unarmed source: no signature, exit non-zero,
                       a stderr reason.
  3. self-describe   the artifact header's root= is DERIVED FROM the source that
                       actually signs (a kseed property that carries forward):
                       a map can never be signed by one key and attributed to
                       another, because root= names the signer that produced it.
  4. never-export    no verb, flag, error path, or log emits key material. The
                       private half has no wire representation, ever.

## What CHANGES vs. today (nothing on the verify side)

  - kseed keeps its ceremony shape (append both artifacts, version-bump each,
    chain prev, re-sign both, verify both) but its signing step delegates to the
    signer SOURCE instead of deriving from a passed seed-hex. The arg becomes
    `<source>`, not `<root-seed-hex>`.
  - kpax/kalloc `verify`, `resolve`, `canonical` — SOURCE-agnostic, UNCHANGED.
    This is the payoff: the ~95% of the chain that READS and CHECKS signatures
    does not care whether the sig came from software or silicon.
  - The kpax/kalloc `sign` TEST helper is RETIRED the moment ksign exists (it was
    already flagged for removal — claim-carve.draft.md §Open). ksign dev-root
    replaces it everywhere a rig needs to author a signed map.

## Fail-closed rules (LOCKED, carry forward from ruling B)

  - se050 unreachable or unarmed (no human consent) -> STOP, nonzero, stderr.
  - Never dev-root in production, never se050 in a rig. Source is EXPLICIT, never
    defaulted, never inferred from "what's plugged in".
  - A produced signature MUST verify against the header root= that names its
    signer, checked by the writer before it reports success (kseed already does
    this; ksign must too where it writes the sig back the caller verifies).
  - The private half has no path, no file, no env var, no log line. If it would
    appear in any string, that is a bug by construction.

## done-when

  - ksign exists as ONE verb, source-selected, signing canonical bytes for
    dev-root (now) and se050 (a later backend, interface already frozen).
  - kseed delegates signing to the SOURCE and is re-rig-proven: fresh seed,
    second resident, duplicate fail-closed, signer attribution all still green,
    now THROUGH the seam rather than around it.
  - A rig proves the seam itself: dev-root signs -> verifies against header
    root= = the dev-root key-id; the kpax/kalloc `verify` path is byte-identical
    whether the sig came from software or (later) silicon.
  - The kpax/kalloc `sign` test helper is GONE.

## Open questions — LOCKED (Barticus 2026-11-25, GSI: "yes to your recs")

  A. VERB NAME + SHAPE. LOCKED: `ksign <source> <canon> [sig]`, source =
     dev-root:<seed-file> | se050:<device>. One verb, prefixed arg, nothing else.

  B. WHERE THE SE050 BACKEND LIVES. LOCKED: freeze the INTERFACE now, land
     dev-root behind it now, se050 is a STUBBED backend that fails-closed with
     "se050 source not built this cut" until silicon is on the bench.

  C. ATTESTATION, NOW OR LATER. LOCKED: OUT of this cut. ksign se050 carries
     identity() pub + key-id only; the trust-in-CERT chain (NXP-signed chip
     identity) is the later attestation.md apex slice, not the signing seam.

  D. WHETHER kseed KEEPS its seed-hex arg. LOCKED: NO — the arg becomes
     `<source>` outright. No raw-seed back door.

## What this does NOT touch

  - The People app / delegation.md (later slice, unchanged).
  - Attestation / measured boot / fTPM seal (attestation.md apex, later).
  - The firmware #2 device-proof dongle (input-trust) — unchanged; it is a
    roster ENTRY, never a signer, and still is not.
  - The SE050 carrier board design (a hardware slice, later).
