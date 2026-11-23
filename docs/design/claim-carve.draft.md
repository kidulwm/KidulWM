# DESIGN DRAFT — claim/carve (the initial claim ceremony + per-user carve)

Status: DRAFT (bobdotrix 2026-11-23). Builds on settings.md (LOCKED) + re-seat.md
(LOCKED; re-seat-entry.draft.md built+proven through the privacy guard). The law
is the contract; this file is the BUILD ORDER for the claim/carve slice — the
"initial claim ceremony" + "per-resident carve" (settings.md §provisioning),
sibling to re-seat-entry.draft.md. Spec-first because PARTITIONING IS FATAL
(settings.md: "partitioning is fatal, so it is the one place to be heavy").

## The locked architecture (settings.md §provisioning + claim flow)

  - claim = empty roster / first boot: the FIRST key to prove seeds the roster —
    its identity becomes entry #1 (owner); the owner's ROOT signs the roster from
    then on. Once per system, never again. "Empty roster -> claim" is the ONLY
    unclaimed state — no flag (key-entry.draft.md:41, folded into settings.md).
  - Claiming a home = a resident being provisioned; the owner is just the FIRST
    resident. Every "+VIP" after runs the SAME path.
  - the user gives: name + partition size. the system does: carve -> defaultHome
    skeleton -> roster entry -> bind kID -> mount on proof.
  - size: ONE fill bar (no-slider slider). Default by DEVICE CLASS, not the user:
    TV = 50% ("sharing is caring"), PC = full.
  - defaultHome: a defined skeleton template (standard pill layout + default
    theme), instantiated into each new partition — an artifact, not ad hoc.
  - Consent on consent: size -> a Granny-terms nag; ball DEFAULTS TO CANCEL;
    "full" gets an extra beat (the one choice that can eat the system).
  - Carve is BLOCK-DEVICE-only (verified verbs kcarve + sgdisk/cryptsetup);
    mkfs is the APP's job (settings.md: "leave the mkfs for the app"). The
    defaultHome skeleton is laid AFTER kopen.

## What exists today (real code seams this slice cuts)

  - kcarve (kidulkey/gate/src/kcarve.zig, BUILT+PROVEN): sealed carve verb,
    usage `kcarve <device> <percent> <key-id> [vault-dir]`. Reads the free pool
    (sgdisk -p), carves partition max_num+1 (sgdisk -n, fail-closed rollback),
    partprobe + wait-node, LUKS2 encrypts (cryptsetup luksFormat, keyfile as
    passphrase, 64B CSPRNG key), parks key in the cold vault. Prints
    `CARVED <PARTUUID> <keyfile>`. MIN_CARVE_SECTORS = 32 MiB guard. mkfs is
    NOT here (correct — the app lays it). NOT YET WIRED into any flow; standalone.
  - kalloc (gate/src/kalloc.zig, BUILT): CLI for the allocation map — canonical /
    sign / verify / resolve. `sign` is a TEST helper (plain on-disk seed) — the
    doc is explicit: "the real carving ceremony is the People app (delegation.md),
    signed by the owner's key, never this CLI." resolve prints
    `<partition> home=<hash> uid=<uid>` or `none`.
  - kpax (gate/src/kpax.zig, BUILT): CLI for the roster — canonical/sign/verify/
    resolve. Same TEST-helper caveat on `sign`.
  - The allocation map vs roster SPLIT (allocation.zig): roster = WHO (identity,
    global, krouter-sourced, churns on add/strike); allocation = WHAT a key may
    cast (partition + home-hash + uid), a SEPARATE signed artifact. keystone =
    one key, one identity; the SAME key-id the roster attests.
  - kushd re-seat chain (main.zig): proof -> resolve (kalloc resolve <map> <key>)
    -> token + home-hash + uid, or `none`. `none` = "crew or unprovisioned"
    (line 790-791) -> chain no-ops, slide still TRUSTED. token/hash/uid -> open ->
    mount -> re-seat. home-hash empty => fail-closed; uid 0 => fail-closed.
  - The current gate is a DISPOSABLE dev root, TEST-ONLY test roster (CENSUS:
    carried thread). The vault keyfile is still 0 (nothing carved yet). A REAL
    claim has never run — this slice is the thing that first exercises it.

## The three open decisions (resolve before code — see Open questions)

  1. NAME-ENTRY MECHANISM (settings.md literally says "TBD"): how the user enters
     the alias at claim. A letter pill-bar (a second pill bar, of letters) vs
     keyboard-only vs the hard remote problem deferred.
  2. WHERE THE CEREMONY FIRES FROM: kushd on first-proof (claim is a kushd-owned
     transition, single-session-authority I1) vs a new "People" app stub. The law
     says the real ceremony signs with the owner's key — but the People app does
     not exist yet (delegation.md is a later slice). The claim must not silently
     use kalloc's TEST `sign` (plain seed) as its production path.
  3. DEVICE CLASS for the KSD this boots: is StarShipKidul TV-class (default 50%)
     or full? The DEV TV is the Kogan 4K (CENSUS) — class determines the fill-bar
     default, which drives the carve percent. Trivial to flip but must be stated.

## Build order (each lands green before the next)

  1. CLAIM DETECTION (kushd). Empty-roster is the ONLY unclaimed state (no flag).
     On a proof that resolves to an EMPTY roster (no entry for the key, no
     signed roster yet), kushd must route to CLAIM, not to "untrusted". Concrete:
     a proof that yields "roster empty" (not "roster has a key that isn't you")
     = claim candidate. Fail-closed otherwise (deny-by-default).
     - GATE: first-tap on a virgin system enters claim; a taken system never
       re-enters claim; a wrong key on a live roster is still "untrusted".

  2. THE CEREMONY CUES (kushd <-> kidulwm). kidulwm's Sign In slide needs to RENDER
     claim vs sign-in (roster empty -> "welcome, claim your home"; else the normal
     two doors). New cue(s) on the existing homes-gate channel (NOT a new 0666
     socket verb for identity — but claim STATE is not identity: it is "the
     roster is empty", derivable, non-spoofable-critical only in that it changes
     WHAT renders, so carry it on the private gate connection, same veto logic as
     the privacy guard).
     - GATE: virgin boot renders the claim surface; a claimed boot routes straight
       to the two doors; no new socket verb for identity.

  3. NAME + SIZE INPUT (kidulwm Sign In slide). The claim surface collects the two
     things (name + size) using the mechanism Q 1 decides. Size = the no-slider
     fill bar already specced (settings.md:182-203): quarter-jump taps, hold-to-
     fine, keyboard escape hatch, consent-on-consent with cancel-default. Name =
     whatever Q 1 locks.
     - GATE: claim surface collects name + size; the fill bar enforces its hard
       stops; consent defaults to cancel.

  4. THE CARVE (wire kcarve through kushd). On consent, kushd runs the SEALED
     kcarve verb (it already exists + is proven) with the chosen percent + the
     proved key-id + the DEVICE (Q 3 note: WHICH device — see open Q D). Result
     `CARVED <PARTUUID> <keyfile>` -> kushd holds the PARTUUID. Fail-closed
     (kcarve's own rollback) on any carve/LUKS error. mkfs is NOT here.
     - GATE: a consented claim carves a real LUKS2 partition on the target device,
       key parked cold, PARTUUID captured; a cancelled claim carves nothing.

  5. THE ALLOCATION + ROSTER SEED (the signing boundary — Q 2 decides WHO signs).
     After carve: append the allocation-map entry (partition + home-hash + uid)
     AND the roster entry (the WHO), and SIGN each with the real owner key. This
     is the seam where "never the kalloc TEST CLI" bites: the production path
     must sign with the proved owner's key material, not a test seed.
     - GATE: the two signed artifacts land; `kalloc verify` + `kpax verify` both
       return OK against the owner root; the map resolves the new key-id -> the
       carved PARTUUID.

  6. defaultHome SKELETON. A defined template directory (pill layout + default
     theme) that kopen's app-side mkfs step copies into the new partition as its
     first mount content. Artifact-first: land the skeleton as a tracked file/
     tree + a copy verb, not ad-hoc content creation.
     - GATE: a freshly carved + opened partition mounts with the skeleton present,
       proving the template is a real artifact (not a code-side string).

  7. MOUNT-ON-PROOF (the existing chain, now closed). With the allocation map
     seeded + signed, the NEXT proof of that key resolves -> token+hash+uid ->
     kopen -> mount -> re-seat, exactly as re-seat.md builds it. This is the
     moment the whole earlier chain finally runs on a REAL carved home.
     - GATE: post-claim proof re-seats to /home/<hash> with the carved partition
       mounted (the "crossing over" made real on the first home).

## done-when

  - A virgin system's first proof ENTERS CLAIM; a claimed system never does.
  - Claim collects name + size; consent defaults to cancel; "full" gets its beat.
  - A consented claim carves a LUKS2 partition, parks the key cold, seeds + SIGNS
    both roster and allocation map with the real owner key (never the test CLI).
  - mkfs/defaultHome is the app's step, fired after kopen, from the skeleton.
  - The next proof mounts the carved home and re-seats (chain closed on real disc).
  - No identity signal rides a 0666 socket verb; the carve is block-device-only;
    fail-closed at every step (carve rollback, resolve fail-closed, deny-default).

## Open questions (lettered, one recommendation each — "yes to your recs" locks)

  A. NAME-ENTRY MECHANISM. settings.md leaves it TBD.
     REC(letter pill-bar now) — a second pill bar of letters, arrow-native like
     the resident list, keeps the whole ceremony remote+navigation-drivable
     (Granny's terms: no keyboard assumed). Keyboard stays the escape hatch the
     fill bar already reserves. Alternative (keyboard-only) is faster to cut but
     breaks the "no keyboard assumed" promise on the surface where Granny does
     the ONE setup that matters.

  B. WHERE THE CEREMONY FIRES FROM + WHO SIGNS.
     REC(kushd owns the claim transition; sign with the proved owner key) — kushd
     is I1 single-session-authority and already runs/resolves everything; the
     claim is a privileged transition, not app UI. The SIGNING must use the
     key material the proof establishes (the owner's key, via the gate), NOT
     kalloc's TEST seed sign. The People-app ceremony (delegation.md) stays a
     LATER slice; this cut does a minimal kushd-owned claim, and the People app
     later re-homes the delegates. If the owner-key signing is not reachable
     this cut, we STOP and say so (a test-seed-signed production map is worse
     than no map — it looks real and isn't).

  C. DEVICE CLASS (fill-bar default). StarShipKidul boot drive class?
     REC(TV -> 50% default) — the KSD is the StarShipKidul TV per starship.md;
     "sharing is caring", and it leaves the other 50% of the free pool for the
     residents that follow. Full stays one tap away (+ the extra consent beat).

  D. WHICH DEVICE does kcarve target? kcarve takes `<device>` (e.g. /dev/nvme1n1).
     REC(the KSD drive by LABEL, per CENSUS: KSD-ESP + KSD-root on the nvme; the
     FREE POOL is the unallocated tail of that same disc — partitions.md:120,
     ~771 GiB "not pre-carved, the People app carves on demand") — guard the
     device path in kushd (a fixed-by-config target, never a probe of "biggest
     disk"), so a semi-hostile re-enumeration (nvme numbering shifts) cannot
     redirect a carve onto the wrong drive. partitions.md is the pool authority
     and is consistent with kcarve's READ of `sgdisk -p` free-space.

## What this does NOT touch

  - The People app / delegation.md (the owner managing residents via a UI) — later.
  - mkfs + the app-side filesystem layout (kcarve is block-device-only by law).
  - park/resume, the browser credential-flow picker — later slices.
  - fTPM quote + sealed-secret release (attestation apex) — later.
  - smartLock, the privacy guard, the re-seat/mount chain — all built + proven
    and unchanged; this slice closes the loop ON TOP of them.

## Open (non-blocking, for later)

  - The kalloc/kpax `sign` TEST helper — either graduate to a real key ceremony or
    retire it once the production sign path exists, so no one mistakes it for the
    real thing (the doc already carries the warning; enforce by removal or rename).
  - defaultHome template's exact pill layout — needs its own design pass against
    styles.md before step 6 lands; the skeleton's SHAPE is locked (artifact, not
    ad hoc), its CONTENT is a small follow-up.
