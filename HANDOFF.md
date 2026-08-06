# KidulWM HANDOFF — Aug 6 2026

## Session summary

Theater deleted, spyglass born. We killed the entire peek/curtain/dim
machinery and replaced it with EXIT dot-matrix signage — theater exit
signs rendered as gold dot-matrix letters (5x6 grid) at the screen
edges. Clean, minimal, cinematic.

## Key commits

| Repo | Commit | Description |
|---|---|---|
| KidulWM | `082e906` | THEATER DELETED: kill curtains, peek chrome, dim overlays — focused slide full screen |
| KidulWM | `adc8094` | spyglass: whispy magnifying glass icons for peek navigation |
| KidulWM | `28f9c72` | fix: clearChrome + empty-slot guard — kill stale peek borders |
| KidulWM | `4685eca` | spyglass: EXIT dot-matrix icons + empty-slot guard fixes |
| KidulWM | `234e7a9` | spyglass: show EXIT signs on empty-slot sides |

## What's working

- Focused slide fills the screen (93%+ width), no peeks, no curtains, no dim
- Non-focused slides: setEnabled(false) + clearChrome() — zero rendering
- Empty-slot state: all slides disabled, clearFocus called
- EXIT dot-matrix icons at vertical center of left/right screen edges
  - 5x6 gold dot grid spelling E-X-I-T
  - 20px tall, 72px wide, 17px from edge
  - 54% opacity at rest, 70% on hover
  - Shows on neighbor side only (hidden when no neighbor)
  - Shows on empty-slot sides pointing back toward the row
- Click EXIT: navigates to adjacent slide (focusPrev/focusNext)
- Mod+Q close, Mod+R reload

## What's NOT done / next steps

### Spyglass / EXIT (immediate)
- **Hover-triggered peek reveal**: icons brighten on hover but no peek
  content shows yet. Need to temporarily enable adjacent slide at sliver width.
- **2-option selector**: click should offer "focus this peek" vs "go to end of row"
- **Hotkey bindings**: arrow keys for left/right peek (and up/down for rows)
- **PNG icon**: user wants to find a PNG to use instead of Cairo-drawn dots

### Architecture
- **Wallpaper slit design** was abandoned in favor of simply disabling
  non-focused slides. Simpler and cleaner.
- **Universal navigation**: plain arrows reach everywhere, boundary fallthrough
  to compositor. This is a `keyboard.zig` change.
- **Sliders repurposed**: browser history sliders → deck navigation sliders.
  Hover near edge, slider pops out showing all slides in row/layer. Separate
  from spyglass (which is just the quick neighbor glance).

### kfiles needs work
- Navigation: plain arrow keys can't navigate slides while kfiles is focused
- Inteliscroll: centered scroll code written but untested
- Pills: drive pills need to be added/restored
- Layout tweaks: icon size, spacing, text softening
- Preview: needs actual file preview content
- kfiles deploys to `/usr/local/bin/kfiles` NOT `/usr/bin/kfiles`

### Deploy notes
- kfiles: build on host, deploy to `/usr/local/bin/kfiles` (NOT `/usr/bin`)
- KidulWM: build on host, deploy to `/usr/bin/kidulwm`
- Always `rm -rf .zig-cache zig-out` before building kfiles — stale cache bit us
- VM: `virsh -c qemu:///system start fresh-one`, then `hostfwd_add tcp::2260-:22`
- Mod+R reloads KidulWM (systemd restarts it)

## Design decisions (locked)

- NO peeks at rest. Focused slide fills screen. Theater is dead.
- EXIT signs are the "peek at neighbor" affordance — theater signage, not buttons
- Three navigation tiers, equal citizens:
  1. Sliders (mouse users) — full deck map, hover edge to reveal
  2. EXIT signs (quick glance) — hover to peek, click to navigate
  3. Hotkeys (keyboard users) — arrow keys, direct flight
- Sliders will be repurposed from browser history sliders (existing component)
- We are the movie, not the theater. The UI moves so the user's head doesn't.

## Apocalypse backup

Both repos backed up to `/mnt/lacie-apocalypse/`:
- `kidulwm-apocalypse-20260806_1832.bundle` (git bundle, all history)
- `KidulWM-src/` (rsync'd source tree)
- `kfiles-src/` (rsync'd source tree)

## State of mind

From "everything leaks, windows can't be contained, 500 lines of peek
machinery" to "focused slide fills screen, EXIT signs at the edges, -206
lines net." One session. The root cause was old theater thinking —
curtains, peeks, masks. The fix was to stop thinking like a theater and
start thinking like the movie.

The wallpaper slit idea evolved into something simpler: just don't render
what you don't want to see. setEnabled(false) + clearChrome(). Done.

EXIT signs are theater signage — the one theatrical element that survived
the purge, because they're honest about what they are: a way out.

Good day. Stage right. 🎭
