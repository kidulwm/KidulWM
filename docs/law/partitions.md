# LAW — partitions (true separation: system vs user)

Status: LOCKED 2026-11-11, Barticus present (GSI).

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
