# KidulWM Handoff

## Current state

- Branch: `main`
- Last commit: `1851906` docs (KNOWN_CMDS backup/apocalypse + kmedia notes)
- Build: passing (`zig build -Doptimize=ReleaseSafe`)
- Deployed: `fresh-one` VM via scp/ssh
- Backed up: LaCie-Apocalypse (`kidulwm-apocalypse-20260805_final.bundle` + `KidulWM-src/`)

## The day the desktop became a product (2026-08-05)

### kbottle — the new logo
- Pet-button cauldron replaced by a **genie bottle** (`drawGenieBottle` in
  `src/ui/tray.zig`): one continuous whispy vessel path shared by fill /
  stroke / clip, reversed color scheme (muted unfocused-border body, black
  shading = "Bob's extra special shading", border-color highlights, black
  RAM liquid), anchored belly-bottom 17px above the screen edge, 3px left.
- Golden wisp pours from the mouth only while `tray_anim` is mid-flight —
  the tray appears to come out of / back into the bottle. Fully static at
  rest. Zero idle animation.

### Peeks — landing-screen layout locked
- Left peek: moon centered in a 34·s status band (level with the network
  icon), temp + min/max + moon all +3px right, weather icon sized 48·s and
  tucked up (0.62·r center offset), min/max at font_size_s×1.2, widget box
  215·s. Clock/weather numbers matched at font_size_m×1.9, 10pt gap under
  the bands.
- Right peek: network icon −7px, clock numbers −9px, date block −4px net,
  date block = weekday / day / month, widget box 185·s.
- Left-peek gauges hidden by default behind `~/.config/kidulwm/gauges.toml`
  (`kidulwm-control set-show-temp on|off`, `set-show-ram`, 
  `set-temp-threshold`). `src/core/gauge_config.zig` reads it; Settings app
  will toggle the same file later.

### kmedia Phase 1 — the helix (THE BUTTERFLY)
- `src/core/kmedia.zig`: PipeWire monitor capture on a thread (hand-declared
  extern surface + tiny C shim `kmedia_shim.c` for the SPA pod), radix-2 FFT
  2048, **7 octave bands on the 432 Hz ladder** (A2..A8: 108..6912 Hz),
  fast-attack/slow-release smoothing, lock-free band slots + RMS level.
- `src/ui/media.zig` peek: vertical Lissajous **figure-8** as two interleaved
  dot chains (56 dots each) precessing one full turn per 60s; 7 whispy 1px
  octave rungs clipped to the loop walls ([x_inner, x_outer] per side),
  thickening with band energy, ghost whisp above e>0.45.
- Accidental magic: at full precession width it reads as a **butterfly**
  mid-flap with the rungs as wing markings. Officially the brand.
- mpv launched by the media card uses `--ao=pipewire,...` so playback is
  visible to the monitor capture.
- Media peek redraws every frame (animation); frame cadence is the
  wlroots `handleFrame` callback — vsync-locked.

### VM audio environment (fresh-one)
- No audio hardware: null-sink config at
  `~/.config/pipewire/pipewire.conf.d/kidul-sink.conf`
  (`support.null-audio-sink` adapter, `Audio/Sink`, monitor.passthrough).
- Installed: `wireplumber` (enabled user service), `pipewire-audio`.
- Do NOT reference `libpipewire-module-null-sink` — not shipped.
- `kmedia-test` binary prints live band levels for debugging.

## Pending / next

- Dogfood KidulSD on the host (real GPU/audio) — tune FFT sensitivity,
  ghost threshold, attack/release against real music.
- kmedia Phase 2+: per-app mixer, MPRIS over D-Bus from Zig, media IPC
  (`media_bands subscribe`, `media_visual_mode`). Full plan + questions
  for Andrew Kelley in `docs/kmedia-zig-audio-endgame.md`.
- RAM gauge rejoins the temp group when the gauge redesign lands.
- Media card "dicky" note: Left on the top category pills closes the card
  (this is the locked back-to-tray gesture — intentional, but watch how
  it feels in use).

## Build/deploy workflow

See `KNOWN_CMDS.md` — build on host, scp to `kidul@127.0.0.1:2260`,
systemctl restart. Apocalypse backup procedure also in KNOWN_CMDS.
