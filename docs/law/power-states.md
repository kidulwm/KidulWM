# LAW — power states & the boot ladder (LOCKED 2026-10-02, Barticus present)

KISS governs. Only what it needs, cue on demand, no eager boot, no target
machinery, no DM. "Sensible design is all that's needed."

## The boot graph (time-to-first-playable)

  firmware -> limine(timeout 0) -> kernel -> initramfs (mount + load drivers) ->
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

## The one primitive: ready-report

"the act reports done" (SYSTEM.md §2.2) makes the ladder hold. Each rung
signals ready (knetd: network up; kidulwm: wayland up) and kushd waits before
cueing the next. No sleeps, no polling, no target graph.

## OMEMO — the crypto layer

OMEMO (E2E) lives at the trust boundaries (router WAN edge, remote -> device),
cued at connection-establishment, never in the boot order. Full architecture
(root of trust, substrate, consumers, size): crypto.md.
