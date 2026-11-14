# LAW — The Cells (pen, brig, plank — the three cell types) (LOCKED 2026-10-05, Barticus present; RE-CUT 2026-11-14)

RE-CUT 2026-11-14 (Barticus present, GSI): the 2026-10-05 lock dropped the
third cell type and froze "plank" as the DISCARD verb. Barticus's model is
three CELL TYPES; this file restores it. Reversals at the bottom.

The native home is NOT a cell (environment.md: host = native, no wall). A cell
is a foreign thing we wall off. There are THREE cell types, distinguished by
MECHANISM — how much of its own world the guest owns.

## The three cell types (mechanism, not content)

  pen / kcell   shared kernel, HOST compositor. A foreign DISTRO (Debian, apt,
                apps) running on OUR kernel in namespaces + Wayland/PipeWire
                passthrough. Native speed, no hypervisor — "Debian on our
                kernel". Closest to home, the everyday surface. Hardened to the
                ceiling (subuid remap, cap-drop, no_new_privs) but its job is
                "safe enough to hand a kid", not "safe against a hostile
                binary."

  brig / KVM    own kernel, HOST compositor. Foreign CODE we do not trust. The
                guest has its OWN kernel (survives a kernel bug) but renders as
                a SLIDE into kidulwm (the brig-shim scanout) — no guest desktop
                of its own. This is the serious safety tool. The socials seat
                here by default (see "the spoofed persona").

  plank         own kernel, own compositor. The full separate desktop — its own
                distro AND its own window manager AND its own everything. The
                deepest isolation: not just a slide in our face, a whole other
                face. The wild. Granny lands here when the kwayland remote
                desktop + VMs are "flying" — and never knows she moved.

The one-liner, frozen: foreign DISTRO -> pen, foreign CODE -> brig, a whole
other desktop -> plank. A kernel-bug-grade prisoner escalates pen -> brig; a
guest that needs its own world escalates brig -> plank.

Variants are allowed per type. micro-brig is a brig VARIANT (own kernel,
minimal initramfs + one trusted binary), not a fourth type. pen/brig/plank are
the three; everything else is a flavour of one of them.

## Auto-seat-safest (Granny never sees a cell)

"Browsers go in X" — the seating is automatic, chosen by the usher, never by
the user. Granny sees "her browser", never pen/brig/plank (those words are for
B&B, not her). The default auto-suggests the SAFEST class for the content, and
the user may come back from safety — but we encourage staying. The three types
are the mechanism; the auto-seat is the policy; simplicity for Granny is the
whole point (it IS the path to adoption).

## Every type hardened to the ceiling — "as safe as possible," not "safe enough"

The pen being a play-pen does NOT relax its hardening. Every type gets every
wall the box can raise, because the whole point of the split is that each type
is as safe as its mechanism allows, and the choice of type is the only thing
that relaxes. The pen is hardened with namespaces + caps + user-namespace
remap + no_new_privs; the brig with a whole separate kernel; the plank with a
whole separate compositor AND kernel. Never say "it's just a pen, so we can
skip a wall." The wall set is fixed per type; the TYPE is what you change when
the threat outgrows it.

## The pen's own ceiling (what "as safe as possible" means, concretely)

  1. User namespace, always. The cell's root maps onto the SUBUID range
     (subuid 100000+), NOT the host user. Without it the cell runs as the host
     uid and can read every file that uid owns — the filesystem wall is
     cosmetic, not real. The subuid remap is the load-bearing wall.
  2. cap-drop ALL + no_new_privs, so a setuid/setcap binary cannot re-grant.
  3. pid/ipc/uts/cgroup namespaces — it cannot see or signal host processes.
  4. clearenv + exact setenv — no host secrets leak in.
  5. ro-bound rootfs + tmpfs /tmp — it cannot write its own OS image.
  6. die-with-parent — no orphaned prisoners when kcell dies.
  7. socket bridge — the seam crosses the wall without opening the wall (below).

  The one KNOWN gap (documented, not closed): a cell with the real Wayland
  socket can screenshot/keylog other clients. Full GUI isolation for that case
  needs a nested compositor (cage/wayfire) inside the cell. This gap only bites
  if you put untrusted CODE in a pen, which is against the class law above.

## The socket bridge (the k-link seam) — how the wall and the seam coexist

The subuid wall (ceiling #1) creates a problem: the cell's root is host uid
100000, so it cannot traverse the seat user's `700` runtime dir to reach the
Wayland/PipeWire sockets — and even if it could, a `755` socket denies
connect() to a non-owner. The wall would block the very sockets the pen exists
to pass. The seam is the fix, and it uses ONLY what is already there — no new
authority, no new daemon:

  1. bind-mount the declared socket into a per-cell bridge dir, mode `711`
     (traversable, not listable) — the cell CAN reach the socket dentry.
  2. POSIX ACL `u:<subuid_base>:rw` on the socket — connect() is granted to
     exactly the subuid range, "other" stays locked.

The bridge dir is the cell's OWN `XDG_RUNTIME_DIR` — private per-seat, only the
sockets the `.cell` file declares are linked in. It is torn down with the cell:
the ACL entry is removed (the socket lives on the shared inode, so the seat
user's socket returns to its prior access; the auto-added mask that lingers is
inert — it masks no named user and never touches the owner) and the bridge is
unmounted. Two decoupled rules, one primitive: the WALL (subuid remap) isolates,
the SEAM (bridge + ACL) passes exactly what is declared, nothing else.

## The AV bridge: client-side, superior usher, never its own authority

A cell's audio and visual output surfaces in the HOST's single face (kidulwm)
+ single loudness governor (ksound), as a class — never its own authority.
The bridge is CLIENT-side (the cell app is a host Wayland + PipeWire client),
so Wayland's compositor-mediated blindness applies: the cell sees only its own
surface, its own input, its own stream. The four tuning points, frozen:

  1. client-side bridge, not framebuffer passthrough (blindness by protocol);
  2. no host /dev/dri in the cell — its own virtio GPU, only the scanout
     crosses (GPU driver bugs stay in the cell's kernel);
  3. IOMMU enforcing + no untrusted device passthrough (the dmabuf/queue
     region is a DMA surface);
  4. wp_security_context_manager_v1 — tag the cell client as sandboxed so the
     compositor can refuse to let it be screenshotted or read the clipboard.

## The superior usher (the security reason for the hierarchy)

The HOST kushd is superior to the cell's kushd. Not by rank, by necessity: the
superior usher is what enforces that the cell's output is a class, not an
authority. The cell kushd REPORTS a descriptor ("24fps film, stereo 48k,
role=media, class=brig"); the host kushd DECIDES what gets seated. A peer
cell-kushd could claim to be an authority; a subordinate can only hand up a
descriptor and the host seats it or refuses. This is the eye-above law applied
to every cell: the cut lives one level up, always.

## The coordination model (what the usher goes off — two decoupled rules)

AV is FOCUS-COUPLED. The focused slide owns the AV pipe. A cell/brig's audio
and video is just a pipe that reacts to focus: blur it, park it (mute, stop
presenting); focus it, route it. This reuses the class + priority ladder we
already have (ksound's floor table; kidulwm's pixel map) — no new authority.
The VM is not given its own sound or screen; it is given a focus-reactive pipe.

Network is FOCUS-DECOUPLED. Background-persistent. A cell/brig keeps its
network alive regardless of focus, because the network is the recovery path
and the isolation substrate — focus never tears down a network pen. The usher
(kushd) or knetd mints each cell's netns once and holds it for the cell's
whole life, independent of what is on screen.

Both rules are CONFIG the usher reads, not code kcell embeds. The bill carries
the seating chart (which cells, which classes); the .cell file carries the
per-seat wall set; the usher coordinates N cells at once — N netns, N AV
pipes, focus routing the AV, life routing the network.

## Names already locked (do not re-derive)

  pen        = shared kernel + host compositor — our code + foreign DISTROS
               (kcell).
  brig       = own kernel + host compositor — foreign CODE we don't trust.
  plank      = own kernel + own compositor — a full separate desktop.
  micro-brig = a brig VARIANT (own kernel, minimal initramfs + one trusted
               binary, tens of MB). Variants are allowed per type.
  overboard  = the DISCARD verb — process-death-is-the-kill extended to a whole
               cell/guest ("cast overboard"). Never "plank".

## The guest network is just a cell (LOCKED 2026-10-05)

The krouter's "guest network" is NOT a second network construct. It is a pen —
the SAME wall we already build — seated by the usher, carrying the roster's
`guest` role (crypto.md) with QoS owner-over-guest (the class + priority
ladder). Crypto is identical across ALL machines (dom0; the kidulKey is the
only key), so a guest cell sees nothing the owner's cell sees no further into.
"Permissions done right" — nothing new is added, we tweak the walls we have.
Same principle holds for the kweb: a mobile device joining the mesh is another
cell, not a new authority.

## The spoofed persona (socials have nothing real to leak)

The socials (Zoom, the PII-suckers) seat in a brig by default — but the wall
alone isn't the win. The brig ships with a SYNTHETIC identity: fake name, fake
history, no real contacts, no real files. The socials can exfiltrate their
entire world and get a fake person. Defense by architecture, not vigilance:
there is nothing real in the cell to slurp. Granny logs in as herself; the cell
only ever sees a shadow of her.

## Per-folder access — the same wall for DATA (LOCKED 2026-11-01, Barticus present)

Same server, different folders, different roles. A POSIX GROUP is the WRONG
primitive here: a group can still see (stat) a file it cannot edit, so it
leaks existence and metadata. The cell's bind-mount is the RIGHT one — a
folder that is not bind-mounted does not EXIST in that cell's mount namespace:
not "permission denied", "no such directory".

  identity -> role -> cell. The roster (crypto.md) maps an attested key to a
  role; the role maps to a cell whose bind-mounts ARE its folder set:
      adult / owner    = work folders (X,Y,Z) + the public set (A,B,C)
      child-N          = their own + the public set
      guest            = the public set only
  The SERVER enforces it — the cell lives on the server. The krouter only
  coordinates the rendezvous; run the coordinator, never trust it
  (identity.md). A cell can neither see nor learn of a folder it was not
  given.

Same wall as the pen: the bind-mount is the load-bearing seam for DATA exactly
as it is for CODE — "safe enough to hand a kid" is "this folder does not exist
for you", not "this folder is read-only for you".

## Reversals (2026-11-14 re-cut)

  This file's 2026-10-05 lock froze "plank = the DISCARD verb" and dropped the
  third cell type. That is REVERSED: plank is cell type 3 (own kernel + own
  compositor); the discard verb is "overboard" / "cast overboard".
  environment.md's "plank = the discard", distribution.md's "plank = the discard",
  and GLOSSARY.md's "plank = the DISCARD verb" are corrected to match.
  theme.md's "browser plank" zone already meant the deepest zone — that reading
  now aligns with plank = cell type 3, no change needed there.
