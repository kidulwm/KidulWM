# DESIGN DRAFT — privacy guard (BLUR on lock/re-auth; blank = fail-safe)

Status: DRAFT (bobdotrix 2026-11-23). Builds on re-seat.md (LOCKED
2026-11-17, 67202f5 + v2 + v3). The law is the contract; this file is the
BUILD ORDER for the privacy-guard HALF of the entry slide. Sibling to
re-seat-entry.draft.md (the entry-slide surface) — this slice is the
privacy-guard bullet of that draft's step 3, cut in isolation because the
conductor-reconnect probe (step 6b) had to land first and has now PASSED
(hardware, 2026-11-23).

## The locked architecture (already frozen — re-seat.md)

  - FREEZE-NOT-KILL: sign-in SIGSTOPs the data tentacles (only {face, audio}
    survive); the frozen tentacles' last frame stays on screen as the slide's
    BACKGROUND, dimmed for legibility; the face composites LOGO + "tap your
    kidulKey" over it.
  - "SNAPSHOT" == "FREEZE": a SIGSTOPped tentacle's last frame IS the frozen
    backdrop — no separate screenshot. The held frame is genuine because the
    face never freezes and keeps compositing.
  - PRIVACY GUARD (re-seat.md, LOCKED): "the frozen frame is the PRE-SIGN-IN
    frame. Public->owner: that is the public browser (no personal data — safe).
    LOCK or RE-AUTH from a signed-in owner: BLANK or BLUR the frame, never
    snapshot it — a sensitive owner frame must not persist as a visible
    backdrop." re-seat-entry.draft.md locks the detail further (Barticus
    2026-11-23, GSI): LOCK/re-auth BLURS — "heavy house-glass blur"; blank is
    the cheap FAIL-SAFE only. "Watch the blur's per-frame CPU/GPU cost as we
    build — it is the candidate for a LATER richer system-lock screen, NOT
    today (smartLock's blank is unchanged)."

## What exists today (the real seams this slice cuts)

  - kidulwm dim (re-seat slice 3, kidulwm 9900812): a fullscreen translucent
    BLACK overlay (DataBuffer 1x1 ARGB32 {0,0,0,140}, ~55% black) composited
    above the deck + peeks, below the signin prompt. Drives on freeze/thaw via
    setTentaclesFrozen (src/server.zig:2361) -> dimEnsure (:2410) ->
    tickDim (:2464) 280ms smoothstep. The dim is DARKENING ONLY — it does NOT
    blur; the frozen owner frame behind it stays sharp (a privacy leak: a
    confidential screen is still legible through 55% black).
  - Freeze trigger: homesSyncGate (src/server.zig:2291) fires setTentaclesFrozen
    on the signin bar's .prompt entry, thaws on exit. The freeze is a STATE
    (tentacles_frozen, server.zig:415), not a mode.
  - kushd re-seat: seq on mount success sets session_uid 0 -> proved uid
    (owner 1002); "already re-seated" guard skips a second proof. kushd KNOWS
    who is seated; kidulwm does NOT — the face is conductor 990 and never
    re-seats, so it cannot read its own uid to infer owner-vs-public.
  - The gate verdict (handleGateReadable, server.zig:2492) relays
    "TRUSTED role=<role>" per-tap; it is the PROOF result, not the STANDING
    seat state. No path today tells kidulwm "the seat is currently a signed-in
    owner, not public."
  - smartLock blanking (keybinds.zig BlankConf, server.zig:602) is a SEPARATE
    anti-burn blank — unchanged by this slice (locked).

## The two open decisions (resolve before code — see Open questions)

  1. WHO-IS-SEATED: kidulwm needs a standing signal "seat is owner vs public"
     to pick dim-vs-blur at freeze time.
  2. BLUR MECHANISM: wlroots 0.20 has NO built-in scene blur — a true
     house-glass blur needs a renderer shader pass, which is a new capability,
     not a color constant.

## Build order (mark each green before the next)

  1. THE SEAT-STATE SIGNAL (kushd -> kidulwm). kushd already owns session_uid;
     it must TELL kidulwm when the seat flips. Recommended (open Q A): on a
     successful re-seat (seq mount success), kushd writes a STATUS line to the
     cue socket ("seated role=<role>") and kidulwm stores a `seat_is_owner`
     flag (server.zig Server state). Fail-safe default = owner (blur) so a
     missing/unknown signal errs toward privacy, never toward leaking a frame.
     - GATE: after a re-seat on the tower, kidulwm's flag flips true; a cold
       boot (public) starts false; log line confirms the flip.

  2. THE GUARD STATE + DIM-VS-BLUR BRANCH (kidulwm). Add a guard selector to
     the freeze path: on .prompt entry, if seat_is_owner -> BLUR (or its
     fail-safe), else -> DIM (today's 55% black, unchanged for public->owner).
     Selected at freeze START and held until thaw — no live re-decision
     mid-freeze.
     - GATE: public->owner freeze still renders today's dim, byte-identical
       behaviour; owner lock/re-auth freeze takes the guard branch instead.

  3. THE BLUR (or fail-safe), per open Q B. The house-glass treatment, however
     B settles it. If B = true blur: a full-screen blur pass behind the dim
     (renderer shader); if B = layered frost: no shader, a stacked translucent
     overlay. Blank remains the fallback when the chosen blur is unavailable.
     - GATE: an owner frame through the guard is unreadable (blurred or blank),
       never sharp behind 55% black.

  4. COST PROOF (locked-in requirement). Measure the blur's per-frame cost on
     the TV panel (FRAMETRACE already logs per-source rates from handleFrame).
     If the blur pushes rendered/s or commit/s outside the house budget, fall
     back to blank and record the price as the reason — the ruling explicitly
     ranks "cheap + private" above "pretty + expensive".
     - GATE: FRAMETRACE shows the blur cost explicitly; a cost call (blur vs
       blank) is made and recorded in the census.

## done-when

  - Public->owner sign-in: the public frame dims (55%), exactly as today — no
    change, no regression.
  - Owner lock/re-auth: the sensitive frame is BLURRED (or blanked on cost
    fallback), never legible through the dim; no pixel snapshot persists.
  - smartLock blanking, the gate proof, and the re-seat flip are all untouched.

## Open questions (lettered, one recommendation each — "yes to your recs" locks)

  A. WHO-IS-SEATED SIGNAL. How does kidulwm learn the seat is owner (blur) vs
     public (dim)?
     REC(kushd status line on re-seat; fail-safe defaults to owner/blur) — kushd
     is I1 ONE SESSION AUTHORITY; it owns session_uid and already seeds/mints
     the seat. kidulwm should not re-derive identity from its own uid (it can't
     — conductor 990 never changes) nor infer it from a transient per-tap
     verdict. Alternative: seed the flag from the last gate verdict
     (weaker — dies on relog, no re-seat awareness).

  B. BLUR MECHANISM. wlroots 0.20 has no scene blur. Two honest options:
     B1. TRUE BLUR — a compositor shader pass (house-glass gaussian) behind the
         dim. Real effect, but a new renderer capability + real per-frame cost
         risk on the TV panel. REC(HOLD): this is the "later richer lock screen"
         candidate the ruling already parked.
     B2. LAYERED FROST — stack a few translucent scene buffers (no shader) to
         frost the frame while the dim does the heavy darkening. Cheap, shader-
         free, lands NOW. REC(BUILD): matches "heavy house-glass" closely enough
         at near-zero cost, keeps the slice green this session, and B1 stays a
         clean later upgrade without re-cutting the freeze path.
     In BOTH cases blank stays the fail-safe (B settles the default, not the
     floor).

## What this does NOT touch

  - The re-mint / mount / gate proof chain (kushd + kidulkey) — proven, done.
  - smartLock anti-burn blanking (keybinds BlankConf) — unchanged.
  - claim/carve, Homes provisioning UI, defaultHome skeleton — the slices after
    this one (settings.md steps 5-6).
  - The Sign In door flow (Residents/KidulCrew) — this attaches to the existing
    freeze branch only.

## Open (non-blocking, for later)

  - B1 true-blur as the richer system-lock screen (parked by the ruling).
  - park/resume (key-out session battery) — this slice's freeze is the sign-in
    transition only.
