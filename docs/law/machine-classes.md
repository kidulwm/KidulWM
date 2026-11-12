# LAW — machine classes (the classist law)

Status: LOCKED 2026-11-11, Barticus present (GSI).
This is the expansion of kboot.md's "three branch points" into the full
catalog, plus the setup-time selection rule and the safety-by-default posture.

---

## 1. The one-line law

A machine's CLASS is a single signed enum, chosen ONCE at setup (manufacture
or install), sealed into the immutable base image, and read at boot — never
probed, never mutable at runtime. Everything the box IS derives from it: kernel
driver strategy, the bill, input admission, network stance, access surface,
availability posture, trust posture. One image, one installer; the class is the
fork. No per-class editions, ever.

## 2. Why (the mega-roach this kills)

Maintaining a "server / desktop / router / laptop / TV edition" is N images, N
installers, N drift vectors, and N places a safety default can be forgotten.
A class enum is one codebase, one image build, one installer — the class forks
only the DERIVATIONS. Granny never sees a fork: the TV's class is set by us at
manufacture; the installer is the blueprint's hand (SYSTEM.md §7.3), not a
wizard.

## 3. The catalog — the boxes of the KWEB

HOST classes (physical, chosen at manufacture or setup):

  tv        the appliance. Remote input (paired at first-boot), face, closed
            leaf, golden image. ATTENDED. Granny's box.
  pc        the personal workstation. Laptop OR desktop — built-in vs external
            keyboard/trackpad is HARDWARE the kernel autodetects, not a class
            fork. Face, full input, operator stance, writable workbench.
            ATTENDED.
  server    headless. net+storage drivers, no face, no input, serving stance
            (services + storage + compute on the LAN). A workload host, NOT a
            packet mover. Administered over LAN: ssh + k-wayland remote.
            UNATTENDED. The compute server (the H200) is a SERVER whose bill
            carries the compute act — no separate class.
  router    the network box. knetd router stance (DHCP server, forwarding, AP,
            fibre). THE NETWORK AUTHORITY — most closed, serial console only,
            NO remote desktop, ever. UNATTENDED, and first up after power loss.

GUEST class (runs INSIDE a KVM brig — the test harness / foreign-code cage):

  brig      virtio-only drivers, no face (or a virtio-gpu console), virtio-net
            client. The ksd-reset VM. This is a class ONLY because kmodd must
            load the virtio chain for it; cells (pen) need no class entry.

Four host classes + one guest. tv and pc share one kernel/face/bill branch and
diverge only on INPUT, ACCESS SURFACE, and TRUST. server/router share the
unattended headless branch and diverge on NETWORK STANCE and ACCESS SURFACE.

## 4. The axes — what the class derives

Each class fixes every axis. There is no free-form axis exposed to the
installer; a new box type is a new NAMED class, reviewed like a law change.

  A  KERNEL DRIVER STRATEGY (kmodd)
       baked           tv — all-in-kernel, zero modules.
       modalias        pc — autoload by modalias (not udev).
       fixed-list      brig — the hardcoded virtio chain.
       subsystem       server (net+storage+compute), router (net) — modalias
                       LIMITED to those subsystems; never GPU/input/sound.

  B  FACE (display + compositor)
       face            tv, pc — kidulwm + seatd + DRM.
       headless        server, router, brig — no kidulwm, no Wayland, no seatd.

  C  INPUT (admission by proof — input-trust.md)
       none            server, router.
       remote          tv — a PAIRED remote (see §5.1), no generic codes; no
                       keyboard/trackpad admitted.
       full            pc — keyboard + pointer by proof; built-in or external
                       is discovered, not chosen.

  D  NETWORK STANCE (knetd)
       client          tv, pc.
       router          router — DHCP server, forwarding, AP.
       server          server — serves services/storage/compute; uplink as
                       client.

  E  ACCESS SURFACE (safety-by-default — closed unless opted in)
       closed-leaf     tv — local remote + mouth getty only. NO ssh, NO inbound
                       LAN. The TV is not a management surface.
       operator        pc — local input + mouth getty + ssh (opt-in,
                       kidulKey-auth).
       admin           server — knetd-auth mgmt channel + operator ssh +
                       k-wayland REMOTE (server only).
       serial-mgmt     router — LAN mgmt + serial console ONLY. No ssh, no
                       remote. The network authority carries the least
                       reachable surface.

  F  THE BILL (kushd acts)
       full-theatre    tv, pc — seatd + kidulwm + ksound (body); kmedia /
                       kplayd / pipewire / kbrain / kfiles / browser (cued).
       headless-organs server — knetd (foundation) + workload acts as cued
                       tentacles: file-serving, service-bobs (named on
                       landing), the COMPUTE act (local model / ollama on the
                       H200). The bill is per-instance, not a class fork;
                       vault stays COLD.
       empty           router — knetd (foundation, router stance) + a
                       near-empty bill; kushd present, nothing cued.

  G  TRUST / IMMUTABILITY (verified-boot + dom0)
       golden          tv, router — dm-verity sealed, kidulKey-signed, no
                       writable base.
       layered         server — dm-verity base + writable data layer.
       workbench       pc — writable until base swap proven.
       caged           brig — guest; caged by the host's cell walls.
       EVERY class keeps the mouth (getty) + the drop-back (kbuggerOff) BELOW
       the thing it recovers. No class is ever unreachable in disaster.

  H  AVAILABILITY / ENTRY (the attended/unattended split — Barticus 2026-11-11)
       attended        tv, pc — a human is present to authenticate at the door
                       (the ladder: kidulkey.md, see §6). Power loss -> a human
                       reboots and authenticates.
       unattended      server, router — boot the CLOSED base automatically
                       after power loss; expose only the authenticated mgmt
                       channel; DATA stays key-gated. Booting is not unlocking.
       "come up on LAN" is a SETTING whose default the class fixes: ON for
       server/router (must survive a power cut with nobody home), OFF-and-
       hidden on pc, fixed-attended on tv.

## 5. Setup-time selection (the installer's fork)

  - The installer writes the class ONCE into /etc/kboot/class, as part of the
    sealed dm-verity base. It is signed by kidulKey and becomes part of the
    verified-boot identity: after setup it is IMMUTABLE.
  - The installer then DELEGATES per class: bake drivers (tv) or ship the
    module tree (pc); write the bill; write the input allowlist; set the
    access surface; set the availability default; configure knetd's stance.
  - tv / router are set at MANUFACTURE by B&B — the factory image carries the
    class; Granny never sees a prompt.
  - Public stance (SYSTEM.md §7.1): the installer is public, but the safety
    boundary is structural — the class is sealed+signed, and every access
    default is CLOSED. A stranger choosing "server" gets a closed server, not
    an open one.

### 5.1 Remote pairing is a FIRST TASK (tv only)

The TV's remote is admitted by PROOF, not by generic codes (input-trust.md:
"admitted by proof, not presence"). Pairing is a setup-time first task: the
remote is bound to the box at manufacture (or first-boot), the binding is
sealed with the class, and no unpaired remote — and no clone with the same
button codes — is admitted. Granny's remote "comes paired"; she never runs a
pairing wizard.

## 6. The entry ladder — lives in kidulkey.md, not here

Entry (key vs PIN/password) is the SAME ladder on every class, and it is
already LOCKED in kidulkey.md ("The PIN — passwdless is earned, never
default") with identity.md ("two-factor by architecture": the key's own
fingerprint/PIN is the wall, a bare key is possession = access). The class
does NOT restate it. Axis H fixes only the AVAILABILITY seam (attended vs
unattended); HOW a door opens is kidulkey.md's one ladder, everywhere.

## 7. Safety by default (the rulings)

  1. DEFAULT IS CLOSED. Every class opts IN to access; nothing is open by
     inheritance. Fail-closed: unknown class = REFUSED (kmodd must reject, as
     bill.kush already does for process classes).
  2. THE CLASS IS PART OF THE VERIFIED-BOOT IDENTITY. It rides in the
     dm-verity base, not a mutable config file. An attacker who rewrites
     class (tv -> server, to open ssh) must rewrite the sealed image, which
     needs the key. Class tampering = authenticity failure = fail-closed.
  3. THE ROUTER IS THE NETWORK AUTHORITY, NOT A SERVER. It is first up (it IS
     the LAN), carries the whole mesh's blast radius, and is therefore the
     MOST closed: no face, no input, no ssh, no remote desktop, serial-only,
     immutable. A server is a workload host and may be more open. Do not
     collapse them.
  4. REMOTE DESKTOP IS SERVER-SURFACE ONLY. The k-wayland remote is legitimate
     on the server (interactive admin of a workload host) and FORBIDDEN on the
     router (a GUI on a packet-mover is attack surface on the
     highest-blast-radius box for zero gain).
  5. THE BRAIN IS NOT A BOX. "Brain" is reserved for THE BRAIN (GLOSSARY.md):
     the knowledge system — structure, links, dockets, workflow — encrypted by
     the key, Private, never shipped. It is not a machine class, not hardware,
     not an LLM. The H200 is a SERVER that runs compute; the local model is an
     LLM, a tool. No class is ever named "brain."
  6. NO FREE-FORM CLASS. A new box type = a new named class, reviewed like a
     law. No runtime flag soup, no cross-product ("server in a VM" is a new
     named class, not a flag on server).
  7. THE CLASS IS NOT A PROFILE. profiles.md = CELL confinement (pen/brig/
     plank — what walls a foreign process gets). The class = the MACHINE (what
     kind of box). Orthogonal; do not merge the words.

## 8. The KWEB access graph (who reaches whom)

  reach ->          router   server   tv    pc
  router  reaches    (self)   --       --      --
  server  reaches    yes      (self)   --      --
  tv      reaches    yes      yes      (self)  --
  pc      reaches    yes      yes      yes     (self)

  Reached BY:
    router   <- everything (gateway; least surface, most hardened)
    server   <- pc (operator + mgmt), tv (services + compute)
    tv       <- nobody (closed leaf; local remote is not LAN)
    pc       <- nobody inbound (operator reaches out, never listens)

  The shape IS the safety: the box everyone reaches is the most closed; the
  box that reaches everyone (operator pc) holds the keys but the vault stays
  cold and off the pc (dom0.md).

## 9. Relationship to existing law

  kboot.md        this is the "three branch points" expanded to the catalog.
                  kboot reads the class once; kmodd executes strategy A.
  distribution.md the golden image IS per-class (sealed, signed). The
                  installer writes the class at base-build.
  verified-boot.md  class is part of the sealed base identity (ruling 2).
  dom0.md / starship.md  seat grades per class; network never in trust core.
  input-trust.md  the allowlist is class-derived (C: remote/full/none); the
                  remote pairing (§5.1) is proof-admission, not codes.
  identity.md / kidulkey.md  the entry ladder (key vs PIN/password) lives
                  there; §6 defers to it, the class does not restate it.
  GLOSSARY.md     "THE BRAIN = Bob Dotrix" — ruling 5 enforces the reserved
                  word; the class never uses "brain" for a box or an LLM.
  SYSTEM.md §7.1  knetd stands alone — router/server run it without the full
                  KSD stack (no kidulwm, no kushd, no Wayland, no slide model).
  SYSTEM.md §7.3  class is a base property, written by the blueprint (KEYE),
                  never by a user shell.
