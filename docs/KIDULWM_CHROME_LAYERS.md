# KidulWM Chrome / Peek Rendering Architecture

## Date
2026-07-15 — discovered and verified during the `corner-bg-fix` / peek-glass work.

## tl;dr
- Compositor chrome must live in `server.overlay_tree` to render **above** client surfaces.
- Per-window `chrome_tree` (child of the window's own scene tree) is always occluded by the client surface.
- Peek chrome should fill the whole wrapper and draw its border as a hard Cairo stroke; background-mask/border-ring geometry is unreliable when the client surface leaks through.
- Changing paint colors alone does nothing until the overlay ordering is correct.

## Scene graph order (bottom to top)
1. Desktop background
2. Window scene trees (each contains surface tree + old per-window chrome tree)
3. `server.overlay_tree` ← **this is where chrome must live**
4. Cursor

`server.overlay_tree` is created in `Server.init` and floats above all window scene trees. Children of the overlay tree are also subject to sibling order; raise peeks above focused chrome with `tree.node.raiseToTop()`.

## Where chrome was broken
`Window.updateChrome` originally created the chrome tree as a child of `self.scene_tree`. Because the client's `wlr_scene_buffer`/`surface tree` renders on top of its parent window tree, the chrome was hidden behind the app content. Moving `const tree = self.server.overlay_tree.createSceneTree()` fixed visibility.

## What we tried that did NOT work until ordering was fixed
- Changing border colors to bright red / cyan / gold.
- Drawing thick 4 px strokes.
- Moving chrome to `server.overlay_tree`'s direct sibling.
- Drawing glass inside an inset rectangle.

None of these were visible because the overlay was composited **below** the window surfaces or because the client surface leaked over it.

## What DID work
1. Parent chrome under `server.overlay_tree`.
2. Move the overlay tree node to the window's layout position each frame (`setPosition` in `setLayoutTarget` and `tickAnimation`).
3. For peeks: fill the entire wrapper with dark glass using `CAIRO_OPERATOR_SOURCE`, then stroke a hard 2 px rectangle with the unfocused border color (`style.color_border`).
4. Trim only the hidden (off-screen) edges after the border is drawn; do not trim the visible seams.
5. Set `corner_style = .none` for peeks so the visible seam edge is straight and aligned with the focused window.

## Theme linkage
- `peek_glass_border_color` defaults to `color_border`.
- Setting the `border` theme key now also syncs `peek_glass_border_color`, so peeks and unfocused slides share one border color.
- `show_title_bars` is backed by environment variables (`GTK_CSD`, `GDK_DEBUG`, `QT_WAYLAND_DISABLE_WINDOWDECORATION`) applied at startup and on toggle. Only newly launched apps pick up the change.

## Files involved
- `src/window.zig` — chrome tree creation under `server.overlay_tree`; position updates.
- `src/render/chrome.zig` — `renderChrome()`; peek vs focused drawing paths.
- `src/core/style.zig` — `peek_glass_border_color`, glass alphas, corner defaults.
- `src/server.zig` — `applyTitleBarEnvironment()`, theme sync for `border`.

## Good commits
- `b6ff45d` "Peek chrome: full dark glass with 2px unfocused-slide border"
- Tags: `greatest-yet`, `peek-glass-locked`

## Implications for future corner work
- Chamfered peek corners in Cairo are easy **as long as the glass fill continues to cover the whole wrapper**. The overlay hides the client's own rounded frame.
- Chamfering the *inner reveal* (a hole through which client content shows) would expose the client's rounded rectangle and possible shadow, so it must match the client's shape or be kept square.
