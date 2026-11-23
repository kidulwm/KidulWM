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

  1. THE SEAT-STATE SIGNAL (kushd -> kidulwm). LOCKED + BUILT (2026-11-23,
     Barticus, GSI): NO new kushd verb — kidulwm reuses the crypto-gated
     "TRUSTED role=<r>" verdict it already receives on its own gate connection
     (unspoofable; the 0666 cue socket is not a trust boundary). kidulwm sets
     seat_signed_in=true once any verdict lands; monotonic per boot. Fail-safe
     posture: once personal data has appeared, every later freeze frosts.
     - GATE (verified): flag flips only in homesGateApply; cold boot starts
       false (public); no other writer.

  2. THE GUARD STATE + DIM-VS-BLUR BRANCH (kidulwm). LOCKED + BUILT: dimEnsure
     picks the black weight from seat_signed_in at freeze START — public 140
     (~55%, unchanged dim), signed-in 235 (~92% black frost, unreadable). Held
     until thaw, no live re-decision mid-freeze.
     - GATE (verified): public->owner freeze still renders today's dim; a
       signed-in lock/re-auth renders the frost.

  3. THE FROST (Q B settled). LOCKED + BUILT: BLACK frost, not white (off-theme;
     black fading in/out is the house specialty, least cost). One heavier black
     overlay — no shader, no layer stack (layered translucent black only adds
     darkening, not frost). Blank (255) remains the fail-safe floor.
     - GATE (verified): an owner frame through the guard is unreadable, never
       legible through 55% black.

  4. COST PROOF. The frost adds ZERO new per-frame cost (same 1x1 stretched
     buffer + 280ms smoothstep as the dim — only the alpha constant differs).
     True shader blur (B1) stays parked for the later richer lock screen.
     - GATE (verified): no new renderer path; FRAMETRACE unaffected by
       construction.

## done-when

  - Public->owner sign-in: the public frame dims (55%), exactly as today — no
    change, no regression.
  - Owner lock/re-auth: the sensitive frame is BLURRED (or blanked on cost
    fallback), never legible through the dim; no pixel snapshot persists.
  - smartLock blanking, the gate proof, and the re-seat flip are all untouched.

## Open questions — RESOLVED (Barticus 2026-11-23, GSI: "yes to your recs")

  A. WHO-IS-SEATED SIGNAL. RESOLVED: no new kushd verb — kidulwm reuses the
     crypto-gated TRUSTED verdict on its own gate connection. Security audit
     (bobdotrix 2026-11-23): kushd already OWNS the seat state (session_uid);
     the only new surface is disclosure, and a "seated role=" verb on the 0666
     cue socket would be spoofable by a public tentacle (uid 1001) to defeat
     the frost. The verdict-as-signal avoids that entirely — a third party
     cannot inject into kidulwm's established stream.

  B. BLUR MECHANISM. RESOLVED: BLACK frost now (B2), true shader blur held
     (B1) for the later richer lock screen. Frost = one heavier black overlay
     (235), shader-free, on-theme, zero new cost. Blank (255) stays the
     fail-safe floor either way.

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
