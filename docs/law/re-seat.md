# LAW — re-seat (the conductor face + background identity re-mint)

LOCKED 2026-11-17, Barticus present (GSI).

## One line

The FACE is a CONDUCTOR — a fixed, data-blind process that never re-seats and
never IS a user. Sign-in RE-SEATS only the USER identity that tentacles inherit:
a background re-mint (proof -> re-mint -> mount), the face never dies, nothing
blinks. SAFEST first, seamless second — and the two CONVERGE: the data-blind
conductor is both the safest and the seamless shape.

## The conductor (the face, re-framed)

- kidulwm = the FACE = a CONDUCTOR. Its own uid (never "public", never any
  user), holding the display + input (seat/render/video/input groups) and
  NOTHING else. DATA-BLIND: it renders every user's surfaces but cannot read any
  user's files — no user group membership, 0700 homes block it.
- public (uid 1001) stops being the face's identity and returns to a plain
  TENTACLE identity — the boot-default USER identity, nothing more.
- The seat is minted ONCE at boot; ESCALATION is a later RE-MINT of the USER
  identity, NOT a seatUid() tweak (public-seat.md §Owner escalation). Re-seat
  flows through kushd's mintSession; it is PROCESS-mount (kushd's hand), NOT a
  new sealed verb (privileged-verbs.md).

## What re-seat DOES (the background flip)

On a TRUSTED proof (role + key-id from the gate):

  1. kushd flips the seat's CURRENT-USER identity: public(1001) -> the proved
     user (owner uid 1002; residents later).
  2. the face is CUED (never killed) to reveal the full roster (step 5 landing).
  3. the mount half (already built) mounts the user's partition at THEIR home.
  4. NEW tentacles seat under the proved uid (mintSession with the new uid);
     RUNNING tentacles transition by policy — audio (ksound/kplayd) KEEPS
     PLAYING (sign-in is the focused app; only music can be live, and it
     survives), the browser swaps profile IN PLACE (auto-open for Granny).

The flip is NOT a blanket kill. It changes the identity NEW tentacles inherit
and cues the face; each running tentacle transitions by its own policy.

## The safety spine (in order)

  1. Face is data-blind — the one privileged process has zero user-data access.
  2. Vault unlock = sealed one-shot verbs (kopen/kmount), fail-closed, face
     uninvolved (privileged-verbs.md; built kushd b4ff2db).
  3. uid separation — public(1001) / owner(1002) / each resident; a tentacle
     sees only its own mount; 0700 homes block cross-read.
  4. Browser passwords live INSIDE the user's key-gated partition, unreadable on
     disk until the tap mounts it; the public browser has NO persisted profile.

## The vocabulary (two splits, locked to kill "one word, N jobs")

  key-id        base64url(pubkey). The RESOLUTION handle ONLY — what the gate
                emits ("TRUSTED key=<key-id>"), what the roster (kpax) and the
                allocation map (kalloc) index by. NOT a secret (it is broadcast
                in the clear during proof), NOT a directory name, NOT a login.
  home-hash     a RANDOM string (generated at claim) naming the user's Linux
                login AND their home dir /home/<home-hash>. Unguessable: not
                derivable from any public value. The owner is PRE-PROVISIONED in
                the golden image: uid 1002, login/home = bee62e237cdd37a455eeafca.
  user partition  the user's key-gated partition (home + data + browser
                passwords). Mounted only on proof. THIS is "the user's vault".
  cold vault    kvaultd (cold-storage.md). Holds ONLY key material (volume keys,
                secrets). NEVER user data. Auto-provisioned per user at claim.

The mount resolves key-id -> role -> uid -> pw_dir, and mounts at pw_dir =
/home/<home-hash>. The key-id never names a directory.

## The aim (the tap replaces passwords)

The kidulKey tap REPLACES every password restriction: one proof unlocks the
user's home, their browser profile + saved logins, their files — no password
entry anywhere, no sudo binary (public-seat.md; "owner = sudo" = kushd CLASS
escalation). Granny: login page -> flashing light -> tap -> the site opens.
Path of least resistance, no safety sacrificed — the tap is the WYSIWYS proof
(kidulkey.md).

## Reversals (explicit — never silent)

  - kid.md §"The two names": "hash = the key-derived string (/home/$HASH)" is
    REVERSED. The home/login name is a RANDOM hash (home-hash), NOT key-derived.
    The key-derived value (key-id) is resolution-only. Rationale (Barticus
    2026-11-17): "random hash sounds safer" — the key-id is broadcast in the
    clear during proof, so a key-derived home name is a guessable target; a
    random hash is not derivable from anything public.
  - public-seat.md §Owner escalation: "the seat boots as public (uid 1001)"
    becomes "the FACE boots as a conductor uid; the seat's USER identity boots
    as public (uid 1001)". The face is never public.

## Open build items (not law — the next slices)

  1. The Wayland socket crossing the uid boundary (face at conductor uid serves
     tentacles at a DIFFERENT uid). Candidates: (a) seat-group socket + symlink,
     (b) absolute WAYLAND_DISPLAY, (c) shared runtime dir. Resolve next slice.
  2. key-id -> uid/home-hash resolution does not exist yet. Roster maps key->
     role; kalloc maps key->partition. The mount target (pw_dir) needs key->
     uid (or kalloc extended to carry home-hash). Owner = fixed uid 1002.
  3. MOUNT-POINT CORRECTION: kmount today mounts /home/<key-id> (built
     b4ff2db); it must mount /home/<home-hash> (pw_dir). A correction to
     already-built code, not a new design.
  4. The conductor account + socket model: the boot refactor — the face gets a
     conductor uid; bill.kush's kidulwm act moves off class "user".

## Relationship to existing law

  public-seat.md    owner escalation -> this law builds the re-seat it names.
  kid.md            the kID umbrella; this law reverses its "key-derived hash"
                    naming (the home name is a random home-hash).
  partitions.md     the mount half; this law fixes its mount POINT (home-hash).
  privileged-verbs.md  PROCESS-mount vs DRIVE-mount; re-seat is PROCESS-mount.
  settings.md       Homes build order step 4 (RE-SEAT + MOUNT) -> this is the
                    re-seat half; the mount half is re-seat-mount.draft.md.
  cold-storage.md   the cold vault stays key-material only (this law's Q6).
  bill.kush         the seating chart; the face's act moves to a conductor seat.
