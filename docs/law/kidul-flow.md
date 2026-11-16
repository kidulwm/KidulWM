# LAW — the Kidul Flow (one navigation model, three layers, three homes)

LOCKED 2026-11-14, Barticus present, GSI. The whole system is a TREE with one
navigation law; no modes, no per-app exceptions to the direction meanings.

## The three layers (Z-order)

  background   the bottom layer (wallpaper, ambient colour)
  SlideDeck    the slide layer — every surface is a slide in the deck
  Top layer    the compositor's top-most Z-layer — the Kidul TV mark + the widget
               faces + navDots. Never a slide; always above the deck. The word
               "top" now means ONLY this layer: the home screen is KidulHome (not
               "the top"), and "the top of the deck" is a position, not a layer.

## The three homes (the tree)

  KidulHome    the system home ("our home"), the boot root — "Kidul TV" CFC'd +
               the widget faces + navDots, drawn on the Top layer.
  UserHome     the user's home — the apps list (the pill bar). "My apps." Generic:
               one concept, many users. publicHome (the public seat — a
               restricted, "useless & harmless by design" account) and bartsHome
               are instances of it, not a separate kind of bar.
  AppHome      each app's own landing — its CFC'd top bar. Every app opens AT its
               AppHome and navigates DOWN from there.

  KidulHome → (↓) UserHome → (↓) AppHome → (↓) content
                (↑)           (↑)          (↑)

  The "up+1 / up+2 / the top / the bar / app top" vocabulary is RETIRED. Three
  homes, named by what they are: Kidul / User / App.

  "GlobalPillsBar" ("gpb") is NOT retired — it stays as the COMPONENT name for
  the pill bar that UserHome draws, to distinguish it from the library pill bar,
  the browser hybrid search bar, and the other bars. UserHome = the slide name;
  GlobalPillsBar = the bar itself.

## UserHome focus (session state)

  Public = fresh every use: UserHome opens focused on Library (the centred
  landing pill). The TV always lands Library; the PC keeps persistent history
  later (resume the last-used app). ↑ back from an app returns focus to the
  app you just left — the focused pill never resets while you navigate within
  a session (the `focused` field holds it). Sign in / out lives on the kidulKey
  pill (the key experience — environment.md).

## The verbs (hard stops, no cycling)

  ↑     shallower — one level up the tree
  ↓     deeper — one level down the tree
  ←→    siblings — one step sideways at the current level
  Enter apply / open (enter a focused widget, open a focused app)
  TL    (top-left diagonal) the HOME button = the user's home = UserHome.
        Express jump from any depth.
  TR    (top-right diagonal) QUIT = ctrl+Q — quit everything → KidulHome.
  Esc   cancel

  One "home" button (TL → UserHome) and one "quit" (TR → KidulHome). AppHome has
  no button of its own — it is the ↓ from UserHome.

## The Kidul TV mark

  The "Kidul TV" title (landing.md) doubles as KidulHome's CFC'd mark, drawn on
  the Top layer. Opening UserHome moves it up to the top 1/3 — the title above
  the apps list. One mark, one motion. Naming (naming.md) unchanged: RatuKidulTech
  / Kidul Systems / Kidul Works all keep their place.

## The widgets — faces on the Top layer, apps in the deck

  [Weather]          [Network]
                     [Time]

  ←→  Weather ↔ Time
  ↑↓  Network ↔ Time
  Focused widget = white. Enter = enter the focused widget.
  MUCH LARGER than today, same sides (weather left, network/time right),
  up top around the Kidul TV CFC.

  Time is ONE app — the clock (time of day) + the calendar (place in the
  historical time line) + alarms + appointments. The face shows the time/date;
  pressing it opens the app as a normal slide.

  A widget is a FACE + an APP, never an always-on gauge:
    the FACE  = compositor-painted on the Top layer — a live, dumb shortcut ("just
                a keycombo that looks pretty").
    the APP   = a normal slide, spawned when you press the face. The face is
                forgotten once the slide opens — the widget was never a card.
  The face's data is BACKEND-fed, never compositor-owned. A backend polls a source
  (weather = a website every so often; clock/calendar = the host clock/date;
  beacon = knetd), writes the result to a state file (the ksignals pattern,
  /tmp/kidul-signals/*.detail), and the compositor reads it and re-paints the face
  on change (a state_generation bump). The backend never touches pixels — it writes
  state, the Top layer paints.
  Everything inside is a .md file (appointments, reminders, etc.) that Bob
  manipulates on request or the user edits in-app. The beacon/signals open the
  Settings app (a later slice) — signals are part of it, not a separate face.

## The empty-slides are KidulHome

  The empty-slides at the left/right of every row ARE KidulHome. The peeks are
  retired; their job (show what's to each side) moves to navDots — dots on the
  Top layer, coded per side (slide count). Inter-app navigation stays per-app.
  BobsBalls fill the empty-slides' visual space.

## The deck

  The deck (slides side-by-side) is keyboard/mouse only. The remote never walks
  the deck — it uses the flow (home + dive). navDots show the slide counts to
  each side, in place of the retired peeks.

## Relationship to existing law

  environment.md  UserHome is no longer autostarted at boot; KidulHome is the boot
                  root and UserHome is summoned (↓/TL). "up ALWAYS = home" refines
                  to "up = one level shallower, all the way to KidulHome".
  landing.md      "Kidul TV" stays; it doubles as KidulHome's CFC'd mark.
  kidul-remote    the remote collapses to arrows + enter + TL + TR + dial; the
                  second D-pad and the deck walk are retired.
  naming.md       three names (RatuKidulTech / Kidul Systems / Kidul Works) unchanged.
                  The "top" vocabulary (up+1 / up+2 / app top / the top) retires in
                  favour of KidulHome / UserHome / AppHome.
