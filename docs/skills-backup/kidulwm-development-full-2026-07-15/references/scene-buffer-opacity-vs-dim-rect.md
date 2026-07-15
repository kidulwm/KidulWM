# Per-window opacity with `wlr_scene_buffer_set_opacity`

## TL;DR

Do not dim unfocused windows with a compositor-drawn black `wlr.SceneRect`. Long-term, set the opacity of the client's scene-buffer node via `wlr.SceneBuffer.setOpacity()`, then `wlr_scene` blends the whole surface for free.

## API

In zig-wlroots 0.20.1 the binding is:

```zig
pub const SceneBuffer = extern struct {
    // ...
    extern fn wlr_scene_buffer_set_opacity(scene_buffer: *SceneBuffer, opacity: f32) void;
    pub const setOpacity = wlr_scene_buffer_set_opacity;
};
```

Underlying C header: `/usr/include/wlroots-0.20/wlr/types/wlr_scene.h`.

## Why this is better than `dim_rect`

- **No overdraw.** A black `SceneRect` draws an entire extra quad per window. Scene-buffer opacity reuses the same buffer and renderer blend pass.
- **Respects rounded corners / CSD.** The alpha modulates the actual client pixels, so a peek's rounded corners or drop shadow fade together with content instead of being overlaid by a sharp black rectangle.
- **One knob per window.** Focused window = `1.0`. Unfocused peek = match the existing 18% dim with `0.82`.
- **Subsurface consistency.** The surface tree (and its subsurfaces/popups, where permitted) all inherit the same opacity naturally because it is applied to the root of the branch.

## How to reach the buffer

`Window.surface_tree` is created with `scene_tree.createSceneXdgSurface(toplevel.base)`. wlroots inserts one or more `wlr_scene_buffer` nodes under that tree. The cleanest way to find the primary one is to walk it:

```zig
fn setSurfaceOpacity(tree: *wlr.SceneTree, opacity: f32) void {
    tree.node.forEachBuffer(f32, struct {
        fn iter(buffer: *wlr.SceneBuffer, sx: c_int, sy: c_int, data: *f32) void {
            _ = sx;
            _ = sy;
            buffer.setOpacity(data.*);
        }
    }.iter, &opacity);
}
```

Call this from `Window.updateDim` (renamed to `updateOpacity`) or wherever the focus state changes.

## Migration from `dim_rect`

1. Remove the `dim_rect` field and all `createSceneRect` / `setSize` / cleanup code for it.
2. Keep the focused/unfocused decision logic.
3. In `updateDim`, instead of sizing a black rectangle, call the buffer walker above with `1.0` or `0.82` depending on focus.
4. Make sure `Window.handleUnmap` no longer tries to destroy `dim_rect`.

## Interaction with chrome and clips

- The chrome overlay must live in its **own** scene tree sibling, not as a child of `surface_tree`, so it is not dimmed along with the client content.
- `wlr_scene_subsurface_tree_set_clip()` and `wlr.SceneBuffer.setDestSize()` still work independently of opacity; set opacity after setting clip/dest size.

## Caveats

- Only buffers that exist are affected. Walking with `forEachBuffer` before the client has committed a buffer is a no-op; call it again on each commit or layout pass if needed.
- Opacity applies to the whole branch. If you later want per-subsurface opacity (e.g., a bright video overlay that must stay opaque while the rest of the window dims), you will need per-node opacity, which is also exposed on scene buffers but requires walking more selectively.
- On the Pixman software renderer, alpha blending is correct but slower than on GL. This is still cheaper than a dim overlay.
