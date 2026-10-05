# LAW — power states & the boot ladder (LOCKED 2026-10-02, Barticus present)

KISS governs. Only what it needs, cue on demand, no eager boot, no target
machinery, no DM. "Sensible design is all that's needed."

## The boot graph (time-to-first-playable)

  firmware -> limine(timeout 0) -> kernel -> kboot (mount + load drivers) ->
  FOUNDATION: knetd (network authority, ACTIVE — a CAGED sys-net brig, see
  dom0.md) + log drain + getty (the mouth)
  -> kushd (usher) -> kidulwm (the face) -> cue kplayd -> playing.

Foundation-first BECAUSE the usher stands on it: kushd consumes knetd (to dish
out network pens for the beer garden / VMs / every machine class) when it seats
each act. There is no "under or over" — knetd is neither a kushd child nor
alongside it; it is the substrate the usher needs already up to do its job.
knetd survives kushd (the recovery path) for the same reason.

BUT knetd is CAGED, not a bare-kernel peer of the secrets: network does not
live in the trust core (dom0.md). It is the sys-net brig — boots before
kushd, survives kushd, owns the pens, and is isolated from kvaultd/kidulKey by
the same wall that keeps the beer garden out of the theatre. The usher holds
the cut on it ("make a mistake and I will cut you").

The vault is NOT a foundation process — it is COLD STORAGE: an encrypted file,
unlocked on demand (cued), wiped from RAM on close (zeroize + no-swap + no-dump).
No boot presence. Key-mode rides the kidulKey.

Two maps never blurred (theatre.md): knetd owns the NETWORK (pens included),
kushd owns the LIFECYCLE. When the usher seats an untrusted act it ASKS knetd
for a pen — it never mints one itself.

bill correction: drop the knetd line from bill.kush's BODY list (knetd is
foundation, not a kushd act) — same class of fix as the dropped kvisd line.

## kboot — the usher's handoff (LOCKED 2026-10-03, Barticus present)

kboot is the boot stage: firmware handoff -> kernel -> mount root + load
drivers -> exec kushd. Its whole job is one word: kboot -> kbuggerOff. It
boots, hands off, and is gone. A fresh usher every boot.

The boot order IS the usher's handoff. mkinitcpio HOOKS, limine.conf, the
drop-back flags — these are not a ticket; they are HANDOFF NOTES, written for
the next usher (same shape as HANDOFF.md between relogs). The usher updates
the kboot files; the thing just kboots. De-systemd-ize = hand back the jobs
Linux already does, and write the handoff ourselves — in our handwriting, not
systemd's unit-file handwriting.

## The recovery path lives BELOW the thing it recovers (LOCKED 2026-10-03)

One principle, three instances — the shape that makes the handoff survive a
bad boot. A thing cannot pick its own rescue:

  limine  recovers kushd+kernel  (snapshot rollback) — below the usher.
  knetd   survives kushd         (network up first) — dom0.md.
  remote  survives the vault     (seed proves, vault cold) — input-trust.md.

This is why kushd does NOT do the bootloader job: the usher is the thing the
bootloader recovers. The recovery path is the handoff itself, and it must
never be corrupted by the boot it is there to rescue.

CLARIFICATION (2026-10-04): knetd's place in foundation is NOT "so a remote
can reach in." knetd boots first because the usher STANDS ON IT — kushd asks
knetd for a network pen every time it seats an untrusted act, and never mints
one itself. Remote reachability (knet, the sshd-replacement lane) is a
CONSUMER of the network, not the reason the network daemon exists. The
"knetd survives kushd" line above is the mechanism, not the motivation: the
network staying up through a usher crash is a beneficial side-effect of knetd
being foundation, not the cause of it.

## The fault lines — what kboot zeroization removes, and what it cannot

Zeroizing kboot + kushd + kidulwm de-foreigns every SOFTWARE stage from the
firmware handoff up: boot stub, init, daemons, face — all ours, one tower.
Two things remain not-ours, and they are different kinds of foreign:

  KERNEL   the last foreign SOFTWARE. Held only because it owns the drivers we
           would otherwise write for a decade. The north-star docket (kboot.md:
           RISC-V + FPGA puts even bring-up in our hands).

  SILICON  CPU microcode, the Intel ME / AMD PSP, the UEFI firmware itself.
           Loaded at reset — BEFORE our code runs — resident in the CPU and
           chipset for the whole session, with DMA to memory. Zeroizing the
           boot chain does NOT remove them; they sit below it, and no software
           we write can evict them. Only owning the chip does.

This is why the skipper's law (starship.md) is doctrine, not defeatism:
"NOTHING IS EVER 100% safe." The manufacturer's silicon is the one fault line
software cannot zeroize — it is the reason the captain's safe is in the cockpit
with only the captain's keys, and the reason the north star is our own silicon.

## Device bring-up (drivers + perms)

Drivers load at BOOT, before kushd seats anything — never a daemon's job, never
a usher job. Machine class decides the shape:

  TV (immutable)   drivers BAKED into the kernel (built-in). Zero module
                   loading, golden image, max lean. Hardware change = replace
                   the appliance.
  laptop / NAS     changeable hardware: module AUTOLOAD by modalias. The kernel
                   emits a MODALIAS uevent -> a tiny helper (kmodd, a body act)
                   reads modules.alias (depmod) -> modprobe loads the match.
                   Generic, not hardware-specific: a new card loads its own
                   module; a missing driver is a log line, the device stays
                   absent, knetd tolerates it. kmodd is NOT udev (no rules, no
                   node management) — a kernel-gap filler, same class as knetd.

Device-node PERMS: devtmpfs makes /dev nodes root:root; the face (non-root
kidulwm) needs /dev/dri, /dev/input, /dev/snd with the right group/mode. A few
static chown/chmod at boot (kushd early step) — not a daemon, not udev. Hotplug
(USB, disk swaps) is the only thing that'd want real udev; a TV has none.

## Power states by machine class

  KSD TV        remote-driven. NO WoL. "Off" = S3 suspend; power-on/remote =
                ~1s resume. Cold boot is the rare case.
  network box   knetd — the router, one daemon, two stances (client / router).
                Foundation. S3 + WoL, idle-until-poked.
  server / NAS  the Brain (H200) + the NAS media store. S3 + WoL, idle-until-poked.

WoL is pre-OS (NIC firmware / BIOS / EFI). Our only roles: knetd sets the NIC
wol flag; the A5 ladder branches on the wake reason (WoL vs key vs power button).

## The krouter — the tiny router that plugs into the ISP router (LOCKED 2026-10-05)

"Have we got our router design mixed with our system design" — resolved: we
did NOT overload knetd, and the router is NOT the TV's job. The answer was
already locked (line 117): knetd is ONE daemon, TWO stances, on TWO boxes.

  client stance  the TV's knetd. REACHABILITY ONLY: DHCP client, wifi
                 supplicant, MAC spoof, link state. It is the CAGED sys-net
                 brig (dom0.md) and the network AUTHORITY (it mints the pens,
                 kushd asks) — but it is a CLIENT, never a server. It has no
                 DHCP-server code, no ip_forward, no NAT, no MASQUERADE, no
                 route-add for anyone but itself. Verified by source grep on
                 2026-10-05: dhcp.zig is a DISCOVER/OFFER/REQUEST/ACK state
                 machine leasing an address FOR ITS OWN interface. That is the
                 whole "no overtime" guarantee — the TV never hands out IPs.

  router stance  the network box = the krouter. DHCP server, forwarding, the
                 internet edge, the household roster (crypto.md) — and, for
                 v1, a simple LAN firewall + the guest network (a cell — see
                 cells.md). This is the "tiny kidul router that plugs into the
                 ISP router": OUR box at the ISP boundary, so the
                 passwordless/granny-proof system leans on a router we own,
                 not the ISP's. It runs knetd in router stance (kboot.md:
                 foundation, not a kushd act).

  two edges      the krouter is one box with TWO edges, but NOT both at once:
                 v1 ships only the WAN edge (to the ISP router). The KWEB mesh
                 edge (the antenna on the roof — our identity-addressed mesh,
                 identity.md) is "put in place for later use": a placeholder,
                 not a v1 duty. It activates only on machines that actually
                 need it (the mobile devices that join the kweb) — and the TV
                 never does, unless the kweb becomes the ONLY web. The TV's
                 connection is direct to the krouter and the NAS/servers, and
                 nothing else.

  kweb transport (for later, LOCKED 2026-10-05) — the mobile edge rides TWO
                 stacked layers, never confused:
                   physical  BATMAN-adv (in-kernel L2 mesh; `bat0` is a virtual
                             switch, protocol-agnostic — IPv4/IPv6/DHCP/mDNS
                             work unmodified; mobility, heterogeneous links).
                             Link layer = 802.11s MESH-POINT mode (IBSS/ad-hoc
                             is deprecated). Path metric = BATMAN V (throughput).
                   logical   KWEB / Reticulum (identity-addressed routing +
                             encryption) — this is what identity.md already
                             calls "our mesh". BATMAN-adv moves the frames;
                             KWEB decides who may talk and encrypts it.
                 "Add BATMAN & whatever else is useful for mobile networks" =
                 the physical layer under the kweb; it is a LATER docket, not
                 a v1 build, and only where the mesh actually lives.

  guest network  "just a cell" (cells.md): the guest network is NOT a second
                 network construct — it is a pen (the same wall we already
                 build), seated by the usher, with the roster's `guest` role
                 and QoS owner-over-guest (the class + priority ladder). Crypto
                 is the same across ALL machines — dom0, the kidulKey is the
                 only key — so there is nothing for the guest network (or the
                 kweb) to see. Permissions done right, nothing new added.

The split is clean and already half-locked. What this freezes NEW is the
no-overtime PIN (client stance must never grow server/forward/NAT code — any
future DHCP-server, NAT, or routing work lands in router stance, not the TV),
the v1 scope (LAN firewall + guest cell + QoS; KWEB is a placeholder for later,
only where needed, never the TV), and the guest-network-is-a-cell principle.

## The one primitive: ready-report

"the act reports done" (SYSTEM.md §2.2) makes the ladder hold. Each rung
signals ready (knetd: network up; kidulwm: wayland up) and kushd waits before
cueing the next. No sleeps, no polling, no target graph.

## OMEMO — the crypto layer

OMEMO (E2E) lives at the trust boundaries (router WAN edge, remote -> device),
cued at connection-establishment, never in the boot order. Full architecture
(root of trust, substrate, consumers, size): crypto.md.
