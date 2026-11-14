# LAW — delegation (the grant tree: owner = admin, sub-users, attenuation)

LOCKED 2026-11-14, Barticus present (GSI). This is build-order slice (1) of
docket #59 USER PARTITIONS & ISOLATIONS.

## One sentence

Every permission has a CREATOR. A creator grants a receiver only what the
creator already holds — never more. The owner's key is the root of the tree;
every other user is an attenuating branch off it.

## The owner is the admin

OWNER = the admin. On a home TV, Granny; in a business, the CEO. The owner's
key is the ROOT of the delegation tree — every allocation (user, partition,
permission) descends from it. One root, one creator-of-record for every grant;
no authority above the owner key, none beside it.

## The delegation tree

The roster ROOT (crypto.md, roster-format.md) is the top creator. Below it,
sub-users form a tree, each node a grant made by its parent:

  owner (root creator)
    +-- sub-user (R&D, Sales)   administers its OWN workers + permissions,
    |                            without seeing a sibling department
    +-- worker                  the leaf; holds only what its chain granted

The tree is not a flat role list — it is a chain of attenuating grants, and
the chain is the authority.

## Attenuation — grant <= own, never more

The one rule that makes the tree safe (the monotonic-decrease law — "you can
only give yourself less"):

  a grant can hand down only a SUBSET of the granter's own permission set.
  It can never AMPLIFY. Johnny in Sales never sees B&B's R&D budget — the
  grant chain attenuates, never escalates.

Scope shrinks or stays equal as you descend; it never grows.

## Log read is an attenuating permission

Reading the audit log is not free. The log READ is itself a grant on the same
tree: a sub-user reads only their own scope (what they created + what their
children did), never a sibling's or an ancestor's. The owner reads the whole
tree. Attenuation, applied to evidence (logs.md).

## KLIP transfer — the concrete instance

A klip (a move between cells/profiles) is the everyday act the tree governs.
Two moves, one rule each:

  AMBIENT      same class, same sub-profile (pen<->pen, brig<->brig) — free,
               no grant, no keypress. Cheap append to the audit log.
  ESCALATION   cross-class OR cross-profile (Private / Play) OR across a Kustom
               variation — a dongle keypress PER-KLIP, resolved to a roster
               identity, never a broad ruling. The key proves WHO; WHO is a
               node on the tree.

Every klip — ambient and escalation alike — appends to the audit log, so the
record is complete, not just the loud events.

## People vs My People (two surfaces, two names)

  "People"    the admin door — add/delete users, cast their partitions. The
              owner's admin surface (docket #59 step 3).
  "My People" the phone book — the owner's contacts, one .md per person, read
              by a tentacle. DATA, not administration.

Never let one word mean both.

## Relationship to existing law

  kid.md            one key, one roster, deny-by-default — this names the TREE
                    that roster key stands at the root of.
  crypto.md         household roster (identity -> role) — the roster's keys are
                    the tree's nodes.
  roster-format.md  the kpax file — tree membership on disk + the prev-hash
                    chain the audit log reuses.
  profiles.md       the profile is the cell — the tree grants which profile
                    (folder set) a user may reach.
  public-seat.md    owner (uid 1002) = admin; the seat boots public, re-seats
                    on the owner's proof.
  cells.md          per-folder bind-mount ("this folder does not exist") — the
                    enforcement of a grant at the data layer.
  partitions.md     per-user key-gated partition — the grant cast onto the disk.
  cold-storage.md   the vault is the SECRET store; the tree decides WHO may
                    unlock it, never the vault itself.

## Build status (honest)

Architecture frozen here. MECHANISM not built — the People app (docket #59 step
3) is where add/delete-user + partition verbs land, and the grant chain is
enforced there + in kushd's re-seat. This is the law the build must obey, not a
claim it is built.
