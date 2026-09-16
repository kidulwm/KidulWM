# TRAY DEMOLITION & TRAY-SLIDE BIRTH — spec (2026-09-16, Barticus-locked)

Status: READY TO BUILD. All rulings locked. Do not re-ponder; build.

## The ruling (verbatim)

"it needs to become a slide — slightly special slide in that it may not need a
border & slide settings as we want them to act like a slide in the deck, BUT
only CFC'd text should appear in the middle of the screen."

"the tray as we know it has been the butt of half our issues."

## Why (the case, agreed 2026-09-16)

The tray is the last surviving member of the lens-mode species: a parallel
world layered ON the deck instead of a thing IN the deck. Scars:

- Session-21 pm probe: A→B routed to the HIDDEN TRAY widget — sound, no
  picture, whole addendum wasted proving the test missed the crime scene.
- media-is-a-slide.md exists as LAW because the tray made media NOT a slide.
- Chrome placement bugs (pause pill at 55%), PTR-CLAIM hunts, notification
  layering, the raise-overlay-above-X-below-Y z-dance in applyLayout.
- Every fullscreen feature must special-case "and also suppress the tray"
  (today's widgets-off law included).

The lens was deleted for this root shape. The overview became a sentinel
slide for this root shape. The tray is next. Code that gets DELETED is the
only fix that ever works here.

## What the tray-slide IS

- A normal entry in `deck.slides` (per-output deck, src/core/slidedeck.zig).
  It navigates (Mod4+j/k), parks, peeks, fullscreens like any slide. ZERO
  special input handling, ZERO z-choreography, ZERO pointer-claim specials.
- Specialness is COSMETIC ONLY:
  1. No border / no chrome (updateChrome skipped or a none-chrome kind).
  2. No per-slide settings.
  3. Content = CFC'd TEXT centered in the output. Widget contents (media
     card readout, weather, signals, notification feed) become what the
     slide SHOWS — not where they FLOAT. The slide IS the readout.
- Compositor-owned (like the overview sentinel / media slide): no client
  window, no window_id from a client. Reuse the sentinel pattern — a
  compositor-owned scene tree drawn by a ui/ module.

## Open design answers (locked 2026-09-16 session, Bob's leans ACCEPTED by
silence — revisit only if Barticus objects)

## SESSION-2 AMENDMENTS (locked 2026-09-16 evening, Barticus — supersede
anything above that conflicts)

A1. PROPER SLIDE: the tray slide gets a REAL border + background, stock
    chrome path — NOT the borderless special of ruling text/hard-NO #4.
    Acting like the rest of the slides comes from having normal chrome.
    "Transparent text-only later" = one alpha constant in the render, not
    an architecture change. Hard NO #4 is hereby REPEALED.
A2. HOME SLIDE: tray slide sits at index 0 of its row and is the boot
    landing + tray_toggle target. AMENDED by A7 (see below): it is a
    STOCK slide — closable, no indestructibility.
A7. HOME SLIDE IS QUITABLE (Barticus, same session): the standard quit
    keybind destroys the home slide like any other. At most ONE home
    slide per row; per-row not per-output (dual screens on one row share
    it, no clones). It does NOT auto-respawn — tray_toggle = "focus the
    home slide, or spawn one at index 0 if this row has none". PUBLIC
    boot (no kidulKey) lands on the MEDIA PLAYER (A5 appliance law);
    USER boot (kidulKey in) lands on the HOME slide. The home slide is
    otherwise summoned on demand, never force-spawned. After that its
    existence is the user's choice. Last-slide-closed → plain empty
    deck, EXIT signs do the talking (A3); no fake slide, no
    void-protection machinery.
A3. NO PLACEHOLDER SLIDES: no empty slides at row ends, no empty-slide
    body for empty rows. EXIT signs are the affordance (they exist, they
    are deployed). End-of-row/edge EXIT signs render at 100% opacity —
    ends are where the sign is loudest. "Move opposite the arrows on the
    remote" is the whole lesson.
A4. FULLSCREEN PLAYS BALL: fullscreen is a SIZE, and the deck moves the
    fullscreen slide WITH the other slides during a walk (rendered at its
    saved pre-fullscreen rect, mid-row, with border). On motion settle,
    a 1–2s dwell timer re-expands it in place; walking again before the
    timer fires keeps it windowed. No "exit fullscreen first" mode, ever.
    Peek/overview shows it as a normal mini. Cheap version first (instant
    drop to windowed rect on walk, expand on settle); tweens later.
    Applies to the media player too — one law, all slides.
A5. BOOT LADDER: v1 boots to the home (tray) slide. v2 (with kidulKey/
    session-restore): keyless boot → media-player appliance (basics
    immutable & public); key in → full computer unlocks (files, rows,
    settings); key out → back to appliance. Home slide content is
    key-scoped: keyless = clock/weather/now-playing only.
A6. REMOTE: two direction pads — pad 1 = deck walk (always the deck),
    pad 2 = in-slide (scroll/focus inside the viewed slide). Deck walk
    may be claimed ONLY by fullscreen slides, and an EXIT sign must show
    whenever it is.

## Original design answers (kept for history; A-amendments win on conflict)

1. ONE tray slide, all widgets as CFC sections stacked (media readout,
   weather, signals, notifications). Granny learns ONE place.
2. Position: FIRST in deck order (index 0). Mod4+k from anywhere walks
   home to it.
3. Notifications = CFC lines in the tray slide's feed section. The popover
   dies. media_card_toggle (Mod4+m) jumps focus to the tray slide instead
   of opening a card.
4. Pointer: CFC text is read-mostly. Actions are keybinds + Granny's
   buttons (already ruled the constant). No tray pointer hit-testing at
   all — deletes the PTR-CLAIM class for the tray.
5. widgets-off-in-fullscreen law SIMPLIFIES: no overlay left to suppress;
   fullscreen = "you're looking at a slide that isn't the tray slide."
   Keep the law's check but it reduces to a no-op for the tray-slide.

## Demolition map (measured 2026-09-16)

- src/ui/tray.zig — 4313 lines. BIRTH the new `src/ui/tray_slide.zig`
  fresh; do NOT evolve tray.zig. Delete tray.zig when the slide renders.
- 59 `tray` touchpoints in src/server.zig — each is either DELETE
  (z-dance, host wiring, toggle plumbing) or REDIRECT (focus-jump to
  tray slide).
- Tendrils: src/core/animation.zig, core/kmedia.zig, core/style.zig,
  core/theme.zig, render/curtain.zig, input/pointer.zig, input/keyboard.zig,
  ipc/message.zig, config/keybinds.zig, ui/files_card.zig, ui/network.zig,
  ui/notifications.zig, ui/media_slide.zig, ui/media.zig,
  kidulwm-control.zig.
- Keybind actions to repoint: tray_toggle, tray_select_next/prev,
  tray_activate, media_card_toggle → all become "focus the tray slide"
  (or delete outright where redundant with Mod4+j/k).

## Sentinel template to copy

src/ui/overview_slide.zig is the proven compositor-owned-slide pattern
(tree ownership, per-output render, layout skip). The tray-slide copies
its shape minus the reparenting (no minis inside — pure CFC text card).
media_slide.zig shows the "compositor-owned content in a deck slot"
variant. Read both before writing line one.

## CFC text

CFC = the house centered-flow text layout law (ksd-brand-pills-and-cfc-slides
skill). The tray slide's content renders via cairo text, centered both
axes, sections stacked with house gap. Gold on near-black, kfiles theme
tokens (0x0a0a0b bg, 0x948e7b gold).

## Build order for the 4pm demo

1. git worktree or branch `tray-slide` off main (62b342a is deployed HEAD).
2. New src/ui/tray_slide.zig: compositor-owned, CFC text, no chrome.
3. slidedeck: tray slide occupies index 0 as a compositor-owned slot
   (sentinel-style, NOT a fake client window — window-count invariants
   must hold; overview_slide_open shows the pattern for "not in
   slides.items" — DECIDE: sentinel-flag like overview, or real entry.
   LEAN: sentinel-flag at BEFORE_FIRST, mirroring overview's after_last).
4. Keybinds repoint (tray_toggle → jump to tray slide).
5. Content sections: notifications feed first (simplest CFC), then
   weather readout, then media readout. Media card LAST (it has the most
   state).
6. Delete tray.zig + touchpoints only after the slide renders on screen.
7. zig build test + ReleaseSafe + nested-smoke, deploy host, verify with
   Barticus on the real display.

## Verification gate

zig fmt touched files; zig build test; zig build ReleaseSafe;
bash scripts/nested-smoke.sh; deploy /usr/local/bin (atomic mv);
Barticus eyeballs: Mod4+k to tray slide, CFC text centered, no border,
Mod4+j away, fullscreen unaffected, spyglass EXIT signs still correct
on non-fullscreen slides.

## Hard NOs

- No tray overlay survival "temporarily" — demolition is the demo.
- No pointer hit-testing on the tray slide v1.
- No Barry asset port — CFC text only. Barry's home is a separate ponder.
- No border/chrome on the tray slide.
- Do not touch spyglass.zig (today's EXIT work is locked & deployed).
