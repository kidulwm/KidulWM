# LAW — the profile is the cell (wall = containment, not armor) (LOCKED 2026-11-10, Barticus present)

A cell is surfaced to the user as a "profile." The one ruling that makes the
whole model read correctly is the DIRECTION of the wall — what the cell
defends — and it inverts the obvious reading.

## The wall is containment, not armor

The cell wall does not protect the contents of the cell from the outside. It
protects the trust core FROM the contents of the cell.

  trust core (our code)   no wall at all — the base + native tentacles, signed
                          and verified, nothing foreign. Open by construction.
                          This is where the valuables live.

  pen                     light wall — foreign DISTRO (Debian/Arch userspace),
                          mostly trusted, kid-safe (cells.md class law).

  brig                    heavy wall — foreign CODE, own kernel. The serious
                          tool; a kernel-bug survives its own kernel.

  plank                   heavy wall — own kernel + own compositor: a full
                          separate desktop (its own distro, window manager,
                          everything). The wild.

The more dangerous the guest, the thicker the wall — not to protect the guest,
to protect us from the guest. The high-value stuff needs no wall (it is ours);
the low-trust stuff needs the strongest wall (to keep it away from the value).

## Native is safer than any VM — colder than Qubes, at home

"our home is safer/colder on the native base, not in a VM at all" — the least
attack vector possible, because we own every line. This extends dom0.md's
"colder than Qubes" from the vault to the home: the vault is colder than Qubes
because it is off; the home is safer than any VM because there is no foreign
code to contain. Granny's valuables live here, not in a cage.

  Granny name: "Private". Technical name: "native" (the trust core; no cell).

## The profile is the cell

A person has an account; the account holds profiles; each profile IS a cell (or
the native core). The profile is the user-facing unit of confinement.

  identity -> account -> profiles -> cell — cells.md's "identity -> role -> cell"
  generalized: one person, many cells, each a profile with its own folder set,
  app set, and wall type.

  Granny sees "profiles with feature lists," never the words cell / pen / brig /
  VM. grannyize.md applied to the security model: the depth is hidden, never
  removed. Qubes colours windows; KSD lists profiles.

  Granny surface (LOCKED 2026-11-14): Private / Play / Progress.
    Private  = native (valuables, banking, our code, no foreign).
    Play     = the socials + fun, a brig by default (spoofed persona, cells.md),
               the plank later when the remote-desktop VMs are "flying".
               Granny sees "her browser", never the cell.
    Progress = study & work, the family's everyday (pen). Granny's "progress
               days are over" — she never lands here; it is for the rest of
               the family.

## The escalation (classify at seat, overboard on threat)

Dodgy code is never "moved" pen -> brig live. Two moves, already in cells.md:

  1. CLASSIFY AT SEAT TIME — foreign DISTRO seats in a pen; foreign CODE seats
     in a brig, never a pen. The hostile thing was never in the pen.
  2. DISCARD ON THREAT — if something in a pen turns hostile after all, it is
     cast overboard and, if it still deserves to run, re-seats in a brig.

Casting overboard is the enforcement of the escalation.

## Lifecycle — cued, not resident

Profiles are per-session and static OFF. The default profile starts at login;
the rest start on click. A per-profile "start-at-boot" toggle (set at creation,
changeable later) is the user's one knob. kushd's ABSENT / STANDBY / ACTIVE;
network stays alive regardless of focus (cells.md, focus-decoupled). Three
profiles does not mean three resident VMs.

## The settings app owns profiles

A full settings tentacle owns user-add and profile create / edit / delete. The
"change user" button and profile management both land there — user-facing
surface = tentacle, never a body organ. kidulKey verifies the lifecycle: the
PERSONAL key authorizes create/delete; the OWNER key gates footprint (space,
drives), per kidulkey.md's FRIENDLY tier — presence free, footprint owned.

## Colours — deferred

Colour is now security, not candy, but the mapping is a feel-it-in-the-hand
call, not a paper ruling. Left open. This parks theme.md's cell/brig/plank
colour mapping and the browser-plank "play/safe" reading until the surface is
live and the direction reads right.

## Reversals

  theme.md    the browser cell/brig/plank ZONES are subsumed by profiles — the
              browser's zone is whatever profile it runs in. Browser plank
              settings removed later (no hurry); the plank colour mapping is
              parked, not re-ruled.
  cells.md    REVERSED 2026-11-14: this file's 2026-11-10 note claimed "plank =
              discard verb is expanded, not reversed". That itself is reversed —
              plank is cell type 3 (own kernel + own compositor); the discard
              verb is "overboard". See cells.md Reversals.

## Relationship to existing law

  cells.md        extended: identity -> role -> cell becomes identity -> account
                  -> profiles -> cell; plank = cell type 3, overboard = discard.
  dom0.md         "colder than Qubes" extended to the native home (safer than
                  any VM, own code, no foreign).
  kidulkey.md     PERSONAL authorizes profile lifecycle; OWNER gates footprint.
  grannyize.md    the profile picker is the Grannyized face of the cell model.
  distribution.md the profile is where the cell-keyed package story lands:
                  profile -> cell type -> package manager.
  kushd (usher)   profiles are cued cells; the usher seats them.
