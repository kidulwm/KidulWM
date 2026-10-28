# LAW — move/copy (the LIFT: a file in hand, orange until it finds a home)

LOCKED 2026-10-28, Barticus present.

Lane: kfiles (the tool drawer).
Related: theme (orange = warning, red = critical — a NEW token), input-trust /
input law (arrows nav, Enter commits), landing + chrome (corner language:
chamfer = framing, round = interactive).

## Problem

Move and Copy are the two destructive two-location verbs, and kidulFlow is a
single linear walk. Three wrong shapes were on the table:

- DUAL-PANE (source left / destination right): two CFC anchors at once — the
  developer-tool energy the placecard was built to kill, and Granny can't hold
  two contexts.
- INSTANT COMMIT (verb fires on Enter immediately): a stuck key or a wrong tap
  executes a move with no consent gate — the exact "takes you away without
  consent" bug the viewer hard-stop already killed.
- A NEW floating panel / top strip: adds chrome that re-explains what is already
  on screen.

## Concept — the LIFT

Choosing Move or Copy does NOTHING to the file. It LIFTS the file "into hand."
The placecard that already shows the file — the right third, card + date/type/
size — is told to HOLD: it freezes on the source, wrapped in warning orange, and
stops mirroring the list cursor. The rest of kfiles stays fully live as the
DESTINATION browser. The user walks the whole app (Drives, Home, folders) to the
new home, then places or drops. The subject is visible the entire time; nothing
happens until the consent key.

## The states

LIFTED (orange): right third frozen on the source — warning-orange CHAMFER border
  + a one-word mark ("Moving" / "Copying") under the card. Border = "this zone",
  word = "this is why" (colour alone flags; Granny needs the WHY). The card
  DECOUPLES from the list cursor for the duration of the lift. Drives/Home/
  Settings stay navable — the destination may be another drive. Depth-gauge dots
  = destination path; centre list = destination contents; frozen card = what is
  in hand.

COLLISION (red): placing into a folder that already holds the same name escalates
  orange -> RED and takes over the centre stage: a red border + CFC'd text Granny
  can read from the lounge ("A file named X is already here — Enter to replace,
  Esc to go back"). Enter = overwrite, Esc = return to LIFTED (un-placed).

DONE: green placed the file (Move removes the source; Copy keeps it) or red/Esc
  dropped it (source untouched). The right third un-freezes and resumes mirroring
  the focused row.

## The verbs (two, on three surfaces)

  GREEN  = place into the CURRENT folder    (Enter · remote green · green pill)
  RED    = drop / cancel                    (Esc   · remote red   · red pill)

During the LIFT, Esc means CANCEL — never "up a folder" (up is Left/BackSpace,
the kfiles-native back-out), so the two are never confused.

## The law (properties)

1. LIFT IS NON-DESTRUCTIVE. Move/Copy changes nothing until green. No consent,
   no write.
2. THE SUBJECT STAYS VISIBLE. The frozen placecard keeps the file on screen from
   lift to place/drop. You can't act on what you can't see.
3. ARROWS NAV, ENTER COMMITS. Arrows walk the destination and never cross the
   app boundary (input law); Enter/green is the only place, Esc/red the only drop.
4. ORANGE = WARNING, RED = CRITICAL (colour = meaning, hue escalates). Lift =
   orange #d9722e (theme slot 2). Collision = RED — a NEW critical token, the
   escalation above orange, to be added to the theme law.
5. NO TOP-PILL LOCK. Drives/Home/Settings stay live during the lift (Barticus,
   2026-10-28: "you may want to move from one drive to the next"). The whole
   kfiles walk is the destination browser.
6. DATE FREEZES WITH THE SUBJECT. The frozen card shows the source's current
   date; mtime/ctime update only on execute.

## Rulings (this lock)

- Q.A  the right-third freeze is a FULL freeze (card + date/type/size), not just
       the image — the details describe the SOURCE and freeze with it. (Barticus.)
- Q.B  the right third is the "nice to have" visual, NOT the path — the path is
       the depth-gauge dots (parents) + CFC'd current folder. Freezing it loses
       nothing. (Barticus.)
- Q.C  collision escalates to RED + a CFC'd centre-stage takeover, not a small
       toast. "NOT too bright" — muted red border, CFC'd text. (Barticus.)
- Q.D  border + word-mark over a sash: cleanest, colour + one word carries the
       why. (Barticus gsi.)

## Reversals

- Reverses the (unbuilt) idea of locking the top pill during the lift.
- Reverses "Move/Copy = instant action": they become lift verbs, place-on-consent.

## Open (build-time, not blocking)

- The collision "keep both" alternative (Enter overwrites / Esc back, vs a third
  "keep both" option) — the red takeover is frozen; the exact CFC'd wording and
  the keep-both branch are build + harness detail.
- Exact pill placement (bottom of the frozen card vs the bottom hard-stop zone) —
  build detail; the two-verb three-surface law is fixed.
