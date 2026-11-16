# LAW — settings architecture: Homes (immutable) vs Settings (transportable)

LOCKED 2026-11-16, Barticus present (GSI). AMENDED same day (Barticus): the
immutable entity is named HOMES, not "Admin" — the door that switches
publicHome -> privateHome, where the userHomes live. Supersedes the
key-entry.draft.md framing (folded below; the draft is marked superseded,
not deleted — archive).

## The split (the ruling)

Two settings surfaces, architecturally separated. They are NOT one app with an
admin corner; they are two entities.

  Homes      standalone, IMMUTABLE, root-owned, system-adherent. The door that
             switches publicHome -> privateHome (claim/sign-in,
             kidulkey-entry.md) and where the userHomes are managed: the
             user/kidulKey roster (People, delegation.md) + allocations. "Out
             of touch" by design: your identity + access layer is not a
             personal preference you edit. Opened by a KEYBIND (Mod4+T). This
             is THE WALL (#57) — docket #59 step (3).
  Settings   the user's PERSONAL, transportable surface — themes, brightness,
             presets. Travels with the user, never the machine. Per-app
             openings ("each app takes you to its part of the settings") + a
             Settings button on the non-public userHome. A LATER slice
             (kidul-flow.md: "Settings app (a later slice)").

## The naming (Homes vs Home vs userHome — the disambiguation)

  Homes      the entity: the door + the roster + the allocations. PLURAL — the
             place where the homes ARE, and the switch between them.
  Home       the deck / back-home navigation surface (back-home.md: "QUIT /
             HOME = reveal the deck"; kidul-flow.md). SINGULAR — where you are.
  userHome   a Linux home directory (/home/public, /home/$HASH — public-seat.md).

The kidulKey/People pill on the GPB is renamed Homes: it names the BEHAVIOR
(enter your home), not the hardware (the key). The key is the means; the home
is the end.

## Mod4+T = Homes (the keybind)

Mod4+t was the retired "tray toggle" — the old launcher that became the tray,
and the tray was designed out by the deck (Home). That code is dead; Mod4+T is
re-bound to open Homes. Keycombos are now SECONDARY to kidulFlow (arrow-down
into what you want) but stay available for testing and laptops — kidulFlow
reduces the need for them, it does not delete them.

## Sub-admin = the delegation tree (consolidation, not a new ruling)

The CEO / marketing-department model is EXACTLY delegation.md's grant tree:
owner = admin; each sub-user (a department) administers its OWN workers +
allocations; a creator grants only <= their own (attenuation). A sub-admin
allocates WITHIN the space the owner granted at creation (expandable on
request) — never more. Screens around the building all seat off the one
authoritative box (ktv native networking, machine-classes.md) — no
remote-desktop middleman. Nothing new: the ruling lives in delegation.md; the
Homes surface is where those verbs are CAST.

## Build order (the #57 slice, folded from key-entry.draft.md)

  1. KEYBIND -> HOMES SLIDE   re-bind Mod4+T (retire tray_toggle) to spawn a
     Homes slide (kind .slide, modeled on Library's spawn). Empty shell first:
     title "Homes" + the "person" row.
  2. KEY-ENTRY SCREEN         opening "person" swaps the slide to the one-prompt
     "tap your key" surface (no password field ever).
  3. GATE PROOF (reuse)       the tap -> kidulkey-gate challenge/verify ->
     "TRUSTED role=<role>" line. ALREADY live (slice 4 + test roster); this
     slice only wires the slide's tap to the gate's verdict.
  4. KUSHD RE-MINT            on proof, kushd RE-SEATS the session as the
     resolved role: public (uid 1001) -> owner (uid 1002, random-hash name).
     A RE-MINT feature, NOT a seatUid() tweak (public-seat.md §Owner escalation).
  5. LANDING REVEAL           kidulwm's landing shows the FULL roster on owner,
     public roster on public — the "crossing over" made visible.
  6. CLAIM FLOW               empty roster -> first proof seeds the roster as
     owner (born from the first tap); gates every later sign-in.

  Order note (SPEC BEFORE SURFACE): 1-2 surface, 3-6 the mechanism it fires.
  Build 1 -> 2 -> 3 -> 4 -> 5 -> 6; each lands green before the next.

## done-when (the #57 slice)

  - Mod4+T opens Homes; "person" shows "tap your key";
  - the tap proves against the roster and re-seats the session as the resolved
    role (claim seeds owner on empty roster; sign-in resolves the role set);
  - the landing reveals the full roster on owner, public roster on public;
  - no password field and no sudo binary anywhere in the path.

## Deploy note (operational, not law)

Deploy ALL AT ONCE — the built-but-undeployed GPB + kidul-flow + re-centred
pill bar, together with this Homes slice — then Barticus boots and inspects.
No incremental partial deploys.

## Reversals / naming

  - "Homes" (new name) resolves the surface kid.md / kidulkey-entry.md call
    "settings / person" and delegation.md calls "People / the admin door":
    one name for the identity door (Homes), one name for the personal app
    (Settings).
  - "Admin" RETIRED as an entity name — it survives ONLY as the delegation
    ROLE (delegation.md: "owner = admin"; "sub-admin"). Homes (surface) and
    admin (role) no longer share a word.
  - Loose "settings" senses NOT swept here (deferred to the build cut):
    ksignals = the HOST's v1 settings surface (daily-driver.md, host-side,
    not KSD); kfiles "SETTINGS" = a kfiles nav element (app-local); "advanced
    settings" (environment.md / theme.md) = the geek granular-control tier.
    Each stays app-local; none of them is Homes.

## Relationship to existing law

  delegation.md     sub-admin tree (consolidated above); People = Homes' door.
  public-seat.md    owner escalation -> the re-seat this slice builds (step 4).
  kidulkey-entry.md claim vs sign-in -> the Homes key-entry flow (steps 2-6).
  kid.md            "settings / person" access = Homes (renamed).
  environment.md    no profiles; environment per-app (unchanged — Homes is a
                    surface, not a profile).
  kidul-flow.md     keycombos secondary to flow; Settings app = the later slice.
  back-home.md      Home (singular) = the deck; Homes (plural) = the door.
