# SlideDeck neighbour placement

The SlideDeck layout centres the focused window and shows narrow "peek" slivers of unfocused neighbours on the left and right.

## Goal

The visible part of each neighbour should look like the continuation of the focused window:

- Left neighbour: show the **rightmost ~8-15%** of its window at the left screen edge, with its right edge butting up against the focused window.
- Right neighbour: show the **leftmost ~8-15%** of its window at the right screen edge, with its left edge butting up against the focused window.
- Focused window: centred, full-height, no gaps between windows (gap is applied as an inset inside the target).

## Code recipe (horizontal layout, Zig)

```zig
fn horizontalTarget(self: *SlideDeck, delta: isize) Rect {
    const w: f32 = @floatFromInt(self.width);
    const focus_w: i32 = @intFromFloat(w * self.split.focus);
    const left_w: i32 = @intFromFloat(w * self.split.left_peek);
    const right_w: i32 = @intFromFloat(w * self.split.right_peek);
    const h = self.height;

    const x: i32 = switch (delta) {
        // Left neighbour: full-width surface positioned mostly off-screen so
        // only the rightmost `left_w` pixels remain visible at the left edge.
        -1 => -@as(i32, @intCast(self.width)) + left_w,
        0 => left_w,
        1 => left_w + focus_w,
        else => @as(i32, @intCast(delta)) * @as(i32, @intCast(self.width)),
    };
    const width: u32 = switch (delta) {
        -1 => self.width,        // surface can be full width
        0 => @intCast(focus_w),
        1 => @intCast(right_w),
        else => self.width,
    };
    return .{ .x = x, .y = 0, .width = width, .height = h };
}
```

After the target is computed, `targetForSlide()` applies `self.gap` as an inset.

## Why off-screen positioning is better than on-screen clipping

If the left neighbour is placed at `x = 0` with width `left_w`, the visible sliver shows the **leftmost** edge of the window — usually a left bezel/blank margin. Placing it at `x = -width + left_w` shows the **rightmost** pixels, which is the side that actually faces the focused window and matches the user's "deck" mental model.

This positioning also lets the output edge act as the clip, avoiding a hard rectangular scene clip that would square off rounded corners and client-side shading. When a window's buffer is still at the old larger size during a transition, most of it is simply off-screen to the left.

If stale buffers still leak back on-screen, add `wlr_scene_subsurface_tree_set_clip()` (see `references/scene-clipping.md`), but be aware it will cut rounded corners on any visible clip boundary.

## Coupling with scene clipping

The target rectangle sets the scene node's position. To prevent a stale full-size buffer from spilling back into the focused region, the preferred approach is correct off-screen placement. If a clip is still required, clip to the same target size. See `references/scene-clipping.md`.

## Related files

- `src/core/slidedeck.zig` — `targetForSlide()` and `horizontalTarget()`.
- `src/window.zig` — `setLayoutTarget()` and `updateClip()`.
- `src/server.zig` — `applyLayout()` loop.
