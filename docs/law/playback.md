# playback.md — LAW (locked 2026-09-08)

Audio authority and slide-close semantics for the media player.

## 1. Closing the slide: MUSIC survives, VIDEO quits

Closing the media card is a **view change only for MUSIC**. The album
keeps playing headless, the peek label stays lit, and reopening the
card lands mid-track. This is the whole point of music: it lives in
the background.

**VIDEO CARVE-OUT (Barticus, 2026-09-08):** closing the slide while a
VIDEO (movie, episode, or live TV) plays IS a quit. The sound dies
with the picture. A video playing headless is nonsense — nobody
listens to a film from another workspace. Orphaned video audio was
also the root of the second-video blank screen: the headless player
kept its decoder alive across a slide reopen, the fresh widget's
`player_generation` aliased the stale `seen_player_generation`, and
the dmabuf cache served freed VA surfaces — a transparent hole where
the video should be.

Quit sources for video, all equivalent:

- Player-mode Escape (Player.handleKey → isDone → ensureStopped)
- Closing the slide (toggle, second Escape, IPC media_card_toggle)
- isDone at end of stream

## 2. One player per session

Exactly one player engine and one audio stream ever (ruling 3 of
media-is-a-slide.md). Starting playback anywhere stops every other
widget's playback first (`stopOtherPlayers`).

## 3. Audio stops only on: explicit quit, slide-close (video), or
   end-of-track (isDone)

Nothing else may kill audio. View changes (card close with music,
workspace switch, occlusion) never stop playback.

## 4. The peek is the lifeline

While audio plays, the player is always findable — card open, or the
peek label lit in the tray. A headless music player MUST light the
peek (slide-owned playback mirrors its cached state into the tray
widget for exactly this).

## 5. Video pixels are a view

The video scene path exists only while the card can show it. Tearing
down scene buffers on close is a present-stop, independent of the
player-stop decision above (§1 makes them coincide for video).
