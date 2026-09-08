# LAW — media is a slide, not a sentinel

LOCKED 2026-09-08 (Barticus: "lock it in & build it !").
Supersedes `media-slide-location.md` (2026-09-07) in full. That law patched
a bug inside the sentinel design; this law retires the sentinel design.

Applies to the compositor-owned media player (kmedia engine, KidulWM shell).

## The rulings (Barticus, 2026-09-08 session)

A. LOCKED — "It is not a special slide. I have said this over & over."
B. LOCKED — Granny's TV: one compositor, the screens physically attached
   to it. One player for all attached screens, one audio stream ever.
   Remote/wayland screens around the house = NOT NOW, worlds away; do not
   design the shell for it, do not drag a server in through the back door
   (no-server law stands).
C. LOCKED — The remote is boss ONLY in this sense: no app may ever render
   the remote useless ("that would mess with granny's head"). Remote keys
   are hotkeys we bind (open/close, left/right, etc.). Remote hardware
   plumbing = worlds away, not this design.

## The law

1. THE MEDIA SLIDE IS A NORMAL SLIDE.
   It lives in the deck like any client window. It can be parked, slid
   past, and seen in the Mod4+Tab overview ("terminal view"). No
   before_first sentinel slot, no sibling-sentinel status, no special
   empty_slot. The `EmptySlot.before_first` media carve-out dies.

2. FOCUS BEHAVES LIKE ANY OTHER SLIDE.
   Keys reach the media slide only while it is the focused center slide.
   When it is not focused, deck navigation keys do deck navigation — the
   slide must never capture, swallow, or redirect input. No modal key
   routing. The `if media_slide_open: mediaSlideKey first` branch in
   keyboard.zig dies.

3. ONE PLAYER, MANY VIEWS.
   The media CARD may be open on any attached output's deck,
   independently. There is exactly ONE player engine and ONE audio
   stream per session (audio-authority law unchanged). Pressing play on
   a second screen's card takes over the single player (or is refused —
   implementation detail, default: take over, granny-simple). Playback
   never duplicates across screens.

4. NO SCREEN MAY BE BLANKED OR MADE USELESS.
   Opening/playing media on one output must leave every other output's
   deck fully interactive. No session-wide takeover, no raising above
   other outputs, no closing another screen's view to move the slide.

5. NOTHING RENDERS THE REMOTE USELESS.
   Any focus, fullscreen, overlay, or playback state must still accept
   bound hotkeys. There is no state in which input is dead. (Today this
   is already true for key bindings; the law exists to stop the media
   slide's old modal capture pattern from ever returning.)

6. FULLSCREEN IS A SIZE, NOT A SEIZURE.
   A playing player may render at the full output rect (playback.md
   stands). It must not capture input, must not suppress the deck,
   must not hide the tray/chrome of OTHER outputs, and Escape/nav keys
   behave per ruling 2.

## What gets deleted (the shell redo)

- The sentinel machinery: `media_slide_open` deck flag as special state,
  `EmptySlot.before_first` media semantics, one-slide-per-session
  output-hopping close/reopen logic in `mediaSlideToggle`.
- Modal input routing in keyboard.zig.
- Output-stealing: "close the other output's view, reopen here".

## What stays (do not rebuild)

- The kmedia engine ENTIRELY: Player.zig, zero-copy dmabuf, vsync grid,
  lip-sync, live-TV, watch-state, art chain, expansion model.
- media.zig presentation (the wall, cards, pill row MOVIES·TV·MUSIC,
  playing chrome) — it renders into a slide-sized buffer; only WHERE
  that buffer lives in the deck changes.
- playback.md, ui.md, live-tv.md laws — untouched.

## Open after lock

- Chrome placement bug (pause pill straddles video/letterbox boundary)
  — fix lands in the redo using letterbox math.
- Backups: KidulWM d7bb2a5 not yet pushed (sda1/Codeberg/Apocalypse).
