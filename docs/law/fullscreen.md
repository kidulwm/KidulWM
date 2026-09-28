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

7. ZERO CHROME = PURE PASS-THROUGH (sharpens rulings 1 + 6, LOCKED
   2026-09-28). "Zero chrome" is not "no border ring" — it is "the
   compositor does nothing to the surface." A fullscreen surface is
   composited straight through: no corner mask, no rounded/chamfered clip,
   no border, no per-frame geometry clip, no full-window compositor-side
   buffer. Every pixel the client sends reaches scanout untouched. Highest
   quality, least resistance — the client owns the frame; the compositor
   only composites. A foreign client at fullscreen (Helium) already passes
   through clean with no corner crops and is the reference behaviour.

8. NO FULL-WINDOW CHROME BUFFER (LOCKED 2026-09-28). The compositor must
   not allocate a full-window ARGB chrome buffer for a fullscreen surface.
   Such a buffer is waste (a full-screen raster to paint a thin border) and
   a leak. Pin (2026-09-28, perf uprobe fp-stack): updateChrome →
   DataBuffer.create dupes a 27.14MB full-window ARGB buffer per layout
   event and never releases it — ~3GB anon per session, the RSS wedge.
   Fullscreen makes this buffer not exist; the windowed path must not leak
   it either.

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

## The present choreography (LOCKED 2026-09-22 — "the kidul way")

How the fullscreen mode hands the screen over, both directions. The timing IS
the style; get it wrong and it reads cheap and desperate.

- Controlled present, never pop-on-receive. The video NEVER shows the moment
  its first decoded frame arrives. It fades in over black. "Show as soon as
  we receive" looks desperate and shocks the old granny; controlling the in
  and out precisely is the difference between a hack and the kidul way —
  and it costs only an opacity ramp (Fade-only law, GPU-free).

ENTER (card -> black -> video):
  1. black curtain fades 0->1  (~180ms smoothstep) — deck + peeks fade to black
  2. hold black until kplayd's surface maps (zero energy — no frame re-arm)
  3. video fades 0->1 over the black (~180ms) — it fades ITS OWN pixels in
  4. at rest: curtain stays at opacity 1 behind the video (invisible, free —
     it is the black the exit fade will reveal); video edge-to-edge, zero
     chrome, scanout.

EXIT (video -> black -> card):
  1. video fades 1->0 (~180ms) — revealing the black curtain behind it
  2. teardown kplayd + host (sound dies with the video)
  3. curtain fades 1->0 (~180ms) — deck + peeks fade back in
  4. at rest: curtain destroyed, card still focused, never moved

- One easing language everywhere: the same t*t*(3-2t) smoothstep as the
  wallpaper boot reveal. Two opacity ramps (curtain + video), both on scene
  nodes. No per-pixel passes, no geometry motion. The card is a normal slide
  the whole time — it never moves, never parks, never peeks.
- z-order: deck < overlay_tree(peeks) < curtain < kplay_window. Re-asserted
  every tick while fullscreen is active (applyLayout raises overlay_tree on
  every layout event and would strand the peeks above the curtain).
- Movie "edging" (an iris/wipe/whirlpool reveal) is DEFERRED — requires
  research to do without looking cheap; the fade is the professional v1.

## Open after lock

- Play-in-card preview: DEFERRED INDEFINITELY — only if it ever earns it,
  and only if it can be done without feeling buggy. Not part of this law.
- Movie edging: DEFERRED — fade is the style until edging is researched.
