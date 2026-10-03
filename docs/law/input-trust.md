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

## Status

Principle LOCKED now. The MECHANISM (the gate's exact hook — extend the USB
guard vs a seatd plugin vs a udev gate) is a docket, not yet built. Until it
lands, an unauthenticated input device is treated as UNTRUSTED, which is the
safe default this law makes explicit.
