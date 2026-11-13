# DESIGN (draft) — the kidulKey is "a key for everything": one roster, many consumers (input-trust is the first)

DRAFT 2026-11-13, bobdotrix. Freeze this before any code. The "user vault"
Barticus described is NOT a device registry and NOT a special place — it is the
WHOLE kidulKey system: one key that verifies the user across EVERY surface
(buying media / accessing the account, the 5-phones-per-TV roster, opening
"person" in settings, and using the keyboard). "A key for everything." This doc
pins the ONE shared substrate and names the FIRST consumer we wire (input-trust
Tier 2, because it is the one with hardware today), then records the honest
build status.

## The increment (one sentence)

Do NOT build a new vault feature, and do NOT build a device-only registry. Wire
the ONE roster — the kidulKey-signed `{ attested-key -> role }` list (crypto.md
§household roster, kidulkey.md §what-it-signs) — as the single source of WHO for
EVERY "admit by proof." Input-trust Tier 2 is the first consumer; media purchase,
the phones roster, and settings/person are the SAME verification, not new
systems. "Every admit-by-proof resolves to the ONE signed roster."

## One key, many consumers (the "key for everything" map)

The kidulKey verifies the user; every surface that needs to know WHO you are
asks the SAME question and resolves to the SAME roster. The consumers are the
same primitive wearing different faces:

  input-trust Tier 2   the keyboard/remote proof  — FIRST (hardware today: the
                       kidulKey dongle is a CDC-ACM prover, 2fe3:0004)
  media purchase       "download / buy" account access — the media shop, and
                       anything else we end up selling. Same proof, same roster.
  phones per TV        the household roster (crypto.md role ∈ { TV, child-1..5,
                       guest, adult, NAS, remote }) — the kweb 5-phones-per-TV.
                       Same proof, same roster.
  settings / "person"  opening your person in the settings app — access
                       required, key exchange fires. Same proof, same roster.

This is crypto.md §One substrate, three consumers made explicit: ONE crypto
substrate (X25519, Ed25519, AES-GCM — kidulKey), MANY cued consumers. The
"crossing over" Barticus flagged is not a confusion — it is the design. The
roster is the keystone every admit resolves to; input-trust is just the first
place we turn it on.

## Identity vs approval (the boundary that keeps it clean)

These are two different things and must stay split — Barticus locked this, and
it is already law in two places:

  WHO (identity)   the roster/kpax. Signed ONCE by the root. Global: every box
                   caches a copy, verifies the signature, knows "this is
                   Barticus's Planck / Granny's phone." Non-repudiable. This is
                   what propagates system-wide, and it is the SAME roster for
                   every consumer above.

  WHAT (approval)  the per-node tier + allowlist (input-trust.md §ladder) and,
                   more generally, each surface's own grant. Local, revocable.
                   "Approved on the TV" means "approved for TV things on the TV,"
                   NOT "root everywhere." One key = one identity, NOT one
                   universal approval; approval stays per-surface.

Collapsing the roster into the cold vault (cold-storage.md) undoes this split.
The roster is PUBLIC signed material (cached per box, on the krouter —
kidulkey.md: "Public = published, no secret"). The cold vault holds SECRETS.
Two different organs; keep them two.

## The roster is the shared WHO for every consumer (resolve the naming)

Barticus's "user vault" = the kidulKey system itself, not any one file:

  roster (kpax)   { attested-key -> role }  signed by kidulKey root
                  cached per box, source of truth on the krouter
                  PUBLIC, signed, global = the ONE list every admit resolves to
  cold vault      the user's encrypted home — data at rest, cued, decrypt-on-read
                  holds SECRETS, holds NO private keys (crypto.md)

One line: the roster is WHO is known (for input, purchase, phones, settings);
the vault is WHERE secrets rest. The "key for everything" is the roster plus
the signing root above it — not the vault, not a device-only registry.

## How the FIRST consumer wires into the ladder

Today (deployed 21e8a90) the ladder classifies at enumeration from topology +
identity only:

  TIER 0  INTERNAL    bustype on a native bus        -> full binds (no proof)
  TIER 1  USABLE      VID:PID in /etc/kushd/input-allowlist -> type+navigate only
  TIER 3  UNTRUSTED   everything else                -> type+navigate only

  TIER 2  PROVEN      the crypto arm — NOT wired. No device lands here.

The wiring this doc pins: TIER 2 resolves against the ROSTER, not a local file.
At enumeration, a device presenting a proof identity is challenged against the
roster's attested key for that device (kidulKey Ed25519 challenge/response,
WYSIWYS tap). Pass -> the roster's role for that key applies -> Tier 2, harmful
binds live. The SAME roster later answers "may this phone board" (crypto.md
§TV is the policy approver) and "is this the account that buys media" — those
are later consumers on the same keystone, not new rosters.

  roster (WHO)  --signed once-->  cached on box  -->  every consumer challenges it
  ladder (WHAT)   per-device, at enumeration, fail-closed to UNTRUSTED

## The gate today — what it is, what it is NOT

kidulkey-gate (kidulkey/gate/) is the crypto heart, built and passing:

  - challenges the dongle: PUBKEY -> SIGN <nonce> -> tap -> verify Ed25519
  - emits TRUSTED / UNTRUSTED + writes a GLOBAL verdict /run/kushd/input-trust
  - the GLOBAL verdict is SUPERSEDED (input-trust.md §Status): it proves the
    SEAT (dongle tap), not THIS device. Promoting every device on a trusted seat
    re-opens the "first keyboard wins" hole. Do NOT wire Tier 2 to that verdict.

The kidulKey dongle itself is CDC-ACM only (VID 2fe3 PID 0004) — a PROVER, not
a keyboard. It never reaches libinput as an input device. The device that earns
Tier 2 is the REMOTE (a HID keyboard carrying the kidulKey seed, kidulkey.md
§personal shell). The dongle is the prototype proof primitive; the remote is
the production input.

So the "plug in the kidulKey and verify" step verifies the CRYPTO PRIMITIVE
(challenge/response holds), not yet a live Tier 2 keyboard. That is the honest
boundary of what is testable today.

## Honest build status (as of 2026-11-13)

  BUILT + verified        kidulKey firmware #2 (Ed25519 device-proof) — flashed,
                          test-proof.py VERIFY: OK.
  BUILT + passing         kidulkey-gate (crypto heart) — zig build clean.
  BUILT + deployed        per-device tier enforcement in kidulwm (21e8a90):
                          harmful binds gate on INTERNAL(0)/PROVEN(2) only.
  BUILT + deployed        wlroots four-tier classification (0/1/3 live, 2 stubbed)
                          + netlink hotplug + wlr_libinput_get_device_trust().
  NOT BUILT              roster/kpax enforcement (krouter-held, signed list);
                          key-cast vault unlock; hardware-attested SSH; and
                          Tier 2 wired to the roster. These are docket #53,
                          not done.

Both crypto.md and kidulkey.md carry: "architecture is frozen; MECHANISM not yet
built. Bench access TODAY is a plain ed25519 key on disk."

## Build order (the next slices, in order)

  1. Freeze this doc (the increment + the naming + the boundary).
  2. Roster file shape: signed `{ attested-key -> role }`, one file, krouter is
     source of truth, box caches + verifies. (Spec the format, not the code.)
  3. Tier 2 wiring: ladder challenges a proof-presenting device against the
     roster's attested key at enumeration; fail-closed to UNTRUSTED.
  4. kidulkey-gate: split the crypto heart (challenge/verify) from the global
     verdict write — the heart becomes the per-device proof call; the global
     verdict write is dropped.
  5. Wire the remote (HID + kidulKey seed) as the Tier 2 production device.

## Local-only artifacts (LOCKED, cross-ref kidulwm-codeberg-workflow)

  VPN/WireGuard/Mullvad config + creds, and the Planck allowlist config, NEVER
  go to Codeberg. They are copied directly machine -> KSD m.2. The roster
  (kpax) is PUBLIC signed material — it is NOT a secret and NOT a credential;
  only its SIGNING key is. Keep signing keys in silicon, never in a repo.

## Relationship to existing law

  crypto.md          §One substrate, three consumers + §household roster -> this
                     doc makes the consumers explicit (input, purchase, phones,
                     settings); every admit resolves to the ONE roster.
  kidulkey.md        §what-it-signs ("every admit-by-proof resolves to the ONE
                     signed roster") -> the roster is the key-for-everything
                     keystone; input-trust Tier 2 is its first consumer.
  input-trust.md     §ladder + §Status -> TIER 2 PROVEN resolves against the
                     roster, never the global /run/kushd/input-trust verdict.
  cold-storage.md    the vault stays SECRETS-ONLY; it is not the roster's home.
  identity.md        §key transparency -> the roster needs the append-only
                     auditable log shape (rotation = visible event, not silent).
