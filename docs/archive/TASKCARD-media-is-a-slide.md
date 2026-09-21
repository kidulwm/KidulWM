# TASKCARD — media-is-a-slide: retire the sentinel

Locked law: docs/law/media-is-a-slide.md (LOCKED 2026-09-08, Barticus).
Superseded: docs/law/media-slide-location.md (history only).
Work dir: /home/dad/dev/KidulWM. Host builds ReleaseSafe. Sign commits as
B&B <bnb@ratukidultech.com>, GPG 344B8C86C2E835F1AF9766E40AE9A7E153BFA843.

## Mission

Make the media slide a NORMAL deck slide per the locked law. The
before_first sentinel dies. Engine untouched. One player per session,
one audio stream. No screen blanked. No modal input.

## The refactor (5 pieces)

### 1. slidedeck.zig — deck owns media as a bool, not an empty_slot

- `media_slide_open` STAYS as a plain deck bool (per-output cards are
  wanted — law ruling 3), but it no longer touches `empty_slot` or
  `virtualFocus()`. Media open = the deck's CURRENT focused slot shows
  the media card instead of a client window. The deck's slides/focus
  are UNDISTURBED underneath.
- DELETE: `media_return_index`, media semantics in openMediaSlide/
  closeMediaSlide that set `empty_slot = .before_first`.
- openMediaSlide(): set flag only (+ close overview if open — siblings
  never both). No slides.len==0 change: on an EMPTY deck the media card
  still opens, rendering into the empty-slot rect (ruling: media must
  open at first boot with no windows).
- closeMediaSlide(): clear flag only. Focus/slides never moved.
- mediaSlideTarget(fullscreen): unchanged logic — non-fullscreen target
  is the current focused slot rect (or the empty-slot rect when the
  deck is empty), fullscreen is the full output.
- Tests: update "sentinel toggle round-trips" (it asserts media-free
  overview only — verify), ADD: open media on a 3-slide deck, focus
  next/prev still walks the 3 slides, empty_slot stays .none
  throughout; close media, focused_index unchanged.

### 2. server.zig mediaSlideToggle — per-output, no stealing

- OPEN: operate on the output owning the current focus deck ONLY.
  DELETE the loop that closes other outputs' slides (old lines
  1649-1657). Other decks' media cards stay open and usable.
- CLOSE: close the slide on the current deck's output ONLY.
  DELETE the "find where it actually lives" scan (that law is
  superseded).
- mediaSlideOpen/Close/Refresh/Teardown: unchanged except they no
  longer reference `media_return_index` or expect empty_slot changes.

### 3. keyboard.zig — focus-gated, never modal

- The `if (server.currentDeckPub().media_slide_open) { if
  (server.mediaSlideKey(sym)) return; }` block STAYS — it is already
  gated on the current-focus deck and already falls through when
  unconsumed (INPUT LAW). Verify: media open on output A, keys pressed
  while deck focus is on output B → mediaSlideKey returns false,
  normal routing proceeds. (mediaSlideKey already guards
  `deck.media_slide_open` on currentDeck — confirm after refactor.)
- Ctrl+Q block (line ~124): keep behavior — media open + Ctrl+Q closes
  the media slide. Update the comment (no longer a sentinel).
- The Escape-closes-slide case inside mediaSlideKey (server.zig
  ~2191): keep — Esc on a focused non-playing media slide closes it,
  same as before.

### 4. applyLayout / window layout — media card vs client window

- Where a deck has media_slide_open, the focused client window must
  NOT take the focused slot visuals (media card renders there — media
  tree raises above that output's slide trees, below overlay).
  Non-focused slides on that deck: unchanged (hidden as usual).
- When media closes or deck focus moves off, normal layout resumes.
  Simplest correct shape: in applyLayout, for an output whose deck
  has media_slide_open, lay out windows as usual but do NOT
  raiseToTop the focused window; call mediaSlideRefresh(output) after
  window layout so the card tracks slot geometry, then raise the
  media tree above the output's windows (not above overlay unless
  playing — existing raise logic stands).
- Playing player fullscreen (raise above overlay on THAT output) is
  unchanged — per-output only, other output untouched (law ruling 4).

### 5. One-player-per-session enforcement

- media_play IPC + widget.play(): if another output's widget has
  player_active, that widget gets ensureStopped() first (take-over,
  granny-simple default — law ruling 3). One audio stream ever.
- The play_timer / handleFrame present loops already scan all outputs
  and skip non-playing widgets — verify they tolerate media open
  without player_active on multiple outputs (they should; flag if not).

## Out of scope (do NOT touch)

- kmedia repo, Player.zig, dmabuf/vsync/lip-sync code — engine is law-
  protected.
- media.zig widget internals (wall, pills, expansion, playing chrome).
- Tray music path (tray.media) except the take-over guard in piece 5
  must also stop tray playback when a slide player starts (and vice
  versa — that pairing already partially exists; make it symmetric).
- The chrome-placement pill bug (listed as open in the law doc) — own
  commit AFTER this lands if trivial, else next session.

## Harness (all must pass before commit)

- zig build (Debug AND ReleaseSafe) — clean, 0 warnings.
- zig build test / existing unit tests incl. updated slidedeck tests.
- walltest / playertest / livetest in /home/dad/dev/kmedia — engine
  untouched, all must stay green.
- Manual smoke list for Barticus host test (write it in HANDOFF):
  open media on TV, slide deck on laptop still works; slide past media
  on the TV deck; park/unpark around it; play video, stop, play second
  video (session-19 regression); Esc behavior; music take-over both
  directions.

## Commit shape

One commit: "media slide: normal deck slide — retire the before_first
sentinel (law: media-is-a-slide.md)". Law docs already committed by
bobdotrix — do not amend them, your commit is code+tests only.
Report back: commit hash, test output tails, anything that fought you.
