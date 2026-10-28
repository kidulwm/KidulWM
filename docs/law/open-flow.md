# LAW — the open flow (RIGHT flows in, LEFT backs out, Enter acts)

LOCKED 2026-10-28, Barticus present.

Lane: kfiles (navigation + the tools drawer).
Related: input law (↑↓ focus, ←→ move, Enter apply, Esc back — this law is the kfiles
instantiation), theme (colour = meaning), #45 Smart Tools (per-type action table),
#44 (REVISED: the open gesture moves from Enter to RIGHT).

## Problem

"Enter to open" made Enter do two jobs at once — navigate (open the viewer) AND act
(fire a tool). Blurring them means a stray Enter opens things without intent, and it
put the "open" on the wrong key. Separately, the per-type drawer risked cluttering: a
.mp3 showing Play/Open/Open In…/Edit/… when all Granny wants is Play.

## Concept — the open is a FLOW, not a verb

RIGHT flows you INTO a thing; LEFT backs you OUT; Enter only ever ACTS. Opening a file
is navigation (RIGHT), never a command (Enter). What RIGHT flows into is decided by the
file's class:

  FOLDER     → navigate in (the list).
  IMAGE      → the in-app viewer (the image IS the open state — nothing to "do" but see it).
  NON-IMAGE  → the tools drawer (the options ARE the open state — Play/Open/Install first).

Enter is reserved for ACTION — firing the focused tool, confirming a move/copy place.
Nothing executes on RIGHT; only Enter (or green/red) commits. That is the consent gate.

## The law (properties)

1. RIGHT = FLOW IN. LEFT = BACK OUT (permanent). UP/DOWN = focus. ENTER = act on the
   focused thing — from the MAIN STAGE, Enter opens the focused file's TOOLS drawer
   (the geek's "I know exactly what I want to move/copy" shortcut, skipping the flow);
   inside the drawer, Enter FIRES the focused tool.
2. IMAGE OPENS IN-APP. The only class whose open state lives in kfiles is the image
   (the viewer). RIGHT goes straight there — in-app, reversible, non-destructive.
3. EVERYTHING ELSE OPENS IN THE DRAWER. Any file whose open state is ANOTHER app
   (kmedia / editor) or a SYSTEM act (install) — RIGHT opens the drawer with the
   primary action first, and Enter fires it. One press to see, one press to cross the
   boundary.
4. OUR APPS FIRST, NO CLUTTER. When we own the app for a type (image -> viewer,
   video/audio -> kmedia, text -> our terminal, package -> kushd install), the drawer
   shows ONE verb (Play or Open) and nothing else. "Open In…" appears only where there
   is a REAL choice (a non-default program). Remove clutter everywhere we can.
5. PLAY vs OPEN. media (video/audio) = "Play" (kmedia). text/docs = "Open" (the default
   terminal, a setting). image needs no "Open" verb (RIGHT already opened it) — its
   drawer carries "Play" (the slow-loop) + owner tools.
6. ONE TRUTH, TWO ZOOMS. Industry standard = the file's behaviour (a .deb installs, an
   .mp3 plays). Granny's view is a ZOOM of the same table (primary only), never a
   parallel fiction.

## Rulings (this lock)

- Q.A  RIGHT flows, Enter acts. REVERSES #44's "Enter (short) image -> viewer" — the
       viewer opens on RIGHT from the main stage, LEFT backs out. (Barticus.)
- Q.B  video/audio open in kmedia via the drawer ("Play"), never in the kfiles viewer.
- Q.C  Applications = B (modular): one seating chart from kushd, two views (home grid
       + a kfiles "Applications" folder). No second launcher. (Barticus.)
- Q.D  KISS but fully featured: the primary tier is one verb; owner CRUD + Archive▾
       live lower / behind "More…".
- Q.E  Enter from the main stage opens the tools drawer (the geek's shortcut to act,
       skipping the flow). Granny never needs it — she reaches the same tools at the
       hard stop after a full viewing. (Barticus, 2026-10-28.)
