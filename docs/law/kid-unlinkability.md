# LAW — kID unlinkability (zero-PII by construction, unlinkable by construction)

LOCKED 2026-11-17, Barticus present (GSI).

## One line

The kID already carries zero PII by construction (kid.md: the name is a
key-derived hash, the alias is a face never stored). This law adds the SECOND
guarantee: UNLINKABILITY by construction — the identity is never the thing a
verifier sees, so "verify everything everywhere" reveals nothing AND correlates
nothing. Two properties, one kID, three axes.

## The three axes (WHO / WHAT / ENVELOPE)

  WHO        the kID hash. Stable, non-repudiable, one key one roster (kid.md).
             The identity the roster resolves. NEVER ratcheted — ratcheting the
             identity loses "one key = one identity" and the roster stops
             resolving.
  WHAT       the OMEMO / Signal double ratchet (crypto.md §who-makes-moves).
             Deniable, forward-secret, post-compromise self-healing. Encrypts
             CONTENT. It does NOT hide the address — the ratchet closes the
             content leak, never the identity leak.
  ENVELOPE   the unlinkability layer. NEW. Keeps the WHO itself from being
             correlated across surfaces. Two mechanisms, in build order:
               (1) ephemeral per-session address — a fresh child handle derived
                   off the stable WHO per session (keyed derivation, stealth-
                   address style). The server/shop sees a different handle every
                   visit and cannot correlate "same key, here again."
               (2) blind-signature credential — the ROOT certifies "valid
                   member / owner" WITHOUT seeing which member. The verifier
                   checks validity and learns not even which kID. Identity is
                   not hidden — it is not transmitted.

## Why the double ratchet is not the fix (the seam everyone else misses)

The ratchet encrypts the payload; the ENVELOPE still carries the sender/recipient
address in the clear because the server must route on it. So "user keys as
XMPP users, server stores no PII" still leaves the server holding the kID hash
as a stable address plus timestamps — the correlation hole, untouched. Forward
secrecy and deniability are worth having for the content; neither hides which
address presented, when. The fix lives one layer up, in the ENVELOPE.

## Blind signatures — verify everything everywhere, reveal nothing

  base        ROOT blind-signs a token (Chaum-style): the signer cannot link the
              credential back to the issuing interaction.
  attribute   the credential carries the CLAIM (role, product-owner, age-over-N),
              never the identity. This is the government-digital-ID done right:
              prove attributes, carry no PII. They weld the PII into the token
              instead — the failure we do not repeat.
  storage-    upgrades "storage without storage" (kid.md): the account key stops
  without-    being a hash the shop sees and becomes a proof the shop checks.
  storage
  multi-show  HONEST LIMIT: a one-show blind credential is LINKABLE on a second
              presentation (same credential shown twice = same credential). The
              multi-show-unlinkable primitive is BBS+ / anonymous credentials
              (ZK-based: selective disclosure + unlinkable repeats). Base =
              blind signature; diamond = BBS+. Name the upgrade, never hand-wave
              it away.

## The boundary (what keeps it from defeating itself)

  three       ENVELOPE is a THIRD axis, not a merge. WHO stays universal;
  axes        approval stays per-surface (kid.md); ENVELOPE sheathes the WHO
              without touching either. Collapsing them is the "one key = root
              everywhere" mistake again.
  never       the WHO is never ratcheted and never blinded into a NEW stable
  ratchet     identity. Blinding is a proof OVER the WHO, not a replacement of it.
  the WHO
  three       ROOT signs WHO (non-repudiable — crypto.md); the ratchet runs WHAT
  modes       (deniable); the blind credential is a THIRD signing mode:
              non-repudiable (a real ROOT signature) yet unlinkable (the ROOT
              cannot say who presented it). Three modes, never blurred.

## kWeb — the double ratchet rides our own mesh (parked)

The OMEMO double ratchet incorporated into the kWeb = "a tailscale we control"
(Barticus 2026-11-17): transport + ratchet as ONE owned mesh, no third party
between peers. PARKED for another time — its own docket, not this law.

## What it does NOT close (the honest boundary)

Zero-PII and unlinkability are OUR side of the wire. The open-web hop is
irreducible timing metadata — a network we do not own can always log "a
connection happened here, now." The ENVELOPE stops our id leaking into it; it
cannot stop a foreign network correlating traffic. Parked (the "whole other
hole").

## Relationship to existing law

  kid.md           the umbrella — the kID. This file is its privacy/unlinkability
                   law.
  crypto.md        the WHO/WHAT split + the ratchet (WHAT). This file adds the
                   third axis (ENVELOPE).
  kidulkey.md      ROOT = the blind-signer (three tiers, never a seed).
  identity.md      the four scopes + the bar.
  roster-format.md kpax resolves the WHO; the blind credential PROVES against it.

## Build status (honest)

Design frozen here. Mechanism NOT built — this rides on the OMEMO substrate
(crypto.md STATUS: not built) + roster enforcement (kid.md STATUS: not built).
The primitives are chosen and the axis split is locked; nothing here is a build
claim.

## Build order (docket #63)

  (1) OMEMO substrate — the WHAT (crypto.md, existing).
  (2) roster enforcement — kpax verify/resolve (kid.md, existing).
  (3) ENVELOPE (a) — ephemeral per-session address off the kID.
  (4) ENVELOPE (b) — blind-signature credential from the ROOT (single-show).
  (5) upgrade — BBS+ / anonymous credentials (multi-show unlinkable + selective
      disclosure). The diamond.
