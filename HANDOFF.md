# KidulWM HANDOFF — Aug 8 2026 (session 5)

## Session summary

Battery arc complete, end to end: satellite → slide → tray glyph. Also
installed power-profiles-daemon on fresh-one for real power mode control.

## What was built this session

### signal-battery satellite (kbrain repo, src/signal-battery.zig)
- Reads /sys/class/power_supply/BAT* (capacity, status, energy_full OR
  charge_full for health) + `powerprofilesctl get`
- Writes /tmp/kidul-signals/battery.state ("85% ok battery") and
  battery.detail ("pct charging minutes health profile") every 2s,
  atomic via .tmp+rename
- No BAT* (VMs): simulates perpetual discharge 95→15, snap back to 95.
  NEVER simulates charging — tray glyph hides when charging and VMs exist
  to look at the glyph
- Severity: alert ≤15%, warning ≤30% (when not charging)

### ksignals battery slide (ksignals repo)
- 50 whispy lines on the butterfly wings, 1 per 2% — wing density IS the
  charge (decorative for Granny, real digits beside it: 44px % readout)
- Soul dot breathes faster when charging
- Stats: charge, state, time remaining, health, profile
- Power profile pills: "Long lasting / Balanced / Fast" — ←→ move focus,
  Enter applies via `powerprofilesctl set` (optimistic UI, satellite
  confirms). power-profiles-daemon installed+enabled on fresh-one
- battery.detail parsed in App.zig scanBatteryDetail()

### Tray battery glyph (KidulWM network.zig drawBatteryIcon) — DONE & SET
- Landscape car-battery, whispy stroke, 2 terminal posts (w=0.63r,
  h=1.3×nub) at 18%/82% of top edge
- 6 waved cell-bars (real 12V anatomy = 6 cells) — lit portion rises
  from the BOTTOM with charge; ghost bars full height show the scale
- LEFT of the beacon (VPN further left), gap 18px×scale
- y-nudge: cy − 4.5px×scale (beacon's visual mass sits above centerline)
- Visible ONLY when discharging — hidden on AC/charging
- Data: battery.detail via compositor scanBattery (falls back to /sys
  when satellite absent). Amber < 20%
- LOCKED commit 79c71a3

## Key commits

| Repo | Commit | Description |
|---|---|---|
| KidulWM | `79c71a3` | battery icon DONE & SET |
| ksignals | `59d7095` | battery slide: 50-line charge butterfly + power profile pills |
| kbrain | `6e8838d` | signal-battery satellite + sim |

## Next up

1. Network slide: available networks (scan), saved networks, current —
   connect/disconnect/forget via nmcli. "Disguise this device" MAC-spoof
   toggle (wifi.cloned-mac-address random), off by default, gold when on,
   no MAC addresses shown on the Granny side
2. Bluetooth slide LAST (BlueZ D-Bus: scan/pair/remove/trust)
3. Beacon click launches ksignals (currently Ctrl+S only)
4. Rip dead card code from compositor (drawSignalsCard/drawSignalPill etc.)
5. Later: sacred healing frequencies on butterfly rungs (432Hz + Solfeggio)

## Design rule locked this session

Butterfly geometry IS the data, never decoration. If a slide's butterfly
looks identical regardless of state, we failed.

---

# KidulWM HANDOFF — Aug 8 2026 (session 4, archived)

## Session summary (previous)

Big kfiles redesign session. Moved kfiles from an in-compositor card to a
standalone Wayland satellite that fills the focused slide. Full visual
overhaul: stadium-shaped pills, centered focus, breadcrumb navigation,
system color matching, 3D shading, and TV-readable sizing. Also fixed a
long-standing compositor crash on window close and added Ctrl+Q keybind.

## Key commits

| Repo | Commit | Description |
|---|---|---|
| KidulWM | `e4dd942` | tray in place — centered vertically on peek |
| KidulWM | `80f19bd` | fix: window destroy listener removal + Ctrl+Q close-window keybind |
| kfiles | `dea737b` | tray getting stuck open when opening kfiles + drive grouping + breadcrumb ellipsize + nav flow + sizing |

## What's working

### kfiles (standalone satellite)
- Full slide layout: drive pills → breadcrumbs → search bar → file list → preview
- All elements use stadium shape (full rounded ends) — same shape language
- System colors: card_mat #0a0a0b, gold #696555, text #948e7b, muted #6a6354
- 3D shading on textbox card (gold highlight bottom/right, black shadow top/left)
- Grey border all around textbox (2px, muted at 0.25)
- Equal 56px gaps on both sides of the slide
- Scrollbar in right gap, centered, weather-card timeline scrubber style
  (8px track, gold fill at 0.18, focused border stroke, gold ball/knob)
- Scrollbar spans full slide height (pad to h-pad)
- Drive pills: 60px tall, 320px wide, fixed width, stadium shape, Bob's special shading
- One pill per physical drive (partitions grouped by parent device)
  - vda → "System", sda → "Drive A", nvme → "NVMe", mmc → "SD Card"
- Breadcrumb pills: 50px tall, 180px fixed width, text ellipsized with "..."
  - Current folder centered on screen, parents trail left fading 25% per level
- Search bar: 50px, stadium shape, centered text
- File rows: 50px, stadium shape, focused line text 18% larger
- Focus stays dead center at all times — only 1 row relax at top/bottom extremes
- Textbox fills full allocated space, rows clipped inside, offset to center focus
- Navigation flows top to bottom: pills → crumbs → search → files → preview
- Arrow keys + Enter + BackSpace all work; force redraw on keypress (frame_pending cleared)
- Drive pills highlight current drive (startsWith path match)

### KidulWM compositor
- Tray centered vertically on the peek (screen center, no shift)
- Ctrl+Q closes focused window (same as Mod4+Q)
- Window destroy bug fixed: destroy.link.remove() in handleDestroy
  (was crashing compositor on every window close — wlroots assertion)
- Keybind system now supports Ctrl+ modifier in defaults and config parser

## What's NOT done / known bugs

### kfiles
- **Tray gets stuck open** when kfiles is launched from it — tray calls
  close() but panel stays visible. Needs investigation in tray close animation.
- **Search bar & breadcrumbs don't highlight when focused** — focus area
  is tracked but no visual indication on those elements
- **Breadcrumb home pill needs a lock icon** — require sudo to access
  files above /home/kidul
- **Drive pills not centered on focus** — focused drive pill should center
  on screen like breadcrumbs do
- **Folder icon** still at bottom of preview area (pinned)
- **Inteliscroll** untested, **drive pills** need restoring, preview needs content
- kfiles deploys to /usr/local/bin/kfiles NOT /usr/bin/kfiles
- Always rm -rf .zig-cache zig-out before building kfiles — stale cache bit us

### KidulWM
- Tray stuck open bug (above) may be in tray_anim not animating to 0
- Spyglass hover-triggered peek reveal still not implemented
- 2-option selector, hotkey bindings for spyglass not done
- Sliders repurposed (browser history → deck navigation) not done

## Deploy notes
- kfiles: build on host, deploy to /usr/local/bin/kfiles
- KidulWM: build on host, deploy to /usr/bin/kidulwm
- Always rm -rf .zig-cache zig-out before building
- VM: virsh -c qemu:///system start fresh-one, then hostfwd_add tcp::2260-:22
- Mod+R reloads KidulWM (systemd restarts it)
- Ctrl+Q or Mod4+Q closes focused window

## Design decisions (locked)

- Stadium shape (full rounded ends) everywhere — pills, search, focused line
- Everything centered — focus comes to you, you don't chase it
- "We are the movie, not the theater" — UI moves so the user's head doesn't
- System colors from KidulWM style.zig — not custom kfiles colors
- Drive pills show one pill per physical drive, friendly labels for Granny TV
- Breadcrumb current folder centered, parents trail left fading
- 56px equal gaps on both sides of the kfiles slide
- Tray centered vertically on peek — set and forget

## Apocalypse backup

Both repos backed up to /mnt/lacie-apocalypse/ (Aug 6 session):
- kidulwm-apocalypse-20260806_1832.bundle (git bundle, all history)
- KidulWM-src/ (rsync'd source tree)
- kfiles-src/ (rsync'd source tree)

## State of mind

From "kfiles is a small card inside the compositor" to "kfiles is a
full-screen file manager that looks like a movie title card" — one session.
Stadium pills, centered focus, breadcrumbs that fade into the darkness,
a scrollbar that looks like jewelry. The file manager nobody knew they
wanted.

The window destroy bug was the silent killer — every Ctrl+Q or Mod4+Q
was crashing the compositor because one listener was never detached.
One line: `window.destroy.link.remove()`. Classic.

Good day. 🎭

---

# KidulWM HANDOFF — Aug 8 2026 (session 4)

## Session summary

Major architecture pivot: moved from compositor-rendered cards to standalone
Wayland satellite apps. Built kslide-template (shared theme template) and
ksignals (first app built on the template). Compositor Ctrl+S now launches
ksignals as a real Wayland window, not a card.

## What was built

### kslide-template (/home/dad/dev/kslide-template/)

Standalone Wayland satellite template for ALL KidulWM slide apps. Every
app built on this fills the focused slide naturally because it's a real
Wayland window positioned by the compositor.

Files:
- src/c.zig — C imports (wayland, cairo, xkbcommon)
- src/Theme.zig — shared theme: 3 background layers, stadium pill helper
  - color_card_mat = #0a0a0b (darkest, slide background)
  - color_textbox = #1F1E1C (mid warm grey, gold 0.15 over card_mat, matches weather card panels)
  - color_gold = #948e7b (text color)
  - severity colors: ok=#948e7b, warning=#d97230 (burnt orange), alert=#b82e2e (red), muted=#6a6354
  - drawPill() helper — stadium shape with shadow + glass body + border
  - roundedRect() helper
- src/Wayland.zig — generic Wayland boilerplate (connect, surface, shm,
  double-buffered, keyboard, pointer, render loop, frame callbacks)
  - Calls app.tick(), app.render(), app.handleKey() — doesn't know what the app does
  - Takes app_id and title strings for the toplevel
- src/App.zig — minimal app interface (init/deinit/tick/render/handleKey)
- src/main.zig — entry point
- build.zig — links cairo, wayland-client, wayland-cursor, xkbcommon
- protocol/ — wayland protocol headers (copied from kfiles)

Build: cd kslide-template && zig build (compiles clean)

### ksignals (/home/dad/dev/ksignals/)

First app built on kslide-template. Signal beacon + full slide for signal
details. Built from the template, not from the compositor.

Files:
- src/App.zig — signal scanner (reads /tmp/kidul-signals/*.state every 500ms),
  navigation state (pills vs details focus), sacred butterfly animation phase,
  key handling (left/right cycle signals, down/enter to details, up/down scroll,
  tab/escape back to pills)
- src/Renderer.zig — three-layer render:
  1. Slide background (card_mat darkest)
  2. Signal pills at top (Granny zone — stadium pills, severity dots, name+state)
  3. Nerd zone below (textbox bg, sacred butterfly visualization, signal title,
     state, scrollable nerd stats)
  - Sacred butterfly = Lissajous figure-8 from media player, two interleaved
    dot chains, slow precession (60s per turn), pulsing rungs, severity-tinted
    soul dot at center with breathing ring
- src/Wayland.zig, src/Theme.zig, src/c.zig — copied from template
- src/main.zig — entry point (app_id: com.kidulwm.ksignals, title: Signals)
- build.zig — same as template

Build: cd ksignals && zig build (compiles clean)
Deploy: scp to VM, cp to /usr/local/bin/ksignals

### Compositor changes (KidulWM)

- Ctrl+S now spawns /usr/local/bin/ksignals (Wayland satellite), not the old card
- signals_card_toggle action in keybinds.zig now calls server.spawnCommand
- All former card renderers (weather, network, media, calendar, files, signals)
  had card_frame removed — fill background with color_card_mat directly
- updateCard fills full focused window box (no shrink, no shadow)
- card_shadow_tree disabled (setEnabled(false))
- Beacon (network icon in clock widget) color = worst severity, 500ms poll
- Signal data structures (SignalEntry, SignalSeverity, scanSignals, worstSeverity,
  severityColor, signalHash) still in tray.zig for the beacon

## Navigation

- Left/Right — cycle through signal pills (Granny zone)
- Down/Enter — enter nerd zone for selected signal
- Up/Down — scroll nerd details
- Tab/Escape — back to pills
- Escape (from pills) — close ksignals

## What's working

- kslide-template compiles clean, runs as Wayland window
- ksignals compiles clean, deployed to VM at /usr/local/bin/ksignals
- Ctrl+S launches ksignals — fills focused slide
- Signal pills show network, battery, bluetooth with severity colors
- Sacred butterfly animation running (gold for OK, severity-tinted otherwise)
- Signal scanning from /tmp/kidul-signals/ every 500ms

## What's NOT done / next up

- Wireshark-like traffic scans visualized in sacred butterfly style
  (user requested — "cybersec workers will be lining up")
- More nerd stats per signal: real-time graphs, connection tables, traffic flow
- Network: live RX/TX graph, connection list, signal strength
- Battery: charge curve, health, cycle count, voltage, temperature
- Bluetooth: connected devices, signal strength per device
- Audio: volume level, output device, input level visualization
- CPU/memory/disk graphs
- Click handling on pills (touch/mouse)
- Beacon click should launch ksignals (currently only Ctrl+S)
- Remove old card system from compositor (card_anim, card_tree, card_box — legacy now)
- kfiles should eventually use shared Theme.zig from template
- More signal satellites (bluetooth, battery, audio — only network exists)
- The old compositor signals card (drawSignalsCard, drawSignalPill in tray.zig)
  is now dead code — can be removed

## Deploy

```bash
# Build and deploy ksignals
cd /home/dad/dev/ksignals
rm -rf .zig-cache zig-out && zig build
scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/ksignals kidul@127.0.0.1:/tmp/ksignals
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo cp /tmp/ksignals /usr/local/bin/ksignals && sudo chmod 755 /usr/local/bin/ksignals'

# Build and deploy KidulWM
cd /home/dad/dev/KidulWM
rm -rf .zig-cache zig-out && zig build
scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm-new
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm-new /usr/bin/kidulwm && sudo systemctl start kidulwm'

# Signal files on VM
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'mkdir -p /tmp/kidul-signals && echo "wlan0 ok wifi" > /tmp/kidul-signals/network.state && echo "87% ok battery-charging" > /tmp/kidul-signals/battery.state && echo "2devices ok bluetooth" > /tmp/kidul-signals/bluetooth.state'
```

## Design decisions (locked)

- Full slides, not cards — whole focused area IS the surface
- kfiles is the style guide for all slides
- kslide-template is the foundation for all new slide apps
- New apps = standalone Wayland satellites, not compositor-rendered
- Beacon in peek (top-right network icon), color = worst severity, 500ms poll
- Battery icon only when on battery power
- Ctrl+S or click beacon launches ksignals
- Signal pills keep severity coloring design
- Sacred butterfly visualization for all live data (from media player)
- Nerd stuff scrollable, sacred butterfly visuals for network stats
- 3 background layers: card_mat (darkest), textbox (warm grey), gold text
- Never modify kfiles — copy from template

## Repos

- KidulWM: /home/dad/dev/KidulWM/ (compositor)
- kfiles: /home/dad/dev/kfiles/ (file manager — style guide)
- kslide-template: /home/dad/dev/kslide-template/ (template for slide apps)
- ksignals: /home/dad/dev/ksignals/ (signals app)
- kbrain: /home/dad/dev/kbrain/ (Bob the Builder PI)

Enjoy the park. 🦋

---

# KidulWM HANDOFF — Aug 8 2026 (session 3)

## Session summary

Two major changes: (1) signal beacon + full slide system, (2) all former
cards converted to full slides. No more card frames, shadows, or
shrinking. Everything fills the entire focused window box like kfiles.

## Signal beacon + signals slide

- Beacon = former network icon in right peek (clock widget buffer)
- Color reflects worst severity across all signals (ok=gold, warning=amber, alert=red, muted=grey)
- Battery icon shows next to beacon ONLY when on battery (existing code)
- Signal scan polls /tmp/kidul-signals/*.state every 500ms
- Ctrl+S or click beacon opens signals full slide
- Signal pills keep stadium design with severity coloring (shadow, glass body, severity rim, dot, name+state text)
- Details section below pills (name: state + severity dot per signal)
- scanSignals(), worstSeverity(), severityColor(), signalHash(), drawSignalsCard(), drawSignalPill()

## Full slide pivot (ALL former cards)

ALL former cards (calendar, weather, media, network, files, signals) are
now full slides. The updateCard function:
- Uses full focused_window_box dimensions (no more w-=140, h-=120 shrink)
- Positions at box.x, box.y (no centering offset)
- No shadow rendering (shadow tree disabled, setEnabled(false))
- All renderers fill background with color_card_mat (#0a0a0b at 0.91 alpha)
- No card_frame.Registry.default.drawNamed calls anywhere
- No borders, no clip, no rim — just the dark background and content

Files changed:
- tray.zig: updateCard rewrite, drawSignalsCard, drawClockCalendarCard
- weather.zig: renderCard background
- network.zig: renderCard background, removed card_frame import
- media.zig: renderCard background
- files_card.zig: renderCard background

## Keybinds

- Ctrl+S = toggle signals card (signals_card_toggle)
- Click beacon = toggle signals card
- Mod+M = media card toggle (unchanged)
- All other keybinds unchanged

## What's working

- Compiles clean on Zig 0.16.0
- Deployed to fresh-one VM
- Signal files: network.state, battery.state, bluetooth.state (all OK)
- Beacon color responds to signal severity changes (500ms poll)
- All slides fill full focused area, no card frames

## What's NOT done / next up

- Visual verification (no vision on current model — user checks via SPICE)
- Signal pill click handling on the slide
- Icon rendering from icon_hint (dot only for now)
- Signal settings sub-slides (each signal opens config)
- More signal satellites (bluetooth, battery, audio)
- Slide animation/transition polish for full slides
- Scrollable details section (more detail as you scroll down)
- card_frame.zig is now unused but kept in repo (can be removed later)
- card_shadow_tree still exists but is always disabled (can be removed)
- Consider whether card_anim/card_tree/card_box naming should become slide_anim/slide_tree/slide_box

## Deploy

```bash
cd /home/dad/dev/KidulWM
rm -rf .zig-cache zig-out && zig build
scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm-new
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm-new /usr/bin/kidulwm && sudo systemctl start kidulwm'
```

## Design decisions (locked)

- Full slides, not cards — whole focused area IS the surface
- kfiles is the style guide for all slides
- Beacon in peek, everything else on the full slide
- Signal pills keep severity coloring design
- Battery icon only when on battery power
- 500ms signal poll for snappy beacon response

---

# KidulWM HANDOFF — Aug 8 2026 (session 2)

## Session summary

Tray signal pills landed. The tray now reads /tmp/kidul-signals/*.state
files and renders stadium pills in the right peek, between the clock
and media widgets. Each pill shows the signal name (left, muted gold),
a severity dot, and the state text (right, severity-colored).

## What was built

### Signal pill system (tray.zig)

- `SignalSeverity` enum: ok, warning, alert, muted
- `SignalEntry` struct: name, state_text, severity, icon_hint (fixed buffers)
- `PerOutputSignals` struct: per-output scene tree, buffer, redraw tracking
- `MAX_SIGNALS = 8` — up to 8 signal pills rendered

### scanSignals()
- Polls /tmp/kidul-signals/ every 2s (same interval as network scan)
- Reads each *.state file, parses "state_text severity icon_hint"
- Filename minus .state is the signal name
- FNV-1a hash of all signal content for change detection
- No D-Bus, no daemon — just files. Directory IS the registry.

### drawSignalWidget()
- Positioned in right peek between clock (top) and media (bottom)
- Claims available height: box.height - clock_height - media_height
- Stadium pills (32px tall, 6px gap), centered vertically in buffer
- Uses panelOutline + roundedRect — same shape language as tray buttons
- Redraws only when signal count, hash, size, or theme changes

### drawSignalPill()
- Shadow (offset 2px right, 3px down, 0.35 alpha)
- Glass body with severity tint in middle band (0.15 alpha)
- Severity-colored rim (0.55 alpha, 1px stroke)
- Severity dot on left (3.5px radius, 0.9 alpha)
- Signal name in muted gold (left, after dot)
- State text in severity color (right-aligned)
- Dark text shadow on both (0.7 alpha, 1px offset)

### Severity colors
| Level    | Color source           | RGBA                              |
|----------|------------------------|-----------------------------------|
| ok       | style.color_gold       | #948e7b (system gold)             |
| warning  | hardcoded amber        | 0.851, 0.447, 0.18                |
| alert    | hardcoded red          | 0.72, 0.18, 0.18                  |
| muted    | style.color_text_muted | #6a6354 (system muted)            |

### Wiring
- `signal_widgets` ArrayList added to Tray struct
- `signals[MAX_SIGNALS]` and `signal_count` on Tray
- `signal_last_scan_ms` for 2s poll interval
- init/deinit/addOutput/removeOutput all wired
- `scanSignals()` + `drawSignalWidget()` called in update() after network
- `destroySignalWidget()` for cleanup
- `dirent.h` and `string.h` added to tray.zig c_std import

## What's working

- Compiles clean on Zig 0.16.0
- Signal files on host: network.state, battery.state, bluetooth.state
- Binary builds to zig-out/bin/kidulwm (38MB)
- Not yet deployed to VM or visually verified

## What's NOT done / next up

- **Deploy to VM and visually verify** — need to copy signal files to
  the VM's /tmp/kidul-signals/ and check rendering
- **Click handling** — signal pills don't respond to clicks yet
  (need click_box tracking + open settings slide)
- **Icon rendering** — icon_hint is parsed but not drawn (dot only)
- **Signal settings slides** — clicking a pill should open a config slide
- **More signal satellites** — bluetooth, battery, audio (only network exists)
- **inotify** — currently polls every 2s; could use inotify for instant updates
- **Animation** — pills appear/disappear instantly, no stagger animation

## Deploy notes

```bash
cd /home/dad/dev/KidulWM
rm -rf .zig-cache zig-out && zig build
scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm \
  zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm /usr/bin/ && sudo systemctl start kidulwm'
# Copy signal files to VM:
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'mkdir -p /tmp/kidul-signals && echo "wlan0 ok wifi" > /tmp/kidul-signals/network.state'
```

Signal satellites run on the host and write to /tmp/kidul-signals/.
The VM needs its own signal files or a shared mount.

## Key commits

This session's work is not yet committed. When committed, will be under
the tray signal pills feature.
