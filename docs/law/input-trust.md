# LAW — input trust (the seat admits devices by proof, not presence) (LOCKED 2026-10-03, Barticus present)

A TV has no keyboard. The keyboard is a crypto-connected remote — a whole
other device that must act like a keyboard once it is authorized. This law
names how the seat trusts an input device, and it does so without ever
unsealing the vault.

## The correction that makes it work: seeds live on the devices, not the vault

The vault (cold-storage.md) holds secrets that REST. The remotes and mobiles
hold seeds that PROVE. These are different things, and blurring them was the
mistake this law fixes:

  vault   = data at rest, cued, decrypt-on-read, cold. Needed for the E2E
            substrate (crypto.md), NOT for admitting a keyboard.
  seed    = the private identity on the remote itself. It proves "I am the
            real remote" at connect time, and it needs nothing unsealed.

Because authorization rides on the remote's own seed — not on the vault — the
remote is a valid input even in a degraded boot where the vault is cold and
kidulwm is dark. That is what makes it the fallback getty's hand (below).

## Authorization is a GATE below the seat, not a daemon

The crypto to the remote is not "part of seatd" — it is BELOW seatd, as a
check in the input-enumeration path. Three clean layers:

  TRANSPORT   the remote enumerates as HID (USB, or the wireless dongle).
              Dumb. Scancodes only. No trust at this layer.

  AUTH GATE    the thin shim between "device enumerated" and "seatd admits it."
              When a new input device arrives carrying the remote's credential,
              the gate challenges it against the burned-in public key. Pass →
              admitted as a TRUSTED keyboard. Fail → rejected, or admitted
              UNTRUSTED (no keybinds that can hurt). This is the usher checking
              the ticket before the px sits.

  MAPPING      once authorized, the buttons translate (keycombo.map, below).

Less-running law: the gate is a decision point in the device path, not a
resident process. It extends the security-bob USB guard (which already
whitelists Yubico/FIDO) — recognize the remote, challenge it, admit it.

## Pair once over the wire, burn it in (from kidul-remote, now LOCKED)

The carry key on the remote IS its identity. Pairing happens once, at setup:
plug the remote into the TV box over USB, run the key exchange, burn the pair
in. After that, wireless HID only — no NFC, no always-on auth radio. The wire
is the trust anchor; the crypto proof travels with the remote on every connect
(challenge/response against the burned-in public key). No crypto in the boot
order, ever (crypto.md).

## Pairing attests, not just authenticates (LOCKED 2026-11-17, Barticus present)

Pairing proves IDENTITY — the remote holds the on-die key (clone-resistant).
It has not proved INTEGRITY: a remote reflashed with trojan firmware that
still holds the copied key passes the challenge and is trusted as a kidulKey
carrier. So pairing attests TWO things, both structural, never diligence:

  AUTHENTICATION  challenge/response against the burned pubkey — "does it
                  hold the key" (firmware #2, already proven).
  ATTESTATION     the device measures its own firmware, signs the hash with
                  the on-die key, the host verifies it against the ROOT-signed
                  manifest. "Is it the genuine device running the firmware we
                  signed." NEW.

The device runs a secure boot chain (immutable ROM -> signed firmware only) so
tampered firmware cannot boot; the pairing-time attestation makes the verdict
VISIBLE (wall before door, WYSIWYS): "remote verified — genuine" /
"unrecognized device — do not trust as a kidulKey carrier." Remote AND
keyboard — every device that carries a kidulKey tier or handles the key
exchange — one ruling, two surfaces.

Honest limits: attestation proves genuine + signed firmware, NOT "never opened
by a state lab" (decapping/microprobing is the SE050's tamper-responsive job,
closed in production). The bench dongle (signature-less bootloader) cannot do
real measured boot — attestation lands on the SE050 silicon, not the nRF52840.

Blast radius stays bounded by the tier design: the remote carries the PERSONAL
tier, never the ROOT (crypto.md); approval is per-surface (kid.md). Attestation
closes the firmware-tamper path that would let a trojan remote silently sign
or exfiltrate the seed — the last open sec opening.

## Base keys are standard; the chord layer is a pre-settings FILE

up/down/left/right/enter/esc are already standard HID keyboard usage codes. If
the remote's firmware reports those standard codes, getty, fzf, and every
existing input consumer understand the remote with ZERO custom code. The only
thing that needs defining is the chord layer — "this direction means X while
held" — and that is a declarative file, not code:

  /etc/kushd/keycombo.map   (pre-settings, read by getty AND machine)

Same shape as the bill (the usher reads both). BASE keys fall through on
standard usage codes; the CHORD map is the only bespoke part.

## The remote is the floor input for the fallback getty

The fallback getty (silent-boot slice) has an input device because the remote
is authorized at the seat and independent of everything that can break. The
up/down/left/right/enter chord drives the diagnostic; the TV needs no physical
keyboard. The remote is the mouth's hand.

## What this closes in kidul-remote (three open questions, now answered)

  HID single-vs-composite   base keys are standard usage codes (one HID
                            keyboard interface; no descriptor swap needed).
  carry-key protocol        pair once over the wire, burn in, challenge on
                            connect (above).
  seat trust                admit by proof at a gate below seatd, not presence.

## The admission ladder — four tiers (LOCKED 2026-11-10, Barticus present)

Admission is PER-DEVICE, decided at enumeration time — not a single global
verdict. A device lands in exactly one tier:

  TIER 0  INTERNAL (the box) — detected by KERNEL-STANDARD signals, no list of
          ours. bustype (libinput_device_get_id_bustype, linux/input.h) on a
          native bus (I8042/HOST/PCI/INTEL_ISHTP/I2C/SPI), OR a USB device whose
          sysfs removable=fixed (soldered internal — internal webcam/touchscreen).
          Covers the AT keyboard, touchpad, lid/power/sleep buttons, the iGPU,
          and the whole HDA audio stack (headphone jack, speakers, HDMI/DP audio).
          Auto-admitted, TRUSTED, no proof. These never ask; they ARE the box.

  TIER 1  KNOWN EXTERNAL (identity) — USB/BT whose VID:PID(+serial) is in the
          burned allowlist (Planck 03A8:A4F9, kidulKey 2fe3, the remote).
          Admitted as a USABLE keyboard/pointer. Identity is spoofable, so this
          tier grants USABLE, not harmful.

  TIER 2  PROVEN (crypto) — challenge/response against the burned pubkey
          (kidulKey Ed25519). The ONLY tier that grants TRUSTED: harmful binds
          live (spawn/close/reset/browser). Only the remote earns it.

  TIER 3  UNKNOWN — everything else. Benign class (keyboard/pointer) = admitted
          UNTRUSTED (types, navigates, no harmful binds). Dangerous class
          (mass-storage, smartcard, network adapter) = REJECTED (the USB
          guard's block list).

The discriminator is TOPOLOGY + IDENTITY + PROOF — never arrival order. "The
first keyboard plugged in" is not a trust signal (a rubber ducky that arrives
first would win). Default is not deny (a dead keyboard is a dead TV); default
is UNTRUSTED, with the three escalations above. The same ladder is the ONE
admission doctrine for input, storage (the USB guard), and later network and
audio — one pattern, not five bespoke rules.

## Status

Principle LOCKED 2026-10-03; ADMISSION LADDER LOCKED 2026-11-10. The MECHANISM
(open here since October) is now RESOLVED: the gate is a path-based libinput
backend in our own wlroots build — each device is classified into a tier AT
enumeration, before it is admitted to the seat (no resident daemon; a decision
point in the device path, per the less-running law). The old single-line
verdict (/run/kushd/input-trust: TRUSTED/UNTRUSTED/ABSENT) is superseded by
per-device tier assignment at admission time. Patch spec:
docs/design/input-path.draft.md.

AMENDED 2026-11-13 (Barticus present): HOUSE TRUSTED EXTERNAL exception. The
Planck (03A8:A4F9) — Barticus's daily driver ("I use it for everything") — is
escalated to TIER 0 INTERNAL trust by house decree, so it fires harmful binds
(spawn/close/reset/browser) exactly like the box's own keyboard. Deliberate,
named, single-device exception; a NEW external still clears the ladder. The
discriminator (topology + identity + proof, never arrival order) is unchanged —
this is a decree about ONE known identity, not a new admission path. Implemented
as a hardcoded VID:PID check in ksd_classify_device (events.c), before the
allowlist lookup.
