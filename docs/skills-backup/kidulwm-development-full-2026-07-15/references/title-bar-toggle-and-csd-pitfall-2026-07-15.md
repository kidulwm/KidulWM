# Title-bar toggle and CSD pitfall

## Goal

Let the user toggle between "client title bars visible" and "compositor chrome
only" without breaking existing windows. The toggle is runtime via
`kidulwm-control set_theme show_title_bars true/false`.

## Existing wiring

- `src/core/style.zig` defines `show_title_bars: bool = false`.
- `src/server.zig` `handleNewToplevelDecoration` requests
  `wlr.XdgToplevelDecorationV1.Mode.server_side` when `show_title_bars` is
  false, and `.client_side` when true.
- `kidulwm-control` parses `set_theme show_title_bars <value>` and the server
  applies the change in `applyTheme` (`server.zig` line ~1197).

## What was added

- `server.zig` calls `applyTitleBarEnvironment()` at startup and whenever the
  flag changes. It sets/unsets these environment variables in the compositor
  process so child apps launched from KidulWM inherit them:
  - `GTK_CSD=0`
  - `GDK_DEBUG=no-csd`
  - `QT_WAYLAND_DISABLE_WINDOWDECORATION=1`

## Non-breaking rule

Existing windows keep the mode they negotiated at map time. The toggle only
affects new windows. This avoids on-the-fly decoration renegotiation that can
blank or crash clients.

## Pitfall: GTK4 / libadwaita still show CSD

GTK4 with libadwaita ignores both `xdg-decoration` SSD requests and
`GTK_CSD=0`. Apps like Ghostty, Nautilus, etc. will still draw their own title
bars and rounded window frames. The visible frame is then pure client CSD, not
the compositor chrome.

### How to tell

If changing the compositor chrome's `corner_style`, border color, or
`border_width` produces no visible change on the window, the visible frame is
CSD. A conclusive test is to temporarily set the peek/focused border color to a
bright neon value; if it still does not appear, the compositor overlay is
occluded by or behind the client surface.

### The minimal GTK4 CSS override

For per-user suppression of GTK header bars and rounded CSD frames, create:

`~/.config/gtk-4.0/gtk.css`:

```css
window, window decoration, headerbar, .titlebar, .windowcontrols, decoration {
  border-radius: 0px;
  box-shadow: none;
  border: none;
}
headerbar, .titlebar, .windowcontrols, .windowcontrols button {
  min-height: 0;
  padding: 0;
  margin: 0;
  border: none;
  background: transparent;
  color: transparent;
}
headerbar *, .titlebar * {
  opacity: 0;
}
decoration {
  border-radius: 0;
  box-shadow: none;
}
```

And the same file in `~/.config/gtk-3.0/gtk.css` for GTK3 apps.

This makes the compositor's square border/ring visible. It is a user-level
override because apps launched outside KidulWM will also pick it up.

### Scene order note

In `src/window.zig`, raise `chrome_tree` to the top of its wrapper scene tree
after creation so the compositor border can't be covered by later sibling
nodes:

```zig
const tree = self.scene_tree.createSceneTree() catch return;
tree.node.raiseToTop();
```

### Next options if env vars + CSS are not enough

1. Cover the CSD area with the compositor chrome overlay and verify with a
   temporary neon border.
2. Document that apps launched outside KidulWM's environment will not inherit
   the variables; users can set them in their shell profile if they want a
   global no-CSD environment.

## Verification

- `zig build && zig build test --summary all`
- Deploy to a disposable VM.
- Check journal for `KidulWM: disabling client title bars` or
  `KidulWM: enabling client title bars`.
- Spawn three Ghostty windows from within the compositor (not from an unrelated
  shell) and check for title bars.
- Test toggle: `kidulwm-control set_theme show_title_bars true`, then spawn a
  new window; it should have CSD. Then `set_theme show_title_bars false`, then
  spawn another new window; it should lack CSD.
