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

  host  = ORANGE (muted)      "keep out unless you really need to" — the only place
                              you hesitate; don't bring strays home.
  pen   = LIME GREEN          light wall, shared kernel (kid-safe).
  brig  = ELECTRIC BLUE       heavy wall, own kernel.
  plank = ELECTRIC PURPLE     heaviest wall — do anything, can't hurt the system.

Muted home -> electric cells. The home is the only thing you protect, so it alone
stays muted (the warning colour); the cells go electric — the deeper the wall, the
louder the colour, because a contained app can do anything and that freedom should
feel vivid. Reverses theme.md's pen/brig/plank mapping (below).

## Lazy-open — a door, not a running app

The bar is a row of doors. An app's code does not execute until the user moves DOWN
into its button — a plank does not spin up a whole GNOME until you walk in. A door
not entered has no process. Same discipline as process-death-is-the-kill.

## UserHome (the pill bar) is the apps list

The global pill bar IS the apps list — one per seat, always the very top. Public
user: AI / Browser / Games / Library / People. The owner: every installed app is its
own pill. People = the admin surface (users, grants, roster), not a profile picker.

Three homes, one deck (the up+1 / up+2 / "top" vocabulary retires — kidul-flow.md):
  KidulHome = the system home ("our home"), the boot root. "Kidul TV" CFC'd + the
              four widget faces + navDots, drawn on the Top layer. The compositor
              lands here at boot, NOT on UserHome (kidul-flow.md).
  UserHome  = the user's home — the apps list (the pill bar), its OWN SLIDE in the
              deck, NOT a global overlay. SUMMONED (not autostarted) via ↓ from
              KidulHome or the TL button. "Up" from any app returns to it; "up"
              from UserHome returns to KidulHome (kidul-flow.md).
  AppHome   = each app's own CFC'd top bar (the app's landing); the first move DOWN
              from UserHome opens the app AT its AppHome (spawned lazily — no
              process until the down-move). Every app navigates DOWN from there.
  the peek  = RETIRED from general code, reserved for kgames. The title below
              UserHome is just "the title" — the focused app's generic name.

The TITLE is one generic name, the same text below UserHome AND above the AppHome.
"What does Granny want": Browser, Public Library, Media Player — plain, large,
outline-only, no branding, no k'ified code name. The code keeps its k'ified
identifiers; Granny sees only the generic word. No reinvented second title.

UserHome owns the TOP of the deck: every app's landing renders the SAME bar (the
"still picture" — identical geometry, only the focused button + the title below
differ), so the deck's slide animation is what moves the focused button. The bar
never actually moves. ONE app = ONE column; up = the column's landing (UserHome).
TREES EXPAND DOWNWARD so "up = one level shallower" is universal — the file tree
is the one surface that must OBEY this rule, not break it (project root = the
top row, subfolders open BELOW). Up from an app = UserHome; up from UserHome =
KidulHome (kidul-flow.md).

## Reversals

  profiles (this file)  the 2026-11-10 "profile is the cell" model and the
                        2026-11-14 "Private/Play/Kustom" Granny surface are REVERSED.
                        No profiles; environment is per-app.
  "native is safer than any VM"  reframed, not reversed: native has the LOWEST
                        attack surface (our code only) but NO wall — so the glow
                        shows native MUTED (the "keep out unless you need to"
                        warning), while the cells go electric. "Colder than Qubes"
                        still holds for the DATA; the glow is a different axis.
  theme.md              the pen/brig/plank colour ramp is REVERSED to host/pen/brig/
                        plank = orange(muted)/lime/electric-blue/electric-purple;
                        the sash/browser-zone becomes the glow.
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
