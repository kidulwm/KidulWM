# DESIGN DRAFT — surface + flow polish (eyes-verify of re-seat slice 3)

Status: DRAFT (bobdotrix 2026-11-18) — captured from Barticus's eyes-verify of the
re-seat entry slide (slice 3, built kidulwm 9900812). NOT law — design inputs
awaiting Barticus's lock on return. The slice 3 mechanism is VERIFIED WORKING
(smooth freeze/dim in-out, no jank, "walks the app as it should"); this draft is
the surface polish + a repurpose of the dim + a new flow. None of it blocks the
re-seat wiring (steps 4-6); it is a parallel surface lane.

## What Barticus confirmed working (the important parts)

  - The entry slide freeze/dim goes in and out smoothly — no hang, no jank.
  - The sign-in flow "walks the app just as it should".
  - "Ready to wire up" — steps 4-6 (key->home-hash resolution, kmount
    mount-point correction, re-mint) can proceed on the proven slices 1-3.

## 1. FADE-TO-50% REPURPOSE -> the pillsBar-focus CFC treatment

The slice 3c dim (translucent-black, ~55%, 280ms smoothstep) is "too beautiful"
to spend only on the key prompt. REPURPOSE it as the GENERAL pillsBar-focus
treatment: when ANY pillsBar is in focus, fade the background to ~50% so the bar
pops and the CFC is emphasized. The canonical case is the kidulHome -> usersHome
transition — the fade shows off the pills bar and dims the background behind what
is meant to be focused.

  - This GENERALIZES slice 3c's dim from "Homes key prompt" to "any focused
    pillsBar". The curtainEnsure recipe (the house lights) is the mechanism.
  - Focus-driven (Barticus: "when any pillsBar is in focus -> fade").

## 2. ENTRY BAR (replaces the fade as the key-waiting indicator)

"Time to enter your key" should NOT be signalled by the fade. Instead an
entryBar that FILLS (progress), with "insert key" text inside, and bobs balls
(the dot-motif) doing a "waiting dance" along a line or circle — a live
"we are waiting for you to put in your key" affordance.

  - NEW surface for the Homes key prompt's waiting state (slice 3's one living
    element), replacing the fade-as-waiting.
  - Balls dance = animation; shape (line vs circle) = OPEN ("along a line or
    circle, something with your balls").
  - CFC'd like the rest: fill bar + text + balls.

## 3. ARROW-UP = QUIT (the kidulFlow)

The up arrow at the top of each app should QUIT the app: it goes back up into
the usersBar, and up again = kidulHome. appTop+up1 = usersHome, appTop+up2 =
kidulHome. This unifies the old "top+2" into the arrow flow and applies to ALL
apps (today Barticus had to quit the media player + Homes apps manually to get
back to the usersBar).

  - Replaces the current top+2 with the arrow flow; the arrows carry the flow.

## 4. SIZING

  - Pill text + pills too small -> bigger. "91% of the width will probably be OK".
  - Text OUTSIDE the pills is "miniature" (later job — "it's just a pic & some
    text").
  - The names text (sign-in / Homes app) is miniscule.

## 5. NAMING (later, non-important)

  - "Homes" button looks wrong (later, non-important job).
  - The sign-in / login app: "log in" / "Sign In" (fits alphabetical — Si after
    Se of Search) / "Crew" / "KidulCrew" — UNDECIDED.
  - "+VIP" -> "add user" (or "add user to system" / drive).

## 6. BUG

  - The key picture has a weird line off to the top right (a rendering artifact
    in the key-prompt graphic).

## klink

  - styles/pill-spec.md (THE PILL + CFC) — sizing + the CFC focus fade.
  - kidul-flow.md — the arrow-up quit flow (appTop+up1=usersHome, +up2=kidulHome).
  - re-seat-entry.draft.md (slice 3 surface) — the entryBar replaces the dim as
    the key-waiting indicator.
  - re-seat.md (law) — these adjust the entry-slide SURFACE, not the freeze /
    re-mint mechanism.

## done-when (this draft's scope)

  - The pillsBar-focus fade generalizes: any focused bar dims its background.
  - The key prompt shows a filling entryBar + "insert key" + dancing balls.
  - Arrow-up quits an app into usersBar; up again to kidulHome.
  - Pill text/pills resized (~91% width); names + outside-pill text resized
    (the latter is a later job).
  - Naming settled; the key-picture top-right line fixed.
