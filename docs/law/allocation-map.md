# LAW — allocation map (kalloc): the signed { attested-key -> partition } file

LOCKED 2026-11-17, Barticus present (GSI). This is build-order step 4 (re-seat +
mount) slice 1 — the WHAT half of the proof->re-seat->mount pass. It pins the
on-disk shape of the key-gated partition map so the sealed mounter (slice 2) has
a concrete format to parse and verify.

## The increment (one sentence)

Spec the byte-exact format of the ONE signed allocation map — kalloc — that maps
an attested key-id to its per-user partition (the FREE POOL carve). It is a
SEPARATE artifact from the roster (kpax): the roster is WHO (identity), the
allocation is WHAT (storage). Both signed by the same kidulKey ROOT, both
deny-by-default.

## Why separate from the roster (the boundary)

  roster (kpax)  { attested-key -> role }  = WHO. GLOBAL, sourced from the
                 krouter, cached per box, churns on key add/strike. It is the
                 identity file (roster-format.md: "WHO only").

  allocation     { attested-key -> partition } = WHAT. LOCAL — this box's FREE
  (kalloc)       POOL, carved by the People app / owner (delegation.md), churns
                 on carve/decommission. Two boxes have DIFFERENT allocations
                 even with the SAME roster.

Two axes, two files, one trust anchor. Mixing the partition into the roster
would make a global identity file carry per-box storage facts (wrong lifetime,
wrong author, wrong scope) and force a roster re-sign on every carve.

## The keystone fact (why one key-id serves both files)

The `attested-key` in BOTH files is the SAME 32-byte Ed25519 public key — the
device's identity/proof key (roster-format.md §keystone). The roster says WHAT
ROLE that key is; the allocation says WHAT PARTITION that key may cast. The gate
proves the key, the roster resolves WHO, the allocation resolves WHAT, the sealed
mounter mounts exactly that partition. Three verbs, each sealed, each checking
the next (privileged-verbs.md).

## The format (concrete, byte-exact)

kalloc is a line-oriented canonical text file, mirroring kpax exactly:

  Line 1 (header):     allocation version=<n> root=<root-key-id> prev=<hash>
  Line 2.. (entries):  <key-id> <partition> [added=<version>] [struck=<version>]

Fields:

  <n>            monotonic uint64 version. Every re-sign bumps it by 1.
  <root-key-id>  which ROOT key signed this file (key#1 or key#2 — the two-key
                 rule, kidulkey.md). Both public halves are on the box; this
                 field says which one to verify against.
  <prev>         hex sha256 of the PRIOR canonical bytes (append-only chain,
                 identity.md §key transparency). Empty/zeros for version 1.
  <key-id>       base64url (RFC 4648, NO padding) of the device's 32-byte
                 Ed25519 public key — the SAME key-id the roster attests.
  <partition>    a single whitespace-free token: a PARTUUID or filesystem UUID
                 the sealed mounter resolves to a device path. Absent key-id =
                 NO partition (deny-by-default — a crew/guest key is simply not
                 listed); struck = decommissioned (append, never erase — a
                 carve removal is a visible line, not a silent delete).
  added / struck optional version numbers, same semantics as the roster.

Canonical order: entries sorted by <key-id> ascending (byte order of the decoded
key). The verifier re-sorts before hashing/checking, so hand reordering still
verifies.

The SIGNATURE is a detached Ed25519 signature over the EXACT canonical bytes,
stored as `<file>.sig` (base64url, no padding) beside the map. The signing key
is named in `root=`; the box holds both ROOT public halves (verified-boot.md).

  kalloc            -> the canonical text above
  kalloc.sig        -> base64url( Ed25519_ROOT_sign( sha256(kalloc) ) )

## What is NOT in this file (the boundary)

  - NO mount flags, no fstab semantics, no fsck policy — those are the sealed
    mounter's job (slice 2), not a signed data fact.
  - NO LUKS keys, no key-wrapping material — the partition is encrypted and the
    unlock key rides the cold vault (cold-storage.md) / the key's own proof, NOT
    this public file (kidulkey.md: the roster/allocation are PUBLIC, the signing
    key is the only secret).
  - NO role, no scoping (Residents vs KidulCrew) — that is derived from the
    roster's role field, not duplicated here (one source of truth per axis).
  - NO approvals. A partition the key may cast is a storage allocation, not an
    admission approval (input-trust.md §ladder stays local + revocable).

## Verification flow (what the sealed mounter does)

  1. Load kalloc + kalloc.sig (box-local, written by the People app at carve).
  2. sha256 the canonical bytes; verify the detached sig against the ROOT public
     half named by `root=`.
  3. Resolve the proven key-id -> partition. Absent / struck / bad-sig -> none
     (deny-by-default, the mounter mounts nothing).

Nothing here runs at boot-time. Resolution is cued at proof, exactly like every
other admit-by-proof (crypto.md: crypto is connection-time, never boot-time).

## Rulings (LOCKED 2026-11-17, Barticus present)

  A. SEPARATE FILE — kalloc is its own signed artifact, NOT an extension of kpax.
     WHO (global identity) and WHAT (local storage) are different axes with
     different lifetimes and authors; one file per axis.
  B. SAME KEY-ID — both files attest the same 32-byte Ed25519 key-id. No new
     identity namespace; the key for everything is the key everywhere.
  C. SAME SHAPE — kalloc mirrors kpax byte-for-byte (canonical text, sort,
     detached sig, version + prev chain). One format family, two members; a
     verifier written for one is a template for the other.
  D. PARTITION = TOKEN — a single UUID token, resolved by the mounter, never a
     raw device path (device paths are not stable across boots; the UUID is).
     The mounter owns the token -> /dev/ resolution, not this file.

## Relationship to existing law

  roster-format.md   the sibling file (WHO); kalloc mirrors its shape (Q C).
  partitions.md      per-user partitions cast by the key -> this file IS the
                     cast map made concrete (the "just another partition" key).
  privileged-verbs.md  the sealed mounter (slice 2) verifies + resolves against
                     THIS file, then mounts exactly what it says (deny-by-default).
  kidulkey.md        two-key rule (root= field), public-not-secret, cold-vault
                     key material stays out of this file.
  delegation.md      the People app / owner carves + signs kalloc at allocation.
  cold-storage.md    the LUKS unlock key is NOT here; it rides the cold vault.
  identity.md        key transparency -> the prev-hash chain.
