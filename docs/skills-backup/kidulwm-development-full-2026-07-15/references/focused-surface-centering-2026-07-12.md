# Focused surface centering — 2026-07-12

## Problem

After removing the focused `setSurfaceDestSize` scaling, the focused window renders at the client's natural committed size. While that eliminates the squish/un-squish re-render glitch, a transiently smaller buffer sits at the wrapper origin (`0,0`), leaving an uneven background gap at the bottom/right of the focused slide.

## Fix

Center the focused surface inside the wrapper target, using the window's current XDG geometry as the content size:

```zig
pub fn setSurfaceCentered(self: *Window) void {
    const surface = self.toplevel.base.surface;
    if (!surface.mapped) return;

    const geom = self.toplevel.base.geometry;
    const target_w: i32 = @intFromFloat(self.animation.target_w);
    const target_h: i32 = @intFromFloat(self.animation.target_h);

    const x: i32 = @divTrunc(target_w - geom.width, 2);
    const y: i32 = @divTrunc(target_h - geom.height, 2);

    self.surface_tree.node.setPosition(x, y);
}
```

Use it for focused windows in both layout paths and re-apply it in `handleCommit` so transient resizes stay centered.

## When to use

- When the compositor asks the client to resize (`toplevel.setSize`) but does not itself scale the committed surface.
- When you want a clean, symmetric background fill around a surface that may still be animating to the requested size.

## Do not use for peeks

Side peeks must remain edge-aligned (`x = 0` for left peek, `x = target_w - geom.width` for right peek) so the visible sliver shows the correct window edge.
