# Peek glass with user-changeable colored border

Session: 2026-07-15, KidulWM black-glass peek work on `bob-is-a-douche`.

## When this applies

- User wants the black peek glass to extend all the way to the edge of the peek.
- User also wants a colored border around the glass layer, tunable at runtime.
- Existing chrome overlay is per-window and can be occluded by client surfaces
  or by the focused window's scene tree.

## Verified solution

1. Move the chrome overlay out of the per-window wrapper tree into the
   **server-level overlay scene tree** (`server.overlay_tree`) in
   `src/window.zig::updateChrome`. Then it renders above the client surface and
   above the focused window's chrome.
2. Position the chrome node at the window's world coordinates (snap in
   `setLayoutTarget()`, follow transitions in `tickAnimation()`).
3. In `src/render/chrome.zig`, for peeks (`!edges.eql(EdgeMode.all)`):
   - Fill the peek wrapper area with the black glass (full area or slightly
     inset only for hidden off-screen edges).
   - After glass and border ring, stroke a 2–4 px line just inside the wrapper
     bounds using `CAIRO_OPERATOR_SOURCE` so it stays opaque on top of the dark
     glass.
   - Use a dedicated style token rather than hard-coding the color.
4. Add the new token to `src/core/style.zig`, e.g.:
   ```zig
   peek_glass_border_color: Color = .{ .r = 0x94, .g = 0x8E, .b = 0x7B, .a = 0xFF },
   ```

## Pitfalls found

- A per-window `scene_tree` node will be covered by the focused surface if the
  focused window is raised after chrome creation. `overlay_tree` or the root
  scene tree is required.
- `CAIRO_OPERATOR_SOURCE` is needed for the stroke; translucent operators let the
  dark glass swallow a thin colored line.
- For square-corner peeks, the hidden-edge `DEST_OUT` clear strip must be only
  `border_width + 1` wide. The older rounded-corner clear width
  `min(w/2, depth+border+1)` removes too much of the visible seam border when
  corners are `.none`.
- GTK/libadwaita title bars are client-side decorations. The title-bar toggle
  must be paired with per-user GTK CSS (`~/.config/gtk-4.0/gtk.css`) to actually
  hide them; env vars alone are ignored by GTK4.

## Color wiring

- At runtime, `kidulwm-control set_theme peek_glass_border_color <hex>` can be
  supported once the token is added to the theme parser; until then, change the
  default in `src/core/style.zig` and rebuild.

## Verification steps

- `zig build` on the host.
- `scp` binary to the work VM, stop `kidulwm`, overwrite `/usr/bin/kidulwm`,
  restart.
- Spawn >=3 Ghostty windows, cycle focus so both side peeks are visible.
- Confirm a colored border is visible where the peek meets the focused slide.
- If no border appears, the overlay is still on the wrong layer, not the color.
