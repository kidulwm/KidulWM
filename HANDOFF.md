# KidulWM HANDOFF — Aug 7 2026

## Session summary

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
