# Scene clipping in KidulWM

## Problem

In the SlideDeck layout, unfocused neighbour slides are allocated a narrow "peek" slot (e.g. 8-15% of output width). When a window that was previously focused loses focus, its surface buffer can remain at the old full size until the client commits a new frame. Without clipping, the scene graph renders the full buffer at the new small-slot position, so the old content can bleed:

- behind the transparent centred focused window, or
- past the edge of the output.

## First-choice fix: correct positioning

If the neighbour is placed mostly off-screen so only the intended sliver is on-screen, the output edge naturally clips the invisible part and no scene-node clip is needed. In that case, rounded corners and client-side shading/shadows stay intact because there is no artificial rectangle cutting through them.

See `references/slidedeck-layout.md` for the off-screen placement recipe.

## When you still need a clip

If a stale buffer leaks visibly despite correct positioning (for example, a slow client hasn't resized and its larger buffer sticks into the focused region), call `wlr_scene_subsurface_tree_set_clip()` on the scene node returned by `wlr_scene_xdg_surface_create()`.

```zig
const wlr = @import("wlroots");

pub fn updateClip(self: *Window) void {
    const clip = wlr.Box{
        .x = 0,
        .y = 0,
        .width  = @intFromFloat(self.animation.target_w),
        .height = @intFromFloat(self.animation.target_h),
    };
    // scene_tree was created with scene.tree.createSceneXdgSurface(toplevel.base)
    self.scene_tree.node.subsurfaceTreeSetClip(&clip);
}
```

Call `updateClip()` for each slide in `Server.applyLayout()` immediately after `setLayoutTarget()`.

## Pitfall: scene clips square off rounded corners

`wlr_scene_subsurface_tree_set_clip()` is an axis-aligned rectangle. Any rounded corner, gradient glow, or shadow that crosses the clip boundary will be cut straight. Typical symptoms:

- Top-left of the visible region looks fine (clip origin is at the window's top-left geometry).
- Top-right, bottom-left, and bottom-right look square or have missing shading.

This is expected behaviour from a rectangular clip. If rounded corners are required, keep the clip boundary hidden behind an opaque window edge, or implement rounded-clip masking in a custom shader. Do not try to fix it by adjusting the clip box size without a rounded SDF — the clip is geometrically incapable of preserving curves.

## Dim overlay

Always size the focus-dim rectangle from the surface's committed **buffer size** (`surface.current.width/height`):

```zig
const surface = self.toplevel.base.surface;
const w: i32 = @intCast(surface.current.width);
const h: i32 = @intCast(surface.current.height);
```

Sizing from the layout target makes the overlay a solid rectangle larger than the drawn window, overwriting transparent rounded corners and client-side shading.

## When correct positioning makes clipping unnecessary

In the SlideDeck layout, moving unfocused neighbours mostly off-screen so only the intended peek sliver remains on-screen can remove the need for a hard scene clip entirely. After the geometry fix, verify by removing the clip and checking for stale-buffer leakage. If no leakage occurs during normal focus changes, leave the clip off to preserve client-side rounded corners and shadows.

If leakage does occur (e.g. a slow client still shows its old full-size buffer in the focused region), re-add the clip and accept that the clip edge will square off any rounded corner or shadow it crosses until a rounded-clip shader is implemented.

## Reference

wlroots docs, `wlr_scene_subsurface_tree_set_clip()`:

> Sets a cropping region for any subsurface trees that are children of this scene node. The clip coordinate space will be that of the root surface of the subsurface tree. A NULL or empty clip will disable clipping.

Clip coordinates are surface-local, so an origin `(0, 0)` and size equal to the layout target is correct.

## Related files

- `src/core/slidedeck.zig` — target geometry calculation.
- `src/window.zig` — per-window clip and dim overlay.
- `src/server.zig` — `applyLayout()` loop where both are invoked.
