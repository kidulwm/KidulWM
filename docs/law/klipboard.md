# LAW — the klipboard (klipd): one permissioned clipboard organ, app-scoped, default-deny

PROPOSED 2026-10-30, Barticus present. Name klipd is Barticus's lock; the
authority split and the default-deny model are bobdotrix's ruling, presented
for Barticus to lock.

Lane: the clipboard — a SHARE HOUSE organ (system-owned, kushd-cued), NOT a
user front-end. It is the connective tissue every app reaches for, so it is
infrastructure like kplayd/kbrain, not a surface like kmedia/kfiles.
Related: terminal (ktty owns the selection + the middle-click gem), crypto
(identity, the trust ledger, kidulKey), identity (four scopes — the app_id
does NOT live here, it is a compositor fact), input-trust (the seat that
drives the paste), cold-storage (the at-rest key problem), theatre (seating).

## Problem

Wayland has no central clipboard. The standard clipboard is a negotiation
between the source app and the destination app, brokered by the compositor,
and every client gets EQUAL access. There is no place to ask "who is this
and what may it read." On X11 you got the PRIMARY selection (the middle-click
gem) for free; on Wayland it is an optional protocol that ghostty's GTK apprt
explicitly refuses (`primary => false`), so our terminal does not even have
the highlight->middle-click flow to secure.

Two things are therefore missing, and they are the same thing:

- no AUTHORITY — nothing owns the clipboard, so nothing can gate it;
- no PRIMARY — the terminal has no middle-click paste at all, secured or not.

Qubes has the trust model we want (explicit, default-deny, directional
copy-between-domains) but ships it as a clunky dom0 qrexec policy with ugly
confirmations. We want that trust model with a beautiful surface.

## Concept — klipd is the single authority

klipd owns EVERY clipboard slot and becomes the one chokepoint every copy and
paste crosses. Two mechanisms make that possible:

  wlr-data-control-v1   a daemon observes AND owns the selection without
                        holding a surface (how wl-clipboard / cliphist work)
  klip.sock             our apps bypass raw wl_data_device and talk to klipd
                        over a private unix socket (kplay.sock precedent)

The socket is where identity is resolved and policy is enforced. Every grant,
every direction, every revocation lives in klipd — nowhere else.

Three slots, mapped to ghostty's existing `apprt.Clipboard` (already stubbed
in ktty's apprt/kidul/Surface.zig):

  .standard   Ctrl+Shift+C / Ctrl+Shift+V   the explicit clipboard
  .primary    highlight -> middle-click     the gem (we build it; ghostty
                                            never had it). ENUM NOTE: the
                                            core calls this `.selection` and
                                            both `copy-on-select` and
                                            `middle-click-action` target it;
                                            the apprt maps `.selection` ->
                                            klipd's "primary" slot.
  .selection  ghostty's enum for the gem    served (NOT dead — see Q.G)

klipd owns .standard AND .primary under ONE policy engine. No slot bypasses
it, or that slot is an unpermissioned hole.

## The law (properties)

1. ONE CLIPBOARD ORGAN. klipd is the single clipboard authority on the face.
   Every slot (.standard, .primary) is owned by klipd via wlr-data-control.
   Our apps do NOT use raw wl_data_device for copy/paste — they speak klip.sock.
   No bypass = no unpermissioned hole.
2. APP-SCOPED, DOMAIN-TAGGED. Identity is a TUPLE: (app_id, owner-class).
   app_id says WHAT the app is (com.kidulworks.ktty); owner-class says WHERE it
   runs and how far we trust it (host-owned / cell-owned / brig-owned — the
   theatre.md owner classes). A brig-owned ktty is a DIFFERENT principal from
   a host-owned ktty, with its own (empty) grant set. Trusting app_id alone is
   crypto.md's "the box can lie" transplanted to the clipboard. The owner-class
   is resolved from kernel/hypervisor truth, never from anything the app claims.
3. DEFAULT-DENY, DIRECTIONAL, LIVE-REVOCABLE. Connections (app->app, app->
   group) are OFF by default. Each grant is DIRECTIONAL (read = paste-from,
   write = copy-in), granted separately. Any grant toggles off LIVE — a
   misbehaving process is cut in one IPC, no relog, no restart.
4. KEY-GATED APPROVAL, LOW STAKES. A grant is a POLICY RECORD confirmed by a
   kidulKey tap ("yes, I meant this"), NOT a signing commitment. The blast
   radius is small and reversible, so this is the right place to START using
   kidulKey approval — contra crypto.md's "what does the key approve", that
   trap binds a signing ROOT; a revocable clipboard grant does not have the
   same stakes. The user may still over-grant if they insist ("don't stop the
   user being stupid") — best-security by default, stupidity allowed on purpose.
5. BEAUTIFUL SURFACE, SETTINGS-HOME. Grants are managed in the settings slide
   (CFC'd), never a per-copy popup. Qubes' trust model, our controls. Security
   by architecture (the chokepoint), not by nagging on the hot path.
6. SENSITIVE + TTL + PURGE. Entries carry flags: never-leave-host,
   never-cross-VM, clear-after-Ns. A "purge now" kill clears everything.
   At-rest encryption is the eventual store; the store key is crypto.md's
   unsolved WYSIWYS problem — build in-RAM first, do NOT block on it.
7. VM BOUNDARY = LEAST-TRUST, BY CONSTRUCTION. The brig (KVM) runs its OWN
   kernel and filesystem — a process inside it cannot reach the host's
   /run/klip.sock. There is no side channel. The only path between a VM and
   the host clipboard is a BRIDGE we build (virtio-serial/vsock/knetd), and
   that bridge is default-off, per-direction, key-tap-gated. "Copy between
   VMs only on request & approval" IS the design: opening the bridge is the
   request, the kidulKey tap is the approval. The pen (container) shares the
   host kernel (crypto.md), so a cell process CAN reach the socket — its
   domain tag comes from the kernel's own containment facts (/proc/<pid>/cgroup
   + namespaces), which a process cannot forge. Built LAST.
8. REUSE LINUX, DON'T REHASH. Identity = SO_PEERCRED -> /proc/<pid>/exe ->
   app_id (kernel primitives we already have). Isolation = the cgroup /
   namespace / VM work already done. klipd adds ONLY the layer Linux
   deliberately omits: application-level access policy. That is the whole
   build — not a re-implementation of the kernel's job.

## Rulings (this lock)

- Q.A  NAME = klipd. Fits kplayd/knetd/kushd (organ suffix). Rejected
       Klippy/Klipr — they read as user-facing apps; the daemon is an organ,
       and the naming law says names follow behavior.
- Q.B  OWNERSHIP = SHARE HOUSE organ (system-owned, kushd-cued), never a user
       front-end. Same class as kplayd/kbrain.
- Q.C  AUTHORITY SPLIT: muster = IDENTITY + groups (who this app_id is,
       certified by the cold key); klipd = POLICY + enforcement + revocation
       (hot, in-memory); kushd = seating/lifecycle cues; vault = cold, signs
       the muster, NEVER in the hot clipboard path. The cold key stays cold.
       (The "muster" here = the roster/kpax = the kID's list — kid.md: one
       key, one roster, deny-by-default.)
- Q.D  IDENTITY TODAY: the muster is not built (crypto.md). klipd therefore
       ships with a LOCAL app_id registry (SO_PEERCRED -> app_id, seeded with
       the house apps) and binds to the real muster when it lands. Do NOT
       block klipd on the muster.
- Q.E  ktty INSTANCES SHARE one clipboard (one app_id). No per-window /
       per-session subgroups at launch — YAGNI. PRIMARY is inherently
       system-wide (it is "the last highlight"), never per-app.
- Q.F  COPY KEY = Ctrl+Shift+C, PASTE = Ctrl+Shift+V. Bare Ctrl+C is SIGINT —
       the terminal's load-bearing interrupt — and is never rebound; bare
       Ctrl+V is quoted-insert (type-a-literal-control), which the shell
       needs, so it stays with the shell too. Both keys SHIFTED, symmetric.
       Middle-click is reserved for the PRIMARY gem (paste-at-cursor).
- Q.G  SLOTS map to apprt.Clipboard: .standard (Ctrl+Shift+C/V), .primary
       (middle-click). ENUM LOCK (2026-10-31): ghostty's core calls the
       middle-click slot `.selection` — `copy-on-select` and
       `middle-click-action` both target `.selection` — and reserves `.primary`
       for OSC 52 only. The kidul apprt therefore maps `.selection` -> klipd's
       "primary" slot and leaves `.primary` unused. klipd owns .standard AND
       .primary under one policy engine.
- Q.H  DOMAIN TAG IS KERNEL-TRUTH. klipd never trusts app_id alone. The
       owner-class half of identity is resolved from facts the app cannot
       forge: a brig process can only reach klipd through the bridge (the
       transport proves brig), a pen process is tagged by /proc/<pid>/cgroup +
       namespaces, a host process is everything else. app_id + owner-class
       together = the principal.
- Q.I  RETENTION = RAM-ONLY, REPLACE-ON-KLIP, GONE ON LOGOUT (Barticus,
       2026-10-31). The klipboard is transient working memory, NOT a store: no
       vault, no disk, no clipboard-HISTORY manager by default. Each copy
       replaces the slot (single-item semantics — how a real clipboard works);
       PRIMARY is "the last highlight", even more ephemeral. klipd is a
       kushd-cued user-session daemon, so session end = process death = data
       gone. (Freed, not actively scrubbed — an explicit zero-on-clear +
       no-swap hardening step is a later option, not needed for the app-policy
       model.) A clipboard HISTORY is a separate, opt-in, vault-gated feature
       if we ever build one — never the default.

## Reversals

- Reverses "the clipboard is an OS utility, not our concern" — it becomes an
  owned organ with policy.
- Reverses the Wayland default "every client gets equal clipboard access" —
  access is granted, never assumed.
- Reverses Qubes' assumption that the permission unit is the VM — ours is the
  app_id + owner-class tuple (finer grain, same trust model, better-looking
  controls).

## Open (build-time, not blocking)

- The at-rest store key (crypto.md #2 / kidulKey WYSIWYS). In-RAM store first;
  the key model lands with the crypto tentacle, not the clipboard.
- The muster binding (Q.D) — local app_id map first, real registry later.
- The VM bridge transport (virtio-serial/vsock vs a knetd brig channel).
- Whether a third ".selection-style" pasteboard is ever needed (the gem already
  rides the .selection enum — see Q.G).
- Selection highlight render pass in the cairo backend. DONE 2026-10-31 (Phase
  1, ktty commit f04be2f): mouse-drag selection + reverse-video highlight are
  wired; the highlight needed NO cairo pass — the generic renderer already
  bakes selection colours into the cells the cairo backend blits. Clipboard
  itself (klipd v0.2 — both slots + ktty wiring) shipped 2026-10-31.

## Protocol (klip.sock wire format — v0.2 build spec, bobdotrix 2026-10-31)

Mirrors kplayd (the house socket-daemon precedent): SOCK_SEQPACKET, unlink at
START only (never at exit — ksound's 14:50 race), one line per command record.
The data PAYLOAD rides a SEPARATE SEQPACKET message so arbitrary/multiline text
never collides with line framing.

  socket      $XDG_RUNTIME_DIR/klip.sock (fallback /run/user/<uid>/klip.sock).
              User-session daemon, kushd-cued — the SAME class as kplayd (Q.B),
              NOT a root system organ, because it must reach the user's Wayland
              compositor for wlr-data-control.

  identity    The client NEVER claims an app_id. klipd resolves it from kernel
              truth: SO_PEERCRED (pid/uid/gid) -> /proc/<pid>/exe -> a local
              app_id registry (seeded with the house apps). The wire carries
              no identity token — the peer creds ARE the token (property 8,
              Q.H: never a wire claim). Owner-class is host-only in v0.1;
              brig/pen tagging rides the later VM/pen paths ("built LAST").

  commands    each = one SEQPACKET message, ASCII line, '\n'-terminated;
              <slot> = "standard" | "primary":
    set <slot> <len>\n   copy-in. klipd replies "ok\n", then reads the NEXT
                         message (exactly <len> bytes) as that slot's payload.
    get <slot>\n         paste-out. Reply "ok <owner_app_id> <len>\n" + a
                         payload message, OR "deny\n" (policy blocks), OR
                         "empty\n" (none).
    ping\n               -> "pong klipd 0.2\n"

  policy v0.2  two in-RAM slots: .standard (text) + .primary (text). set
               replaces the slot and records owner = resolved app_id; the
               slots are INDEPENDENT (each holds its own data + owner). get
               is allowed iff the resolver yields the SAME app_id that wrote
               that slot (same-app read-back: ktty->ktty across windows, per
               Q.E). Cross-app is default-deny ("deny") until the grant
               engine (settings slide + kidulKey tap) lands.

  build order  v0.1 socket + store + identity + policy (house-internal
               clipboard, DONE 2026-10-31) -> v0.2 PRIMARY slot / middle-click
               gem (DONE 2026-10-31: drag-select auto-copies via copy-on-select
               = primary, middle-click pastes via middle-click-action =
               primary-paste — both ride the .selection enum, mapped to the
               "primary" slot) -> v0.3 wlr-data-control ownership (foreign
               Wayland-app interop, the "single authority" role) -> last: VM
               bridge, at-rest key, muster binding.

  protocol (LOCKED 2026-10-31, bobdotrix): ext-data-control-v1, NOT the
               deprecated zwlr_data_control_manager_v1. wlroots 0.20 ships BOTH
               headers, but zwlr is marked legacy-and-to-be-dropped; the modern
               seam is ext_data_control_manager_v1 (unstable). The compositor
               (KidulWM) now advertises `ext_data_control_manager_v1 v1` +
               `zwp_primary_selection_device_manager_v1 v1` (server.zig), and
               deliberately does NOT create zwlr_data_control_manager_v1. klipd
               is the ext-data-control CLIENT that owns the selection.

  repo         /home/dad/dev/klipd, Zig 0.17.0 (house toolchain), build.zig +
               src/main.zig mirroring kplayd_main.zig (SEQPACKET + poll loop).
               IN-HOUSE (no remote), signed B&B.
