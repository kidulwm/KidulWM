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

## Who makes & moves the OMEMO keys (LOCKED 2026-11-01, Barticus present)

Four roles, never blurred. The ratchet runs on the TV — not the key, not the
router, not the vault:

  kidulKey (ROOT)  CERTIFIES the OMEMO identity key — signs its public half
                   ("this IK belongs to a muster member"). Never generates it,
                   never runs the ratchet: the root signs the WHO (identity,
                   non-repudiable), never the WHAT (the ephemeral DH = deniable).

  TV (the box)     GENERATES the OMEMO IK + prekeys and RUNS the double ratchet
                   (the per-message crypto). The IK private key is resident on
                   the box (SYSTEM tier), never on the cold root. The TV is also
                   the policy approver — which phones/peers board.

  krouter          DISTRIBUTES: relays signed prekey bundles, holds the roster
                   (kpax) as single source of truth. Never creates, never signs,
                   never holds a private key. Offline = peer-to-peer direct; the
                   krouter is a relay when present, never a trust anchor.

  vault (kvaultd)  COORDINATES: the cold, immutable point that holds the PUBLIC
                   side of an exchange (signed bundles + roster + session state)
                   and mediates the handshake. No seeds/private keys, so NO
                   ratchet generator of its own — a ratchet needs the IK, which
                   the law keeps off the vault. Its "be there for the secrets to
                   be passed" = the PUBLIC material only.

One line: the kidulKey vouches, the TV encrypts, the krouter delivers, the
vault holds the (public) door open. The ratchet is the TV's; the vault's
immutability is for coordination custody, never private-key custody.

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

## krypto — the access scheme (one key, two doors) (LOCKED 2026-10-05)

krypto is the NAME for the whole kidulKey access/rendezvous scheme — the "one
key, two doors" spine that opens internal (bench VMs) and external (servers,
webpage) alike. It is NOT a new cipher and NOT a new daemon; it is the existing
crypto substrate (this file) pointed at the access problem.

  attest, not authenticate  the kidulKey never "logs in" and never dials out.
                            It stays cold and offline (never on a box). It
                            ATTESTs/signs each device's SSH host+client keys, so
                            "this VM is really my VM" is anchored in silicon,
                            not first-seen trust (no TOFU). The chip vouches
                            for the thing that dials.

  no doorman, one skipper  there is no doorman and no counter that "decides".
                            The KID (the skipper's key) says yay or nay by
                            SIGNING the list; the list (kpax) lives in the
                            safe (dom0) where nobody can tamper with it.
                            Admission = "is your name on the signed list", not
                            "did the doorman wave you through". A server never
                            grants its own access — the cut lives one level up,
                            always (the eye-above law).

  key on person             the kidulKey is held by the human for the INITIAL
                            connection only. After that, session keys take over
                            (transient, ~500 bytes, discarded on close — the
                            O(time) rule). Cued at connection-establishment,
                            never resident.

  one key, two doors        internal (bench VMs) and external (servers/webpage)
                            are the SAME identity spine — what the key opens is
                            decided by the signed roster (this file), not by
                            which side of the wire you're on. Same rendezvous,
                            both directions (identity.md: run the coordinator,
                            don't trust it).

  sshd by role              bench VMs + server/NAS run sshd (the NAS's is the
                            BODY act). The TV NEVER runs a listening sshd — it
                            dials out, no remote-admin surface. krypto does not
                            change that; it is why it holds.

## KID + kpax — the admission gate, named (LOCKED 2026-10-05)

The whole scheme has one granny sentence, and these are its two nouns. The
kidulKey IS the identity; there is a counter where that identity boards the
ship. Both sit on the krypto machinery (the section above) — these are the
NAMES for the human-facing halves.

  KID    = the skipper's key — the kidulKey. The ONLY thing aboard that can let
           people on. It says yay or nay. It signs the list. Never a password;
           the captain's key is the admission. There is NO doorman — a doorman
           is a second authority to corrupt, and this ship has exactly one.

  kpax   = the passenger LIST (WHO boards). The roster (this file's household
           roster) — the manifest on the door. Extends the ship's own word PAX
           (starship.md §7.2: Captain, crew, PAX): not the gate, the LIST. The
           KID signs it; the list lives where nobody can mess with it (dom0, the
           captain's safe). Admission = "is your name on the list, as signed by
           the KID" — not "did the doorman wave you through".

  kiosk  = the OPEN kiosk (kiduldm --kiosk). NOT the kpax. No list, no KID, no
           admission: grab popcorn, seat yourself in the public/free theatre.
           The foyer, not the show. The DM's no-login mode stays exactly where
           it is — the two must never blur.

  krypto = the machinery (the section above) that makes the list HOLD: the
           assembled crypto, attest-not-authenticate, key on person, one key
           two doors.

One sentence for Granny: "The skipper's KID signs the kpax" — the list on the
door says she boards, nobody else can change it, and she never remembers a
password again, because it is her, boarding her ship, and the list already
knows her.

(The KID here is the kID — the kidul identification — now with its own law at
kid.md: deny-by-default, one key, one roster, file-by-file. This section names
the gate; kid.md is the umbrella. The privacy/unlinkability layer — the
WHO/WHAT/ENVELOPE split + blind signatures — lives at kid-unlinkability.md,
LOCKED 2026-11-17.)

STATUS (honest): the architecture is frozen here; the MECHANISM is not yet
built. Bench access TODAY is a plain ed25519 key on disk
(~/.ssh/id_ed25519_kidulwm); hardware-attested SSH + the resident-key client
is a docket, not done. Until then we "keep it in mind" while working: use any
key for the bench, but leave the seam shaped for krypto (attest, not
authenticate; dom0 yay/nay; key on person) so it drops in without rework.

## Size — the honest number

  keys        ~128 bytes per identity (Ed25519 + X25519 keypair); a signed
              prekey bundle ~300 bytes; ~100 one-time prekeys ~3 KB; a device's
              full material ~3-4 KB.
  trust store ~0.5 KB per known device; 100 devices ~50 KB.
  binary      primitives ~300-400 KB + X3DH/ratchet ~100-200 KB = ~0.5-1 MB.

Total ~1 MB, keys included. O(devices), never O(time): keys are fixed, sessions
are transient (~500 bytes, discarded on close). It never grows with usage.
Footprint is a non-issue on every device class — deploy everywhere, it's free.
