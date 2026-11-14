# LAW — the Environment (per-app, not profiles) (RE-CUT 2026-11-14, Barticus present, GSI)

RE-CUT 2026-11-14: this file was "the profile is the cell" (LOCKED 2026-11-10) and
briefly "Private / Play / Kustom" (2026-11-14). Both are REVERSED. There are no
profiles to switch in and out of. ENVIRONMENT is a per-app property — where this
app runs — chosen at install, shown by a glow on the focused pill. Reversals at
the bottom.

## The wall is containment, not armour (kept)

The cell wall does not protect the contents of the cell from the outside. It
protects the trust core FROM the contents of the cell. This ruling survives
unchanged and is now the whole meaning of the glow.

  host (native)   no wall at all — our code, signed and verified, nothing foreign.
                  Open by construction. The valuables live here (banking, keys, our
                  files). Lowest ATTACK SURFACE — but NO WALL, so if a host app is
                  ever compromised it reaches everything. Full trust, zero
                  containment.

  pen             light wall — foreign DISTRO (Debian/Arch userspace), mostly
                  trusted, kid-safe (cells.md class law). Shared kernel.

  brig            heavy wall — foreign CODE, own kernel. The serious tool; a
                  kernel-bug survives its own kernel.

  plank           heaviest wall — own kernel + own compositor: a full separate
                  desktop. The wild. Nothing it does reaches the system.

The more dangerous the guest, the thicker the wall — not to protect the guest, to
protect us from the guest. Two axes, never conflated: ATTACK SURFACE (how much
foreign code is invited — the host is lowest) vs CONTAINMENT (how thick the wall —
the host is thinnest). The glow shows CONTAINMENT, the wall thickness, not the
attack surface.

## No profiles — environment is per-app (the reversal)

A person has an account; the account holds APPS; each app has an ENVIRONMENT
(host/pen/brig/plank), chosen at install. There is no "get into / out of a profile"
barrier. Granny's banking app sits next to her Zoom app on the one bar — one on the
host, one on a plank — and she never switches anything. She sees "another app on my
top bar", never a cell, never a VM, never a profile.

  identity -> account -> apps -> environment. cells.md's "identity -> role -> cell"
  is cut back: the cell is no longer a user-facing unit you switch into; it is a
  property of each app, chosen once at install (safety-by-default) and shown by the
  focused pill's glow.

## Install-time, safety-by-default

The environment is chosen at INSTALL (the mini app store), not at run-time by the
user. The installer suggests the SAFEST seat for whatever the app is, and the user
may come back from safety — but we encourage staying. The owner overrides per-app;
the geeks get "advanced settings" for granular control. Granny, if she ever
installs, sees "select defaults" and nothing else.

## The glow (containment, not armour)

The focused pill carries a soft transparent glow around its outer edge, in the app's
environment colour, a touch more opaque than Bob's ball glow but translucent, X px
out. It is the one visible record of where an app lives. Default = the safety colour;
the user may recolor any app/machine to their own scheme (colour = meaning,
user-changable — theme.md).

  host  = ORANGE   warning — no wall, "be careful here", a bad app can hurt the system
  pen   = amber    warm — light wall, shared kernel
  brig  = purple   cool — heavy wall, own kernel
  plank = BLUE     coolest — heaviest wall, safe to do anything

Warm = uncontained (danger) -> cool = contained (safe). Reverses theme.md's
pen/brig/plank mapping (below).

## Lazy-open — a door, not a running app

The bar is a row of doors. An app's code does not execute until the user moves DOWN
into its button — a plank does not spin up a whole GNOME until you walk in. A door
not entered has no process. Same discipline as process-death-is-the-kill.

## The bar (GPB) is the apps list

The global pill bar IS the apps list — one per seat, always the very top. Public
user: AI / Browser / Games / Library / People. The owner: every installed app is its
own pill. People = the admin surface (users, grants, roster), not a profile picker.

Three names, one deck (the up+1 / up+2 offset vocabulary retires):
  the bar    = the GPB, the system apps-list, always the very top.
  app top    = each app's own CFC'd topPillsBar (today's "up+1"); the first move
               DOWN CFC's it and the app opens.
  the peek   = the app's title shown under the focused GPB button before entering —
               no process behind it. The title is copied from the app's topTitle,
               so the peek tracks the focused button.

## Reversals

  profiles (this file)  the 2026-11-10 "profile is the cell" model and the
                        2026-11-14 "Private/Play/Kustom" Granny surface are REVERSED.
                        No profiles; environment is per-app.
  "native is safer than any VM"  reframed, not reversed: native has the LOWEST
                        attack surface (our code only) but NO wall — so the glow
                        (containment) shows native warm, not cool. "Colder than
                        Qubes" still holds for the DATA; the glow is a different axis.
  theme.md              the pen/brig/plank colour ramp is REVERSED to host/pen/brig/
                        plank = orange/amber/purple/blue; the sash/browser-zone
                        becomes the glow.
  cells.md              "auto-seat-safest" becomes "install-time, safety-by-default".

## Relationship to existing law

  cells.md         the three cell types stand; the cell is now a per-app
                   environment, not a user-switchable profile.
  theme.md         the glow colours live in the shared tokens; colour = meaning.
  delegation.md    klip escalation is cross-environment, not cross-profile.
  kushd (usher)    still seats apps; the seat is now chosen at install, not by a
                   profile switch.
  public-seat.md   "public user" = a dedicated account whose apps seat in the public
                   environment, not a "profile".
