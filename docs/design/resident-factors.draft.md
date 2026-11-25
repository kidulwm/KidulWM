# DESIGN (draft) — resident factors: FIDO2/CTAP2 open-key interop, a personal lane
#                    that is ALONGSIDE the signing root, never INSIDE it.

LOCKED 2026-11-25, Barticus present (GSI) — "yes to your recs" on A-D. The
PERSONAL-FACTOR LANE is frozen: FIDO2/CTAP2 open interop, a witness never a
notary; first cut = CTAP2 client + roster enrollment only (no badge machinery);
endorsement model parked under licensing.md; presence+consent never a password
field; FIDO2 keys enroll through the OWNER, never self-serve.
Draft 2026-11-25 (bobdotrix, GSI). Spec-first freeze BEFORE code. This is a
TRUST-MODEL lane and a VALUES decision, not a feature tick. It answers "should we
let security-minded people bring their own YubiKey/Titan/etc" with: yes — but by
speaking the OPEN standard (FIDO2/CTAP2), so YubiKey, Google Titan, SoloKeys,
Nitrokey, and our own future kidulKey are all the SAME thing to the system, and
NONE of them touch the crown jewels.

Authority referenced: kidulkey.md (LOCKED — the signing root is OUR cold silicon,
private half lives nowhere else), signer.draft.md (LOCKED 2026-11-25 — ksign seam,
signer = SE050 ROOT), input-trust.md (LOCKED — the four-tier admission ladder),
device-registry.md (one roster, many consumers).

## The decision in one sentence

Persona/account admission gains an OPEN personal-factor lane: any FIDO2/CTAP2
security key can authenticate "the human holding it is present and consents",
enrolled into the SAME roster as everything else — and this lane is quarantined
to proving-a-person-is-present, with zero authority to sign the roster/allocation
map, prove a device, or attest boot state.

## The reframe that makes it safe (and de-proprietary)

We do NOT "support YubiKey." We implement FIDO2/CTAP2 (the open W3C/FIDO
Alliance standard) as a client over USB HID — no browser needed, it is a clean
spec. Then EVERY FIDO2 key works: YubiKey, Titan, SoloKeys, Nitrokey, and the
kidulKey itself the moment we let its host MCU speak CTAP2. One door, every key
that can walk through it. No vendor whitelist, no brand special-casing, and —
critically — NO "you must buy the kidulKey" proprietary stunt. Forcing our own
key, however open-source, would smell exactly like the closed-system behavior we
swore off. Open interop is the anti-proprietary move, and it is also the market
move.

## The BOX — why this does not weaken "we don't joke about security"

Every key has a ROLE here, and roles do not overlap:

  SIGNING ROOT      signs roster + allocation map. COLD SE050 kidulKey ONLY.
                    LOCKED (kidulkey.md, signer.draft.md). A FIDO2 key NEVER
                    signs a trust artifact — its firmware is closed, we cannot
                    verify key-birth-on-die, so it is given zero authority here.

  DEVICE-PROOF      firmware #2 dongle: "this is the real physical machine."
                    Ours, LOCKED (input-trust.md Tier 2). No FIDO2 key here.

  ATTESTATION       measured-boot / fTPM seal (attestation.md apex, later). Ours.

  PERSONAL FACTOR   "a human holding this credential is present, and consents."
                    THIS is the FIDO2/CTAP2 lane. Phishing-resistant (origin-
                    bound) and presence-proving. NOTHING more.

Because the lane only ever proves presence, even a fully compromised personal
key can only claim "I am here" — it cannot sign the residency map (never given
that authority), cannot attest a machine, cannot promote itself. The system
verifies everything that matters on OUR side; the key's closed firmware becomes
irrelevant the moment its only job is witness, not notary.

## Why (multi-faceted — the reasons are all real)

  1. EARLY ADOPTERS. The people who already own a YubiKey already believe "the
     key is the safest way." They are exactly our first users, and the ones
     talking the system up on YouTube. Let them plug in what they own and try
     kidulTV for FREE — zero hardware friction, zero cost to download.
  2. SOURCE RESILIENCE. If we cannot source SE050 parts at any stage (supply
     chain), the personal-factor lane is a live backup: enrollment and presence
     survive on any FIDO2 key while the signing root is replenished. The crown
     jewels stay cold; the front door stays open.
  3. THE UPSELL IS HONEST. The YubiKey owner becomes a kidulKey buyer naturally
     — same standard, our silicon, our provenance. Their key is the on-ramp;
     our key is the endgame. We monetize HARDWARE (the founding thesis), not
     access.

## The money model — interop is FREE, endorsement is OPTIONAL

  - USE: free, forever, non-revocable. Any FIDO2 key authenticates on kidulTV.
  - "APPROVED FOR KIDUL TV" badge: OPT-IN, not a gate. A vendor who wants the
    kidulWorks name on their site asks us to certify-and-verify their key against
    our stack; we charge a TOKEN sum for the engineering time (test it against
    kushd/KidulWM, confirm CTAP2 interop, sign off). It is compensation for our
    hours, NOT a fee to unlock the user. No vendor pays = their key still works;
    it simply does not carry our name.
  - This is the distinction that matters, and it is Barticus's own point made
    sharp: token money buys a seller's RIGHT TO SAY WE'VE VETTED THEM, never a
    user's right to be admitted. Access stays GPL-open; endorsement is the only
    thing for sale.

## Rules (fail-safe, carry the doctrine)

  - The personal factor authenticates the HUMAN; it NEVER alone authorises a
    claim/re-seat/ownership change. Those remain the SE050 ceremony (polling +
    consent). The FIDO2 key is ONE factor, never the gate.
  - No FIDO2 key may be the signer for roster/allocation (signer.draft.md is
    explicit: signer = SE050); this lane is a roster CONSUMER, not a root.
  - FIDO2/CTAP2 only over a wired path we control (USB HID). No ambient-relay
    surface creep; the NFC convenience of the fob remains a separate, later,
    disposable-grade device (see signer.draft.md hardware-note).
  - kidulKey's own personal-factor mode speaks the SAME CTAP2 — Granny's kidulKey
    and a security-nerd's YubiKey are indistinguishable to the system, so there
    is no "our key vs their key" path divergence. (kidulKey remains THE signing
    root regardless; this lane is an ADDITIONAL mode, never a substitute.)

## done-when

  - A CTAP2-over-USB-HID client exists (open spec) that can enroll a key into the
    roster as a PERSONAL-FACTOR entry (device-registry.md §consumer), issuing a
    presence proof, never a trust-artifact signature.
  - The People-app delegation surface can bind a FIDO2 factor to a resident and
    show "key present" without the key ever touching sign/attest/device-proof.
  - A rig proves the box: a FIDO2 key authenticates presence BUT is refused (and
    logged) the moment it is asked to sign the roster/map or attest the machine.

## What this does NOT touch

  - The SE050 signing root / ksign seam (signer.draft.md) — UNCHANGED.
  - Device-proof (firmware #2), input-trust ladder, attestation — UNCHANGED.
  - The People app / delegation.md surface — this lane is a LATER slice that
    CONSUMES the roster; it does not re-cut the roster keystone itself.

## Open questions — LOCKED (Barticus 2026-11-25, GSI: "yes to your recs")

  A. SCOPE OF THE FIRST CUT. LOCKED: CTAP2 client + roster enrollment as
     PERSONAL-FACTOR ONLY — no "approved badge" machinery, no vendor vetting
     pipeline in this cut. The badge/endorsement is a later business slice.

  B. THE BADGE'S HOME. LOCKED: the endorsement model (free use, token fee for
     the "Approved for Kidul TV" name) is a LICENSING/business doc — parked under
     licensing.md, not a security rule in this trust-model doc.

  C. MFA SHAPE. LOCKED: personal factor is presence + consent, never a password
     field (key-entry.draft.md: "tap your key"). A FIDO2 factor gates the PERSON;
     the claim gate stays the SE050 ceremony.

  D. WHOSE CTRL. LOCKED: FIDO2 keys enroll through the OWNER (delegation.md),
     never self-serve — a resident can't mint their own factor above what the
     owner granted.
