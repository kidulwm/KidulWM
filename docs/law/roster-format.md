# LAW — roster-format (kpax): the signed { attested-key -> role } file

LOCKED 2026-11-14, Barticus present (GSI). This is build-order slice 2 of
docs/design/device-registry.draft.md ("Roster file shape — spec the format,
not the code"). It pins the ON-DISK / ON-WIRE shape of kpax so the Tier-2 wiring
(slice 3: ladder challenges a proof-presenting device against the roster) has a
concrete format to parse and verify.

## The increment (one sentence)

Spec the byte-exact format of the ONE signed roster — kpax — that every
"admit by proof" resolves to, so input-trust Tier 2 (first consumer) and the
later consumers (media purchase, phones-per-TV, settings/"person") parse and
verify the SAME file. This doc is the FORMAT only; WHO-vs-WHAT, deny-by-default,
and file-by-file are already law (kid.md, crypto.md, kidulkey.md).

## What is already law (ground, do not re-derive)

  kpax          { attested-key -> role }, signed by the kidulKey ROOT, cached
                per box, source of truth on the krouter (crypto.md §88-110,
                kidulkey.md §56-61 "ROOT signs the roster / kpax").
  role          ∈ { TV, child-1..5, guest, adult, NAS, remote, ... } — up to 5
                child slots; "..." = extensible (crypto.md §95).
  PUBLIC        the roster is PUBLIC signed material, NOT a secret, NOT a
                credential; only the SIGNING key is secret (in silicon)
                (kidulkey.md §184-185, device-registry.draft.md §150-155).
  WHO only       identity (the roster) is global + non-repudiable; APPROVAL
                (per-node tier + allowlist) stays local + revocable and is
                NEVER in this file (kid.md §47-52, device-registry.draft.md §43-63).
  key transparency  rotation must be a VISIBLE event, never a silent swap
                (identity.md §67-73) -> the format carries an append-only shape.
  two-key rule  the ROOT is TWO keypairs (#1, #2); strike a lost key's public
                half and register fresh — recovery is register-new, never
                restore-a-copy (kidulkey.md §71-81).
  deny-by-default  absent / unknown key-id -> UNTRUSTED floor, never an implicit
                role (kid.md §17-19, input-trust.md §ladder).

## The keystone fact (why one format serves every consumer)

The roster's `attested-key` IS the device's Ed25519 identity/proof key — the
same 32-byte public key the Tier-2 challenge/response proves (device-proof.md:
tap-sign a nonce, host verifies Ed25519). One key does two jobs and must NOT be
split: it names the device in the roster AND it is the thing challenged at
admission. A phone boarding, a media purchase, and a keyboard admission all
challenge the SAME key that is on the SAME list. That identity = the "key for
everything"; this format is where the key's name lives.

## The format (concrete, byte-exact)

kpax is a line-oriented canonical text file. One record per line, LF
terminated, no trailing whitespace, no blank lines, no comments in the
serialized form (comments live only in the source-of-truth authoring copy on
the krouter's dom0, never in what a box verifies).

  Line 1 (header):     kpax version=<n> root=<root-key-id> prev=<hash>
  Line 2.. (entries):  <key-id> <role> [added=<version>] [struck=<version>]

Fields:

  <n>            monotonic uint64 version. Every re-sign bumps it by 1.
  <root-key-id>  which ROOT key signed this file (key#1 or key#2 — the two-key
                 rule). Both public halves are registered on the box; this field
                 says which one to verify against.
  <prev>         hex sha256 of the PRIOR canonical bytes (the previous version's
                 exact serialized text). Empty/zeros for version 1. This is the
                 append-only chain (identity.md §key transparency).
  <key-id>       base64url (RFC 4648, NO padding) of the device's 32-byte
                 Ed25519 public key. All attested keys are Ed25519 today; a
                 future post-quantum key (kidulkey.md §283) adds an algo tag
                 (`<algo>:<b64>`), never a bare different-length blob.
  <role>         lowercase kebab-case: tv, child-1 .. child-5, guest, adult,
                 nas, remote, or a free-form extension token. Unknown roles
                 fail-closed to guest/untrusted (never an implicit grant).
  added / struck optional version numbers. `added=<v>` records when the key
                 joined; `struck=<v>` TOMBSTONES the key (revocation is append,
                 never delete — a strike is a visible line, not an erased one).
                 A struck key-id verifies but is NOT admitted anywhere.

Canonical order: entries are sorted by <key-id> ascending (byte order of the
decoded key). The verifier re-sorts before hashing/checking, so hand-edits that
reorder lines still verify — canonicalization is the sort, not the authoring.

The SIGNATURE is a detached Ed25519 signature over the EXACT canonical bytes
(header line + sorted entries), stored as `<file>.sig` (base64url, no padding)
beside the roster. The ROOT key that made it is named in the header's `root=`
field; the box holds both ROOT public halves (registered at verified-boot /
baked into the signed golden image — verified-boot.md, NOT a runtime fetch).

  kpax              -> the canonical text above
  kpax.sig          -> base64url( Ed25519_ROOT_sign( sha256(kpax) ) )
  both cached on the box, re-verified at every association (refresh-on-associate)

## Example (illustrative, not authoritative)

  kpax version=3 root=k1 prev=9f2c...
  <b64-ed25519-A> tv added=1
  <b64-ed25519-B> child-3 added=2
  <b64-ed25519-C> guest added=1 struck=3

(C died / was struck in v3: its line stays, tombstoned, so the strike is a
visible append — a revoked device is gone everywhere at once, kidulkey.md §208-210.)

## What is NOT in this file (the boundary)

  - NO approvals. Per-node tier + allowlist (input-trust.md §ladder) is local +
    revocable and lives on the box, not here. One key = one identity, NOT one
    universal approval (kid.md §47-52).
  - NO secrets, no private keys, no PINs, no cold-vault material. The cold
    vault (cold-storage.md) is a different organ.
  - NO network identity (SSIDs/PSKs/addresses). Local-only, never pushed
    (kidulwm-codeberg-workflow — secrets hygiene).

## Verification flow (the only thing a box does)

  1. Fetch kpax + kpax.sig from the krouter (source of truth).
  2. sha256 the canonical bytes; verify the detached sig against the ROOT
     public half named by `root=` (from verified boot, not a fetch).
  3. Check version monotonic + prev-hash chains from the cached copy (rotation
     is visible; a non-chaining file is refused).
  4. Resolve any key-id against this verified roster at admission. Unknown /
     struck / bad-sig -> UNTRUSTED (deny-by-default).

Nothing here runs at boot-time (crypto.md: crypto is connection-time, never
boot-time). Verification is cued at association, exactly like every other
admit-by-proof.

## Rulings (LOCKED 2026-11-14, Barticus present: yes to all recs)

  A. CONTAINER — line-oriented canonical text. Minimal Zig parser (no JSON in
     stdlib), grep-auditable for the sysadmin, canonical-by-construction (sort
     + exact bytes, no canonicalization library). JSON is NOT used on-box.

  B. SIGNATURE — single ROOT signature + `root=` field naming which of the two
     root keys signed. The two-key rule is REDUNDANCY (either root can act,
     strike the lost one), not a quorum; a strike is a version bump re-signed
     by the survivor / a freshly registered key.

  C. CHAIN — version + prev-hash. Rotation is a visible, chained event
     (identity.md §key transparency); a silent rollback is detectable. Cost is
     one 32-byte field per version.

  D. ROLE ENUM — fixed known set + free-form extension, child-1..5 as FIVE
     explicit slots. The five-token cap is structural (crypto.md §99), not a
     policy check; an unknown role fails-closed to guest/untrusted.

## Relationship to existing law

  crypto.md          §household roster + §KID+kpax -> this is that file's shape.
  kid.md             deny-by-default + file-by-file + "one roster" -> the file
                     is the "one roster" made concrete.
  kidulkey.md        §what-it-signs (ROOT signs the roster) + two-key rule ->
                     root= field + single-signature ruling (Q B).
  identity.md        §key transparency -> prev-hash chain (Q C).
  device-proof.md    the attested-key IS the proof key (the keystone fact).
  device-registry.draft.md  build-order slice 2 -> this doc IS slice 2.
  input-trust.md     §ladder -> Tier 2 resolves against THIS file, fail-closed.
