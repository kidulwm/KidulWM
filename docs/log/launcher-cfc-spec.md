# CFC Launcher Spec — DRAFT (awaiting Barticus lock)

Status: **DRAFT** — prepared 2026-09-15 from the Barticus tray→launcher locks.
Nothing here is implemented; this is the target design for the cut that
replaces the tray panel with a center-screen launcher overlay.

## 1. What dies, what survives

- **Dies:** the tray peek PANEL — the side panel, its scene buffers, stack
  buttons, underline spring, and panel-geometry hit-testing.
- **Survives:** the tray PAYLOAD — the item list, their actions, selection /
  ordering / scroll state, and the toggle door. In `src/ui/tray.zig` these
  halves are now marked with
  `// == LAUNCHER PAYLOAD (survives the CFC cut) ==` and
  `// == END LAUNCHER PAYLOAD / BEGIN PEEK PANEL (dies in the CFC cut) ==`
  so the next session can lift the payload cleanly.

## 2. The CFC launcher overlay

- Center-screen overlay, Star-Wars-entrance spirit.
- **Instant presence** with a fast **cosmetic fade-in (~120–180 ms)** — the
  overlay is fully interactive from frame one; the fade is decoration only.
- **Uniform font size** — NO size ramp between focused and unfocused lines.
- Focused line rendered in **soft white**; all other lines same size in the
  normal muted color.
- Content is the surviving launcher payload (items, ordering, selection),
  drawn center-screen instead of in the peek panel.

## 3. The two doors

- **kidulButton** (alias "rkt-button"): the bottom-right-peek logo button —
  post-Barry, the remaining logo at the bottom of the peek. Mouse-clickable;
  toggles the launcher overlay.
- **SW (Super/Mod4) key** on the crosspad: identical action. Both doors take
  the same path as the existing keyboard `tray.toggle` path
  (`server.zig` `tray_toggle` → `tray.toggle()`).

## 4. Gauges — optional independent pack

- Gauges (temps/speeds) become an **optional, independent pack** with **zero
  tray coupling**.
- Toggleable by the user, or auto-triggered on a **warning threshold**.
- They do not open with the launcher and do not depend on tray state.

## 5. Media player ownership

- The media player is owned by the **Server**, not the tray. The tray (and
  later the CFC launcher) may render media state but owns nothing of the
  player.
