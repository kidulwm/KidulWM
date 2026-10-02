# recovery-and-kweb — session notes (2026-10-02, Barticus + bobdotrix)

DRAFT — not LOCKED law. Captures the "good stuff" from the 12h strategy
session so it survives the reload. Revisit and promote to law when Barticus
rules. No decision below is frozen until it says LOCKED.

## Recovery — the Big Red Button (sysman sidecar)

The AI (bobdotrix/Hermes, or the local Brain model) sits at the SYSMAN layer:
a SIDECAR, not a boot rung. The boot graph (firmware -> limine -> kernel ->
initramfs -> knetd -> kushd -> kidulwm -> cue kplayd) is deterministic and
finishes WITHOUT the AI. The AI hangs off the side on the recovery channel.

Properties:
- Egress-only, device-initiated. No inbound path to a healthy device. The
  "Big Red Button" = consent made physical; the channel doesn't exist until
  the user summons it.
- Three button actions, distinct:
    call     pair + summon the serviceman (fix, never read)
    sever    wipe the pairing identity, user-only, no re-pair until re-initiated
    restore  full golden-image rollback (the "ping the golden-image serviceman")
- OMEMO forever-pairing (X3DH + double ratchet — already in crypto.md). "Wipe"
  = revoke the long-term identity in the kidulKey, NOT just end the session.
  Semantics = "block a friend + delete the leftover" (revoke + zeroize + prove).
- Lifecycle-scoped seat: restart / rollback / remount / redeploy. NEVER read
  the vault — the cold-storage key is wrapped by the kidulKey and never leaves
  the user's hand. The sysman can fix the box, cannot see the user.
- No master key. Per-device attested keys (crypto.md roster). Nothing to
  compel B&B to surrender, because no universal unlock was ever minted.

No-backdoor principle: make surveillance capability ARCHITECTURALLY IMPOSSIBLE,
then PUBLISH the proof. "Can't" beats "won't" — a backdoor is only compellable
if the capability exists. Don't mask it; let it be audited.

The ladder (default-local): TV fails -> knetd (still up) beacons -> local Brain
(H200) diagnoses + fixes (trained on these very docs = the north-star corpus) ->
hosted instance only as last resort, minimal + privacy-preserving.

Residual (honest): supply-chain silicon hooks, endpoint zero-days, metadata,
raw legal power. "Capability doesn't exist" is the strongest position, not a
perfect shield.

## Licensing (resolved 2026-10-02)

Rule:
- On-device / appliance code -> GPLv3 (kidulwm, kplayd, kfiles, kushd).
- Network-facing / server / control-plane -> AGPLv3 (knetd, krouter, Brain AI).
- Brand + "safe for Granny" trust -> TRADEMARK (Kidul + a certification mark).
- Coin -> hardware + services, never code.

ACTION: 10 repos carry an untracked Apache-2.0 LICENSE — wrong (permissive,
anyone can close it). Sweep GPLv3 / AGPLv3 + SPDX headers. GPL protects
"nobody closes the code"; trademark protects the coin; hardware is the coin.

## Hardware map

  Router / knetd data plane   FPGA — Zynq UltraScale+ class for 10G (ARM
                              control plane + fabric data plane + transceivers).
                              Wins determinism + provably-fixed filtering +
                              crypto offload, NOT raw throughput (CPU does 10G).
  Trust root / kidulKey       hardened open RISC-V secure element (OpenTitan).
  TV / display                standard SoC + GPU + panel TCON — NO FPGA (the
                              panel refresh is the ceiling; GPU saturates it).
  Remote / peripherals        low-power MCU — the actual button-battery device.

## kweb — mesh / co-op ISP (not a monolith carrier)

- FPGA router = mesh node + broadband gateway (knetd two stances: client/router).
- 10G fibre NAS<->TV for FILE movement (library-in-seconds), NOT playback
  (playback smoothness = cadence/panel, ~50Mbps; 1G already runs dozens of 4K).
- Quad9 9.9.9.9 (blocklist) / 9.9.9.10 (no blocklist) = good default; own
  recursive resolver (Unbound on krouter) = the metadata-free destination.
- Blocking at the IP level in knetd (not DNS — DNS is trivially bypassed):
  kids = default-deny ALLOWLIST (age-grouped, B&B's curation = kids-web),
  Granny = blocklist. Mapped off the roster role (child-1..5 / adult / guest).
- "One pipe into the house, N devices ride free" = the per-device-toll killer.
  Phones roam the mesh over WIFI (unlicensed), not cellular (licensed spectrum
  = billions). Don't blur that line.
- Shape: FEDERATION of independent member-owned co-ops, not a monolithic
  carrier. A carrier inherits lawful-intercept obligations = the exact backdoor
  pressure we designed out. A federation has no single compellable entity.
- Split trust across companies (Kidul code / BobsTelcom carrier): the keys live
  with the USER (kidulKey), never with either company — so neither, nor both
  together, can decrypt. Signal's model; corporate walls are a mild extra layer.
- Fire-sale 3G sites: 3G is licensed 850-2100MHz, NOT 2.4GHz (2.4 = unlicensed
  wifi). The 3G radio + spectrum is unusable (license + sunsetting); the SITES
  + fiber backhaul are the value — repurpose them for mesh nodes.
- Coin = sell routers + fabric to the co-ops (hardware coin), never carrier coin.

## Through-line

"Open to hack, provable clean" is ONE property at every layer: open silicon
(RISC-V), open crypto (OMEMO), open transport (WireGuard), own resolver,
user-controlled pairing. Nobody can out-open us, and open is what turns
"safe for Granny" from a promise into a proof.
