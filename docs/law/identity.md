# LAW — identity (the four scopes + the bar) (LOCKED 2026-10-04, Barticus present)

HOLD THE BAR, NOT THE PROTOCOL. Protocols change; we change with them and
hold the bar HIGH when we do. The bar is: forward secrecy, real verification
(out-of-band where it counts), no shared secrets. The protocol is just the
tool that serves the bar this year.

## One token, many keys

One physical thing in the pocket, MANY cryptographic identities inside it.
This is not elegance — it is the security: a separate key per scope, so a
breach of one surface never leaks another. No shared secret anywhere.

  - Resident keys (passkeys/FIDO2) — one per website, stored on the token.
  - Device identity keys — one per box, signed by the kidulKey root.
  - Session keys — transient, discarded on close, forward-secret.

Lose one key, revoke ONE public key (crypto.md already says this). Possession
= access is accepted physical reality (the car-key rule); the engineering
answer is that a single lost key is a nuisance, never a catastrophe, because
nothing is a shared secret. "Two or more keys" is redundancy + per-key
revocation, not a feature.

## Two-factor by architecture (the TPM + token split)

  DEVICE-bound  the TPM (already soldered on, sitting idle). Holds what must
                never leave the box: LUKS decrypt, attestation. Proof of "this
                is the box."
  HUMAN-bound   the removable token (secure element / keye). Holds what must
                never be usable without you present: resident keys, identity.
                Proof of "this is the person."

Two factors, no password, no typing. The fingerprint/PIN gesture (FIDO2 user
verification) is the load-bearing wall — a bare keyfile is "possession =
access" with the laptop and the key in the same bag.

## The four scopes (which tool serves which audience)

  1. websites / apps  -> PASSKEYS (FIDO2/WebAuthn). Already solved; already in
                        every browser and in Linux (pam_u2f, systemd-homed).
                        Turn it on, don't build it. A website is stateless and
                        anonymous: passkeys are the right shape.

  2. bank / gov       -> OMEMO-CLASS E2E (double-ratchet) + IN-PERSON verify +
                        KEY TRANSPARENCY. Correct precisely because this
                        relationship is identity-bound and persistent: you
                        walked into the branch ONCE, and that real-world anchor
                        is what lets you verify a fingerprint out-of-band — the
                        strongest move in crypto, MITM defeated by construction.
                        Media (voice/video) rides the same ratchet.

  3. our mesh (kweb)  -> OMEMO + kidulKey-signed identity. Already built; the
                        bank/gov case is this same spine pointed at institutions.

  4. trust root       -> kidulKey, cold, offline, never on a box. Signs device
                        identity keys, never itself a participant (crypto.md).

Never blur the four. "OMEMO everywhere" is wrong the moment it reaches a
website; "passkeys everywhere" is wrong the moment it reaches the mesh. Scope
first, tool second.

## Key transparency (the thing "verify once, trust forever" needs to survive)

Out-of-band verification is strongest ONCE. But identity keys rotate (new HSM,
incident, staff change), and an unpinned rotation is a silent re-impersonation
gap. The fix is a public, append-only, auditable key log per institution, so a
key change is a visible event, never a silent swap. Bake it in from day one;
Signal/WhatsApp/Matrix all had to bolt it on after shipping.

## What is NOT here

  - No passwords to sign or remember. Passkeys REPLACE the password; a
    token-gated password vault is the bridge for legacy sites that still
    demand one.
  - No prison. This is the mansion: the door opens because it is you, not
    because you recited a secret you can be tricked out of.
  - No new ciphers. The same audited primitives (X25519, Ed25519, AES-GCM /
    ChaCha20-Poly1305, libsodium-class) as crypto.md. Hold the bar, reuse the
    wheel.

## The rendezvous — run it, don't trust it (LOCKED 2026-10-04)

An identity-addressed mesh needs a COORDINATOR: the signed map that turns a
hash into a current endpoint (kweb.md §12). The temptation is a cloud service
for it — but that is a "trust-me" choke point, the exact thing this architecture
refuses. The rule: WE run the coordinator, on our own krouter, signed by our
own kidulKey. Then it is verified by construction, never trusted by hope.

  dont-trust-verify  a coordinator you cannot audit is a password with extra
                     steps. Ours you can check, because the signature chain
                     ends at the kidulKey in your pocket, not a vendor's CA.

Identity rides on KEYS, never on addresses. The address is an invisible,
untrusted locator; the key is the name. An attacker who sees an IP sees a
spoofed locator and derives no identity from it.
