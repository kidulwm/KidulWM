# LAW — re-seat (the conductor face + background identity re-mint)

LOCKED 2026-11-17, Barticus present (GSI).
AMENDED 2026-11-17 (v2, Barticus present, GSI): the transition is FREEZE-not-kill —
the data tentacles are SIGSTOPped (only the face + audio survive), and the entry
slide shows the last frame as a frozen backdrop with the tap prompt overlaid.
See §The entry slide.
AMENDED 2026-11-18 (v3, Barticus present, GSI): the re-seat is MEANT TO TAKE OVER —
controlling BY DESIGN, the identity door, every detail CFC'd for Granny. The
guard against a media-player-style roach is a SELF-DISMANTLING transition:
kclose + kclean + kushd fire ASAP, nothing lingers. See §The transition is a
transition.

## One line

The FACE is a CONDUCTOR — a fixed, data-blind process that never re-seats and
never IS a user. Sign-in RE-SEATS only the USER identity that tentacles inherit:
the data tentacles FREEZE (SIGSTOP), the tap proves, kushd re-mints the identity
(public 1001 -> proved owner 1002) and the deck resumes in the same slot — the
face never dies, the last frame never leaves the screen, nothing blinks. SAFEST
first, seamless second, and the two converge: the freeze makes the swap invisible
AND race-free.

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

## The entry slide (freeze, not kill — the seamless transition)

Sign-in is a FIRST-CLASS SLIDE in the deck — not a modal, not a process kill.
When a proof is requested:

  1. the deck slides IN the entry slide; it gains focus and pushes the rest of
     the deck out of focus.
  2. gaining focus FREEZES the data tentacles — a true SIGSTOP, not backgrounding:
     they go inert (no read, no write, no redraw). A deliberate new behavior,
     narrow to this slide.
  3. the frozen tentacles' LAST frame stays on screen as the slide's BACKGROUND
     (dimmed for legibility); the face composites the LOGO + "tap your kidulKey"
     prompt OVER it, live (the face is the conductor and never freezes).
  4. on tap -> proof -> re-mint -> mount, the deck resumes: the owner's live
     session replaces the frozen backdrop in the same slot. Granny's site opens
     right where her login page was.

The "snapshot" and the "freeze" are the SAME thing here: a SIGSTOPped tentacle's
  last frame IS the frozen backdrop — no separate screenshot is needed (a literal
  pixel copy only earns its keep if a frame must outlive a kill, and the browser
  crossfade holds its frozen surface instead).

PRIVACY GUARD: the frozen frame is the PRE-SIGN-IN frame. Public->owner: that is
  the public browser (no personal data — safe). LOCK or RE-AUTH from a signed-in
  owner: BLANK or BLUR the frame, never snapshot it — a sensitive owner frame
  must not persist as a visible backdrop.

## What re-seat DOES (the background flip)

On a TRUSTED proof (role + key-id from the gate):

  1. the deck freezes the data tentacles (the entry slide, above). The only live
     things are the face (conductor) and public audio (ksound/kplayd — session-
     scoped, reads public media only). ONLY {face, audio} survive.
  2. kushd flips the seat's CURRENT-USER identity: public(1001) -> the proved
     user (owner uid 1002; residents later).
  3. the mount half (already built) mounts the user's partition at their home.
  4. NEW tentacles seat under the proved uid (mintSession); the FROZEN public
     data tentacles are REPLACED by owner-uid processes in the SAME slot —
     surface-in-place, process-re-seats (a running process cannot change uid
     1001->1002, so the process swaps, the surface does not). Audio keeps playing.

The freeze is the transition's muscle, NOT the security boundary — the mount +
  uid are the boundary. Every data-touching tentacle (browser/terminal/files)
  re-seats; nothing lingers that could touch owner data.

## The transition is a transition (self-dismantling — no lingering control)

AMENDED 2026-11-18 (Barticus present, GSI). The re-seat is MEANT TO TAKE OVER —
it is central BY DESIGN, the identity door, and Granny sees every detail CFC'd on
the entry slide. That is the OPPOSITE of the media player, which took over BY
ACCIDENT: its model leaked into the conductor and lingered (the "mother roach",
slide-process.md), leaving controlling bugs to squash later. So the re-seat is
allowed to be central, but its control is BOUNDED and SELF-RELEASING:

  - The re-seat is a TRANSITION, not a resident state. freeze -> proof -> re-mint
    -> mount is ONE cued pass; when it completes, it is GONE.
  - The teardown is PART of the transition, not a later cleanup: kclose (the LUKS
    container), kclean (the Kleaner zeroize), and kushd (reap the frozen
    tentacles + drop the gate verdict) all fire to get it OUT of there ASAP.
  - PROCESS-DEATH IS THE KILL (SYSTEM.md §2.2): a frozen public tentacle is
    REPLACED, not unfrozen-and-kept; nothing lingers that could later "control"
    the deck the way the media player did.

The slide stays THIN (settings.md: "Homes is a SLIDE, not a controlling
feature") — the mechanism lives in the organs (kushd/kidulkey/knetd). Thinness
was the media-era guard; for a feature that is meant to take over, the guard is
SELF-DISMANTLING: the verbs that build the transition (kushd mintSession,
kopen/kmount) are mirrored by the ones that tear it down (kumount -> kclose ->
kclean), and they run on the SAME cue — never "when someone remembers".

## The safety spine (in order)

  1. Face is data-blind — the one privileged process has zero user-data access.
  2. Vault unlock = sealed one-shot verbs (kopen/kmount), fail-closed, face
     uninvolved (privileged-verbs.md; built kushd b4ff2db).
  3. uid separation — public(1001) / owner(1002) / each resident; a tentacle
     sees only its own mount; 0700 homes block cross-read.
  4. Browser passwords live INSIDE the user's key-gated partition, unreadable on
     disk until the tap mounts it; the public browser has NO persisted profile.
  5. Freeze-before-flip: a SIGSTOPped tentacle cannot read, write, or race the
     identity flip — defense-in-depth on top of the mount/uid boundary.

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

## The socket convention (named, not candidates)

One shared SESSION-SOCKET convention so a conductor and several user uids
interleave on one seat:

  - ONE group-owned socket dir (e.g. /run/kushd/wayland), 0770 SETGID, group
    "seat" — the setgid bit makes every socket bound inside inherit group
    "seat" (not the creator's own uid-group);
  - ONE seat group that every session uid (public/owner/residents) AND the
    conductor join;
  - ABSOLUTE socket paths — libwayland treats a name containing '/' as an
    absolute path, so WAYLAND_DISPLAY=/run/kushd/wayland/wayland-1.
  - The socket FILE must be group-WRITABLE, not just the dir: connect() needs
    WRITE on the socket file. A 0770 dir alone still yields a 0755 (owner-
    write-only) socket that blocks every OTHER uid. So kushd sets the seat's
    umask 0007 — kidulwm's wayland-1 then lands 0770 :seat and every seat uid
    connects. (Locked 2026-11-18; proven on-host: a 0640 socket -> EACCES.)

Every session service (Wayland, ksound, kplayd, ...) follows it. This convention
IS the core of seamless re-seat — not a per-socket hack.

## The aim (the tap replaces passwords)

The kidulKey tap REPLACES every password restriction: one proof unlocks the
user's home, their browser profile + saved logins, their files — no password
entry anywhere, no sudo binary (public-seat.md; "owner = sudo" = kushd CLASS
escalation). Granny: login page -> flashing light -> tap -> the site opens, the
last frame never having left the screen. Path of least resistance, no safety
sacrificed — the tap is the WYSIWYS proof (kidulkey.md).

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

  1. the SOCKET CONVENTION (above) — implement the shared dir + seat group +
     absolute paths across the Wayland socket and the session sockets.
  2. the ENTRY SLIDE — the deck slide for sign-in + the freeze (SIGSTOP) on
     focus + the frozen-frame backdrop + prompt overlay + the privacy guard
     (blank/blur on lock/re-auth).
  3. key-id -> home-hash resolution DONE + PROVEN (kalloc entry carries
     home=<home-hash>; kalloc resolve emits it; kushd parses it fail-closed).
     key-id -> uid remains for step 6 (re-mint) — one map bump, not two.
  4. MOUNT-POINT CORRECTION DONE + PROVEN: kushd builds /home/<home-hash> from
     the resolved home-hash (kmount unchanged — it mounts the mountpoint it is
     handed).
  5. the conductor account + socket model: the boot refactor — the face gets a
     conductor uid; bill.kush's kidulwm act moves off class "user".

## Relationship to existing law

  public-seat.md    owner escalation -> this law builds the re-seat it names.
  kid.md            the kID umbrella; this law reverses its "key-derived hash"
                    naming (the home name is a random home-hash).
  kidulwm-layout.md the SlideDeck primitive — the entry slide rides the deck;
                    "freeze on focus" is a new, narrow deck behavior.
  partitions.md     the mount half; this law fixes its mount POINT (home-hash).
  privileged-verbs.md  PROCESS-mount vs DRIVE-mount; re-seat is PROCESS-mount.
  settings.md       Homes build order step 4 (RE-SEAT + MOUNT) -> this is the
                    re-seat half; the mount half is re-seat-mount.draft.md.
  cold-storage.md   the cold vault stays key-material only (this law's Q6).
  bill.kush         the seating chart; the face's act moves to a conductor seat.
