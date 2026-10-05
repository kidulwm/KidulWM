# LAW — The Cells (pen & brig, the security classes) (LOCKED 2026-10-05, Barticus present)

The two arms of the seat grade are the two security classes, and they map to
WHO plays there, not to a geometry. One naming, stated once.

## The classes: kids in the pen, adults in the brig

  pen / kcell   the PLAY PEN — kids play here. Our code AND foreign DISTROS
                (Debian userspace, apt, apps). Namespaces + Wayland/PipeWire
                socket passthrough, shared kernel, native speed, no hypervisor.
                It is NOT the serious safety tool. Seeing a foreign distro run
                on the host kernel is what makes it a true play-pen: it is the
                comfortable, feel-local, everyday surface. It must still be
                hardened to the ceiling, but its job is "safe enough to hand a
                kid," not "safe against a hostile binary."

  brig / KVM    the PUB — adults go here. Foreign CODE we do not trust
                (hostile binary, kernel-bug-grade threat). Own kernel survives
                a kernel bug; a container shares the kernel so it does not.
                This IS the serious safety tool. The exception, not the default.

The division is a one-liner, frozen: foreign DISTRO -> pen, foreign CODE ->
brig. A kernel-bug-grade prisoner escalates from pen to brig; a hostile binary
is never seated in the pen at all.

## Both arms hardened to the ceiling — "as safe as possible," not "safe enough"

The pen being a play-pen does NOT relax its hardening. Both arms get every
wall the box can raise, because the whole point of the split is that each arm
is as safe as its mechanism allows, and the choice of arm is the only thing
that relaxes. The pen is hardened with namespaces + caps + user-namespace
remap + no_new_privs; the brig with a whole separate kernel. Never say "it's
just a pen, so we can skip a wall." The wall set is fixed per arm; the ARM is
what you change when the threat outgrows it.

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

  pen        = namespaces/LXC — our code + foreign DISTROS (kcell).
  brig       = KVM — foreign CODE we don't trust; the pub.
  the plank  = the DISCARD verb — process-death-is-the-kill extended to a
               whole cell/guest.
  micro-brig = the lean foreign-code guest (stock kernel + minimal initramfs +
               one trusted binary, tens of MB).

## The guest network is just a cell (LOCKED 2026-10-05)

The krouter's "guest network" is NOT a second network construct. It is a pen —
the SAME wall we already build — seated by the usher, carrying the roster's
`guest` role (crypto.md) with QoS owner-over-guest (the class + priority
ladder). Crypto is identical across ALL machines (dom0; the kidulKey is the
only key), so a guest cell sees nothing the owner's cell sees no further into.
"Permissions done right" — nothing new is added, we tweak the walls we have.
Same principle holds for the kweb: a mobile device joining the mesh is another
cell, not a new authority.
