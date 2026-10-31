# LAW — kidulKey (the signing root / trust anchor) — the key family

LOCKED 2026-10-31, Barticus present (GSI). v2 — three key tiers + the dual-
computer keyboard + the personal shell.
Resolves crypto.md's trust-ledger open problems (2) WYSIWYS, (3) deniability
vs non-repudiation, (4) revocation propagation. MECHANISM = docket #53; this
file is the rulings the firmware and the device build must obey.

## Three keys, one family (the model)

kidulKey is not one dongle — it is a KEY FAMILY in three tiers. This resolves
the standing tension between "the key stays cold, never on a box" (crypto.md)
and "the key slots into the router/TV" — they are different keys.

  ROOT      cold, on the keyring, human-present ceremonies only. Signs the
            roster and mints the subordinate keys. Never resident, never on a
            box, never dials out. The one thing that is NOT disposable.
  SYSTEM    resident, slots into its HOME device — router, TV, server,
            gamingPC. Proves "this box is a muster member" and does that box's
            daily signing. A subordinate: strike it from the roster, mint
            another. One key per box.
  PERSONAL  the fingerprint key, built INTO the keyboard/remote. Proves "this
            is Granny." Gates the banking / personal-touch taps. Human-bound,
            travels with the person.

This is identity.md's device-bound / human-bound split, one level up, with the
root above both. The root signs the WHO; the box keys prove the BOX; the
personal key proves the PERSON. Three tiers, never blurred.

## The owner / master key + space-allocation hierarchy (OPEN — ponder, not locked)

Pondered 2026-11-01 (Barticus), NOT yet locked. Extends the three tiers with a
per-machine OWNER authority and a space/quota grant path. The think, before the
freeze.

  ROOT      (unchanged) the global trust anchor: mints all keys, signs the
            roster. The "master key" Barticus names is ONE OF the two ROOT keys
            — the 1-of-2 (two-key rule), held by the boss.
  OWNER     the "boss of the machine": the key that OVERRIDES all others on its
            home box. Grants drive space to users (Dad's yay/nay when a kid
            asks for more space). Its override is scoped to the machine, not
            the roster.
  SYSTEM    (unchanged) the box proves itself; daily signing.
  PERSONAL  (unchanged) the person.
  FRIENDLY  a kidul user with their own drive/key/remote. Needs NO approval to
            be present — nothing from them persists (ephemeral). Needs OWNER
            approval to be ALLOCATED drive space. Presence is free; footprint
            is the owner's call.

The hierarchy answer so far: presence is free, footprint (space) is gated by
the owner's key, and the owner's key overrides all others on its machine. The
open question is the grant record's shape — a signed quota per friendly, minted
by the owner (the PERSONAL-tier "policy record" pattern, extended to a space
quota) — to ponder before freezing.

## What the kidulKey SIGNS — by tier

  ROOT        the roster / kpax ({ attested-key -> role }), and each
              subordinate's public key (device identity, SSH host+client keys,
              OMEMO identity keys, the IMA/fs-verity keyring). The keystone:
              every "admit by proof" resolves to the ONE signed roster.
  SYSTEM      the box's own daily material: its sessions, its device keys, its
              cold-storage volume wrap, its signed golden-image (kboot.md —
              the only thing that mutates kboot is a root-signed image). Cold
              volume keys are wrapped by the root, cued on the rare open.
  PERSONAL    a POLICY RECORD on the personal-touch taps (banking, a grant),
              NOT a signing commitment — low stakes, live-revocable. The
              finger is the consent gesture; nothing personal-touch signs
              without it.

## The two-key rule (root redundancy) + the safety rule

The ROOT is two SEPARATE keypairs — key #1 and key #2 — never one key copied.
A copy is the private key hitting a box, which loses the point. Register BOTH
public halves in the muster. Lose key #1: strike its public half (one-line
removal) and register a fresh key. No private-key backup, ever — recovery is
register-new + strike-lost, never restore-a-copy.

SAFETY RULE (Barticus, locked): we are the guinea pigs. Hold a PASSWORD backup
as the escape hatch until BOTH keys are present AND confirmed — never lock
ourselves out of our own tests.

## The personal shell — keyboard, remote, HD (Barticus's lock)

The keyboard and remote are dual-computer devices, and together with the key
they form the PERSONAL SHELL — the constant you carry to any screen.

  input half     a lean, always-on radio (ESP32-C6 / nRF52840 class). Lowest
                 power possible: scancodes ride BLE, a direct device->host
                 link attested at pairing. Input NEVER rides WiFi — a keypress
                 is ~100 bytes; BLE is the correct transport, not a waste.
  fast half      a second computer underneath the keyboard, hardware-switched
                 OFF by default. Only powers on when you throw the switch: a
                 full WiFi6/7 radio + an M.2 drive + encryption. APPLICATION-
                 class SoC (RISC-V/ARM), not Pico-class.
  the HD         just an encrypted NETWORKED DRIVE — nothing more special than
                 the NAS. Unlockable by Granny's kidulKey, encrypted at rest,
                 rides the encrypted mesh only when switched on. It is NOT the
                 vault and NOT the identity; the identity lives in the secure
                 element (the fingerprint), separate from the drive.

The keyboard and remote run fine with the fast half OFF — they are simply an
approved input device. Throw the switch and they become a networked drive too.
USB-C docks them for max throughput; WiFi for the no-wire case.

THE SCREEN IS DISPOSABLE. Bring the keyboard + remote + key to home, work, or
a hotel TV, and any screen becomes your system — same identity, same data, a
different window. That is the kweb pitch, and it is what makes the key family
the whole point: the kidulKey is the thing that makes any screen yours.

## Where the keys and salts reside (Granny stays safest)

  private keys   born on-die in each secure element (root / box / personal),
                 never extractable, never in a file, never in RAM outside their
                 own silicon. Private halves live NOWHERE but silicon.
  public keys    the roster (kpax) — signed by the root, cached per box, source
                 of truth on the krouter. Public = published, no secret.
  salts          NOT secret. They defeat precomputation, not knowledge. They
                 live with the vault entry they protect (cold). The secret in a
                 password-derived key is the password + master key — not salt.
  session keys   RAM only, transient (~500 bytes), zeroized on close. The
                 O(time) rule: never grows, never persists.

A stolen box or disk yields only ciphertext + public keys + salts — worthless
without the silicon. Every private key lives in silicon it never leaves; every
secret at rest is wrapped by a key that lives in silicon.

## Clone-resistance (the honest limit — hardware fact)

Software clone (copy bytes off the wire or host): IMPOSSIBLE by design — the
private key is born on-die and never exported; no command emits it, and flash
at rest holds only ciphertext (device-unique-encrypted) plus the public half.

Physical clone (open the chip and extract): the nRF52840's CC310 RAISES the bar
to a chip-level lab attack (decapping, glitching, microprobing) but does NOT
close it. True non-extractability is the SE050's job (tamper-responsive silicon
that destroys the key on probe) — production. So: prototype = clone-proof short
of a lab; production = clone-proof, full stop.

Design backstop: a clone is worthless while its public half is not in the
roster. Strike a compromised key (one line) and the clone dies everywhere at
once.

## WYSIWYS — what does the key approve (revised)

  PERSONAL  the trusted SCREEN shows the transaction (a popup: "approve
            $142.00 to ACME?"), and the FINGERPRINT is the consent. What-you-
            see is what-you-sign, with the human bound by something-you-are.
            No on-key display needed for the personal key.
  ROOT      stays ceremony-only: human-present, no always-on auto-sign, no
            display requirement on the prototype. It signs rarely (pairing,
            roster re-sign, golden image) and each signature is deliberate.
  RESIDUAL  a compromised host that also wins a finger/button press during a
            ceremony is the unclosed hole on the prototype hardware. Accepted
            for the prototype's scope (ceremonies + low-stakes taps), never
            extended to high-stakes unattended signing.

## The ceremony — pair for life, then tidy up

  PAIR      plug the device into the host over the WIRE once (input-trust.md,
            locked: "pair once over the wire, burn it in"). Full verification
            at the wire means nothing else is even visible — admit by proof,
            never presence. After that, wireless, paired for life.
  TIDY-UP   a named end-of-session ritual: pull the key / hit the tidy-up
            button -> unmount the attached drives, zeroize host RAM, nothing
            hung over. Extends cold-storage's wipe-on-close and the
            clipboard's purge-now into one act. We NAG for it — a graceful
            pull, never a yank.

## Deniability vs non-repudiation (unchanged)

Root signs the WHO (identity = non-repudiable, and must be); the ratchet signs
the WHAT (session content = deniable). The root never touches the ratchet's
ephemeral material. Certifying an OMEMO identity key does not break message
deniability — that lives in the ephemeral DH session keys the root never sees.

## Revocation propagation (unchanged)

Strike-from-muster is instant locally. The krouter is the single source of
truth; every association re-verifies the signed roster — refresh-on-associate
closes the window at connection time. No CRL daemon, no gossip. Residual
window = bounded by the next association, accepted.

## What the kidulKey is NOT

  - Not a seed (never derives). Not a password (possession + finger, nothing
    recited). Not a daemon / never resident / never dials out.
  - Not in the boot order (no crypto in the boot graph; its boot role is
    OFFLINE verification — the IMA keyring + the signed golden image).
  - Not the ratchet. Not a second authority (the KID is the ONE admission
    authority — no doorman).
  - The HD is not the vault; the keyboard is not the root.

## North star — the open-source kidulKey (Barticus, klip grant Q.B)

The kidulKey is OPEN-SOURCE hardware: kids build their own, Granny and
businesses buy an official one. Hardware money, FREE-to-hack in metal. The
same key family is the prototype for the future SYSTEM key.

## Build order (docket #53)

  1. This freeze — key family + what-it-signs + WYSIWYS + ceremony, BEFORE
     firmware.
  2. NCS/Zephyr toolchain (none present, multi-GB).
  3. Firmware #1: USB HID presence + tap (no signing) — the seam.
  4. Firmware #2: Ed25519 device-proof (unforgeable) — the truth.
  5. Wire kushd/seat to admit devices by that proof (input-trust).

## Open (build-time, not blocking)

  - The keyboard/remote DEVICE build (dual-computer, ESP32 + app-SoC + M.2) —
    that design lives in input-trust.md / kidul-remote, not this key law.
  - On-key display for the ROOT (optional; ceremony-only covers the prototype).
  - Post-quantum key agreement (ledger #5) — horizon, not action.
  - The muster binding for klipd (local app_id registry first — klipboard Q.D).
