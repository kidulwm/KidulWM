# TASKCARD — fullScreenLayouts (overlay yield law)

Status: OPEN — law agreed with Barticus 2026-09-05, no code yet.
Priority: HIGH — kmedia movie playback depends on it ("movies are meant
to expand to full screen when playing"). Without this, a fullscreen
movie has tray/widgets floating on top of it.

## The law (Barticus, verbatim intent)

Widgets/tray are ALWAYS on top — EXCEPT when slides fill the screen.
When 1 or more slides fill the output (fullscreen slide, or a split
that covers the whole output with no wallpaper/peek exposed), the slide
stack rises ABOVE the overlay for that output. Widgets return the
moment any wallpaper/peek is exposed again.

- PER-OUTPUT, never global: a fullscreen movie on the Kogan must not
  bury widgets on eDP-1.
- Fullscreen video playback (kmedia expansion) is the flagship case —
  100% needed for the media player.
- Split-of-2 slides filling the screen is genuinely useful (GEEK-only
  candy, Granny never goes there) and obeys the same law: if the split
  covers the output, widgets yield. 4+-way splits are stupid (Barticus)
  — not a target, but the law shouldn't care how many slides, only
  whether screen is covered.

## What exists today (cd3bf52)

- Hard stack: wallpaper (bottom) → slides/windows → overlay widgets
  (top). No exceptions, no fullscreen handling anywhere (`fullscreen`
  matches nothing in src/).
- Overlay raised to top at boot, after window raises, and after every
  wallpaper (re)apply (setupWallpaper).
- Split infrastructure exists: deck_split (left_peek/focus/right_peek),
  orientations, per-output decks. Peek values > 0 mean wallpaper shows.
- Keybind pull-from-edge (LEFT/RIGHT/TOP/BOTTOM add to current screen)
  is the planned UX — candy that rides on this law.

## What needs building

1. xdg-toplevel fullscreen request handling (set/unset fullscreen).
2. Per-output "screen covered" test: fullscreen slide present, OR
   active split with peeks == 0 covering the output box. Run at
   applyLayout time; cache the boolean per output.
3. Dynamic root-tree reorder per output: when covered state flips,
   raise that output's slide trees above overlay_tree (or lower
   overlay); restore on uncover. Needs care: overlay_tree is global,
   not per-output — likely demote the fullscreen slide's tree above
   overlay rather than moving overlay itself, OR split overlay per
   output (bigger). Design decision: cheapest correct mechanism first.
4. Kmedia hook: movie playing → expand to fullscreen (uses #1), movie
   done/paused-to-card → unexpand.
5. Smoke assertion: nested test that fullscreen slide hides widgets.

## Pitfalls

- overlay_tree is ONE global tree; raising a slide above it affects
  all outputs. Per-output correctness may require per-output overlay
  trees or scene-node-layer tricks. Think before cutting.
- Transitions: don't flicker z-order during the 2.2s boot reveal or
  slide-open animations. Only reorder on settled state changes.
- Tray pet/gauge widgets raise themselves within overlay_tree — those
  intra-overlay raises must not leak above a covering slide.
