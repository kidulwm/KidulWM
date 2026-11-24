# DESIGN DRAFT — carve-subvolume (the btrfs-subvolume carve re-cut)

Status: LOCKED 2026-11-25, Barticus present (GSI). Rulings A–D [Barticus: yes];
E DEFERRED — PUBLIC stays a separate partition this cut; production folds it to
one shared @public SUBVOLUME + link-in (its own docket — see §Open non-blocking,
and the pool-commissioning step keeps room for it). Builds on disk-guard.md (LOCKED
2026-11-23, ruling A = btrfs SUBVOLUME is the production carve unit). The law is
the contract; this file is the BUILD ORDER for reconciling claim/carve step 4's
carve mechanism against that ruling. Sibling to claim-carve.draft.md (this does
NOT rewrite its steps 1–3, 5–7 — it re-cuts ONLY the step-4 carve primitive).

Spec-first because partitioning is fatal (settings.md): the carve is the one
place to be heavy, and a re-cut that changes the encryption boundary is the
heaviest carve decision there is.

## The locked architecture (quoted, not paraphrased)

disk-guard.md §"btrfs in production (the carve unit question)":
  "the carve UNIT may be a btrfs SUBVOLUME instead of a raw partition. A
   subvolume is the NATIVE realization of the partition wall: read-only
   subvolume flag = immutability by ARCHITECTURE ... snapshot + reflink =
   instant rollback / zero-copy send-receive ... qgroup quota = per-user space
   cap enforced by the fs, not by diligence ... each @home/<hash> subvolume is
   a separate mountable tree, absent when not mounted — same as today."

  Ruling A [Barticus: yes]: "adopt btrfs subvolume as the production carve
   unit (REVERSES the carve-half of partitions.md / allocation-map.md
   'partition = token'). It costs no new identity (subvolumes live on the SAME
   PTUUID root disk — the guard is unchanged) and it is the only shape where
   the free-space double-check is a real second opinion."

  Ruling B [Barticus: yes]: "fscrypt-per-home DEFERRED to its own docket with a
   full verification pass ('must get right') — never folded unproven into a
   carve cut."

  "btrfs does NOT replace the guard. mkfs/dd are BELOW the filesystem. The
   PTUUID/PARTUUID guard stays as the BOTTOM wall; the ro-subvolume is the TOP
   wall. They compose."

The reversals this slice makes, stated outright:
  * allocation-map.md ruling D "PARTITION = TOKEN"  ->  SUBVOLUME = TOKEN.
  * kcarve's primitive "carve a partition from the FREE POOL"  ->  "create a
    btrfs subvolume on the pool."
  * per-user LUKS2 (kcarve luksFormat per partition)  ->  RETIRED. The pool is
    ONE btrfs-on-LUKS container; per-home encryption rides fscrypt (deferred).

## What exists today (real code seams, verified 2026-11-25)

Carve verb — kidulkey/gate/src/kcarve.zig (219 lines):
  `kcarve <device> <percent> <key-id> [vault-dir]`
  readLayout() parses `sgdisk -p` free sectors + max partition number;
  carvePartition() runs `sgdisk -n <num>:0:+<sectors> -t 8300 -c ksd-user`;
  partuuid() reads the new PARTUUID; parkKey() writes a 64-byte keyfile; then
  `cryptsetup luksFormat --type luks2 --key-file <file>` and prints
  `CARVED <PARTUUID> <keyfile>`. MIN_CARVE_SECTORS = 32 MiB (LUKS header floor).

Allocation token — kidulkey/gate/src/allocation.zig + kalloc.zig:
  Entry = { key_id, partition (a PARTUUID/fs-UUID token), home (home-hash),
            uid }. resolve() returns the partition token; kmount resolves it.

Mount verb — kidulkey/gate/src/kmount.zig (155 lines):
  resolveToken() walks /dev/disk/by-partuuid + by-uuid; resolveMapper() walks
  /dev/mapper/<token> (kopen opened the partition AS its token). mount(2) on
  that device at the mountpoint.

Decrypt/close — kopen.zig (luks open per partition, crypt_activate_by_keyfile),
  kclose.zig (crypt_deactivate), kumount.zig (umount2), kclean.zig (scrub).

kushd carve cue — kushd/src/main.zig (CARVE_CUE "homes-carve", KCARVE_PATH,
  CARVE_LABEL "KSD-root"): resolveCarveDevice() = findfs LABEL=KSD-root ->
  lsblk PKNAME -> /dev/<parent-disk>, fail-closed on loop/ram/empty. handleCarveCue()
  retains the claim key-id, forks kcarve <device> <percent> <key-id>, drains
  CARVED. This cue/consent/retain-reject PLUMBING is unchanged by this slice —
  only what kcarve DOES changes.

## The target (one btrfs-on-LUKS pool, homes = subvolumes)

  POOL     the whole FREE POOL is ONE LUKS2 container whose payload is ONE btrfs
           filesystem. Opened ONCE (not per proof); per-home crypto = fscrypt
           (deferred). Its device identity stays PTUUID/PARTUUID-guarded
           (bottom wall, unchanged — disk-guard).
  HOME     a btrfs subvolume @home/<home-hash> (the home-hash is ALREADY the
           per-key identity leaf, kid.md). Created by the carve verb; mounted
           key-gated on proof (subvolume absent when not mounted = the
           "detached by default" wall made structural).
  SIZE     the fill-bar percent becomes a qgroup LIMIT on the subvolume (space
           cap by the fs), not a physical carve. "full" = no quota. Subvolume
           create is instant; re-size later = one qgroup limit write.
  TOKEN    the kalloc entry's "partition" and "home" fields COLLAPSE into one:
           the subvolume = home-hash. No PARTUUID resolution in kmount anymore —
           the mount target is the pool device + `subvol=`.

## Build order (each lands green before the next)

  1. POOL COMMISSIONING (kcarve's replacement target). Define the pool: a
     btrfs-on-LUKS container for the FREE POOL, opened at BOOT by the sealed verb
     (kboot cues `kopen POOL`), mounted at a fixed path (e.g. /mnt/ksd-pool).
     Gate: `btrfs filesystem show` lists the pool; `btrfs subvolume list` works
     against it; the pool LUKS key lives in the cold vault (cold-storage.md),
     never in kalloc.
     — This is the seam where ruling B's "fscrypt later" is honored: no per-home
       LUKS exists, so per-home crypto is a FUTURE fscrypt pass, not this cut.

  2. kcarve RE-CUT (the carve primitive). Replace sgdisk+luksFormat with:
     `btrfs subvolume create <pool>/@home/<home-hash>` + `qgroup limit` set to
     `percent`% of `btrfs filesystem usage` free (data+metadata). Drop the
     keyfile park (no per-user LUKS key). Output contract changes from
     `CARVED <PARTUUID> <keyfile>` to `CARVED <home-hash>`. Fail-closed: missing
     pool, subvolume already exists, quota set fails -> no carve, rollback
     `subvolume delete`.
     Gate: rig-proven create + qgroup limit + rollback; `btrfs subvolume list`
     shows @home/<hash> with the right quota.

  3. kalloc TOKEN COLLAPSE. allocation.zig Entry collapses `partition` + `home`
     into one `subvolume` field (= home-hash), with the mount leaf derived as
     /home/<home-hash>. resolve() returns the home-hash. Drop the by-partuuid /
     by-uuid resolution in kmount's resolveToken/resolveMapper (no PARTUUID
     anymore).
     Gate: allocation map tests green; resolve returns the subvolume name; the
     denied/struck paths unchanged.

  4. kmount RE-CUT. mount the subvolume key-gated: resolve key-id -> subvolume
     (kalloc) -> `mount -o subvol=@home/<hash> <pool-dev> /home/<hash>` (or a
     bind-mount of the pool's mounted subvolume path). kopen/kclose retire from
     the PER-USER path (pool LUKS is opened once at boot, step 1). kumount /
     kclean unchanged.
     Gate: submit rig mounts a subvolume at /home/<hash>, unmounts, scrub; a
     key NOT in kalloc mounts nothing (deny-by-default).

  5. kushd MOUNT-SEQUENCE RE-CUT. The re-seat chain (main.zig re-seat sequence)
     drops its per-user `kopen` leg: resolve -> kmount(subvolume) -> re-seat.
     The homes-carve cue keeps its plumbing (retained key-id, percent, busy/
     no-claim guard); only kcarve's argv/output changes.
     Gate: end-to-end freeze -> proof -> resolve -> subvolume-mount -> re-seat
     on the rig, no kopen in the path.

  6. FREE-SPACE SECOND OPINION. kcarve's size check reads `btrfs filesystem
     usage` (both data AND metadata — df lies; disk-guard §two observers) as
     the sole free-space authority for quota, replacing the sgdisk free-sector
     read. The PTUUID guard (carve target != root disk) stays as the bottom wall.
     Gate: quota rejects when metadata is exhausted even though data shows free.

  Steps 1–3 of claim/carve (detection + ceremony) and steps 5–7 (seed+sign,
  defaultHome skeleton, mount-on-proof) are UNCHANGED — they cut the same seams
  against a subvolume token instead of a PARTUUID token.

## done-when

  - A virgin pool's first proof creates a btrfs subvolume @home/<hash>, key-gated
    via kalloc, mounted at /home/<hash>; no per-user LUKS to be found in the path.
  - The fill-bar percent lands as a qgroup limit (TV 50% default; "full" = no
    quota + the extra consent beat), enforced by the fs.
  - The kalloc entry carries exactly one storage token (the subvolume = home-hash),
    signed by the proved owner key (never the TEST seed).
  - The free-space check is `btrfs filesystem usage` (data+metadata), and the
    PTUUID bottom-wall guard still rejects any carve/mount on the root disk.
  - kopen/kclose no longer appear in the per-user proof->mount chain.

## Open questions (lettered, one recommendation each)

  A. POOL ENCRYPTION BOUNDARY — confirm the whole FREE POOL is ONE btrfs-on-LUKS
     container (so per-user LUKS is retired entirely, per-home crypto = fscrypt
     later). REC: yes — this is the only shape where subvolume carve AND the
     free-space second opinion both hold; it matches the family-TV threat model
     (the owner IS the trust root; outsiders are stopped by verified-boot +
     key-gating, not per-home crypto).

  B. POOL OPEN TIMING — who opens the pool LUKS and when. REC: boot-open by the
     sealed verb (kboot cues `kopen POOL`), key in the cold vault. The pool is
     the shared family floor and homes must be mountable on first proof; a
     lazy/per-home open would re-introduce per-home LUKS (defeats ruling B).

  C. KALLOC TOKEN FORM — collapse "partition"+"home" to one "subvolume" = the
     home-hash, or keep a separate stable subvolume UUID (`btrfs property set`)?
     REC: collapse to home-hash — it IS the per-key identity leaf (kid.md),
     already signed in the entry, and it removes the whole PARTUUID resolution
     surface from kmount (no by-partuuid/by-uuid/mapper walk). A subvolume UUID
     would buy rename-robustness we don't need (we never rename a home).

  D. PERCENT -> QUOTA MAP — "100%/full" means NO quota (uncapped) vs pool-size
     quota. REC: full = no quota, but keep the extra consent beat (settings.md
     already demands it for the choice that can eat the system). "MIN carve"
     (32 MiB LUKS floor) is dropped — subvolumes have no such floor.

  E. PUBLIC FOLD — does the PUBLIC partition (128 GiB shared floor,
     partitions.md) fold INTO the pool (as a subvolume) or stay a separate
     partition? DEFERRED (Barticus, GSI): leave PUBLIC as-is this cut. Production
     shape (recorded, not built): PUBLIC and the shared media library become ONE
     @public SUBVOLUME in the pool, mounted into every home at /public — NOT a
     per-user /public folder, and NOT a symlink across partitions (a subvolume
     mount IS the wall). The trigger is install sizing (a 32 GiB drive has no
     room for a 128 GiB PUBLIC partition + per-user homes) — a partitions.md /
     sizing amendment and its own docket, orthogonal to the carve primitive.

## What this does NOT touch

  - partitions.md's SYSTEM/PUBLIC/FREE-POOL wall (only the FREE-POOL carve UNIT
    changes; the wall stands).
  - claim/carve steps 1–3 (claim detection, ceremony surface) and 5–7 (seed+sign,
    defaultHome skeleton, mount-on-proof) — same seams, subvolume token.
  - fscrypt-per-home (its own docket, ruling B).
  - dm-verity / verified-boot (SYSTEM floor, unchanged).
  - The People app / delegation.md (owner manages residents via UI) — later.

## Open (non-blocking, for later)

  - PUBLIC-fold-into-pool (Q E, DEFERRED): fold PUBLIC + shared media into one
    @public subvolume in the pool, mounted into every home at /public; trigger =
    install sizing (32 GiB drive). Own docket — partitions.md sizing amendment,
    not a carve-mechanism change.
  - defaultHome skeleton's exact pill layout (claim/carve §Open already carries
    this — its own design pass before step 6 lands).
  - kalloc/kpax `sign` TEST-helper retirement (already flagged in claim/carve).
