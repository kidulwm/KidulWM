# Final peek glass + colored rim recipe

Session: 2026-07-15. Goal was to make SlideDeck peek windows show black glass
all the way to the wrapper edge, with a 2 px colored border that the user can
theme. The visible border color must stay in sync with the unfocused-slide
border color (`style.color_border`).

## What worked

- Chrome tree must be created under `server.overlay_tree`, then raised with
  `tree.node.raiseToTop()`, and its position updated on every layout/animation
  frame. Root `server.scene.tree` can end up below a raised focused window.
- Peeks get a full-wrapper black-glass fill, then a hard 2 px stroke drawn with
  `CAIRO_OPERATOR_SOURCE` so it is not blended away by the dark glass.
- Hidden off-screen edges are trimmed with `CAIRO_OPERATOR_DEST_OUT`.
- The border color comes from `style.color_border` (the same token used for
  unfocused slides in `src/core/layout.zig`), and `applyTheme` syncs
  `peek_glass_border_color` whenever `border` is changed via IPC.

## Theme tokens

In `src/core/style.zig`:

```zig
    color_border: Color = Color.fromHex(0x4d4a40),
    peek_glass_border_color: Color = Color.fromHex(0x4d4a40),
```

## `src/render/chrome.zig` — peek branch

Inside `renderChrome`, after the transparent paint:

```zig
    if (is_peek) {
        scaled_style.corner_style = .none;
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.85);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_rectangle(cr, 0.0, 0.0, w, h);
        c.cairo_fill(cr);

        const outer_border_w: f64 = 2.0 * @as(f64, @floatFromInt(s));
        c.cairo_set_line_width(cr, outer_border_w);
        setSource(cr, style.color_border, 1.0);
        c.cairo_rectangle(cr, outer_border_w / 2.0, outer_border_w / 2.0,
            w - outer_border_w, h - outer_border_w);
        c.cairo_stroke(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        // Trim hidden off-screen edges for peeks.
        const clear_w = @min(w / 2.0, depth + border + 1.0);
        const clear_left = if (!edges.left) clear_w else 0.0;
        const clear_right = if (!edges.right) clear_w else 0.0;
        const clear_top = if (!edges.top) clear_w else 0.0;
        const clear_bottom = if (!edges.bottom) clear_w else 0.0;

        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_DEST_OUT);
        if (clear_left > 0.0) c.cairo_rectangle(cr, 0.0, 0.0, clear_left, h);
        if (clear_right > 0.0) c.cairo_rectangle(cr, w - clear_right, 0.0, clear_right, h);
        if (clear_top > 0.0) c.cairo_rectangle(cr, 0.0, 0.0, w, clear_top);
        if (clear_bottom > 0.0) c.cairo_rectangle(cr, 0.0, h - clear_bottom, w, clear_bottom);
        c.cairo_fill(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);
    }
```

## `src/window.zig` — chrome tree creation

Replace the per-window `self.scene_tree.createSceneTree()` with:

```zig
        const tree = self.server.overlay_tree.createSceneTree() catch return;
        tree.node.setPosition(
            @intFromFloat(@round(self.animation.cur_x)),
            @intFromFloat(@round(self.animation.cur_y)),
        );
        const is_peek = !edges.eql(chrome_renderer.EdgeMode.all);
        if (is_peek) tree.node.raiseToTop();
        self.chrome_tree = tree;
```

Update position in both `setLayoutTarget` and `tickAnimation`:

```zig
        if (self.chrome_tree) |chrome| {
            chrome.node.setPosition(
                @intFromFloat(@round(self.animation.cur_x)),
                @intFromFloat(@round(self.animation.cur_y)),
            );
        }
```

## `src/server.zig` — sync peek border to unfocused-slide border

In `applyTheme`, when the `border` key changes:

```zig
        } else if (std.mem.eql(u8, key, "border")) {
            self.theme.color_border = style.Style.Color.fromString(value) catch |err| {
                std.log.warn("invalid border color '{s}': {}", .{ value, err });
                return;
            };
            self.theme.peek_glass_border_color = self.theme.color_border;
        }
```

## Diagnostic workflow

If the colored rim is not visible:

1. Make it bright red/yellow and 4 px wide temporarily to guarantee visibility.
2. If it still does not appear, the overlay is on the wrong scene layer: move it
   into `server.overlay_tree` and call `raiseToTop()`.
3. If it appears but moves away from the window, add the position update to
   `setLayoutTarget` and `tickAnimation`.

## Deploy checklist

```bash
cd /home/dad/dev/KidulWM
zig build
# TARGET: bob-is-a-douche  PORT: 2228
scp -P 2228 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm.new
ssh -p 2228 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm.new /usr/bin/kidulwm && sudo chmod 755 /usr/bin/kidulwm && sudo systemctl start kidulwm && systemctl is-active kidulwm'
```

Then spawn three Ghostty windows and confirm the visible seam of each peek
shows the border.
