# LAW — attestation (the clean-check & the gate)

LOCKED 2026-11-16, Barticus present (GSI).

The kidulKey verifies the host BEFORE it opens anything. It does not trust the
screen (the seal is fakeable) — it verifies the PROOF IN CODE, and refuses to
unseal the user's cryptography on a host that is not clean. "No — not safe
here, don't use this system."

## The kidulKey is the gate, not just the signer

The key's boot role is OFFLINE verification (kidulkey.md: IMA keyring + signed
golden image). It is also the GATE: before releasing the user's cryptography
(the partition key / LUKS decrypt), it verifies the host is CLEAN — the code
hash + the active log config, attested against the KidulWorks root. Clean ->
open. Dirty -> NO, the key refuses, the user's data stays sealed.

## The key does NOT trust the host's word

A compromised host would simply say "I'm clean." So the key verifies a SIGNED
measurement from a hardware root of trust (the fTPM): the host MEASURES (TPM
PCRs over the boot chain), the key VERIFIES (the signed quote). The host is the
untrusted measurer; the key is the secret-holder + verifier. Without this, "the
key says NO" is just "the key asks the liar if it is lying."

## The seal is fakeable; the code is not

A visual checkmark is a hint for the human. The guarantee is the key's OWN
verification of the signed code + config. The key does not care what the screen
looks like; it verifies the proof in code.

## Kiosk / hotel mode — zero-PII metering only

A host the key deems clean may log only the zero-PII schema (usage time, data
size). No PII field exists in the signed schema, so the owner (hotel) cannot log
content / identity / history even if it wants to. If the config drifts past the
allowlist, the attestation breaks and the key refuses. Metering, never
surveillance: it reveals WHEN and HOW MUCH, never WHAT or WHO.

## The NO is the product

"Not safe here, don't use this system." The refusal is actionable — it names
WHAT drifted (code hash, log config), so the user can leave or proceed informed.
The password backup (kidulkey.md two-key rule) is the deliberate override; there
is no silent bypass.

## Trust anchor

The key verifies against the KidulWorks root, never the host's owner. The hotel
owns the TV but cannot sign a fake "clean" — it holds no KidulWorks key.

## Relationship to existing law

  kidulkey.md       the key's roles (signer -> now gate); "any screen becomes
                    your system" cuts both ways — your identity follows you, AND
                    the screen's owner cannot reach past the metering.
  verified-boot.md  the floor the key checks (dm-verity base + fs-verity/IMA).
  identity.md       LUKS decrypt + attestation never leave the box.
  input-trust.md    unsealing the vault — now gated on host attestation.
  logs.md           the zero-PII schema + zero standing read.

## Build status (honest)

Architecture frozen here. NOT built — the fTPM quote + kidulKey verification +
sealed-secret release are ahead of us (partition/isolation + key-hardware
build). This is the law the build must obey, not a claim it is built.
