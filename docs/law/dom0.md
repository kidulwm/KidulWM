# LAW — DOM0 (we are dom0, and its one law) (LOCKED 2026-10-03, Barticus present)

KSD is Qubes that isn't ugly. The defence-by-architecture is Qubes-class; the
face (kidulwm) is the legible, friendly surface Qubes never built. On the vault
we are colder than Qubes (below). This law names what we already ARE and locks
the one dom0 rule we had been violating.

## We ARE dom0 — recognise it, don't build it

Qubes splits the world into a privileged dom0 and isolated domUs, because Xen
virtualises even dom0. We run trusted code on the bare kernel and only cage the
untrusted edge, so our dom0 is not a VM — it is the bare kernel plus the tiers
that sit on it:

  kernel                     the floor (hypervisor-equivalent; theatre.md)
  kushd (PID-1)              management — the usher, seats every act
  kidulwm                    the GUI — the face, paints the pixels
  kidulKey + kvaultd         the trust root — cold, keyed by the chip

Same four jobs as Qubes dom0 — hardware, GUI, management, trust — different
shape: type-0, no hypervisor tax on code we authored. That is the less-running
law (§2.2) applied to the whole box. We have been building Qubes all along;
this law makes it explicit so the next session reads the same words.

## The one dom0 law: network does not live in the trust core

Qubes isolates dom0 from the network (sys-net is a separate domain). We have
been running that backwards: knetd is a bare-kernel FOUNDATION daemon that
boots before kushd, sharing the trust core with kvaultd and kidulKey's
material. Network is our largest parsed-input attack surface, seated inside
dom0. A knetd compromise today is a dom0 compromise.

Correction: knetd is the caged sys-net, NOT a bare-kernel peer of the secrets.
It keeps its two hard-won properties —
  - it boots BEFORE kushd (the recovery path: network survives the usher), and
  - it owns the network pens (mints them for the beer garden, never kushd),
— but it does so from INSIDE its own cage (a bubble), not from the trust core.
A knetd compromise is a bubble compromise, never a dom0 compromise.

## The trust core (what stays bare-kernel, network-free)

  kushd     the usher — management. No network.
  kvaultd   the secrets — cold, keyed by kidulKey (cold-storage.md).
  kidulKey  the silicon root of trust (crypto.md).
  kidulwm   the face — the eye above the stage (theatre.md KEYE).

Nothing else. The trust core is the smallest thing that must be trusted to
touch the hardware; everything else — network, the face's clients, the
tentacles, the beer garden, the bubbles — lives outside it, cued or caged.

## Colder than Qubes

Qubes' vault is a resident KeePassX process inside a networkless VM — the
secrets sit in RAM for the whole session. Our vault (cold-storage.md) refuses
the resident process entirely: encrypted filesystem, cued-on-demand,
decrypt-on-read, zeroize on close, plaintext lifetime of seconds. No seat, no
process, nothing resident in RAM when closed. Colder.

## The two arms of the seat grade (naming, LOCKED)

The seat grade has two arms of isolation (theatre.md beer garden):

  pen     (kpen)     namespaces, fork/exec, cheap, shared kernel — the
                     everyday untrusted seat (browser, email, apps).
  bubble  (was VM'k) KVM, a whole guest, own kernel, heavy — foreign code,
                     untrusted downloads (docket #13), a guest OS you don't
                     trust.

The bubble is the heavier wall and the friendlier name: sealed, self-contained,
transparent (see the untrusted thing without touching it), and disposable —
"pop the bubble" IS the teardown (process-death is the kill). knetd's sys-net
home is a bubble. Qubes' domU / AppVM; our bubble.

## Status

Principle LOCKED now. The MECHANISM (how knetd rides inside a bubble before
kushd — VFIO passthrough vs a lean pre-kushd launcher vs cgroup) is a docket,
not yet built. Until it lands, knetd runs bare-kernel but is DESIGNED as if it
were caged: no access to the trust path, its own netns, its own typed contract.
