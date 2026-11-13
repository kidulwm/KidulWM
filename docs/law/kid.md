# LAW — kID (the kidul identification) — deny-by-default, one key, one roster

LOCKED 2026-11-13, Barticus present (GSI).

## One line

kID = the kidul identification. The identity every other gate hangs off. One
key verifies the user; every surface that needs to know WHO you are asks the
SAME question and resolves to the ONE roster. Deny-by-default, file-by-file.

## The model — what "a key for everything" means

  ONE KEY     the kidulKey family (ROOT / SYSTEM / PERSONAL — kidulkey.md).
              The key proves the identity; it is never a password.
  ONE ROSTER  kpax = { attested-key -> role }, signed by the ROOT, cached per
              box, source of truth on the krouter (crypto.md §household roster).
  DENY BY     nothing is reachable until a kID grants it. UNTRUSTED is the
  DEFAULT     input floor (input-trust.md §ladder); public nopasswd is the seat
              floor (public-seat.md). No grant = no access, always.
  FILE BY     the grant granularity is the FILE, not the box and not the user.
  FILE        fs-verity (Merkle tree per file) + IMA (verified-boot.md) is the
              enforcement; a kID's reach is a set of files it is admitted to,
              never "the whole machine because you got in."

## The one sentence

Every "admit by proof" resolves to the ONE signed roster (kidulkey.md §what-it-
signs). That IS kID: one identity, universally adhered to, restrict-by-default.

## The consumers — same kID, different surfaces

These are NOT new systems and NOT separate keys. They are the ONE verification
wearing different faces, all resolving to the same roster:

  input-trust Tier 2   the keyboard/remote proof (FIRST consumer — hardware on
                       the bench today).
  media purchase       "download / buy" account access — the media shop and
                       anything else we sell.
  phones per TV        the household roster roles (crypto.md: TV, child-1..5,
                       guest, adult, NAS, remote).
  settings / "person"  opening your person in the settings app — access
                       required, key exchange fires.

crypto.md §One substrate, three consumers, made explicit: one crypto substrate,
many cued consumers, one roster behind them all.

## What kID is NOT (the boundary that keeps it from defeating itself)

  NOT universal    kID is IDENTITY (WHO), and WHO is universal. APPROVAL (WHAT)
  approval         stays per-surface (input-trust.md, public-seat.md). One key =
                   one identity, NOT one key = root everywhere. Collapsing them
                   would defeat the whole architecture — Barticus 2026-11-13:
                   "100% universal approval would defeat what we are doing."
  NOT a password   nothing recited, nothing remembered. The key + the finger.
  NOT the vault    the cold vault is WHERE secrets rest; kID is WHO you are.
                   Two organs (cold-storage.md) — never collapse them.

## Relationship to existing law (this doc is the umbrella, not a rewrite)

  crypto.md    §KID + kpax — the admission gate. This file is that section's
               full home; the term appeared there as "KID", here it is "kID
               (kidul identification)" — SAME concept, now given its own law.
  kidulkey.md  the key family (three tiers) + what each tier signs.
  identity.md  the four scopes + the bar (which tool serves which audience).
  input-trust.md  the ladder — fail-closed, UNTRUSTED default (the deny-by-default).
  public-seat.md  the floor — public nopasswd, nothing personal on it.
  verified-boot.md  fs-verity + IMA — the per-file enforcement (file-by-file).
  partitions.md  the key-gated personal layer the kID casts.

## Build status (honest)

Architecture frozen here: the naming, the boundary, deny-by-default, file-by-
file. MECHANISM is not yet built — input-trust Tier 2 is not wired to the roster
(docket #53/#57), roster enforcement is not built, fs-verity/IMA is partial
(verified-boot.md). This is the law the build must obey, not a claim that it is
built. Bench access today is a plain ed25519 key on disk (crypto.md STATUS).
