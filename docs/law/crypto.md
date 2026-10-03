# LAW — crypto (the E2E substrate + root of trust) (LOCKED 2026-10-02, Barticus present)

Sensible safety, not over-engineering. Crypto is connection-time and
identity-time, NEVER boot-time. The boot graph stays crypto-free.

## The root of trust — kidulKey (hardware)

The kidulKey is a secure element / YubiKey-class chip: the master identity +
signing key, offline, unstealable by software. It also wraps the cold-storage
volume key (cold-storage.md) — one chip, the whole trust root. It is silicon,
OUTSIDE the software boot graph entirely — like the CPU, present but never
"booted".
Software USES it at connection-time to prove identity / sign a session. Even
secure-boot verification is the chip's job (hardware), not a software crypto
step in the ladder. No crypto in the boot order, period.

## One substrate, three consumers

One set of primitives (X25519, Ed25519, AES-GCM, SHA — libsodium-class) + one
X3DH / double-ratchet layer. All cued tentacles, all connection-time:

  messaging    kmail, the Dino client, "sessions" (P2P video/call/chat). The
               original E2E surface.
  device auth  remote -> NAS/TV. The remote holds the key (kidulKey), proves
               identity to the device it pokes; the device proves back. The
               control channel (poke / command) is encrypted. The SEAT side —
               admitting an input device as a trusted keyboard, below seatd —
               is its own law (input-trust.md): admit by proof, not presence.
  WAN          router -> ISP. The router is the verifier + encryptor for
               everything behind it; it authenticates upstream and encrypts
               the link.

All three are cued at connection-establishment — inbound (a peer / device
connects) or outbound (just before dial). None is in the boot order.

## NAS↔TV data lane — in-transit (LOCKED)

At-rest (cold-storage.md) is not enough. The media stream between NAS and TV
is encrypted in transit too, even on the "trusted" LAN — a LAN is not a trust
boundary you can rely on (one pawned device and the stream is open). Two lanes:

  control  remote -> device: the "device auth" consumer above. Command-rate.
  data     NAS <-> TV: the media stream. Encrypted, stream-rate.

Data-lane transport = SSH (the known-good operator), scoped lean: sftp/scp
only, no interactive shell, no forwarding, ed25519 key-only auth. sshd is a
BODY act on the NAS (a server's remote-admin gap) but NOT on the TV (a TV has
no remote-admin surface — it dials out, runs no listening sshd). kidulKey is
the trust root: it attests/signs the SSH host+client keys, so "this NAS is
really my NAS" is anchored in silicon, not a first-seen TOFU key.

A homegrown transport ("KSH") is not off the table — but only as a composition
of the SAME audited primitives (X25519 + XChaCha20-Poly1305 via libsodium),
never new ciphers, and only if sshd's surface ever proves too fat for the TV.
Until then: SSH transport, kidulKey trust.

## The household roster — identity → role (LOCKED)

"Who gets what" is identity first, policy second. Identity is already here
(kidulKey attests every device's key). Policy is a small signed roster — not a
server, not baked config:

  roster = { attested-device-key -> role }, signed by kidulKey
  role   ∈ { TV, child-1..5, guest, adult, NAS, remote, ... }

One signed file on the krouter (cached on each TV), re-signed when a device
changes: a foster kid's phone dies, a new one joins — re-sign the roster, done.
Up to 5 child slots at any time; the roster is the source of truth for who
fills them. No cloud registry, no phone-home, nothing leaves the house.

Enforcement (later, rides on the roster — policy, not structure):
  krouter  the internet edge. Grants internet by roster role; caps child-role
           devices at 5 per TV — a resource budget (cap HOW MANY), never
           surveillance (never watch WHAT). Unknown/unattested = guest tier or
           no internet.
  TV       the wifi cell hub. Verifies a phone at association (kidulKey
           challenge) and vouches for it to the router.

Multi-TV is free: the role field already says what's a TV, what's child-N,
what's a guest. No extra machinery — the taxonomy is the structure.

## What it's for, exactly

  identity         prove "you are who you say" (the remote is the real remote).
  confidentiality  the media stream is unreadable in transit — WAN (to the ISP)
                   and LAN (NAS↔TV).
  integrity        a command isn't tampered in flight.
  key distribution keys flow remote -> device without a LAN eavesdropper.

## Size — the honest number

  keys        ~128 bytes per identity (Ed25519 + X25519 keypair); a signed
              prekey bundle ~300 bytes; ~100 one-time prekeys ~3 KB; a device's
              full material ~3-4 KB.
  trust store ~0.5 KB per known device; 100 devices ~50 KB.
  binary      primitives ~300-400 KB + X3DH/ratchet ~100-200 KB = ~0.5-1 MB.

Total ~1 MB, keys included. O(devices), never O(time): keys are fixed, sessions
are transient (~500 bytes, discarded on close). It never grows with usage.
Footprint is a non-issue on every device class — deploy everywhere, it's free.
