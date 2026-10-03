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

Correction: knetd is the CAGED sys-net, NOT a bare-kernel peer of the secrets.
It keeps its two hard-won properties —
  - it boots BEFORE kushd (the recovery path: network survives the usher), and
  - it owns the network pens (mints them for the beer garden, never kushd),
— but it does so from INSIDE its own cage (the brig), not from the trust core.
A knetd compromise is a brig compromise, never a dom0 compromise.

The brig is where the usher holds the cut. "Make a mistake and I will cut you":
knetd lives on the usher's leash — the one seat the usher can sever at any
instant without warning, because the network is the thing that must never be
allowed to misbehave unattended. Contained AND leashed.

## The trust core (what stays bare-kernel, network-free)

The trust core is the CAPTAIN'S SAFE (starship.md) — and it is NOT below decks.
It sits in the COCKPIT, at the captain's side, with security around it 24/7.
ONLY the captain has the keys; no other soul has access. The skipper has to
DIE before he hands over the keys. Neither crew, nor sea, nor sky may reach in.

  kushd     the usher — management. No network.
  kvaultd   the secrets — cold, keyed by kidulKey (cold-storage.md).
  kidulKey  the silicon root of trust (crypto.md).
  kidulwm   the face — the eye above the stage (theatre.md KEYE).

Nothing else. The safe is the smallest thing that must be trusted to
touch the hardware; everything else — network, the face's clients, the
tentacles, the beer garden, the brig — lives outside it, cued or caged.

## Colder than Qubes (the VAULT, not the cage)

Qubes' vault is a resident KeePassX process inside a networkless VM — the
secrets sit in RAM for the whole session. Our vault (cold-storage.md) refuses
the resident process entirely: encrypted filesystem, cued-on-demand,
decrypt-on-read, zeroize on close, plaintext lifetime of seconds. No seat, no
process, nothing resident in RAM when closed. Colder.

DO NOT blur the two arms (2026-10-03 correction, Barticus): the vault is NOT
put inside the cage. The vault is ALREADY the coldest storage — cued, not
resident. The thing that goes in the brig is the NETWORK, not the secrets. The
vault = data at rest, colder than Qubes; the brig = the network authority,
leashed and cut-able. One word each, never shared.

## The silicon floor — colder than Qubes, but not colder than the chip

"Colder than Qubes" is a SOFTWARE claim, and it holds: the vault is cued not
resident, the network is caged not trusted, the face is cued. But one layer
is below all of it and is not ours: CPU microcode, the Intel ME / AMD PSP, and
the UEFI firmware itself — loaded at reset before our code runs, resident in
the silicon for the whole session, with DMA to memory. No software we write
evicts them; only owning the chip (RISC-V + FPGA, kboot.md) does.

This is why the skipper's law (starship.md) is doctrine, not defeatism:
"NOTHING IS EVER 100% safe." We are colder than Qubes in every layer we can
touch; the silicon is the one layer we cannot, and the north star is to own
it too. Zeroizing kboot de-foreigns every software stage above the silicon;
the silicon is the last manufacturer fault line, and it is a hardware docket,
not a software one.

## The two arms of the seat grade (naming, LOCKED)

The seat grade has two arms of isolation (theatre.md beer garden):

  pen   (kpen)   namespaces, fork/exec, cheap, shared kernel — the everyday
                 untrusted seat (browser, email, apps).
  brig  (was VM'k, briefly "bubble")   KVM, a whole guest, own kernel, heavy —
                 foreign code, untrusted downloads (docket #13), a guest OS
                 you don't trust — AND knetd, the network authority.

The brig is the heavier wall and the stauncher name: the ship's jail below
decks, where the untrusted thing is confined AND the usher holds the cut.
StarShipKidul (§7.2) already sails — the Captain, the crew, the PAX, the wheel;
the brig is where the untrusted thing is locked and can be severed at any
instant if it misbehaves. Qubes' domU / AppVM; our brig.

## Status

Principle LOCKED now. The MECHANISM (how knetd rides inside the brig before
kushd — VFIO passthrough vs a lean pre-kushd launcher vs cgroup) is a docket,
not yet built. Until it lands, knetd runs bare-kernel but is DESIGNED as if it
were brig'd: no access to the trust path, its own netns, its own typed contract.
