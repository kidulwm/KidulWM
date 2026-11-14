# LAW — partitions (true separation: system / public / per-user)

Status: LOCKED 2026-11-11, Barticus present (GSI).
AMENDED 2026-11-14 (Barticus present, GSI): USER -> PUBLIC floor + PER-USER
partitions; co-owned second key; external/net drives = "just another
partition"; install % split. (docket #59 step 1.)

The disk is split into TWO partitions with a hard wall between them. The box
boots the PUBLIC face from one; the PERSONAL layer mounts from the other, only
on the key. This is the disk realization of machine-classes.md axis G and of
SYSTEM.md §7.3 (base vs user layer, key casts the layer).

## The two partitions

  SYSTEM   immutable but updatable. The sealed golden base (dm-verity,
           verified-boot.md) + the update slots (rollback = the previous
           signed image). Sized for the base + updates ONLY — it never grows
           to hold a user byte. No user data writes here, ever.

  USER     the key-gated personal layer. The owner's home: data, drives,
           downloads, preferences. Mounted ONLY when the key casts the layer
           (identity.md); detached by default, so the public face sees
           nothing.

## True separation (the wall is structural, not advisory)

  - The SYSTEM partition is read-only at runtime (dm-verity); it changes only
    through a signed update (A/B swap, verified-boot.md).
  - The USER partition is encrypted (key-wrapped) and DETACHED by default.
    Booting lands on the PUBLIC face; the user partition appears only for the
    key. No user byte touches the system partition, and the system partition
    holds nothing personal to leak when the box is a shared TV.

## Backups — whose are they?

  SYSTEM backups  = the previous signed golden image (the rollback slot). Part
                    of the update mechanism; tiny; ON the system partition.
  USER backups    = the user's DATA. They ride WITH the user partition (or a
                    cold vault, cold-storage.md), key-gated. NEVER on the
                    immutable system partition.

  The split is clean: the system holds its own rollback, the user holds their
  own data. No overlap, no shared partition, no "system files mixed with user
  files."

## The public floor, the personal layer

  - Public user (nopasswd) = the SYSTEM partition booted bare: the appliance
    face, nothing personal. This is the entry ladder's FLOOR (kidulkey.md).
  - Personal layer = the USER partition, mounted on key cast. The ladder's
    levels (kidulkey.md) describe how THIS mount is gated.

## Per-user partitions (the owner's key casts MANY layers)

"USER" above is not ONE layer — it is a FAMILY of layers, one per user. Every
user lives on their OWN key-gated partition, cast by their kidulKey:

  - created by the owner's key through the People app (delegation.md);
  - key-gated behind THAT user's kidulKey — mounted on proof, unmounted on
    lock (unplug / sign-out = gone);
  - the public seat never sees it (the bind-mount wall: a partition that is
    not mounted does not EXIST for the public uid — cells.md per-folder law,
    scaled to the disk).

Access granularity: per-folder is the common ask, per-key is our upgrade
(cells.md: identity -> role -> folder set). We ship per-folder ruling as the
option and hold per-key as the substrate.

## Co-owned drives (second key, internal separation)

A shared drive is NOT a special case. It is "just another partition" that
hides behind a key — and a co-owned drive simply has a SECOND key cast on it,
with INTERNAL separation between the two owners. Barry's key sees LESS than
Bob's on the same drive (delegation.md: a grant is always <= the creator's
own; a co-owner is a sub-grant, never a peer with full sight). The owner
decides the split at grant time.

## External & networked drives (just another partition)

An external or networked drive is NOT a new category. It is "just another
partition" that mounts behind the user's key exactly like an internal one —
key-gated, absent when locked. No special "removable" code path; the key is
the only door.

## Install sizing (the % split)

Take only what root + public safely need; the rest is user-key-cast. On the
1TB drive, the default:

  SYSTEM     32 GiB  — the sealed base + A/B update slots + recovery. Sized
                      for base + updates ONLY; never a user byte.
  PUBLIC    128 GiB  — the shared floor (public user home + shared media).
                      Resizable; external drives are "just another partition"
                      so on-box shared media can stay modest.
  FREE POOL  the rest (~771 GiB) — NOT pre-carved. The People app carves
                      per-user key-gated partitions from it on demand.

The law is the PRINCIPLE (minimal root+public, rest = user-key-cast); the
numbers are the install DEFAULT, adjustable at install time.

## Relationship to existing law

  machine-classes.md  axis G (golden / layered / workbench / caged) is this
                      layout per class; the entry ladder defers to kidulkey.md.
  verified-boot.md    dm-verity seals the SYSTEM partition; fs-verity/IMA
                      gates executables on the USER partition.
  identity.md / kidulkey.md  the key casts the layer; the USER partition
                      mounts on it.
  cold-storage.md     the vault stays cold, OFF this disk (or a separate cold
                      volume) — never on the user partition unguarded.
  SYSTEM.md §7.3      base vs user layer, key casts the layer; this law is the
                      disk layout that realizes it.
  distribution.md     the base (SYSTEM partition) is the sealed image; native
                      apps live on the USER partition (per-user footprint).
  delegation.md       WHO casts which partition — the owner is the root creator;
                      sub-user grants attenuate (never more than the creator's).
  logs.md             the audit trail of every cast/unmount is append-only +
                      hash-chained (the immutable evidence under the immutable
                      base).
