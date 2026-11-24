# DESIGN DRAFT — portable homes (a self-sovereign drive that roams any Kidul TV)

Status: SPEC DRAFT — three rulings LOCKED (Barticus 2026-11-23, via bobdotrix),
BUILD NOT YET AUTHORIZED. This is the sibling to claim-carve.draft.md. It does
NOT supersede it and does NOT touch the internal claim/carve; it adds the
external + "no TV" path claim-carve explicitly out-of-scoped. Spec-first,
same reason as the carve: a drive you brought to a stranger's TV carries a
person's whole home, and we cannot afford to mess that up ("partitioning is
fatal; a portable home that leaks or bricks on another TV is worse").

## Why (the gap)

claim-carve builds the INTERNAL house: empty roster -> claim -> carve the KSD
free pool -> seed kalloc/kpax under the owner root -> mount-on-proof. Every
home is cut from that ONE shared disc, and every resident is a roster entry
signed by that box's owner. Two real users have no path through it:

  - the non-resident: someone whose home is NOT on the shared disc but on a
    drive they carry (a travel home, a kids' home that moves rooms/TVs).
  - the "no TV yet" owner: someone who does not own a Kidul TV and should be
    able to walk up to ANY Kidul TV, prepare a drive, and have that drive work
    on every Kidul TV thereafter.

The law already leans into both (partitions.md: an external drive is "just
another partition ... no special removable code path, the key is the only
door"; allocation-map.md: <partition> is a UUID token, never a device path).
What is MISSING is not storage — it is a PROVISIONING path reachable from the
public seat, and a PORTABLE RESOLUTION branch that does not need the roster.

## The three locked rulings

  R1. SELF-SOVEREIGN DRIVE. A KidulWorks-signed manifest IS the identity. No
      roster needed, no krouter cache, no prior registration — the drive works
      on a never-claimed TV. "Set up my drive with no TV" requires NOTHING
      but the drive + any Kidul TV.
  R2. PUBLIC SEAT CAN PROVISION. Any stranger with a drive can provision it
      from the public seat. This is SAFE precisely because the blast radius is
      the caller's OWN drive — the internal claim stays owner-only because its
      blast radius is the shared house. Same ceremony, different radius,
      different gate.
  R3. DRIVE-ONLY, ZERO HOST FOOTPRINT. A portable home lives entirely on its
      drive; nothing is carved on the host TV, no scratch carve, no cache
      carve. A roam leaves the TV exactly as it found it.

## The architecture (ONE ceremony, TWO targets)

The claim surface already built in claim-carve step 3 (name -> size -> consent,
both input surfaces) is REUSED VERBATIM. Only the target and the commit change:

  INTERNAL claim (claim-carve)   target = KSD free pool (label-pinned, owner-
                                 only, once). commit = kalloc + kpax under the
                                 owner root. A resident in the house.

  PORTABLE claim (this spec)     target = the USB drive the caller plugged in
                                 (detected, confirmed by UUID, never the KSD).
                                 commit = a self-contained manifest ON the
                                 drive + the wrapped volume key. A ROAMER —
                                 in no roster, in no box's kpax/kalloc.

The ceremony's three stages are the same; the consent nag's GRANNY line
differs (we are writing YOUR drive, not the house's disc) and stays cancel-
default with a "full" extra beat (full = the whole drive, the one choice that
eats the drive).

## Why this is the elegant + safe solution (the four guards)

  1. BLAST-RADIUS ASYMMETRY. Internal = owner-only because a wrong carve eats
     the shared house. Portable = public because a wrong carve only eats the
     drive the caller physically brought. The SAME carve verb, different gate,
     chosen by the TARGET's radius, not by the verb.

  2. GUEST AUTHORITY, NEVER HOST AUTHORITY. A portable home mounts under ITS
     OWN home-hash on the host (re-seat.md: home-hash is random, unguessable).
     It is a full authority over its own drive and ZERO authority over the
     host TV: it cannot become "owner" of that box's roster, carve the KSD, or
     read other residents — 0700 homes + no roster entry = the partition does
     not exist for anyone else (partitions.md wall, scaled to a roamer). A
     self-sovereign drive that roams is a GUEST at every TV, never an admin.

  3. THE DRIVE CARRIES ITS OWN UNLOCK. The cold-vault key material that
     claim-carve parks on the provisioning box cannot roam. So a portable
     drive stores its LUKS volume key WRAPPED to the drive's own key-id, ON
     the drive. Tap proves WHO (Ed25519, the existing proof), the envelope
     unwraps only for that key, kopen/kmount run exactly as for a resident.
     No host TV ever holds a byte of the roamer's secret.

  4. TWO SIGNATURES, TWO JOBS (the two-key rule, kidulkey.md). The manifest is
     signed by the KIDULWORKS provisioning root = "this is a genuine Kidul
     home drive" (a hostile/foreign drive cannot present itself as a home).
     The wrapped key is gated by the drive's key-id = "and only its holder can
     open it." A fresh, never-claimed TV trusts "valid KidulWorks manifest" as
     ELIGIBLE to seat, and mounts NOTHING until the holder taps.

## The re-seat seam (the portable resolution branch)

The existing proof->resolve->open->mount chain (re-seat.md, claim-carve step 7)
resolves key-id -> role/uid via the ROSTER and key-id -> partition via the
ALLOCATION map. A roamer resolves through NEITHER. New branch, appended at the
END of resolution so the resident path is untouched:

  resolution order (fail-closed throughout):
    1. roster + allocation (resident)   -> the built chain, unchanged
    2. DRIVE MANIFEST (roamer)          -> a detected, KidulWorks-signed
       manifest whose key-id matches the proved key -> mount the drive's
       partition at /home/<home-hash>, uid minted ad hoc (no roster entry)
    3. deny                              -> UNTRUSTED, nothing mounts

The roamer's home-hash is generated at PROVISIONING (stored in the manifest),
so the SAME drive mounts at the SAME /home/<home-hash> on every TV it visits —
the crossing-over is portable.

## The manifest (shape mirrors kpax/kalloc, one format family)

`portable-manifest` on the drive's first (non-Home) partition, line-oriented
canonical text + detached Ed25519 sig (roster-format.md §shape, reused):

  header          manifest version=<n> root=<kidulworks-key-id> prev=<hash>
  entry           <drive-key-id> <home-hash> <partition-uuid> <envelope-id>

  <drive-key-id>   the drive's proof key (self-generated at provisioning)
  <home-hash>      random, generated at provisioning, the roamer's login+home
  <partition-uuid> the drive's Home partition UUID (token, never /dev)
  <envelope-id>    which wrapped-key envelope on the drive unlocks it

Signed by the KidulWorks provisioning root (NOT the box's owner, NOT the
drive's own key — a self-sign would let a hostile drive mint its own
"genuine" manifest). The wrapped LUKS key itself is a SEPARATE secret blob,
not in the manifest (manifest stays public-not-secret, like kpax/kalloc).

## Build order (each lands green before the next; NOT authorized until lock)

  1. DRIVE DETECTION + CONFIRM  kushd hotplug sees a removable block device;
     identify it by UUID, confirm it is NOT the KSD/label-pinned target, and
     distinguish "blank removable" (eligible to provision) vs "already a
     manifest bearer" (eligible to seat). No mount yet.

  2. THE PORTABLE CEREMONY CUE  the public seat's Sign In slide renders a
     "prepare / seat this drive" cue alongside the two doors (a third door, or
     a drive-arrival prompt — surface Q below). Claim-carve step 2's verdict
     channel carries "roamer present", derivable + non-spoofable-critical only
     in what it RENDERS (same veto logic).

  3. PROVISION (reuse the ceremony)  name -> size -> consent, then kcarve on
     the CALLER'S drive (percent-of-drive, cancel-default, full extra beat),
     mkfs + defaultHome skeleton from claim-carve step 6's SAME artifact,
     generate the drive key + home-hash, wrap the volume key, sign the
     manifest with the KidulWorks provisioning root. Fail-closed rollback.

  4. SEAT ON PROOF  extend the proof->resolve chain with branch 2 (manifest
     resolve); mount at /home/<home-hash>, ad-hoc uid, zero host write.
     Cosmetic + privileged verbs reused: kopen/kmount/kmountpoint unchanged.

  5. UNPLUG = LOCKED  ejection (or unplug) = kumount -> kclose -> kclean,
     the SAME self-dismantling teardown as re-seat.md §transition. No host
     state persists (R3).

## The honest boundary (not invented, flagged for its own design pass)

The exact WRAP primitive is UNSPECIFIED here on purpose: whether the drive key
exposes an X25519/ECDH agreement in addition to the Ed25519 sign, or the
envelope is sealed AES-GCM to the key-id with the release riding the proof —
that must be checked against kidulkey.md's ACTUAL key capabilities (what the
dongle/remote can compute) before it is law. Architecture is frozen; the crypto
primitive is a flagged open item, same discipline as device-registry flagged its
mechanism.

## Open surface questions (NOT blocking the architecture)

  - Third door vs drive-arrival prompt on the public Sign In slide (a drive
    that plugs in should not silently change the deck — the entry slide
    freeze already gives us the moment to announce it).
  - The remaining "full" agreement for the portable consent nag's Granny line
    ("this writes YOUR drive") — wording, locks at surface time.
  - Drive key generation: on-drive (the drive mints + seals its own key at
    first provisioning) vs host-minted-and-transferred. On-drive is preferred
    (the key never exists off the drive — defense by architecture).

## Relationship to existing law

  partitions.md      "just another partition, key is the only door" -> the
                     roamer is that, minus the cold-vault tie.
  allocation-map.md  <partition> as UUID token, public-not-secret -> the
                     manifest mirrors the shape, one format family.
  key-entry.draft    the "rando sign-in (attach own drive + key)" stub -> THIS
                     is that delayed sub-flow, now specced.
  re-seat.md         home-hash naming + the self-dismantling teardown -> reused
                     verbatim for the roamer (kopen/kmount/kclose/kclean).
  delegation.md      owner as root creator -> NOT the roamer's model; a roamer
                     is a peer of itself (self-sovereign), never a sub-grant.
  kidulkey.md        two-key rule -> the manifest's KidulWorks root signature.
  claim-carve.md     the ceremony surface + skeleton artifact -> reused; this
                     spec is the "external" half claim-carve left out.
