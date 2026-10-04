# LAW — kboot (LOCKED 2026-10-04, Barticus present)

kboot is SYSTEM-WIDE: one boot stage for every machine class, not a VM stub
and not per-class. It is the full foundation ladder, not a minimum. The fork
is closed: kboot v1 brings up the whole foundation, then hands off.

## The one-word job

kboot -> kbuggerOff. kboot boots, brings up foundation, hands off to kushd,
and is GONE. A fresh usher every boot. Its only named successor is the
drop-back (kbuggerOff), and that drop-back lives BELOW it (power-states.md:
the recovery path lives below the thing it recovers).

## Position in the boot graph

  firmware -> limine(timeout 0) -> kernel -> kboot ->
    [ mount root + load drivers ] ->
    [ FOUNDATION: knetd + log drain + getty (the mouth) ] ->
    fork kushd (usher, kboot's child) -> kidulwm (face) -> cue kplayd -> playing

kboot is the boot stage and the PID-1 supervisor. It mounts, loads, starts
foundation, forks kushd, and then STAYS as PID 1 to recover kushd if it dies.
It does not seat acts (kushd's job), does not mint pens (knetd's job), does
not gate secrets (there is no DM).

## Step order (the whole job, in order)

  1. mount root rw, then the base mounts (proc, sys, dev, devpts, run, tmp).
  2. load drivers by machine class (below).
  3. start FOUNDATION, forked as children: knetd (network authority, a caged
     sys-net brig per dom0.md), the log drain, and getty on a tty (the mouth).
  4. fork kushd. kushd becomes kboot's child (NOT PID 1); kboot stays PID 1
     and supervises: reap orphans, respawn kushd if it dies, own the shutdown
     signals (SIGTERM=poweroff, SIGINT=reboot).

## The handoff — fork, never exec (corrected 2026-10-04)

kboot is PID 1 and STAYS PID 1. kushd is its forked CHILD, never an exec'd
successor. This is the correction that makes the recovery law actually hold:

  - If kboot exec'd kushd, kboot would be a pointless wrapper and "knetd
    survives kushd" would be a lie: kushd-as-PID-1 dying reboots the kernel,
    so knetd survives nothing useful.
  - Forked, kushd is a replaceable child: kushd dies -> kboot reaps and
    respawns it, knetd (kboot's child too) never blinks. The recovery path
    lives below the thing it recovers (power-states.md), and here it is
    literally true: kboot is below kushd and recovers it.

kboot is the parent; kushd is its child. The usher holds the cut on the
foundation, but kboot holds the leash on the usher itself.

The PID-1 floor that kushd carried in its own early slices (mountEarly,
shutdown signals, power verbs) MOVES to kboot — kboot is now the init, kushd
is a pure usher. kushd's own mountEarly() remains idempotent (EBUSY no-op)
and harmless, but the real floor lives here.

## Machine-class branches (one kboot, three branch points)

The boot graph is identical across classes; only step 2 differs.

  TV (immutable)   drivers BAKED into the kernel (built-in). Zero module
                   loading, golden image, max lean. Hardware change = replace
                   the appliance.
  laptop / NAS     changeable hardware: module AUTOLOAD by modalias via kmodd
                   (a body act that reads modules.alias -> modprobe). Generic,
                   not hardware-specific. kmodd is NOT udev.
  network box      knetd runs in router stance (foundation, not a kushd act).

kboot selects the branch from a machine-class flag read once at boot, never
from probing. The class is a property of the box, not a runtime discovery.

## kbuggerOff — the drop-back, below kboot

kboot -> kbuggerOff is the whole reason kboot's job is one word. The
drop-back (BIOS / snappies / DM / BOOT by cue, see power-states.md and the
kbuggerOff design note) must NEVER be corrupted by the boot it is there to
rescue. The grub `init=` line remains as the emergency fallback only — it is
the fire escape, not the product.

## What kboot is NOT

  - Not a daemon. It STAYS as PID 1 (supervising kushd) — it is the init.
  - Not a kushd child. It is the parent; kushd is its forked child.
  - Not systemd. There is no unit graph, no target machinery, no eager boot.
    Foundation is a fixed, tiny list; kushd does the cueing after handoff.
  - Not the vault. The vault is cold storage (power-states.md); kboot never
    touches kvaultd or the kidulKey.

## Toolchain & home

kboot is a boot stub, built with the house Zig (aig), static, no libc
surprise. It lives alongside kushd (its exec target) and knetd (its first
foundation child) in the boot ladder. The mkinitcpio HOOKS and limine.conf
are HANDOFF NOTES (power-states.md) — kboot reads its handoff from the same
shape every other stage uses.

## Why system-wide (the reason it is one stage, not many)

The boot ladder is the one path every box runs before it is anything else —
TV, laptop, NAS, router, Brain. If kboot forked per class, the handoff notes
would fork too, and the drop-back (the thing that must never break) would
have N shapes to survive. One kboot, three branch points, one handoff shape.
KISS governs: only what the ladder needs, cue on demand, no eager boot.
