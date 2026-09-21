# TASK CARD — CARD 2b slice 4: DELETE the embedded player (kvisd owns playback)

**Repo**: /home/dad/dev/KidulWM (main, HEAD = 38b3699)
**Date**: 2026-09-17
**Law**: CENSUS verdict 28 (LOCKED) — "media slide becomes a kvis.sock
client; embedded libkmedia module scheduled for DELETION. Do NOT patch
embedded letterbox/fullscreen bugs — they die with the module."
Attack step 4: "Delete embedded module + present path; slide keeps ONLY
chrome, geometry, focus."
**Trigger**: Barticus — closing the mediaPlayer kills the session
(embedded player crash class). This card kills that class structurally.

## CURRENT STATE (verified 2026-09-17, commit 38b3699)

Embedded machinery to delete:
- src/ui/media_video.zig (457 lines) — dmabuf present path. Whole file dies.
- src/ui/media.zig MediaWidget Player path (the crash class):
  - play() (video) → kmedia_lib.Player.open, embedder_owns_video=true
  - playLive() → Player.openLive
  - playMusic() → Player.open (audio in-process)
  - playPause/next/prev/seek/update → drive in-process Player
  - ensureStopped() → Player.close + generation bump
- src/server.zig play_timer (handlePlayTimer ~line 4030-4160): per-frame
  advance of the in-process Player, dmabuf refresh, vsync quantization,
  peek mirror. This whole block dies — kvisd advances itself.
- mediaVideoRefresh/mediaVideoTeardown delegations (~2117-2128).
- Slide-close carve-out in mediaSlideCloseOn (~2132): ensureStopped +
  mediaVideoTeardown on video close — becomes a kvis.sock 'close' verb.
- stopOtherPlayers + media_play routing (~705-730): widget.play →
  becomes kvis.sock 'open'.
- build.zig static kmedia link: keep ONLY if still used (TV channel list,
  WatchState, music card state). Video decode link dies with the module.

kvisd already provides (kmedia repo, deployed & harness-green):
- kvis.sock verbs: open/open_live/close/stop/pause/resume/seek_abs/
  seek_rel/key/status/parent/unparent.
- Music headless path + video shell, both out of process.
- KvisClient in KidulWM (src/ipc/kvis_client.zig): connect/open/parent/
  unparent/close/pause/unpause. Needs seek_rel added.

## TARGET STATE

Playback = kvis.sock verbs only. The compositor never decodes a frame.
- media_play <path> → KvisClient.open(path); if !music, video slide
  spawns (slice 2) and kvisd parents onto it (slice 3).
- toggle/next/prev/seek → KvisClient.pause/unpause/seek_rel.
- Media player slide close → KvisClient.close (+ videoSlideClose if a
  video slide exists). Nothing in-process to crash; close is a socket
  write.
- MediaWidget keeps: library/search/selectedResultEntry/cached state/
  card painting. Player + WatchState + generation machinery deleted.
- Music: v1 plays through kvisd headless (open verb, no parent). Music
  peek state comes from kvis.sock 'status' (polled lazily) or stays
  cached from the open call — pick the simpler; Granny law applies.
- server.zig play_timer: deleted outright (kvisd advances; no dmabuf,
  no vsync quantize, no peek mirror pump). Peek repaints on state-change
  verbs + scheduleFrame on card_dirty only.

## WINDOWED PLACEMENT FIX (folded in — one line)

placeKvisWindow: windowed currently leaves the slide tree on top →
black placeholder over the video. Fix: raise kvisd's tree above the
slide tree in ALL modes; CHROME LAW fullscreen-zero-chrome unaffected;
windowed ring visibility verdict stays host-only (record in CENSUS).

## CONSTRAINTS / LAWS

- Slide keeps ONLY chrome, geometry, focus (verdict 28).
- CHROME LAW: fullscreen video = ZERO chrome, edge-to-edge (228abf6).
- One player, one truth: kvis.sock status is the only playback state.
- No blocking roundtrip on the internal client (pumpRoundtrip law).
  kvis.sock client is the bounded blocking-with-poll pattern (2s cap) —
  acceptable per its header; do NOT add unbounded waits.
- Hard stops, no wrap. Fix & record: CENSUS verdict 33 + HANDOFF addendum.
- Demolition discipline: every deleted touchpoint classified DELETE or
  REDIRECT; grep gate — zero 'media_video' / 'mediaVideoRefresh' /
  'mediaVideoTeardown' / 'play_timer' hits after.
- Do not touch spyglass.zig. Do not regress notification/home slide paths.

## ACCEPTANCE

1. zig build Debug + ReleaseSafe: 0 errors, 0 warnings.
2. zig build test: pass.
3. nested-smoke: PASS.
4. Grep gate: 'media_video', 'mediaVideoRefresh/Teardown', 'play_timer',
   'embedder_owns_video' = 0 hits in src/.
5. Harness: media_play → kvis.sock open sent (log evidence); video slide
   spawns; close → close verb, session survives (no crash on slide close
   — THE point of this card).
6. CENSUS verdict 33 + HANDOFF addendum. Signed commit(s) on main.
   No push. Deploy by bobDotrix after cold-verify.

## OUT OF SCOPE

- CARD 3 music-peek redesign.
- Full kmedia unlink from build.zig if TV channels/WatchState still link.
- kvisd GL-vs-pixman headless (host-only).
