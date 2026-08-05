# KidulWM Handoff — 2026-08-06 morning brief

## Where we are

- Branch: `main`, last commit: docs + procedural curtain v1 (`docs/per-pixel-chrome-architecture.md` parked)
- Build: passing (`zig build -Doptimize=ReleaseSafe`), deployed to `fresh-one`
- Backed up to LaCie-Apocalypse (bundle + `KidulWM-src/`)
- **Desktop status: essentially a finished product.** kbottle, aligned peeks,
  butterfly helix, live kmedia bands, procedural curtains v1 on screen.

## MORNING QUEUE (in order)

### 1. Design-grid overlay (the tool that unblocks curtains)
- `kidulwm-control grid_overlay on|off` → fullscreen 10px grid, heavier
  lines every 100px, origin at screen corner (maybe second origin centered).
- Scene-buffer overlay tree, above everything, toggleable at runtime.
- Purpose: talk about curtain curves in grid cells, not vibes.
  See docs/per-pixel-chrome-architecture.md — this grid is also step zero
  of the long-term per-pixel chrome idea.

### 2. Curtains — nail them with the grid
Current state (v1, deployed): procedural straight drops, full-length to the
bottom edge, matte black velvet (base 55% darkened), 6 jittered matte fold
columns, 4 gloss slithers full-height (3× 2-3px wisps + 1× 5px hero, random
x/meander/strength), scalloped gather at top, hairline inner rim light.
User feedback so far: closer, but needs final tuning WITH the grid overlay —
fold positions/curve talk in cells next session.
File: `src/render/curtain.zig` (`paintCurtain()`). All numbers are single
tweakable constants. Old PNG asset backed up:
`src/render/assets/curtain_left_tied_20260805_bak.png`.

### 3. Media micro-player popover (the day's main build)
Design (locked with user):
- Appears ONLY when the media peek is hovered or hotkey'd — never ambient.
- Pops out to the LEFT of the right-peek media widget (toward screen center).
- A **micro version of the future ktunes player**: stop + play/pause +
  maybe volume, nothing else. Simple, in line with everything else
  (black glass, gold rim, shape-language from the card mat).
- Content: now-playing title (if it fits), ⏯ toggle, ⏹ stop, tiny volume
  slider/pill.

Must also fix (the reason this exists — two songs played at once tonight):
- **Orphan reaping at startup**: on media widget init, kill any mpv still
  holding `/run/user/1000/kidulwm-mpv.sock` (our socket path is unique;
  `pkill -f kidulwm-mpv.sock` pattern or /proc scan). Compositor restarts
  currently orphan mpvs that keep playing.
- **Real stop**: wire `MediaWidget.ensureStopped()` to the popover ⏹ and
  add `kidulwm-control media_stop` (IPC message exists? — check
  src/ipc/message.zig; if missing, add `media_stop` request + server handler
  + CLI, mirroring `media_toggle`).
- Volume via mpv IPC: `{ "command": ["set_property", "volume", N] }` —
  `sendSimpleCommand` pattern already in media.zig.

Wiring notes:
- Peek hover: tray already tracks pointer motion over widget click boxes
  (`widget.click_box`); the popover should show after a short hover delay
  (~400ms) and hide when the pointer leaves both widget AND popover, or on
  Escape. Follow the card-open/close patterns in tray.zig (`updateCard`,
  `closeAllCards`) — the popover can be a small new scene-buffer like
  TrayCard, or reuse CardMode; judge in the morning which is cleaner.
- Hotkey: bind something sane (e.g. Mod4+M) via `handleAction` → toggles
  the popover. Check `src/input/keyboard.zig` action table.
- mpv launch: already fixed to `--ao=pipewire,pulse,alsa,null` so kmedia
  sees playback. The media card's Enter path works
  (`tray.zig:2398` → `media.play(path)`).

### 4. Parked ideas (do NOT start, recorded so they don't evaporate)
- **Butterfly Easter egg**: when the helix figure-8 is at full width
  (wings open), occasionally — random, rare — draw a few extra light dots &
  whispy lines for a few seconds so it literally reads as a butterfly.
  "Starer-entertainment." Not now.
- **Per-pixel chrome architecture**: `docs/per-pixel-chrome-architecture.md`.
- **kmedia Phase 2** (MPRIS over D-Bus from Zig, per-app mixer, media IPC
  subscribe): `docs/kmedia-zig-audio-endgame.md` — also has the questions
  for Andrew Kelley (user may chat with him; the file is ready to share).
- RAM gauge rejoining the temp group (gauges.toml already has show_ram).

## Key commands (verified, in KNOWN_CMDS.md)

```bash
cd /home/dad/dev/KidulWM && zig build -Doptimize=ReleaseSafe
scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sleep 2 && sudo cp /tmp/kidulwm /usr/bin/ && sudo systemctl start kidulwm'

# kill rogue audio on the VM:
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 'pkill -x mpv; rm -f /run/user/1000/kidulwm-mpv.sock'

# apocalypse backup: see KNOWN_CMDS.md "Apocalypse drive backup (LaCie)"
```

## Traps to remember tomorrow

- The media peek redraws EVERY FRAME (helix) — popover hover checks must
  not fight that; pointer-hit logic only, no render-latch changes.
- VM has no audio hardware: null-sink at
  `~/.config/pipewire/pipewire.conf.d/kidul-sink.conf` on fresh-one.
  If bands read 0.00, check wireplumber is running
  (`systemctl --user status wireplumber`) and mpv uses `--ao=pipewire`.
- `std.log` from the kmedia thread does NOT reach the systemd journal;
  debug with the `kmedia-test` binary instead.
- llvmpipe CPU burn (~300%) on the VM is NORMAL (software GL), not a bug.
- Zig std on this box is trimmed: no `std.Thread.sleep`, no
  `std.fs.cwd()` in some modules — see AGENTS.md + skill notes.
