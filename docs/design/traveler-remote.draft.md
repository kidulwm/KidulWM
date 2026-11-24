# DESIGN DRAFT — the traveler: remote + m.2, paired from the drive, owner never in the loop

Status: SPEC DRAFT — Barticus 2026-11-23 (GSI). The traveler's computer is
"the remote & the m.2, and it fits in your pocket"; a pairable keyboard joins
for serious work. This draft answers ONE question: can the user's own remote +
keyboard be paired AT a stranger TV (a hotel), drawing that pairing from the
USER'S DRIVE, without the hotel owner approving — and without a security risk?
The answer is YES, and the mechanism is the cleanest thing in the whole roamer
design, IF we keep one secret where it has always lived.

## The find: "pairing" is two acts wearing one word

The word "pairing" has been doing two jobs, and the roamer/hotel case forces
them apart:

  PAIR (admit)   the device proves it is genuine and gets admitted to the seat
                 for THIS session. Root of trust = the KidulWorks signing root
                 (attestation.md: the key verifies against KidulWorks, NEVER
                 the host's owner). No owner anywhere in this act.

  PAIR (burn)    write the device's pubkey into the host as durable state, so
                 the host remembers it next time. This is what a resident's own
                 TV does — and it is EXACTLY what a hotel must NOT do.

Barticus's instinct — "paired and forgotten when finished" — is the burn act
collapsing to nothing. The elegant answer is to admit without burning: verify
the device for the session, grant a guest seat, and forget everything on
unplug. Zero host residue, zero cleanup burden, zero next-guest attack surface.

## The mechanism (verify, never burn)

The traveler inserts their m.2. What travels from the drive is PUBLIC material
only, and the device proves the secret it alone holds:

  drive carries   the key-id (pubkey) in its KidulWorks-signed manifest, PLUS
                  the CERTIFIED pubkey of the remote/keyboard the user intends
                  to use. Both public. Both root-signed. No seed, ever.

  device proves   the on-die seed via challenge/response: gate sends nonce,
                  remote/keyboard signs with the seed that never leaves silicon
                  (device-proof.md), gate verifies against the drive-carried
                  pubkey.

  gate verifies   three things, all against the KIDULWORKS ROOT: (1) the drive
                  manifest is genuine, (2) the certified input pubkey is genuine,
                  (3) the tap signature matches. If all three hold, the device
                  is admitted — NOT because the hotel trusts it, but because it
                  IS a genuine Kidul device and it holds its own seed.

  session scoped  guest authority: the user's home mounts from their m.2, the
                  input is confined to usable binds (the A/B ruling below), the
                  hotel TV grants NOTHING and retains NOTHING.

This is "don't trust, we verify" made literal: the hotel TV trusts no one. It
VERIFIES the KidulWorks root chain and the unforgeable tap, then confines the
result. The hotel owner is structurally absent — and that is correct (portable-
homes R2: self-sovereign; attestation.md: "the hotel owns the TV but cannot
sign a fake clean").

## The line we do not cross: the seed stays on the device

Everything the drive carries (pubkey, manifest, certification) is public and
root-signed. The seed is born on-die and never leaves (device-proof.md §seed
lifecycle: "never copied into main RAM, never exported"). Why this exact line
matters:

  - Carry the PUBKEY on the drive -> safe. It is public-not-secret; a hostile
    drive presenting a bogus pubkey is useless without the matching seed.
  - Carry the SEED on the drive -> catastrophic. The drive becomes a key CLONER:
    steal/lose the drive, clone the keyboard. This would unravel device-proof.md
    ("a clone is worth nothing while its public half is not in the roster") by
    putting every key's secret in one pocket-sized box.

So: the remote/keyboard's IDENTITY rides on the drive; its SECRET never does.
The tap is what proves possession of the secret; the drive is what proves the
device is genuine. Two halves, one gate, no residue.

## The hardware seam the m.2 hub opens (and we must close it)

Barticus's m.2 hub is a ribbon-cable module Cambium-replaceable when the
connections wear. That is correct engineering — but it interacts with the
input-trust ladder in a way that is a latent bug, not a detail:

  input-trust.md Tier 0 = "INTERNAL ... bustype on a native bus (PCI/...)".
  A traveler's m.2 in the hub enumerates on PCIe — a NATIVE BUS. A classifier
  following the letter of Tier 0 would auto-trust it as the box's own internal
  storage: WRONG — it is user-swappable, hot-inserted, and must be treated as
  REMOVABLE media (the drive-manifest/verify path), never soldered-internal.

The discriminator has always been "topology + identity + proof, never arrival
order." The removable m.2 slot is a new TOPOLOGY: a native-bus port that is NOT
the box. The ladder needs one new clause: a device on a native bus whose slot
is hot-swappable/removable is NOT Tier 0 — it is REMOVABLE, and storage on it
resolves through the drive-manifest path, never the soldered-internal trust.
Flag it now, close it in the ladder, and the hardware upgrade introduces no
new auto-trust hole.

The same seam applies to the hub's electrical shape: native speed (PCIe) is a
PERFORMANCE fact, not a TRUST fact. We never let "fast" smell like "trusted."

## The attestation fork (this is where Barticus's A/B burns)

input-trust.md §Pairing attests: a genuine device must also ATTEST its firmware
(measured, signed against the root) or a trojan-reflashed remote — one still
holding the genuine seed — passes the challenge. For the traveler this decides:

  USABLE (A)   challenge/response + drive-carried pubkey + KidulWorks manifest
               is ENOUGH. No firmware attestation needed. The device is
               admitted usable-only; no harmful binds. Zero new build beyond
               the roamer manifest.

  TRUSTED (B)  to grant the traveler guest-scoped harmful binds (spawn a
               terminal INSIDE their own seat), the device must ALSO attest its
               firmware (measured boot, signed quote). Heavier — and it is the
               SAME seam as the A/B ruling from input-trust-roamer.draft.md.

The two drafts converge here: whether the traveler's keyboard gets usable-only
or guest-scoped-harmful is ONE ruling, not two. A is the safe default and costs
nothing; B adds firmware attestation to the traveler's device and is a real
build. Both keep the owner out of the loop; both leave zero host residue.

## Why the hotel case is already "no-owner" (not a new exception)

The owner-approval model only EXISTS where there is a household roster — a
family TV. A hotel owner is a corporation; there is no roster for a traveler to
enter, and requiring the front desk to "approve" a keyboard is, in Barticus's
words, too-hard-basket stuff and also WRONG (attestation.md: the owner cannot
sign what the guest needs). So the traveler never asks the owner. They ask the
drive, which asks the KidulWorks root, which the device answers with its seed.
The owner is not absent by oversight; the owner is absent by ARCHITECTURE.

## Relationship to existing law

  input-trust.md        Tier 2 unglues from identity (input-trust-roamer);
                        this draft adds the REMOVABLE-slot clause to the ladder
                        so the m.2 hub is never mis-filed as Tier 0.
  device-proof.md       the seed stays on-die — reaffirmed as the line that
                        makes drive-carried pairing safe; only the pubkey
                        travels.
  portable-homes.md     the manifest already carries key-id; it now MAY ALSO
                        carry the certified pubkey of the user's input devices.
  attestation.md        the trust anchor is KidulWorks, never the host owner —
                        the hotel "no-owner" model is this law, applied.
  sign-in-tap-first     Visitor door ("plug in your drive -> tap") is exactly
                        this path; the drive + tap + seed ARE the sign-in.
  re-seat.md            "unplug = gone" / kclean self-dismantling is the
                        pair-and-forget guarantee: admit, seat, forget on unplug.

## Residual risks flagged (not hidden)

  1. The m.2 removable-slot classification MUST land in the ladder before any
     traveler hardware ships — otherwise the hub is a Tier-0 auto-trust hole.
  2. Certified input pubkeys on the drive are only as trustworthy as the
     KidulWorks root that signs them; if that signing root is ever leaked, every
     traveler's "genuine device" certification collapses. The root's custody is
     already vault-tier (kidulkey.md / kidulkey entry); this draft makes that
     custody load-bearing for the whole traveler fleet, not just one house.
  3. Firmware attestation (B) is not yet built anywhere (attestation.md honest
     status) — the A path needs nothing new, but B is gated on the TPM-quote
     work ahead of us, not a flag we can wave through.
