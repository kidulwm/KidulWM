# Chrome overlay layering order

**Symptom:** `corner_style`, `border_width`, or border color changes inside `src/render/chrome.zig` produce no visible change on screen. The visible frame is client CSD and ignores the compositor chrome.

**Cause:** The `wlr.SceneTree` that holds the XDG surface may render client-provided decorations/shadows on top of a sibling chrome tree, even if the chrome tree was created later and `node.raiseToTop()` was called. The per-window wrapper tree is not a reliable ordering boundary against CSD.

**Fix:** Move the chrome overlay into the global `server.overlay_tree` (or another scene tree that is known to be above all window wrappers) and update its position every time the window moves.

## Code sketch

In `Window` add:
```zig
    global_chrome_tree: ?*wlr.SceneTree,
```

In `setLayoutTarget` and `tickAnimation`, after setting `self.scene_tree.node.setPosition(x, y)`, also set:
```zig
if (self.global_chrome_tree) |chrome| {
    chrome.node.setPosition(x, y);
}
```

In `Window.updateChrome`:
- Destroy any previous `global_chrome_tree` and recreate it under `self.server.overlay_tree.createSceneTree()`.
- Set its position to the window's current world coordinates immediately.
- Attach the `wlr.SceneBuffer` rendered by `chrome_renderer.renderChrome()` to that global tree.
- Destroy the global tree in `handleUnmap` so it does not outlive the window.

## Why this is safe for performance

`updateChrome` already regenerates the overlay lazily on size/style/focus/edge changes. The extra per-frame work is only a `node.setPosition()` call, which is cheap compared with re-rendering the Cairo buffer.

## Interaction with title-bar toggle

If the user later enables client title bars via `show_title_bars = true`, the chrome overlay on top of CSD will still draw a compositor border on top of the client title bar. That is usually acceptable because the CSD title bar exists only inside the client content area; the compositor frame sits outside it.

If the user wants the chrome hidden when title bars are enabled, guard the overlay creation with `if (!self.server.theme.show_title_bars)`.
