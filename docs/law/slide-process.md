# LAW — an APP owns its CONTENT; the WM owns the WINDOW; a SLIDE is a PLACEMENT

Status: LOCKED 2026-10-14 by Barticus ("yes yes yes gsi"). Drafted 2026-10-13 by
bobdotrix after a live census of every running process and both repos. This is
the "mother roach" Barticus named: internal vs external control of a slide was
never separated — because "app" and "slide" had been smeared into one axis.

Companion: GLOSSARY.md (the words), theatre.md (the tier stack), starship.md
(the ship), kplay.md (one owner per truth), separation.md (kfiles = placecard,
kmedia owns the media model). This law names the PROCESS boundary those four
laws imply but never drew.

---

## ⛔ FORBIDDEN LAYER — read before ANY media work (added 2026-10-25 after the fork incident)

The media player is a STANDALONE APP (the kmedia client: kmedia/src/Wall.zig +
Expansion.zig), seated by kushd. There is NO embedded player.

- NEVER build media FEATURES into kidulwm/src/ui/media.zig or media_slide.zig.
  That is the embedded layer C2 bypassed and C5 deletes. Work there is
  wrong-layer and discarded. (Incident: seasons/grouping/CFC/digit-jump built
  into embedded media.zig on the `_deploy_quitfix` fork — archived at tag
  `archive/seasons-in-mediazig-2026-10-25`, never merged.)
- All media CONTENT work (wall, seasons, categories, art, watch-state) goes into
  the kmedia repo. The WM's media card only spawns /usr/local/bin/kmedia; it
  does not render media.
- BRANCH DISCIPLINE: feature work lands on `main`. Never build onto a stale fork
  of origin/main. media.zig on `main` is FROZEN (bypassed) only until the kmedia
  client's Wall filters by category; it then gets swept per C5.
- GATING: pure KSD (kmedia seated, media.zig gone) is blocked on kushd, proven on
  the miniPC. Do not convert the host until a full copy of the brain + repos +
  profile is verified on the miniPC.

---

## The sentence

An APP is a PROCESS that paints a full-screen SURFACE. The WM owns the WINDOW
(where it sits, how big, focus, z-order). The app owns its CONTENT (its model +
state + presentation — what it shows, what it means). The WM never reaches
inside an app; an app never manages a window. SLIDE, PEEK, and FULLSCREEN are
PLACEMENTS the system decides — the app has no say and no knowledge of them.
Playback is a THIRD thing (kplayd), asked for over a socket, never owned by
either.

## The finding (why this law now — the live census, 2026-10-13)

Three of our apps are separate Wayland client processes: the browser, kfiles,
the office. They are normal apps — the WM seats their window and touches
nothing else.

The media player is the ONE anomaly. It is a COMPOSITOR-OWNED scene tree
(kidulwm/src/ui/media_slide.zig: "compositor-owned media player slide"), not a
separate process. Its entire CONTENT (model + state) is compiled INTO the WM:

  kidulwm/src/ui/media.zig  scanCategory()   — shells `find -L "<root> -iname
                                               '*.mkv' | sort | head -1024` at
                                               boot (prewarmThread) to build the
                                               library. The WM scans the drive.
  kidulwm/src/ui/media.zig  g_music/g_movies/g_tv  — the library lives in WM
                                               globals.
  kidulwm/src/ui/media.zig  ArtPipeline      — art resolution inside the WM.
  kidulwm/src/ui/media.zig  watch-state      — resume/next-unwatched in the WM.

And there is a SECOND, parallel copy of the model: the kmedia repo's Scanner.zig
+ Library + WatchState + Wall + Expansion — the real "kmedia owns the media
model" from separation.md — which sits RETIRED in a standalone app (App.zig)
that still carries an embedded Player (Player.init / Player.open) and is not
running.

So the roach is twofold, and they are the same mistake twice:

  1. The media MODEL is duplicated: once live in the WM (media.zig), once dead
     in kmedia (Scanner.zig). Two copies of the model, no owner.
  2. The live copy lives in the WRONG process: the conductor (kidulwm) does the
     APP's job (scan + art + watch-state), which theatre.md already forbids
     ("CONDUCTOR owns the PIXEL map ... never DECIDES").

That is why the media player "does not act like a slide" and "has a weird hold
over other apps": it is not an app being placed. It is part of the WM, so it
quits after the WM has already torn the other apps down, and it cannot flow in
the deck like a foreign client because it has no foreign client.

## The split (four processes, one job each)

  kidulwm   CONDUCTOR (the WM). Pixels only. Owns the WINDOW map: geometry,
            focus, z-order, the deck, peeks, overview, chrome. Seats foreign
            client windows. Reaches inside NOTHING. Knows nothing about media
            files, art, or resume positions.

  kmedia    THE MEDIA PLAYER (a normal Wayland client process, like the browser
            and kfiles). Owns its CONTENT: the list of files, the presentation
            (wall / pills / subcategories / cards / search), and the MODEL +
            STATE — by linking libkmedia (Scanner, Library, WatchState, art
            chain). Disk is truth; the cache is a view (no-server.md +
            library-model.md stand). It is NOT a server and NOT a daemon: it is
            a client app, exactly as port-mapping.md ruled ("library, not app,
            not daemon").

  kplayd    PLAYBACK (a resident daemon, kplay.sock). Demux, decode, the one
            clock, the video surface. kmedia hands it a path ONLY when the user
            hits play. One player, all media (kplay.md LAW 2).

  kushd     USHER (lifecycle, resident daemon). Seats and unseats the other
            three. Built and installed today, NOT running — which is the other
            half of the roach: with no usher seated, kidulwm absorbed lifecycle
            work by hand, so the conductor grew a model of its own.

Body daemons ksound and knetd are already clean and do not move.

## The seams (who asks whom, over what)

  kmedia  → kidulwm    Wayland (a foreign client like the browser/kfiles).
                       The WM seats the window; the app paints its own surface.
  kmedia  → kplayd     kplay.sock  (open / close / pause / stop / seek).
                       Fired ONLY on play; the list never touches kplayd.
  kmedia  → kushd      a seating request (when kushd is live): "seat me as a
                       media app." kushd decides; kidulwm consumes.
  kushd   → all        lifecycle: seat/unseat, restart-on-death, one log.

No new authority, no new daemon beyond kushd (already built). kmedia becomes a
client process; the model + state is a LIBRARY inside it, not a server.

## What moves out of the WM

  FROM kidulwm/src/ui/media.zig  →  kmedia process (via libkmedia):
    - scanCategory / prewarmThread / the g_* library globals
    - ArtPipeline (art resolution)
    - watch-state read/write
    - the subcategory/search/selection state machine (the app's CONTENT)
  STAYS in kidulwm:
    - the WINDOW map: deck position, focus, z-order, peeks, overview, chrome
    - the fullscreen MODE (fullscreen.md: fullscreen is a mode the card enters,
      not a position) — but now the card is kmedia's client surface, so the WM
      composites it, it does not render it.
  DELETED:
    - kmedia/src/App.zig embedded Player (Player.init / Player.open) — the dead
      shell. libkmedia keeps the engine; App.zig dies; kmedia becomes a client.
    - the compositor-owned scene tree path for media (media_slide.zig render-to-
      buffer) — kmedia draws its own surface like the browser does.

## Migration cards (prove in VM before host, per KSD doctrine)

  C1  extract: pull Scanner/Library/WatchState/art out of media.zig into
      libkmedia (the kmedia repo already has these — reconcile the two copies
      of the model to ONE, then delete the WM's copy).
  C2  client-ify: make kmedia a standalone Wayland client (foreign surface,
      xdg-toplevel), no compositor scene tree, no render-to-buffer.
  C3  seat: kushd seats kmedia as a normal app; kidulwm composites its window
      like the browser. Fullscreen becomes a mode over kmedia's surface.
  C4  hand-off: kmedia → kplayd over kplay.sock on play; the list/art/watch-
      state never leave kmedia.
  C5  delete the dead shell: kmedia/App.zig embedded Player and the WM's
      media.zig model/state both go. One model, one window, one player.

## The internal/external law (what to check when an app misbehaves)

  - "won't sit / focus wrong / z-order"          → WM (window, external).
  - "wrong list / wrong art / wrong resume"      → kmedia model/state (content,
                                                   internal).
  - "stutter / sync / no sound"                  → kplayd (playback).
  - "who is even running"                        → kushd (lifecycle).

A symptom with no clear owner means a boundary was crossed — find the process
that reached where it does not belong and move it back. (Same move theatre.md
makes: delete the second owner.)

## Why this helps future developers (the blocks)

Every process above is a KNOWN BLOCK with a known shape. A new dev can open any
one and see "this is a client, it links a library and asks a daemon" — never a
grab-bag. The block vocabulary is frozen in GLOSSARY.md and ksd-vocabulary-law
(apps vs placements), cells/brigs/planks (cells.md), seat grades bridge/
wardroom/deck/quarters/brig (starship.md). This law adds the PROCESS block:
conductor / client / player / usher, four shapes, and the rule that none of them
reaches into the others.
