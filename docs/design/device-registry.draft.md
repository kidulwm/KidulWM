# DESIGN (draft) — device registry = roster/kpax, wired to input-trust admission

DRAFT 2026-11-13, bobdotrix. Freeze this before any code. It pins ONE increment:
the device "user vault" Barticus described is the roster (kpax) that ALREADY
exists in law — the work is wiring it into the input-trust ladder, not building
a new vault. It also records the honest build status so the next session reads
the same words.

## The increment (one sentence)

Do NOT build a new vault feature. Wire the existing roster — the kidulKey-signed
`{ attested-device-key -> role }` list (crypto.md §household roster, kidulkey.md
§what-it-signs) — into the input-trust admission ladder as the single source of
device identity. That is "verify once, known everywhere by the same key."

## Identity vs approval (the boundary that keeps it clean)

These are two different things and must stay split — Barticus locked this, and
it is already law in two places:

  WHO (identity)   the roster/kpax. Signed ONCE by the root. Global: every box
                   caches a copy, verifies the signature, knows "this is
                   Barticus's Planck." Non-repudiable, non-revocable-by-locality.
                   This is what propagates system-wide.

  WHAT (approval)  the per-node tier + allowlist (input-trust.md §ladder). Local,
                   revocable per box. "Approved on the TV" means "approved for
                   TV things on the TV," NOT "root everywhere."

Collapsing the roster into the cold vault (cold-storage.md) undoes this split.
The roster is PUBLIC signed material (cached per box, on the krouter —
kidulkey.md: "Public = published, no secret"). The cold vault holds SECRETS.
Two different organs; keep them two.

## The roster is the "user vault access list" (resolve the naming)

Barticus's "user vault" intuition maps to the roster, not to cold-storage:

  roster (kpax)   { attested-device-key -> role }  signed by kidulKey root
                  cached per box, source of truth on the krouter
                  PUBLIC, signed, global = the access LIST
  cold vault      the user's encrypted home — data at rest, cued, decrypt-on-read
                  holds SECRETS, holds NO private keys (crypto.md)

One line: the roster is WHO is known; the vault is WHERE secrets rest. The
device registry is the roster.

## How it wires into the ladder

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
binds live. The roster is the access list; the ladder is the enforcement point.

  roster (WHO)  --signed once-->  cached on box  -->  ladder challenges against it
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
  (kpax) as a "user vault access list" is PUBLIC signed material — it is NOT a
  secret and NOT a credential; only its SIGNING key is. Keep signing keys in
  silicon, never in a repo.

## Relationship to existing law

  crypto.md          §household roster -> this doc wires it to admission.
  kidulkey.md        §what-it-signs ("every admit-by-proof resolves to the ONE
                     signed roster") -> the roster becomes the Tier 2 source.
  input-trust.md     §ladder + §Status -> TIER 2 PROVEN resolves against the
                     roster, never the global /run/kushd/input-trust verdict.
  cold-storage.md    the vault stays SECRETS-ONLY; it is not the roster's home.
  identity.md        §key transparency -> the roster needs the append-only
                     auditable log shape (rotation = visible event, not silent).
