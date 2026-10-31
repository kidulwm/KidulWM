# LAW — device-proof (firmware #2): the Ed25519 seed proves the device

LOCKED 2026-11-01, Barticus present (GSI). This is the device half of
input-trust.md's "admit by proof, never presence" — the dongle becomes the thing
that proves "I am the real remote/box" by holding a seed and answering a
challenge with a signature. It is build-order step 4 of docket #53.

## What the proof is

The dongle holds an Ed25519 keypair. The private half is the SEED — born on-die,
never leaves. The device-proof is the signature: the gate sends a fresh nonce,
the dongle signs it after the tap, the gate verifies against the burned-in
public key. Only the seed's holder can produce a signature that verifies. That
is the unforgeable truth — possession of the private key, proven without ever
revealing it.

## The seed (lifecycle)

- Born on-die at first ceremony: the CC310 crypto cell + HW RNG mints the
  Ed25519 keypair; the private half is used inside the CC310 silicon, never
  copied into main RAM, never exported.
- The public half is exported ONCE, over the wire, at pairing — that becomes the
  "burned-in public key" the gate holds (input-trust.md).
- No private-key backup, ever. Lose the device = strike its public key and mint
  fresh (the two-key / safety rule is the human escape hatch).

## The tap is the consent (WYSIWYS)

The device never signs on its own. Signing requires BUTTON1. Sequence: gate
sends nonce -> dongle arms (LED blinks) -> human taps -> dongle signs -> returns
signature -> LED idle. No tap = no signature. The finger is the consent gesture.

## The wire (pair once, then prove)

CDC ACM serial — the dongle already carries ttyACM0 alongside HID, so no new USB
descriptor. Minimal line protocol:

  PUBKEY\n        -> PK <64-hex>\n             (once, at pairing)
  SIGN <64-hex>\n  -> arms; on tap -> SIG <128-hex>\n
  anything else   -> ERR\n

## What it will NOT do

- Sign arbitrary data — only a nonce, only on tap.
- Export the private key (the command does not exist in its vocabulary).
- Be a seed-deriver, the ratchet, or resident (unplug = gone).
- Judge nonce freshness — that is the gate's job (step 5). The device signs what
  it is handed, on tap.

## Clone-resistance (the honest limit)

- SOFTWARE clone (copy bytes off the wire or host): impossible by design — the
  seed is born on-die and never exported; copying the flash yields ciphertext
  (device-unique-encrypted at rest) plus the public half. No command emits the
  private key.
- PHYSICAL clone (open the chip and extract): the nRF52840's CC310 only RAISES
  the bar (chip-level attack: decapping, glitching, microprobing) — it does NOT
  close it. The SE050 (production, kidulkey.md) closes it: tamper-responsive
  silicon that destroys the key on probe. Prototype = clone-proof against
  everything short of a lab; production = clone-proof, full stop.
- Design backstop: a clone is worth nothing while its public half is not in the
  roster. Strike a compromised key (one line) and the clone dies everywhere at
  once.

## Acceptance (done-when)

Host sends a random 32-byte nonce -> tap -> 64-byte signature -> verify with
ed25519 against the exported public key. Verifies = done. A wrong key's
signature fails = the proof is unforgeable.
