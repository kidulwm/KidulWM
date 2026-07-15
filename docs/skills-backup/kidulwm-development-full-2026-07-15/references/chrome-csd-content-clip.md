# Clipping client CSD bleed without touching chrome geometry

Session: 2026-07-13. Symptom: client rounded corners / shadows bleed past the
chamfered chrome overlay. The user had already approved the chamfer geometry at
commit `29b8c55`; the task was to clip the excess, not to change corners,
borders, or offsets.

## What actually worked

Clip the XDG surface tree to the **wrapper bounds** in `src/window.zig`:

```zig
pub fn applySurfaceClip(self: *Window) void {
    const surface = self.toplevel.base.surface;
    if (!surface.mapped) return;

    const w: i32 = @intFromFloat(self.animation.target_w);
    const h: i32 = @intFromFloat(self.animation.target_h);
    if (w <= 0 or h <= 0) return;

    const clip = wlr.Box{
        .x = 0,
        .y = 0,
        .width = w,
        .height = h,
    };
    self.surface_tree.node.subsurfaceTreeSetClip(&clip);
}
```

Call it from `src/server.zig::applyLayout()` after `window.updateChrome(...)` for
both focused and peek slides. Only call it from the top-level layout pass; do not
re-apply it from `handleCommit()` or `setSurfaceOffset()` because those can run
with different coordinate spaces during peek transitions.

```zig
window.updateChrome(true, .all);
window.applySurfaceClip();
```

The chrome overlay lives in a sibling `chrome_tree` under the same wrapper
`scene_tree`, so it is **not** affected by the clip applied to `surface_tree`.

## What did not work

1. **Clipping to the XDG content rectangle (`geom.x, geom.y, geom.width,
   geom.height`)** while leaving `surface_tree` at `(0,0)`. This shifts the
   visible content inside the wrapper and detaches the chrome border, producing
   a stray line.
2. **Clipping to `geom.width/height` at `(0,0)` for peeks.** That threw away
   the parts of the buffer the peek needs, breaking geometry: right peek hung
   below border, center slide shifted up/left, left peek showed past the
   chamfer.
3. **Changing `corner_style` from `.cut` to `.none`** to "remove chamfers". The
   user never asked for square corners; this destroyed the approved look.
4. **Mask-only experiments in `renderChrome`** without surface clipping: the
   overlay already had a full-bounds mask, but the client surface still drew
   past it in some cases.

## Rule

When the user says the geometry is perfect, **only clip content**. Do not touch
`corner_style`, `border_width`, `chamfer_border_width`, `corner_depth`, or
placement/offset code. Clip the `surface_tree`, not the `chrome_tree`, to
wrapper bounds.
