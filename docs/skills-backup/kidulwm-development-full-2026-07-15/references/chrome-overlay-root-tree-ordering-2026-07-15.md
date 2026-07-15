# Root scene tree ordering for chrome overlays (2026-07-15)

## Symptom

Composited chrome overlay changes to `corner_style`, border color, or border width produce no visible difference. The visible frame and borders are clearly client-side decoration (CSD), and even moving the chrome to `server.overlay_tree` does not fix it.

## Root cause

`wlr.Scene` children of the root tree render in sibling order. If the chrome tree is created under a per-window wrapper tree, it is only on top of the nodes already inside that wrapper. Client CSD and shadows may be rendered by wayland surfaces in a pass that still covers it, or another root-level tree (e.g. `overlay_tree`) can end up below the window scene tree depending on creation order.

## Fix

Create the chrome `SceneTree` directly under `server.scene.tree` (the root) and call `node.raiseToTop()` immediately. This guarantees the chrome buffer is drawn above every window regardless of CSD.

```zig
const tree = self.server.scene.tree.createSceneTree() catch return;
tree.node.raiseToTop();
tree.node.setPosition(x, y);
```

## Position tracking

Because the chrome is no longer a descendant of the window's wrapper tree, it does **not** inherit position changes. Update it in both:

- `Window.setLayoutTarget()` for the immediate snap/zero-animated final position.
- `Window.tickAnimation()` for every frame of position transitions.

Use the same rounded world coordinates as the wrapper scene tree: `animation.cur_x`, `animation.cur_y`.

## Pitfalls

- Creating chrome under `server.overlay_tree` and raising to top inside `overlay_tree` will be hidden by any window in the root tree that was created after `overlay_tree`. `overlay_tree` is useful for top-layer UI, not for per-window chrome that must sit above clients.
- The per-window `chrome_tree` field becomes a duplicate/legacy tree. Destroy it alongside `chrome_tree` in `handleUnmap` or replace it entirely; leaving stale root-level chrome nodes causes ghost slide frames after windows close.
- Transparent Cairo paint at the start of the buffer means gaps show whatever is behind the chrome node in the scene order. This is correct once the chrome is the topmost node.