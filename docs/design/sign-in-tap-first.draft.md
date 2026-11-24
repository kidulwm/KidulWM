# DESIGN DRAFT — Sign In presents what the key opens (kill the resident names list)

Status: SPEC DRAFT — direction set by Barticus 2026-11-23 (GSI), rulings below
NOT YET LOCKED. This is the surface + resolution companion to portable-homes.
draft.md (the roamer drive) and claim-carve.draft.md (the internal carve). It
changes what the Sign In SLIDE shows and what the proof RESOLVES — it does NOT
delete the roster, does NOT delete the allocation map, and does NOT change the
sealed mounter. Those three stay; this removes their names from a public menu.

## The find (one sentence)

The Sign In slide today renders a RESIDENT NAMES LIST ("Owner", "Kid 1", ...)
as a public navigation menu. That is wrong on two counts at once: it LEAKS the
household (who lives here, to any stranger at the TV) AND it is bad UX (Granny
hunts for her name and consents to it, when the key already proves she is her).
Replace it: TAP THE KEY FIRST → kushd resolves what that key may open → present
THE RESULT as the greeting. What the key opens IS the sign-in. The name is
revealed AFTER proof, to the proven user, never listed for the unproven.

## The mechanism distinction that makes it safe (or not)

"Check all drives, present whatever the key opens" is SAFE only under one
reading and UNSAFE under another. The two must be split, or we build an oracle:

  UNSAFE reading   brute-force LUKS. Each per-user partition is keyed by a 64B
                   CSPRNG keyfile (kcarve) or a wrapped envelope, NOT a
                   passphrase. Serially "trying" cryptsetup open on every
                   partition = N × (PBKDF + root-key op) per tap, a timing
                   oracle, and a self-inflicted slowness. Reject.

  SAFE reading     resolution-to-open. The proof yields the key-id; kushd looks
                   up WHAT that key-id may cast (kalloc: partition UUID) and WHO
                   it is (kpax: role), then kopen's EXACTLY that partition once.
                   Deterministic, one open, no brute force, no oracle. This is
                   the chain claim-carve step 7 already builds — it is the
                   resolve-then-open model, never trial-then-present.

So "the key does all the opening" is TRUE in the sense that MATTERS: the key's
proof is the ONLY thing that decides what gets mounted, and the user is never
presented anything they could not actually open. But the lookup is answered by
kushd + kalloc + kpax, NOT by "try every LUKS and see." The roster + map are
the mechanism that makes the key's opening ANSWERABLE without an oracle — they
are not removed, only their names leave the menu.

The ONE place "opens literally" is correct is the portable drive: it carries
its OWN wrapped volume key (portable-homes.draft.md §The drive carries its own
unlock), so unwrap-to-open IS the admission, cheap and deterministic. There the
key genuinely opens the door alone. Two models, both safe, different footing:

  resident (internal)  proof -> resolve key-id -> role + partition -> one open
  roamer (portable)    proof -> unwrap the drive's own envelope -> mount

## The three-door surface (NewUser / Resident / Visitor)

Barticus 2026-11-23 (GSI): the Sign In slide is THREE buttons, not two doors,
not a name list. The buttons declare INTENT; the key tap then resolves IDENTITY
(the key proves WHO — no name list, tap-first). Names come AFTER proof as the
greeting, never as a pre-proof menu.

  Resident    tap the key. Home lives ON this box (the internal carve). The key
              resolves to role + partition and the seat greets you. No list, no
              consent-to-a-name.
  Visitor     "plug in your drive" -> tap the key. Home lives ON the drive you
              brought (the roamer/portable path). The drive carries its own
              manifest; the key opens it; guest authority, never host. The
              visitor door stays THIN — it is NOT saddled with any further
              detail or a create verb; the drive IS the detail.
  NewUser     the create door. Nothing to prove yet — this is where a home is
              BORN: either the internal claim (empty roster -> first owner ->
              carve the KSD) or the portable prepare (blank drive -> carve it
              -> self-sovereign manifest). The two are the SAME ceremony, two
              targets (portable-homes §one ceremony, two targets).

Naming of the third button is NOT settled ("NewUser" / "CreateNew") — the
FUNCTION is what is locked, the word later (naming law: name the behavior).
What MUST hold: Visitor is never contaminated by the create verb, and the
create door is the ONE place a home is born — it maps 1:1 onto "Add a user"
(owner, internal) and "Prepare drive" (self, portable) being distinct verbs.

## What the slide becomes

  Old: two doors (Residents name list / KidulCrew) -> pick/consent -> tap.
  New: ONE tap prompt. "Tap your key." -> proof -> resolve -> greet.

  - resident:  role + partition resolve -> mount -> "Welcome back, <alias>."
  - roamer:    a signed portable manifest the key opens -> mount that drive ->
               "Welcome." (guest authority, never host — portable-homes R).
  - neither:   deny-by-default -> "no access." Nothing listed, nothing mounted.
  - blank removable + nothing proven: "Prepare this drive" (below) — the
    public self-provision verb.

The two-doors asymmetry (Residents see local+external+networked; Crew external
only) does NOT disappear — it becomes the ROLE's DRIVE-SCOPING at resolution,
computed from kpax, instead of a visible menu choice. The role survive; the
menu does not.

## The "create" verb — TWO verbs, not one (the naming collision to kill)

Barticus flagged "select drive + create new" in the visitor/crew context. This
is RIGHT but it is a DIFFERENT VERB from "add a user," and conflating them is
the house's "one word, N jobs" hazard (kid.md). Split hard:

  "Add a user"    OWNER only. Creates a HOUSE member on the delegation tree
                  (carve a resident partition + roster entry). Lives in the
                  owner's settings (already locked settings.md §Adding a key).
  "Prepare drive" PUBLIC (self). Creates a SELF-SOVEREIGN portable home on a
                  drive the caller brought. Touches NO roster, NO house disc.
                  This is the portable-homes R1/R2 verb, and the visitor/sign-
                  in surface is exactly where it belongs.

Recommended name for the public verb: "Prepare drive" (or "Make this drive my
home") — behavior-named, never "System" (that is the GEAR, SystemFam, naming
law), never "account" (the house is passwordless; an "account" reads like the
media-shop credential we rejected). The two words must look distinct on screen
so Granny never confuses "add a kid" with "make my travel drive."

## The drive picker + nag (hardening the wrong-drive guard)

claim-carve ruling D already pins the INTERNAL claim to the KSD by LABEL, fixed
config, "never a probe of biggest disk." The PORTABLE provision REOPENS the
wrong-drive hole (a user SELECTS the drive), so the picker must carry the guard
the internal claim never needed:

  - DRIVE NAME ABOVE THE BAR: the % fill bar for a portable carve shows the
    target above it — device model + size + serial tail ("Samsung T7 · 1 TB ·
    ...4f2a"). The number alone is blindness; the name is the guard.
  - PICKER = a pills bar of drives, FILTERED to what the caller may touch:
    * a VISITOR sees ONLY removable drives they have attached — NEVER the
      system disc, NEVER the KSD free pool, NEVER another resident's partition
      (the visitor cannot see who is on the system, so they must not see the
      house disc either).
    * the internal claim shows NO picker at all (fixed label target — ruling D).
  - NAG BEFORE EVERY partitioning op (already consent-on-consent, cancel-
    default, "full" extra beat — settings.md §The size control). Harden it to
    NAME the drive in the nag ("write 'Samsung T7 1TB' — this ERASES it"),
    because the wrong drive is the one fatality a generic "are you sure" does
    not cover.

## The resolution order (residents first, roamers second, deny last)

  1. kpax + kalloc (resident)   the built chain, unchanged
  2. portable manifest (roamer) signed-by-KidulWorks manifest whose key-id
     matches -> mount at /home/<home-hash>, ad-hoc uid
  3. deny                        UNTRUSTED, nothing mounts, nothing listed

## The honest open seam (not resolved, flagged)

Role is a WHO fact, not a STORAGE fact — opening a drive tells you what you
can READ, not whether you are the owner or an approved Tier-2 input. So "let
the key do all the opening" holds for STORAGE but not for AUTHORITY. The roster
still answers authority (input-trust Tier 2 admits against it, delegation
scopes against it). Consequence: a self-sovereign roamer with NO roster entry
leaves open what TIER their remote earns (Tier-2 resolves against the roster a
roamer is not in). This is a real seam between portable-homes and input-trust,
needs its own ruling — do roamers trust their input by their key alone, or by
the host's roster? Flagged, not decided here.

## Relationship to existing law

  settings.md      the residents name list + two doors are REPLACED by tap-first;
                   the "add a key has two homes" ruling is UNCHANGED (this intro-
                   duces "prepare drive," which is NOT "add a key" to the house).
  naming.md        SystemFam/OwnersFam/KidulCrew survive; the two-door MENU they
                   named dissolves into role-scoped resolution (names stay as the
                   role vocabulary, not the on-screen menu).
  re-seat.md       the tap-first proof -> resolve -> mount chain is exactly this;
                   the name is the post-proof greeting, not a pre-proof list.
  allocation-map.md/kpax  unchanged — they ARE the resolver that makes "the key
                   opens what it opens" safe (no LUKS oracle).
  portable-homes.md  the "prepare drive" verb's mechanism + the roamer footing.
  kid.md           deny-by-default, one key one roster — this is MORE that law,
                   not less (an unproven stranger now sees NOTHING, not a roster).
