# DESIGN DRAFT — klipd grant engine (v0.4): input-trust wall + directional grants + pillsBar

DRAFT 2026-10-31, bobdotrix. Freeze candidate against klipboard.md (LOCKED).
A/B/C ruled (Barticus present); D open. Not yet law.

## Problem

v0.3 owns the seat's selections but tags every foreign copy owner "foreign" — a
single anonymous bucket. There is no per-app policy. klipboard.md properties
2-5 require identity (app_id, owner-class), default-deny, directional grants,
key-tap approval, settings-home. This draft is that engine.

## The gap — klipd cannot see WHO set a selection, nor WHOSE input drives it

ext-data-control-v1 delivers `selection(offer)` with no identity and no input
provenance. The compositor knows both (the wl_client + app_id; the seat's input
devices). So the compositor relays identity AND input-trust to klipd. That relay
is the load-bearing new piece.

## Design

### 1. Compositor relays (pid, app_id, input-trust)

Channel (Q.C, LOCKED): the compositor connects to klip.sock as a TRUSTED peer.
SO_PEERCRED resolves to kidulwm (already a known app_id) — authenticated by the
socket, no token, no new protocol, no new socket. "We don't do waste" — one
seam, reused.

When wlr_seat_request_set_selection fires for a NON-klipd source, the compositor
writes one relay record before wlr_seat_set_selection:

    seat-set <slot> <pid> <app_id> <trusted> <serial>\n
      pid      = wl_client_get_credentials  (kernel truth)
      app_id   = the source client's toplevel app_id (Window table already holds it)
      trusted  = 1 if the driving input device is TRUSTED (Granny's remote /
                 approved keyboard, input-trust.md), else 0
      serial   = the wl_data_device serial, a defensive correlation aid

klipd pairs the relay with the ext-data-control `selection` event in the same
drain (pending_identity). Ordering is safe: the compositor writes the relay
before wlr_seat_set_selection emits the event, and klipd drains both fds in one
poll loop.

owner-class is NOT on the wire — klipd resolves it from kernel truth (the same
SO_PEERCRED -> /proc/<pid>/... resolver it already runs for house apps).
property 2 / Q.H: never trust a wire claim for owner-class.

### 2. The PRIMARY wall is INPUT-TRUST, not app identity (Barticus, Q.A)

"Best defense is 'is Granny's key in - or not'." A clipboard operation is either
driven by a trusted input device (her remote / approved keyboard) or it is not.
The compositor owns that truth (the seat admits devices by proof, input-trust.md).

  trusted input drives the op  -> it is the human's own intent -> ALLOWED,
                                  silently. No grant, no nag — "she never needs
                                  to know."
  no trusted input drives it    -> automated / background / foreign read ->
                                  DEFAULT-DENY, silently. This is the whole wall:
                                  a background app cannot forge a trusted-input
                                  event, because the device is authenticated at
                                  the seat, BELOW any app (input-trust.md).

The directional app->app grant (Q.A's pair-wise model) is the EXCEPTION path for
the automated case: a daemon/script/auto-fill that needs clipboard access with no
human driving it (e.g. a password manager's fill). That is where the grant table
+ kidulKey tap live. Human-driven cross-app flow needs no grant — her intent is
the authorization, and the law says don't stop the user being stupid.

    grant[source][dest][slot]  in { allow, deny }, default deny — for the
                               AUTOMATED path only
    same-principal read-back always allowed (v0.2 rule, Q.E)

Live-revocable: in-RAM; a toggle-off takes effect on the next read, no relog.
Purge (property 6) clears slots AND the table.

### 3. The surface is the pillsBar (Q.D — open, see rulings)

The grant surface is NOT a settings-slide matrix. Barticus's ruling: the surface
is a contextual PILLSBAR — see Q.D below. Details pending the pillsBar freeze.

### 4. Approval = the toggle, driven by trusted input (Q.B, LOCKED)

A grant toggle is a POLICY RECORD confirmed by the kidulKey tap — but the tap is
STUBBED for v0.4: the pillsBar toggle, driven by her TRUSTED remote, IS the
approval. Low stakes, reversible (property 4), so a stub weakens nothing
structurally. The real tap binds when the key lands.

NOTE (Q.B, crypto lane): Barticus wants an OPEN-SOURCE kidulKey ("open-source
YubiKey") so kids make their own and Granny/businesses buy an official one —
hardware money, FREE-to-hack in metal, matches the values law. A WIP; does not
block v0.4.

## Build order (incremental, each shippable)

  v0.4a  compositor relay — server.zig resolves (pid, app_id, trusted) at
         request_set_selection and writes `seat-set`; klipd stashes it and tags
         the foreign copy owner = (app_id, host) + trusted flag. Plus the
         input-trust state push (focus/device change) so klipd can gate house
         `get` calls. Same-app read-back still the only allow. FOUNDATION.
  v0.4b  input-trust enforcement + grant table in klipd — deny any read with no
         trusted input driving it; add the automated-path grant table + admin
         verbs (grant/revoke/list) gated to trusted peers.
  v0.4c  pillsBar — the contextual surface (its own freeze/law, see Q.D); the
         grant toggle rides it.
  v0.4d  kidulKey tap — bind the real key (open-source kidulKey) to the toggle.
  later  muster binding, VM bridge, at-rest (law Q.D/Q.I).

## Reversals (against locked law — none silent)

- v0.3's "foreign" owner tag becomes a real (app_id, host) tuple — the v0.3
  note's stated intent, not a reversal.
- The klip.sock wire grows `seat-set` + (v0.4b) grant/revoke/list admin verbs —
  a build-spec extension, not an overturn.
- The grant surface moves from "settings slide" (property 5's wording) to the
  contextual pillsBar (Barticus's Q.D ruling). That is a REVERSAL of the letter
  of property 5 ("settings-home"), recorded here explicitly: settings-home
  becomes context-home, because a TV remote is faster contextually than in a
  settings dig. Flag for Barticus to confirm in the D lock.
- No other locked law is touched.

## Rulings

- Q.A  GRANTS. [Barticus: yes to pair-wise directional] AND the PRIMARY wall is
       input-trust ("is Granny's key in") — trusted input = her intent =
       allowed silently; no trusted input = default-deny. The pair-wise grant is
       the automated EXCEPTION path, not the main gate. LOCKED.
- Q.B  KIDULKEY TAP. [Barticus: stub for now] + open-source kidulKey idea (kids
       make their own, official ones sold). LOCKED as stub.
- Q.C  RELAY CHANNEL. [Barticus: trusted peer] — compositor connects to
       klip.sock. "We don't do waste." LOCKED.
- Q.D  SURFACE. OPEN — pillsBar (see below, my recommendation).

## Open question — Q.D, the pillsBar (Barticus's proposal, my recommendation)

Barticus's vision: highlight + right-click (or a remote equivalent) -> a
"pillsBar" of pill-shaped options appears under/at the highlighted item, the
screen optionally dimmed except the highlight and the bar. He asks: full-dim vs
a small bar under the item; and should the pillsBar become the KSD SIGNATURE
(the house context-menu, remote-optimised)?

My recommendation:
  1. Small bar first, no full-dim. Anchor the pillsBar directly under the
     highlighted item; skip the full-screen transparency for v0.4. A full-screen
     fade on a TV reads as "something broke" and costs a whole overlay pass for
     marginal gain. The pillsBar is the signature — the dimming is not the point.
     Add a subtle spotlight/vignette later ONLY if it earns it in the VM.
  2. Make it the signature — as a LAW, not a clipboard one-off. The pillsBar is
     the house context-menu for every surface (text, files, media, clipboard),
     so it wants its own locked interaction law (placement, CFC, remote
     left/right navigation, default pills), applied consistently. This also
     ANSWERS the v0.2 docket open question (a) — the right-click CONTEXT DROPDOWN
     for mouse users — in one move.
  3. It coheres with input-trust: the pillsBar is driven by her trusted remote,
     so a pillsBar toggle IS the approval (Q.B's stub), no separate gesture.
  4. It needs its own input mapping: right-click on the remote (a dedicated
     button / chord) opens the pillsBar — that lands with kidul-remote, not
     klipd. Track as a parallel docket, don't block the clipboard relay on it.

Recommend we freeze the pillsBar as its OWN law (separate session, styles +
kidul-remote present) and let v0.4a/v0.4b (relay + enforcement) proceed without
waiting for it — they don't touch the surface.

## Q.D expanded — the pillsBar is the NAVIGATION spine, not a context menu (Barticus 2026-10-31)

Barticus's full vision: the pillsBar is the system's whole navigation model, not
a clipboard surface. Power-on -> landing -> first press of the middle
button/enter -> a MAIN pillsBar of "all our apps". Pressing into an app slides
its own pillsBar in just below, while the MainPillBar sinks one row and FADES
(no colour on the buttons) — a live breadcrumb, so the user still glimpses "favs
= browser, top files = kfiles". Up/down arrows traverse the whole hierarchy
(up = out to the MainPillBar); left/right select siblings. Only possible because
of the CFC/design. That is the "signature".

Placement of the LEAF (the OptionsPillsBar that grants clipboard access), per
Barticus: SMALL and close to the highlighted area — the user is looking there,
no reason to pull their eyes to screen centre. He floated centre as "the most
obvious place"; see my recommendation below.

bobdotrix's refined read:
  1. This is a NAVIGATION law, not a surface law — one interaction language for
     the whole system (landing -> app -> item), which is exactly the
     defence-by-architecture move applied to UX: one pattern everywhere.
  2. The faded breadcrumb is the gem: a TV has no taskbar and no title bar, so
     "where am I" is permanently unanswered. The MainPillBar sinking one row and
     fading while the active pillsBar takes the top slot IS the persistent,
     legible answer. Keep it.
  3. LEAF placement: CLOSE to the highlight, with EDGE-FLIP containment. His
     focal instinct is right — centre only wins on "never clipped", and the real
     fix for clipping is edge-flip (no room below -> render above; no room
     right -> shift left), which keeps locality AND never clips. Centre
     disconnects the menu from the thing it acts on.
  4. RISK TO NAIL IN THE FREEZE: the pillsBar navigation must RECONCILE with the
     existing SlideDeck layout (columns/splits/focus), not become a second
     navigation owner. Theatre law: two maps is the disease. The pillsBar law
     must state, explicitly, how pillsBar (vertical hierarchy, up/down) and
     SlideDeck (horizontal columns) compose — does pillsBar become THE remote
     navigation with SlideDeck as the content-underneath, or do they layer?
  5. Split the freeze: a "pillsBar navigation" law (landing + styles/CFC +
     kidulwm-layout + kidul-remote present), SEPARATE from the clipboard draft.
     The clipboard relay/enforcement (v0.4a/v0.4b) stays unblocked — surface-free.

Barticus's resolution (kills the monster, 2026-10-31): the MainPillBar OWNS
NOTHING. It is a PROJECTION — it asks the USHER (kushd, the lifecycle-map owner)
to show each app's top+2 entry, so its content is identical for every app and it
is NOT a second navigation map, merely a VIEW over the usher's seating plan. Each
app owns its own hierarchy: top+1 is the app's own topPillsBar (CFC'd); the bar
above it (top+2) is the shared MainPillBar. Up = climb to MainPillBar via the
app's top+1; down = descend into the app. A "BobsSpecialDot" arrow (the house
lit-dot indicator, bobs-dot skill) centered top signals "movement available
above". No second owner: a projection cannot own a map. This resolves point 4 —
the bar is not a competing navigator, it is the usher's own map wearing a CFC
face. Deferred to the pillsBar law session; do NOT build in the clipboard lane.

