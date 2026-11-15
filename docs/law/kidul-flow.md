# LAW — the Kidul Flow (one navigation model, root to leaf)

LOCKED 2026-11-14, Barticus present, GSI. The whole system is a TREE with one
navigation law; no modes, no per-app exceptions to the direction meanings.

## The tree (root → leaf)

  Home screen   the system home — "Kidul TV" CFC'd, the four widgets, navDots.
                The boot root: the compositor lands here, NOT on the GPB.
    ↓   down opens the GPB
  GPB           the user's home — the GlobalPillsBar, the apps menu. "Just the bar."
    ↓   down opens the focused app
  App           content
    ↑   up returns to the GPB · ↑ at the GPB returns to the Home screen

## The verbs (hard stops, no cycling)

  ↑     shallower — one level up the tree
  ↓     deeper — one level down the tree
  ←→    siblings — one step sideways at the current level
  Enter apply / open (enter a focused widget, open a focused app)
  TL    (top-left diagonal) the HOME button = the user's home = the GPB.
        Express jump from any depth.
  TR    (top-right diagonal) QUIT = ctrl+Q — quit everything → the Home screen
        ("our home").
  Esc   cancel

## Two homes

  the user's home = the GPB (the apps menu) — reached by TL (home), or ↓ from Home
  the system home ("our home") = the Home screen (Kidul TV + widgets) — reached by
                    TR (quit), or ↑ from the GPB

  "home" on the remote = TL = the GPB. "quit" = TR = the Home screen. Two buttons,
  two meanings: home is "my apps", quit is "the system landing".

## The Kidul TV mark

  The "Kidul TV" title (landing.md) doubles as the Home screen's CFC'd mark.
  Opening the GPB moves it up to the top 1/3 — the title above the GPB. One mark,
  one motion. Naming (naming.md) is unchanged: RatuKidulTech / Kidul Systems /
  Kidul Works all keep their place; "Kidul TV" is the device name.

## The widgets (on the Home screen)

  [Weather]          [Network]
                     [Clock]
                     [Calendar]

  ←→  Weather ↔ Calendar
  ↑↓  Calendar → Clock → Network
  Focused widget = white. Enter = enter the focused widget.

## The empty-slides are the Home screen

  The empty-slides at the left/right of every row ARE the Home screen. The peeks
  are retired; their job (show what's to each side) moves to navDots — dots on
  the filter layer, coded per side (slide count). Inter-app navigation stays
  per-app. BobsBalls fill the empty-slides' visual space.

## The deck

  The deck (slides side-by-side) is keyboard/mouse only. The remote never walks
  the deck — it uses the flow (home + dive). navDots show the slide counts to
  each side, in place of the retired peeks.

## Relationship to existing law

  environment.md  the GPB is no longer autostarted at boot; the Home screen is the
                  boot root and the GPB is summoned (↓/TL). "up ALWAYS = home"
                  refines to "up = one level shallower, all the way to the Home
                  screen".
  landing.md      "Kidul TV" stays; it doubles as the Home screen's CFC'd mark.
  kidul-remote    the remote collapses to arrows + enter + TL + TR + dial; the
                  second D-pad and the deck walk are retired.
