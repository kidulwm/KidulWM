# LAW — settings architecture: Sign In (immutable) vs Settings (transportable)

LOCKED 2026-11-16, Barticus present (GSI). AMENDED same day (Barticus): the
immutable entity is named HOMES, not "Admin" — the door that switches
publicHome -> privateHome, where the userHomes live. Supersedes the
key-entry.draft.md framing (folded below; the draft is marked superseded,
not deleted — archive).
AMENDED 2026-11-23 (Barticus present, GSI): the add-a-key/add-a-user verb has
exactly TWO homes — the initial claim ceremony and the owner's own settings —
and NEVER the sign-in walk. See §Adding a key.
AMENDED 2026-11-23 (Barticus present, GSI): the surface is RENAMED "Homes" →
"Sign In". It is ONLY sign-in (residents list + visitor). The add-user/extra-key
verb and the roster move OUT of the sign-in surface into the owner's own
settings. The "+ VIP" pill is removed. See §The naming + §Adding a key.
AMENDED 2026-11-23 (Barticus present, GSI): the INTERNAL code name is also
swept — the slide identifiers follow the surface. "Homes" → "Sign In" across
SlideKind.signin, signin.zig (was homes.zig), SignInSlide/SignInBar,
signin_slide, signinSlide*, signin_toggle. ONE deliberate exception, recorded
in §Code naming below.

## The split (the ruling)

Two settings surfaces, architecturally separated. They are NOT one app with an
admin corner; they are two entities.

  Sign In    standalone, IMMUTABLE, root-owned, system-adherent. The door that
             switches publicHome -> privateHome (claim/sign-in,
             kidulkey-entry.md). ONLY sign-in — the residents list + the
             visitor door. "Out of touch" by design: your identity + access is
             not a personal preference you edit. RENAMED from "Homes"
             2026-11-23; the roster (People, delegation.md) + allocations +
             add-user/extra-key moved INTO the owner's own settings. Opened by
             a KEYBIND (Mod4+T) — a SECONDARY shortcut; the primary entry is
             the kidulFlow pill. This is THE WALL (#57) — docket #59 step (3).
  Settings   the user's PERSONAL, transportable surface — themes, brightness,
             presets. Travels with the user, never the machine. Per-app
             openings ("each app takes you to its part of the settings") + a
             Settings button on the non-public userHome. A LATER slice
             (kidul-flow.md: "Settings app (a later slice)").

## The naming (Sign In vs Home vs userHome — the disambiguation)

  Sign In    the door — the ONE place you prove WHO you are (claim / sign-in,
             kidulkey-entry.md). Named for the BEHAVIOR, not the hardware. It
             is ONLY sign-in: no add-user, no roster management, nothing else.
             (RENAMED from "Homes" 2026-11-23 — see the amendment note at top;
             the roster + allocations moved into the owner's own settings.)
  Home       the deck / back-home navigation surface (back-home.md: "QUIT /
             HOME = reveal the deck"; kidul-flow.md). SINGULAR — where you are.
  userHome   a Linux home directory (/home/public, /home/$HASH — public-seat.md).

The kidulKey/People pill on the usersBar is renamed Sign In: it names the
BEHAVIOR (prove who you are), not the hardware (the key) and not a management
surface (that lives in the owner's settings). The key is the means; the sign-in
is the act.

## KidulFlow is the door; Mod4+T is the shortcut

The PRIMARY entry is the pill: the usersBar's kidulKey pill is renamed Sign In,
and the flow is KidulHome -> down (UserHome / public usersBar) -> right (to
Sign In) -> down (enter). Arrow-only, remote-native — no launcher. On the pill,
the slide shows its TITLE below the bar (the same title reveal as every slide);
the Residents / KidulCrew content appears once you are IN the slide, not
before.

Mod4+t was the retired "tray toggle" — the old launcher that became the tray,
and the tray was designed out by the deck (Home). That code is dead; Mod4+T is
re-bound to open the SAME Sign In slide as a SECONDARY shortcut. Keycombos stay
available for testing and laptops — kidulFlow reduces the need for them, it
does not delete them.

Sign In is a SLIDE, not a controlling feature. It must NOT grow into a
media-player-style monster widget (media.zig). Thin surface; the gate, the
re-seat and the mount are the mechanism, and they live in the organs
(kushd / kidulkey / knetd) — not in the slide.
AMENDED 2026-11-18 (Barticus present, GSI): the re-seat FEATURE (not the slide)
IS meant to take over — central by design, the identity door, every detail CFC'd
for Granny. That is the OPPOSITE of the media player, which took over BY ACCIDENT
and lingered (slide-process.md "mother roach"). The anti-roach guard for a
take-over-by-design feature is a SELF-DISMANTLING transition (re-seat.md): kclose
+ kclean + kushd fire to get it OUT ASAP — process-death-is-the-kill, no lingering
controlling state to squash later. The slide stays thin; the take-over is bounded
by its own teardown, not by thinness alone.

## Sub-admin = the delegation tree (consolidation, not a new ruling)

The CEO / marketing-department model is EXACTLY delegation.md's grant tree:
owner = admin; each sub-user (a department) administers its OWN workers +
allocations; a creator grants only <= their own (attenuation). A sub-admin
allocates WITHIN the space the owner granted at creation (expandable on
request) — never more. Screens around the building all seat off the one
authoritative box (ktv native networking, machine-classes.md) — no
remote-desktop middleman. Nothing new: the ruling lives in delegation.md; the
owner's settings surface is where those verbs are CAST.

## Adding a key — the verb has TWO homes, sign-in has none

"Add a user" and "add a key" are the SAME verb in this house (kid.md: one key
= one identity). Where that verb may APPEAR is pinned here, and it is an OWNER
verb — a CREATOR act on the delegation tree (delegation.md: a grant descends
from the owner), never something a walk-up or a crew member invents.

  two homes  (1) the INITIAL CLAIM CEREMONY, and (2) the OWNER-ONLY settings
             (the owner's own account). Nowhere else.
  ceremony   claim = first key seeds owner, THEN the same walk asks "who else
             lives here?" and adds the family's keys up front (each: name +
             size -> carve + roster entry). Setup is the ONE moment adding is
             front-and-center. After it, the verb retreats into the owner's
             own settings (delegation.md People) — never the sign-in walk.
  sign-in    the Sign In surface is ONLY that — sign in as a resident or a
             visitor. The Residents list shows the owner's name + any users the
             owner has added, and NOTHING else: no "+ VIP", no add-user, no
             roster management. A walk-up or crew member SIGNS IN, never
             creates. Granny meets "Welcome, Granny." — never an add verb.
  seat, not  the verb's presence is a WHO question (owner sees it), NEVER a
  disk       FREE-SPACE question. It is not hidden when the disk is full and
             shown when empty — that would make "add user" flicker on a
             transient condition and read as broken. The verb is ALWAYS in the
             owner's settings; when the disk IS full, the carve step (the
             one thing that can eat the system) answers honestly in Granny's
             terms — "no room — ask the owner to make space" — instead of
             vanishing the option.

## Residents / KidulCrew (the two doors)

The Sign In slide opens on two CFC pills — Residents and KidulCrew — and the
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

## Provisioning (name + size + the rest)

Claiming a home is a resident being provisioned, and the owner is just the
FIRST resident: empty roster -> first key claims as owner. Every "+ VIP" after
runs the SAME path. The user gives TWO things; the system does the rest.

  the user gives:  name + partition size
  the system does: carve the partition -> instantiate the defaultHome skeleton
                   -> seed the roster entry -> bind the kID -> mount on proof.

  name   the alias (the face — kid.md). Residents check against the local roster
         (the /home symlink needs a unique name); Crew need no unique name
         (hash-keyed). Text entry is the hard remote problem — a letter pill-bar
         (a second pill bar, of letters) or keyboard-only; TBD.
  size   ONE fill bar (spec below). The default is set by the DEVICE CLASS, not
         the user: TV = 50% ("it's a TV, sharing is caring"), PC = full.

  defaultHome   a skeleton — the standard pill layout + default theme,
                instantiated into each new partition. A defined template
                artifact, not built ad hoc.

## The size control (the "no-slider slider")

One fill bar, arrow-native: no dragging, no typing (unless you have a
keyboard).

  [ - ]  ====...====o....========  [ + ]
            taken % shaded gold, ball at the edge, size CFC'd in the middle

  tap <- / ->    coarse: jump a quarter (¼ ½ ¾ full). Hard stops at 0 and full.
  press & hold   fine: walk 1% steps, accelerating (~1% -> ~5%/step) so a full
                 sweep is seconds, not fifty presses. Hard stops, no wrap.
  keyboard       type the exact % (the laptop/testing escape hatch).
  hint line      one line teaching the gesture: "tap for a quarter, hold to
                 fine-tune".

  Consent on consent: any size -> a nag screen in Granny's terms (never
  "mkfs.ext4"), ball DEFAULTS TO CANCEL, and "full" gets an extra beat — it is
  the only choice that can eat the system. Partitioning is fatal, so it is the
  one place to be heavy.

  Tuning knobs (on boot): tap/hold threshold ~250ms, hold acceleration curve,
  and the exact ball/fill chrome.

## Build order (the #57 slice, folded from key-entry.draft.md)

  1. HOMES SLIDE (DONE)       compositor-owned slide (kind .homes) + Mod4+T
     shortcut. Empty shell: title "Homes" + a placeholder row.
  1b. KIDULFLOW DOOR          rename the usersBar kidulKey pill -> Homes; Down on the
     pill enters the slide (homesSlideFocusOrSpawn). Primary entry.
  2. TWO DOORS (DONE)         two CFC pills (Residents / KidulCrew). Residents =
     a name list + "+ VIP" (focus on Owner); KidulCrew = a sign-in only (no
     list). Right on a name (or down on KidulCrew) opens the shared "waiting
     for tap" prompt. Dip-your-toe flow: up backs out at every level.
  3. GATE PROOF               the tap -> kidulkey-gate challenge/verify ->
     "TRUSTED role=<role>" line. ALREADY live (slice 4 + test roster:
     kidulkey/gate + kpax CLI, proven). This slice wires the slide's tap to the
     verdict — KUSHD ROUTE (locked 2026-11-16): the slide cues kushd, kushd
     forks kidulkey-gate (the same fork input-trust already uses), the verdict
     returns to the slide over IPC. The slide never owns the gate.
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

Deploy ALL AT ONCE — the built-but-undeployed usersBar + kidul-flow + re-centred
pill bar, together with this Homes slice — then Barticus boots and inspects.
No incremental partial deploys.

## Code naming — surface vs gate (the ONE exception)

Internal identifiers follow the surface: the sign-in SLIDE is `signin` everywhere
(SlideKind.signin, signin.zig, SignInSlide/SignInBar, signin_slide,
signinSlide*, signin_toggle). ONE deliberate exception, and it is not
accidental drift:

  homes-gate  the KUSHD ROUTE proof verb is STILL named "homes*" — homesGateCue,
              homesGateCancel, homesGateDrain, homesGateFinish, homesGateApply,
              homesSyncGate, and the wire string "homes-gate" itself. These are
              the GATE that seats you into your home (a re-seat to
              /home/<home-hash>, re-seat.md) — not the slide surface. The word
              "homes" is CORRECT there: it names the destination (the user
              homes being entered), not the button.

Why not sweep it too: "homes-gate" is a WIRE CONTRACT — kidulwm writes it,
kushd reads it (kushd GATE_CUE = "homes-gate"). Renaming the verb is a
cross-repo coordinated change (kidulwm + kushd must ship in lock-step) that
buys Granny nothing — she never sees it. Renaming the gate identifiers to
"signin-gate" would also be a MISNAME: the gate does not sign you in, it seats
you into a home. So the split is: SIGN IN (surface, what you tap) vs HOMES
(gate, where you end up). Two words, two jobs — same rule as Home/HomeS at the
surface level. Do not "clean up" homesGate* to signinGate* without re-litigating
the wire verb across both repos.

## Reversals / naming

  - "Sign In" (2026-11-23) is the surface's CURRENT name — RENAMED from
    "Homes": the surface is ONLY sign-in now; the roster/People + add-user
    moved into the owner's own settings. See §The naming + §Adding a key.
  - "Homes" (2026-11-16) named the identity door when it STILL carried the
    roster + allocations. Superseded by "Sign In" once those verbs moved out.
  - "Admin" RETIRED as an entity name — it survives ONLY as the delegation
    ROLE (delegation.md: "owner = admin"; "sub-admin"). The sign-in surface
    and admin (role) no longer share a word.
  - "Visitor" RETIRED -> "KidulCrew": the crew you hang with (non-residents,
    sign-in only), distinct from the OwnersFam (Residents) and the SystemFam
    (the gear). Locked in naming.md.
  - Loose "settings" senses NOT swept here (deferred to the build cut):
    ksignals = the HOST's v1 settings surface (daily-driver.md, host-side,
    not KSD); kfiles "SETTINGS" = a kfiles nav element (app-local); "advanced
    settings" (environment.md / theme.md) = the geek granular-control tier.
    Each stays app-local; none of them is Sign In.

## Relationship to existing law

  delegation.md     sub-admin tree (consolidated above); People = the owner's
                    settings door (add-user / extra-key live there, not Sign In).
  public-seat.md    owner escalation -> the re-seat this slice builds (step 4).
  kidulkey-entry.md claim vs sign-in -> the Sign In key-entry flow (steps 2-6).
  kid.md            "settings / person" access = Sign In (renamed from Homes).
  environment.md    no profiles; environment per-app (unchanged — Sign In is a
                    surface, not a profile).
  kidul-flow.md     keycombos secondary to flow; Settings app = the later slice.
  back-home.md      Home (singular) = the deck; Sign In = the door.
