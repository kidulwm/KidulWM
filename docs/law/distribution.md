# LAW — software distribution & installation (the cell-keyed package model) (LOCKED 2026-11-10, Barticus present)

KSD distributes software three ways, keyed to WHAT it is and WHERE it runs. The
base is a sealed image with no package manager. Native apps come from our store.
Foreign software runs in a CELL, where the foreign OS's own package manager
works inside the cage. This law names the three paths and the cell-keyed rule.

## The purity line (consolidated)

"Distro = kernel + pacman" (SYSTEM.md I7). The host stays pure: no systemd, no
udev, no NetworkManager, no polkit, our init (I7). The cell wall is what lets
purity and foreign software coexist — the host never carries a foreign init, the
cell does.

## Three paths, keyed to provenance

  BASE (organs + share house)  a golden image, sealed dm-verity, signed
                               kidulKey, OTA'd as a whole. NO package manager,
                               ever. kfiles / kbrowser / kmedia are baked in as
                               necessities — "in everything" — not packages.

  NATIVE (KSD apps)            Wayland/Zig tentacles, run directly on kidulwm.
                               OUR store: libalpm engine + kidulkey-signed repo
                               + kidulworks.com. The only package manager we
                               build. Small, native-only.

  FOREIGN (distro or code)     runs INSIDE a cell (pen / brig / plank), where
                               the foreign OS's OWN package manager (apt / pacman
                               / dnf) works inside the cage. We maintain the CELL
                               and its walls, never the foreign packages.

## The cell-keyed rule (the correction to "native-only")

Foreign software is NOT excluded — the cells exist precisely to run it. The
package manager in play is determined by the CELL TYPE, not by us:

  pen    namespaces on our shared kernel; foreign DISTRO userspace (Debian /
         Arch). Its apt/pacman runs INSIDE the pen. Cheap, feel-local, kid-safe
         (cells.md: "foreign DISTRO -> pen").

  brig   KVM, own kernel; foreign CODE, or a whole foreign OS (Ubuntu with its
         own systemd and X11). That OS's package manager runs INSIDE the guest,
         caged by the AV bridge + superior usher + network pen (cells.md:
         "foreign CODE -> brig").

  plank  the discard — the most-unsafe guests: run whatever, overboard on
         misbehave. The least-trusted cell, enforced by discard (profiles.md).
         NOT native/no-cage — "native" is the trust core (Private), not a cell.

## The systemd problem dissolves at the cell wall

A foreign app that needs systemd runs in a BRIG — a guest that carries its own
systemd. systemd lives INSIDE the cell, never on the host. The host stays pure;
the guest carries whatever init it wants. The cell wall is what makes "our side
pure" and "foreign software works" true at the same time.

## The base carries the cage, not the packages

The cell APPARATUS (kcell, kushd, the .cell wall files, the bridges) lives on
the base — it is the confinement machinery that makes foreign software safe. The
package MANAGERS (apt/pacman/dnf) live INSIDE the cells, per-user, per-cell.
Nothing installable touches /. The thin native store is a tentacle, not a base
daemon; it may live per-user too. The base stays minimal and immutable.

## Supply chain: kidulKey signs native apps

A native app installs only if its signature chains to kidulKey (kidulkey.md's
key family). Curated-by-default: the store presents only signed, reviewed apps.
Foreign software is gated by the CELL it runs in (pen/brig/plank walls), not by
our signature — the foreign OS's own package manager + our cage are the trust
story there.

## Granny installs with one tap

The store is a Grannyized surface (grannyize.md): Open / Install verbs, never a
CLI. Granny taps Install on a native app; a foreign need is met by a native app
or by a cell the owner pre-arranged. The machinery behind either is hidden.

## Kids hack free, community store not ours

"FREE for kids to hack" (GPL, non-revocable) is structural: dev-mode side-load
lets a kid run their own app on their own box. B&B builds and maintains NO
community app store — a neutral community showcase may exist, kept by others;
we do not build it, host it, verify it, or vouch for it.

## The Zoom case (revised for cells)

Native (our XMPP client) is the default. The literal Zoom binary, if wanted,
runs in a brig: a lean Ubuntu guest with its own systemd + X11, `apt install
zoom`, bridged to kidulwm's face, focus-coupled AV. We maintain ONE brig recipe,
not a Zoom package — the cell is reusable across a thousand foreign apps.

## Rulings (all LOCKED 2026-11-10, Barticus present)

  A. plank        the most-unsafe guests, discard-on-misbehave. NOT native/no-cage;
                  "native" is the trust core (Private), not a cell. (profiles.md.)
  B. store shape  an app (tentacle), not a body organ.
  C. repo format  YES — reuse pacman's .db + .pkg.tar.zst under our key.
  D. dev-mode gate  OWNER's key (kidulkey.md open owner/master hierarchy).

## Relationship to existing law

  profiles.md        the profile is the cell (wall = containment, not armor);
                     Private = native = trust core, not a cell.
  cells.md           pen/brig/micro-brig classes + the plank (discard); socket bridge.
  dom0.md            network in the brig, not the trust core; knetd caged.
  verified-boot.md   dm-verity base + fs-verity/IMA writable layer (native exec gate).
  kidulkey.md        signing root + FRIENDLY tier (per-user footprint gating).
  SYSTEM.md I7       "distro = kernel + pacman" — this law names WHERE it lives.
  grannyize.md       the store's surface obeys the Grannyize credo.
