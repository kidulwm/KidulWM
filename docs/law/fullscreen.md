# LAW — fullscreen is a mode, not a deck position

LOCKED 2026-09-22 (Barticus: "get it right & make it our way of doing it —
it will just be law, we won't touch it").
Amends media-is-a-slide.md ruling 6 ("fullscreen is a size, not a seizure")
and kplay.md LAW 4 ("slide moves, video rides"). Those two let a playing
fullscreen video RIDE the deck. Wrong. This law retires ride-along.

## The sentence

The screen is CFC for the eyes (sound.md, applied to pixels). Fullscreen
video is ATTENTION, not position: it owns the output and yields the instant
navigation takes over. The deck is navigation; the card is the video's
home; fullscreen is a transient mode the card enters and leaves.

## The law

1. FULLSCREEN IS A MODE. A playing video at fullscreen owns the output:
   zero chrome, zero peeks, zero deck. It is NOT a slide, does NOT ride
   the deck, and never appears as a "next slide over" or in the overview.
   It has no deck position to lose.

2. NAVIGATION EXITS FULLSCREEN. Any deck-navigation input while fullscreen
   is up (1) retires the video to its card FIRST, then (2) applies the
   move. Never navigate with fullscreen still up. The trigger is
   deterministic by construction: fullscreen already hides chrome and
   peeks (CHROME LAW + vocab visibility law), so the only inputs left are
   media controls and navigation keys — a navigation key is an
   unambiguous, deliberate gesture, never a hair-trigger that kills the TV.

3. RETIRE ≠ QUIT (sharpens playback.md §1). Close the CARD while video
   plays = QUIT (sound dies). Navigate away from fullscreen = RETIRE: the
   card persists in the deck, the video PAUSES at its position (watch-state
   records it), the fullscreen surface tears down, sound pauses. One click
   on the card resumes fullscreen from the saved position. Live TV retire
   drops the stream; resume re-tunes (there is no "pause" on a live rail).

4. THE CARD IS THE HOME. The media card is a normal slide (media-is-a-slide
   stands, for the card). It shows title + position + play/pause. The card
   never needs fullscreen to be useful; fullscreen is a convenience layer
   over it, never the other way round.

5. CFC FOR THE EYES (mirrors sound.md). One thing holds fullscreen
   attention at a time. Deck navigation is a higher-priority claim that
   takes the floor — exactly as a higher sound class takes the floor.
   Fullscreen is the "focused" class; navigation is the alarm that
   preempts it.

6. BROWSER FULLSCREEN = SAME LAW, DIFFERENT DOOR. A fullscreen browser
   (WebKit requestFullscreen) is also an attention mode. Navigation exits
   it: the compositor signals the client to leave fullscreen, and the
   browser drops back to its normal webpage view (the page that already
   moved left). No kplayd, no foreign-pixel ownership — kplay.md LAW 3/4
   stand; the browser is a plain foreign Wayland client.

## What gets deleted

- "video rides the deck" — kplay.md LAW 4's ride-along for the fullscreen
  surface (the card still rides; fullscreen exits).
- The parked-.video-slide focus deadlock (verdict 51): a fullscreen that
  quits on navigation has no parked slide to become unreachable.
- placeKplayWindow pin-tracking over a moving slide rect: fullscreen is a
  fullscreen-mapped toplevel, not a rect chased across the deck.
- The z-order burial (black slide + audio): no black placeholder to raise
  over kplayd once there is no separate video slide.

## What stays

- media-is-a-slide.md (the card IS a normal slide; focus behaves normally;
  one player many views; no screen blanked or made useless).
- playback.md (music survives close; video quits on CLOSE).
- kplay.md LAW 1/2/3/5/6 (ownership, whole-and-sealed playback, zero-copy,
  crash containment, one clock).
- The kmedia engine, watch-state, art chain, expansion model.
- CHROME LAW (fullscreen = zero chrome) and the vocab visibility law
  (peeks hidden while fullscreen).

## Open after lock

- Implementation: compositor (exit-fullscreen-on-navigation + .video-slide
  teardown + focus-walk fix), kplayd (retire/resume_us), browser
  (leave-fullscreen signal). The code commit records what it corrects so
  the prior binary is the drop-back.
- Play-in-card preview: DEFERRED INDEFINITELY — only if it ever earns it,
  and only if it can be done without feeling buggy. Not part of this law.
