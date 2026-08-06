# KidulWM HANDOFF — Aug 6 2026

## Session summary

Big day. Ghostbusted the window containment problem that's been plaguing
the project since the Zig/Cairo rewrite. Windows now sit correctly inside
their slide borders for the first time.

## Key commits

| Repo | Commit | Description |
|---|---|---|
| KidulWM | `b96ad8b` | GHOST GONE: chrome in overlay_tree, geometry clip crops CSD, no setSurfaceDestSize |
| KidulWM | `b8eb492` | WINDOWS IN PLACE: zero surface offset, content sits at wrapper origin |
| KidulWM | `247ceb7` | Keybinds: Mod+Q close focused, Mod+R reload compositor |
| kfiles | `719d85b` | kfiles is alive: force-render on configure, accept non-zero resize |
| kfiles | `fe2f009` | System border colors, centered scroll, short-wide layout, icon cap |

## What's working

- Chrome overlay in `overlay_tree` (above client surface) — windows don't leak
- `applyContainment()` clips surface to XDG geometry `(geom.x, geom.y, geom.width, geom.height)` — CSD padding cropped away
- `setSurfaceOffsetForFocus` sets offset `(0, 0)` — wlroots handles geometry internally
- NO `setSurfaceDestSize` — buffer renders at native size, clip does the cropping
- `applyContainment()` is LAST call in `handleCommit` — survives setSurfaceOffset
- Cinema masking panels in `curtain.zig` — black bars with 1px gold edge, animated entrance
- Keybinds: Mod+Q close focused window, Mod+R reload compositor (systemd auto-restarts)
- kfiles: resizes to fill slide (was stuck at 1280x800, now accepts configure)
- kfiles: system border colors (#948e7b focused, #5e5a4c unfocused)
- kfiles: centered scroll (selected line pinned to vertical center, 2-line edge relaxation)
- kfiles: short-wide layout, file list centered on screen, big preview area

## What's NOT done / next steps

### kfiles needs work
- **Navigation**: plain arrow keys can't navigate slides while kfiles is focused. Mod+J/Mod+K works. Need universal nav: boundary fallthrough to compositor.
- **Inteliscroll**: centered scroll code is written but untested (can't navigate to verify)
- **Pills**: drive pills need to be added/restored
- **Layout tweaks**: still needs overall adjustments — icon size, spacing, text softening
- **Preview**: needs actual file preview content (currently just folder icon or "press Enter" hint)
- kfiles deploys to `/usr/local/bin/kfiles` NOT `/usr/bin/kfiles` — tray uses the local path

### KidulWM architecture
- **Wallpaper slit design** (Barticus idea): copy wallpaper as overlay, cut hole for focused slide, peeks hidden behind wallpaper. Eliminates peek chrome, masks, CSD bleed on peeks. Not yet implemented — this is the next major architectural change.
- **Universal navigation**: plain arrows must reach everywhere, never strand user. Left/Right = slides, Up/Down = within app. Boundary fallthrough to compositor. This is a `keyboard.zig` change.
- **Cinema masks**: deployed but may need layering fix — `raiseAboveChrome()` after slide loop in `applyLayout`
- **`renderChromePadded`** function exists in `chrome.zig` but is NOT used — `renderChrome` is the active function. The padded version was an attempt to mask CSD with opaque fill + DEST_OUT hole. Reverted. Don't use it unless needed.

### Deploy notes
- kfiles: build on host, deploy to `/usr/local/bin/kfiles` (NOT /usr/bin)
- KidulWM: build on host, deploy to `/usr/bin/kidulwm`
- Always `rm -rf .zig-cache zig-out` before building kfiles — stale cache bit us
- VM: `virsh -c qemu:///system start fresh-one`, then `hostfwd_add tcp::2260-:22`
- Mod+R reloads KidulWM (systemd restarts it)

## Apocalypse backup

Both repos backed up to `/mnt/lacie-apocalypse/`:
- `kidulwm-apocalypse-20260806_1520.bundle` (git bundle, all history)
- `KidulWM-src/` (rsync'd source tree)
- `kfiles-src/` (rsync'd source tree)

## State of mind

We went from "windows can't be contained, everything leaks" to "windows in place, ghost gone" in one session. The root cause was: chrome was in `scene_tree` (below the XDG surface), `setSurfaceDestSize` was rendering the full CSD buffer, and the surface offset was double-shifting the content. Fixed by: chrome in `overlay_tree`, no dest size, zero offset, geometry clip.

The wallpaper slit design is the next big thing — it'll eliminate the peek/curtain/mask complexity entirely and maximize screen real estate for the focused slide and widgets.

Good day. Team work and the dreamwork.
