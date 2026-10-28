# Play handoff — "play in kfiles = play in kmedia"

The Klinks. When kfiles plays a thing it is the SAME play as kmedia — one
system, not two apps. The seam is the WM's `media_play` door.

## The contract

- kfiles "Play" = `kidulwm-control media_play <path>`. The WM closes any current
  player, then sends `open <path>` to kplayd over kplay.sock. kfiles hands the
  path over and STAYS — it never decodes a frame and never leaves.
- NEVER `system("kmedia <path>")`. That launches the kmedia WALL client, which
  ignores the path. The wall is the browser; playback is kplayd's job. Barticus:
  "NOT kmedia" — the player must not drop you into the wall.

## By kind

- Music (.mp3 .flac .ogg .opus .m4a .aac .wav) -> headless background playback.
  kfiles stays ("goes nowhere"). Granny keeps browsing; the tune plays.
- Video/other -> full playback (fullscreen). kfiles stays underneath; the video
  fades in over it and drops back to kfiles on close/back.
- Image -> NOT media_play. Image "Play" is the kfiles-native slideshow loop (the
  in-app viewer). Stills are kfiles's job, not kplayd's.

## One player, one truth

`media_play` runs `kplayCloseAny()` first — the previous tune/film stops, the new
one starts. No two streams. (ksound owns the floor; kplayd is the pump.)

## Land-on-title (refinement, deferred)

If the title is already in the library, land the player on it (now-playing with
its art); if not, just play. v1 = just play. Land-on-title needs kfiles + kmedia
to share a library identity (a title id), which does not exist yet.

## The video-fullscreen gap (WM slice, deferred)

`media_play` fullscreens ONLY while the media slide is already open
(server.zig: `o.media_slide.isOpen()`). From kfiles (media slide closed) a video
would play audio-only until fullscreen becomes a deck-level video mode.

"Play video in kfiles -> fullscreen -> back to kfiles" needs fullscreen to be a
deck-level video mode, not media-slide-anchored. That is a KidulWM change, and it
must be VM-proven before deploy — the playback seam has a long crash/wedge
history (see the kmedia skill).
