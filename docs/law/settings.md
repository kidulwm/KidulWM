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
             personal preference you edit. Opened by a KEYBIND (Mod4+T) — a
             SECONDARY shortcut; the primary entry is the kidulFlow pill. This
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

## KidulFlow is the door; Mod4+T is the shortcut

The PRIMARY entry is the pill: the GPB's kidulKey pill is renamed Homes, and
the flow is KidulHome -> down (UserHome / publicPillsBar) -> right (to Homes)
-> down (enter). Arrow-only, remote-native — no launcher. On the pill, the
slide shows its TITLE below the bar (the same title reveal as every slide);
the Residents / KidulCrew content appears once you are IN the slide, not
before.

Mod4+t was the retired "tray toggle" — the old launcher that became the tray,
and the tray was designed out by the deck (Home). That code is dead; Mod4+T is
re-bound to open the SAME Homes slide as a SECONDARY shortcut. Keycombos stay
available for testing and laptops — kidulFlow reduces the need for them, it
does not delete them.

Homes is a SLIDE, not a controlling feature. It must NOT grow into a
media-player-style monster widget (media.zig). Thin surface; the gate, the
re-seat and the mount are the mechanism, and they live in the organs
(kushd / kidulkey / knetd) — not in the slide.

## Sub-admin = the delegation tree (consolidation, not a new ruling)

The CEO / marketing-department model is EXACTLY delegation.md's grant tree:
owner = admin; each sub-user (a department) administers its OWN workers +
allocations; a creator grants only <= their own (attenuation). A sub-admin
allocates WITHIN the space the owner granted at creation (expandable on
request) — never more. Screens around the building all seat off the one
authoritative box (ktv native networking, machine-classes.md) — no
remote-desktop middleman. Nothing new: the ruling lives in delegation.md; the
Homes surface is where those verbs are CAST.

## Residents / KidulCrew (the two doors)

The Homes slide opens on two CFC pills — Residents and KidulCrew — and the
two doors are deliberately NOT symmetric. Roles (owner / adult / child / tv /
nas / ...) are ATTRIBUTES of a resident name, not pills. "Family you live
with -> Crew you hang with."

  Residents  a LIST. The OwnersFam — who LIVES here. Each named resident owns
             a per-user partition (allocated at creation) and sees local +
             external + networked drives. Focus lands on the Owner. "+ VIP"
             adds a resident (roster entry + carve the partition up front).
  KidulCrew  NO list — a sign-in only. The crew who DROP BY. A kidulKey
             glyph, focused; keying in proves who they are and their external
             drive rides in with them. Approved key access OR no access — no
             public drives. No roster entry, no partition, no persistence.

The key prompt is the SAME surface for both; only the drive scoping differs.
Key flow (arrow-only): pill level <- -> switches the doors, down descends.
Residents: down into the list, up/down walks names, right consents -> the
prompt. KidulCrew: down steps straight into the prompt. Up (or Esc) steps
back out at every level — "dip your toe in": nothing commits until the key
does. Later file/drive approvals happen in kfiles (move-copy.md).

## Drives on key-in (the plug-and-play wiring)

The DESIGN is already locked (partitions.md): every user lives on their OWN
key-gated per-user partition, cast by THEIR kidulKey, mounted on proof,
unmounted on lock (unplug = gone); external/net drives = "just another
partition". What is NOT built is the one-pass wiring that, on proof:

  re-seat the session (kushd re-mint)  ->  mount the seat's drives:
     Residents  ->  local allocation + external + networked
     KidulCrew  ->  external only (approved key access; no public drives)

Identity/kID answers WHO (kid.md, identity.md); this mount answers WHAT. The
missing piece is tying proof -> re-seat -> mount in a single pass.

## Build order (the #57 slice, folded from key-entry.draft.md)

  1. HOMES SLIDE (DONE)       compositor-owned slide (kind .homes) + Mod4+T
     shortcut. Empty shell: title "Homes" + a placeholder row.
  1b. KIDULFLOW DOOR          rename the GPB kidulKey pill -> Homes; Down on the
     pill enters the slide (homesSlideFocusOrSpawn). Primary entry.
  2. TWO DOORS (DONE)         two CFC pills (Residents / KidulCrew). Residents =
     a name list + "+ VIP" (focus on Owner); KidulCrew = a sign-in only (no
     list). Right on a name (or down on KidulCrew) opens the shared "waiting
     for tap" prompt. Dip-your-toe flow: up backs out at every level.
  3. GATE PROOF (reuse)       the tap -> kidulkey-gate challenge/verify ->
     "TRUSTED role=<role>" line. ALREADY live (slice 4 + test roster); this
     slice only wires the slide's tap to the gate's verdict.
  4. RE-SEAT + MOUNT          on proof, kushd RE-SEATS the session as the
     resolved role AND mounts that seat's drives (Residents = local + external +
     networked; KidulCrew = external only) — the plug-and-play wiring.
  5. LANDING REVEAL           kidulwm's landing shows the FULL roster on owner,
     public roster on public — the "crossing over" made visible.
  6. CLAIM FLOW               empty roster -> first proof seeds the roster as
     owner (born from the first tap); gates every later sign-in.

  Order note (SPEC BEFORE SURFACE): 1-2 surface, 3-6 the mechanism it fires.
  Build 1 -> 1b -> 2 -> 3 -> 4 -> 5 -> 6; each lands green before the next.

## done-when (the #57 slice)

  - Mod4+T opens Homes; "person" shows the "waiting for tap" prompt;
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
  - "Visitor" RETIRED -> "KidulCrew": the crew you hang with (non-residents,
    sign-in only), distinct from the OwnersFam (Residents) and the SystemFam
    (the gear). Locked in naming.md.
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
