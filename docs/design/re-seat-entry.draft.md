# DESIGN DRAFT — step 4: RE-SEAT (the entry slide + socket convention + re-mint)

Status: DRAFT (bobdotrix 2026-11-18); rulings A-D + the self-dismantling steer
LOCKED 2026-11-18 (Barticus, GSI). NOT law — the architecture is RESOLVED into
re-seat.md (LOCKED 2026-11-17, 67202f5 + v2 3443094 + v3 self-dismantling). This
file is the build order for the re-seat HALF; the law is the contract. Sibling to
re-seat-mount.draft.md (the mount half — the verbs). What is NOT built is the
one-pass wiring that ties proof -> freeze -> re-mint -> mount into a seamless
transition. The entry slide is the SURFACE of that wiring; the socket convention
is its FOUNDATION.

## The locked architecture (already frozen — re-seat.md)

  - The FACE = a CONDUCTOR. kidulwm gets its own uid (data-blind, never public,
    never any user, NEVER re-seats). Sign-in RE-SEATS only the USER identity.
  - FREEZE-NOT-KILL (v2): sign-in is a FIRST-CLASS deck slide; gaining focus
    SIGSTOPs the data tentacles (only {face, audio} survive); the frozen
    tentacles' last frame is the backdrop; tap -> proof -> re-mint -> mount; the
    owner session replaces the frozen frame in the SAME slot. No blink.
  - SELF-DISMANTLING (v3, Barticus 2026-11-18, GSI): the re-seat is MEANT TO
    TAKE OVER — controlling BY DESIGN, every detail CFC'd for Granny — the
    OPPOSITE of the media player, which took over BY ACCIDENT and lingered (the
    "mother roach", slide-process.md). The guard: the transition is ONE cued
    pass that tears itself down ASAP — kclose + kclean + kushd fire on the SAME
    cue — process-death-is-the-kill, no lingering controlling state.
  - The socket convention (NAMED, not candidates): ONE group-owned socket dir
    (0770, group "seat"), ONE seat group every session uid + the conductor join,
    ABSOLUTE socket paths (a '/' in WAYLAND_DISPLAY = absolute to libwayland).
    Every session service (Wayland, ksound, kplayd) follows it.
  - key-id (base64url pubkey) = RESOLUTION only. home-hash (random) = the Linux
    login AND /home/<home-hash>. The mount resolves key-id -> role -> uid ->
    pw_dir and mounts at pw_dir = /home/<home-hash>. key-id never names a dir.

## What exists today (the seams this slice cuts)

  - kushd seatUid() (src/main.zig:191) -> 1001 (public), the ONE seat uid.
  - kushd mintSession(uid) (:212) -> /run/user/<uid> 0700, supplementary groups
    {audio video input seat render tty} via setgroups, PATH, XDG_RUNTIME_DIR,
    HOME, and WAYLAND_DISPLAY=wayland-1 (RELATIVE). One uid, one runtime dir.
  - kidulwm addSocketAuto (src/server.zig:1162) -> lands wayland-1 INSIDE
    XDG_RUNTIME_DIR (/run/user/1001). Every tentacle is uid 1001, so the socket
    lives in 1001's dir and everyone reaches it — the uid boundary never had to
    be crossed.
  - The FACE IS uid 1001 today: bill.kush seats kidulwm as class "user", so it
    drops to seatUid()=1001 just like every tentacle.

  The re-seat needs the face and the data tentacles on DIFFERENT uids that share
  ONE socket. That is the whole point of the socket convention, and it is why
  the conductor account is not cosmetic — the re-mint (1001 -> proved uid) is
  impossible while the face itself IS 1001.

## Build order (incremental, testable each step)

  1. THE SOCKET CONVENTION (infrastructure, invisible). DONE + PROVEN (kushd
     8680b58; no kidulwm change — it already honors KIDULWM_WAYLAND_DISPLAY).
     - kushd main(): create /run/kushd/wayland (2770 = SETGID + 0770, root:seat)
       at boot — the setgid bit makes every socket bound inside inherit group
       "seat". Umask-proof chmod (mkdir 0770 under umask 022 yields 0750).
     - kushd mintSession: set WAYLAND_DISPLAY + KIDULWM_WAYLAND_DISPLAY to the
       ABSOLUTE path /run/kushd/wayland/wayland-1, and umask 0007 — so the
       socket kidulwm binds lands 0770 :seat (connect() needs WRITE on the
       socket file, not just a traversable dir).
     - kidulwm: NO change — KIDULWM_WAYLAND_DISPLAY already routes addSocket to
       the absolute path (server.zig start()); addSocketAuto is skipped.
     - Session-service sockets (kmedia ksound.sock, kplay.sock, klip.sock —
       today hardcoded /run/user/<uid>/*.sock) follow the same shared-dir +
       absolute-path pattern. Wayland FIRST (the re-seat blocker); the rest
       follow, not block.
     - GATE: cold boot, face up, ktty types, media plays — all through the
       shared-dir absolute socket, zero visible change.

  2. THE CONDUCTOR ACCOUNT (the boot refactor — "face never dies" foundation).
     DONE + PROVEN (kushd 7ac1efe). kushd gains a "conductor" class: isKnownClass
     + applyClass (dropToUid(conductorUid())) + mintSession(uid, conductor) that
     skips "audio". conductorUid() = KUSH_CONDUCTOR_UID -> /etc/kushd/conductor
     -> 990 (ruling B). kidulwm seats as conductor 990 with supplementary groups
     {render video input seat tty} (NO audio, no user group); 0700 homes block it
     (data-blind). public (1001) returns to a plain TENTACLE identity —
     browser/ktty/kfiles seat as 1001; the face does not. Proven on-host: kidulwm
     seated as uid 990, groups exactly {input render seat tty video}, socket 0770
     conductor:seat, real compositor (uid 1000) untouched.
     - PROVISIONING (rootfs build, alongside owner 1002): conductor uid 990 needs
       its OWN primary group (gid 990), NOT a device group (host had gid 990 =
       "kvm" — a collision the KSD rootfs must not repeat); home /nonexistent or
       0700-empty (data-blind); binary at /usr/local/bin (world-traversable — a
       user-home path is 0700 and the conductor cannot exec from it).
     - bill.kush: kidulwm's act class "user" -> "conductor".
     - GATE: cold boot, face up as conductor uid; ktty + browser still work as
       public; face renders but cannot read /home/* (0700 + no user group).

  3. THE ENTRY SLIDE (the visible surface — freeze, not kill).
     - FREEZE/THAW VERB (kushd) DONE + PROVEN (c0b9289): cue "freeze" ->
       SIGSTOP, "thaw" -> SIGCONT, targeting ONLY the data tentacles (class
       "user"/"restricted"). The face (conductor) + organs (system/service:
       ksound/kplayd) are spared. Proven on-host: freeze stopped a user act to
       T state while conductor + system acts stayed S; thaw resumed it. This is
       the mechanism; the surface below wires to it.
     - The Homes sign-in prompt gains FREEZE-ON-FOCUS: entering "tap your
       kidulKey" fires the freeze cue (kushd SIGSTOPs the tentacle pids it
       seats; face + audio survive). Narrow and deliberate — not the
       park/resume four-step (session-and-deck-spec.md), just the freeze.
     - FROZEN-FRAME BACKDROP: the face composites the frozen tentacles' last
       frame (dimmed) as the slide background; LOGO + "tap your kidulKey"
       overlaid live (the face is the conductor and never freezes).
     - PRIVACY GUARD: public->owner keeps the frozen frame (public = no
       personal data); LOCK or owner RE-AUTH blanks/blurs instead of
       snapshotting — a sensitive owner frame never persists as a backdrop.
     - GATE: enter sign-in -> tentacles frozen (ps shows T state), last frame
       stays on screen, prompt overlaid; tap -> proof -> resume.

  4. KEY-ID -> HOME-HASH RESOLUTION.
     - roster (kpax) maps key -> role; kalloc maps key -> partition. The mount
       target (pw_dir) needs key -> uid (or kalloc extended to carry home-hash).
       Owner = fixed uid 1002 (PRE-PROVISIONED: home-hash bee62e237cdd37a455eeafca).
     - GATE: proof -> kushd resolves the proved key-id to uid + home-hash.

  5. MOUNT-POINT CORRECTION.
     - kmount mounts /home/<key-id> today (built b4ff2db); it must mount
       /home/<home-hash> (pw_dir). A correction to already-built code, not a
       new design. The map/sig/pub it already receives carries the key-id; the
       resolution (step 4) supplies the home-hash.
     - GATE: proof -> mount lands at /home/<home-hash>, never /home/<key-id>.

  6. THE RE-MINT WIRING (the flip — this IS the re-seat).
     - On TRUSTED proof: kushd re-mints the USER identity public(1001) -> the
       proved uid (mintSession with the proved uid, NOT seatUid()); the FROZEN
       public data tentacles are REPLACED by owner-uid processes in the SAME
       slot (surface-in-place, process-re-seats — a running process cannot
       change uid, so the process swaps, the surface does not). The face never
       re-mints; audio keeps playing.
     - SELF-DISMANTLING TEARDOWN (same cue): the frozen public tentacles are
       REPLACED (not unfrozen-and-kept); kclose + kclean + kushd reap the
       transition state (gate verdict, keyfile, LUKS mapping) ASAP — nothing
       lingers that could later control the deck the way the media player did.
     - GATE: sign-in -> owner session in the same slot; the last frame never
       left the screen; the face pid + uid never changed; no lingering
       transition state (kclose/kclean/kushd all fired).

  Order note (SPEC BEFORE SURFACE): 1-2 are the infrastructure the surface
  stands on, 3 is the visible freeze, 4-6 are the resolution/mount/mint the
  freeze guards. Build 1 -> 2 -> 3 -> 4 -> 5 -> 6; each lands green first.

## done-when

  - A tap on the Homes sign-in freezes the data tentacles (SIGSTOP), holds the
    last frame as a dimmed backdrop with "tap your kidulKey" overlaid, then
    proof -> re-mint -> mount swaps the owner session into the SAME slot with
    no blink — the face's pid/uid never moved.
  - The Wayland socket lives in /run/kushd/wayland (0770 group seat), referenced
    by an ABSOLUTE path in WAYLAND_DISPLAY, and the face (conductor uid) serves
    tentacles (public/owner uids) across the boundary.
  - kmount mounts at /home/<home-hash> (pw_dir), never /home/<key-id>.
  - No password field, no sudo binary anywhere in the path.

## Locked rulings (Barticus 2026-11-18, GSI — "yes to your recs")

  A. SEQUENCING: FOUNDATION-FIRST — socket convention (1) + conductor account (2)
     BEFORE the entry slide, because the re-mint (6) is impossible while the face
     IS uid 1001. [Barticus: yes]
  B. CONDUCTOR UID: 990, name "conductor", groups {render video input seat tty}
     only — no audio, no user group, no home (/var/lib/kidulwm). [Barticus: yes]
  C. ENTRY SLIDE = the Homes slide UPGRADED (kind .homes gains freeze-on-focus),
     not a new slide kind. [Barticus: yes]
  D. SOCKET DIR: /run/kushd/wayland, root:seat 0770, recreated by kushd at boot
     (tmpfs). [Barticus: yes]

  Plus the steer (Barticus 2026-11-18, GSI): the re-seat is MEANT TO TAKE OVER —
  controlling by design, every detail CFC'd for Granny — but must NOT become a
  media-player-style roach. The guard is SELF-DISMANTLING: kclose + kclean + kushd
  fire to get it OUT ASAP, no lingering controlling state. Locked into re-seat.md
  v3 + settings.md (amended). See step 6.

## What this does NOT touch

  - The mount VERBS (kopen/kmount/kumount/kclose/kclean/kcarve) — built +
    proven; only the mount POINT (step 5) changes.
  - kboot — stays ~100 lines, sleeps after boot. The conductor uid is a kushd
    seating change, not a kboot change.
  - The Homes slide's door flow (Residents/KidulCrew, two doors) — the freeze
    attaches to the existing sign-in prompt; the flow itself is unchanged.
  - claim/carve + the Homes provisioning UI (fill bar + name) + defaultHome
    skeleton — the slices AFTER this one (settings.md steps 5-6).

## Open (non-blocking, for later)

  - kushd self-trim (re-seat-mount.draft.md step 5) — trim kushd's own bounding
    set so it cannot mount/reboot by accident.
  - park/resume (the key-out session battery, session-and-deck-spec.md) — this
    slice's freeze is the sign-in transition only; park-and-switch is its own
    later cut.
  - The browser credential-flow picker (one key, many per-site identities) —
    carried note, folds into the browser slice.
