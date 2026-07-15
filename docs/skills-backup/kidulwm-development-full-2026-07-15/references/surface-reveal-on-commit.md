# Hiding a new surface until its first real commit

## Symptom

When a new SlideDeck window maps (e.g., Ghostty), the client surface visibly draws in from the top-left toward the bottom-right for a frame or two. This leaves a rough first impression and can look like a render bug.

## Root cause

The compositor attaches the window's XDG surface scene tree immediately on `map`, while the client is still committing its first buffer. Some toolkits configure/resize a few times during startup, so intermediate frames render a surface that is smaller than the final window.

## Fix

1. Create the surface scene tree as usual in `Window.create()`.
2. Set `surface_tree.node.enabled = false` right after creation.
3. Track a `surface_committed: bool` flag on the window.
4. In `handleCommit()`, when the window is mapped and `surface.current.width/height` are non-zero, enable the node and set the flag.
5. Reset the flag and re-hide the node in `handleMap()` so unmap/remap works correctly.

```zig
// Window.create
const surface_tree = try scene_tree.createSceneXdgSurface(toplevel.base);
surface_tree.node.enabled = false;

// Window struct
surface_committed: bool = false,

// handleMap
window.surface_committed = false;
window.surface_tree.node.enabled = false;

// handleCommit
if (!window.surface_committed and window.toplevel.base.surface.mapped) {
    const w = window.toplevel.base.surface.current.width;
    const h = window.toplevel.base.surface.current.height;
    if (w > 0 and h > 0) {
        window.surface_committed = true;
        window.surface_tree.node.enabled = true;
    }
}
```

The slide's background `wlr.SceneRect` remains visible the whole time, so the user sees a solid slide that fills the target bounds until the client surface snaps on.

## When to use

- New window/map paths where the client surface starts small and grows into its final size.
- Not for already-mapped windows on focus transitions; those should already have a committed buffer.

## Files involved

- `src/window.zig` — `Window.create`, `Window.handleMap`, `Window.handleCommit`
