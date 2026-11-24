# LAW — disk guard (one physical identity, many consumers)

LOCKED 2026-11-23, Barticus present (GSI). All three rulings (A, B, C) confirmed
with [Barticus: yes]. Consolidates `kidulkey/references/host-disk-identity.md`
and the agent-side `tools/disk_guard.py` into one ruling, and rules the btrfs
carve-unit question.

## The increment (one sentence)

Disk identity is ONE physical truth (the GPT disk GUID `PTUUID` / partition GUID
`PARTUUID`), read by MANY consumers — the agent's disk guard, KSD's allocation
resolver (kalloc/kmount), and the carve verb all hang off the SAME anchor. They
cross-check each other at two joints (carve, mount), and btrfs subvolumes are
the candidate carve unit that makes the space check a real second opinion.

## One identity, many consumers (the fold)

The nvme `/dev/nvme0n1` NUMBER is NOT stable — it re-enumerates across buses.
The GPT disk GUID (PTUUID) and partition GUID (PARTUUID) ARE stable: they are
written into the partition table and survive re-enumeration. So the stable
identity is the GUID, never the node name. This is the same "one key, many
consumers" fold locked in kidulkey.md — now applied to disk identity:

  PTUUID   names the PHYSICAL DISK (the thing mkfs/dd actually write).
  PARTUUID names the PARTITION (what kalloc/kmount resolve to).
  UUID     names the FILESYSTEM/CONTAINER (LUKS UUID = the container, hidden
           inside; NOT visible on the raw device — a guard keyed on it MISSES
           `mkfs /dev/<disk>` and `mkfs /dev/<disk>p1` entirely).

Anchor of record (this host, read-only verified 2026-11-23; resolve per box,
never hardcode):

  root disk      PTUUID 90604b7b-8ea5-4d9d-b803-a88a5bac5509  (untouchable)
  boot           nvme0n1p1 vfat, PARTUUID ec53743b-cf69-49ad-8581-cdc3de62ecad
  root LUKS      nvme0n1p2, container UUID 248d082f-47a1-4fa5-a7be-331f70ce0b5b
  KSD disk       PTUUID 49945296-b708-4ec9-a3fc-39536eb956d6
  KSD-ESP        PARTUUID 618683a9-0454-4992-aa79-951db740d263

## Two observers, cross-check at the joints (the "two yes's", done cleanly)

Two consumers of the physical identity already EXIST and fail in DIFFERENT ways,
so they are genuine witnesses, not an echo:

  OBSERVER 1 — block layer    the kernel's own view (lsblk -> PTUUID/PARTUUID).
                              Failure mode: re-enumeration, human error, a
                              device that is not what it seems.

  OBSERVER 2 — signed layer   kalloc (allocation-map.md): the kidulKey-signed
                              statement "key X -> partition token Y".
                              Failure mode: tamper / an unsigned or stale map
                              desynced from reality.

They verify EACH OTHER at exactly two joints — never a merged third source of
truth (that is the mess to avoid):

  CARVE — before kcarve writes a partition, BOTH must hold:
    (a) block layer: the target resolves, up its PKNAME chain, to a PHYSICAL
        disk whose PTUUID is NOT the root disk (playground/system, never root);
    (b) free-space is confirmed by BOTH the partition table (sgdisk free
        sectors) AND, when the pool is btrfs, the filesystem accounting
        (`btrfs filesystem usage` — df lies on btrfs).

  MOUNT — before kmount mounts, resolve the kalloc token to a device and confirm
    that device is NOT the root disk (physical guard agrees with the signed
    pointer). A kalloc entry pointing at a partition ON the root disk is a
    tamper/desync ALARM, not a mount — deny-by-default (allocation-map.md).

No new file. The "double check" is a consistency RULE between the two layers
that already exist; its only new cost is the btrfs space read at carve.

## btrfs in production (the carve unit question)

This box already runs btrfs-on-LUKS (@ subvolume, compress=zstd:1) — btrfs is
not a future migration, it is the live layout. Ruling the production carve unit:

  CONSOLIDATED (partitions.md LOCKED): system/public/per-user are separate,
    walled, key-gated; external/net = "just another partition"; FREE POOL carved
    by the People app on demand; SYSTEM read-only at runtime (dm-verity).

  NEW (this ruling): the carve UNIT may be a btrfs SUBVOLUME instead of a raw
    partition. A subvolume is the NATIVE realization of the partition wall:
      - read-only subvolume flag = immutability by ARCHITECTURE (stronger than a
        guard regex: even a non-agent tool mounting it cannot write it);
      - snapshot + reflink = instant rollback / zero-copy send-receive (the
        server->TV media stream is `btrfs send` over a pipe, no re-encode);
      - qgroup quota = per-user space cap enforced by the fs, not by diligence;
      - the bind-mount wall (cells.md) maps cleanly: each @home/<hash> subvolume
        is a separate mountable tree, absent when not mounted — same as today.

  The honest caveat: btrfs does NOT replace the guard. `mkfs /dev/<disk>` and
  `dd` are BELOW the filesystem — a subvolume cannot stop them. The PTUUID/
  PARTUUID guard stays as the BOTTOM wall; the ro-subvolume is the TOP wall.
  They compose: guard blocks the physical layer, fs immutability blocks the
  logical layer. Neither substitutes for the other.

## Open questions for Barticus — verdicts

  A. CARVE UNIT — adopt btrfs subvolume as the production carve unit (REVERSES
     the carve-half of partitions.md / allocation-map.md "partition = token"),
     or keep raw partitions and take btrfs only as the on-box media pool?
     [Barticus: yes — adopt subvolume.] It costs no new identity (subvolumes live
     on the SAME PTUUID root disk — the guard is unchanged) and it is the only
     shape where the free-space double-check is a real second opinion.

  B. fscrypt-per-home — kernel 7.2.8 has CONFIG_FS_ENCRYPTION=y (necessary),
     but btrfs-native fscrypt is young and not yet proven to work+rekey on this
     fs. [Barticus: yes — defer to its OWN docket with a full verification pass.]
     B is a "must get right"; it gets its own full attention later, never folded
     into the carve cut as an unproven promise.

  C. DRIVE CLASS of the KSD m.2 — on the dev host it is PLAYGROUND (free to
     rebuild); on a shipped TV it is SYSTEM (key-gated). [Barticus: yes —
     category is a per-deployment assignment set at commissioning, never baked
     into the code.]

## Relationship to existing law

  partitions.md         the wall (system/public/per-user); THIS law decides the
                        carve UNIT (subvolume vs partition) under the same wall.
  allocation-map.md     kalloc token = PARTUUID; the signed pointer (observer 2).
  kidulkey.md           "one key, many consumers" -> here "one identity, many
                        consumers"; the sealed mount/carve verbs stay the verbs.
  dom0.md / starship.md the ROOT disk is the captain's safe's floor; the guard
                        keeps it untouchable even under --yolo.
  verified-boot.md      dm-verity seals SYSTEM; the ro-subvolume is the matching
                        runtime immutability one layer up the btrfs tree.
