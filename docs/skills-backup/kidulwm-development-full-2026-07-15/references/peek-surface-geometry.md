# SlideDeck peek surface geometry

When a window in the KidulWM SlideDeck is in a side-peek slot, its visible area is just a narrow sliver. The scene-tree layout positions a full-output-width wrapper at the edge of the screen; the actual on-screen portion is the small sliver that remains inside the output bounds.

## Problem

If `setSurfaceDestSize()` is applied to the peek surface, the client buffer is scaled/squashed to the tiny sliver width. This both distorts the content and, in practice, can push the rendered content outside the visible sliver so the peek appears empty or off-screen.

The original code also had the XDG surface scene tree as the direct layout node, so any overlay that had to mask the whole window bounds could not be kept separate from the surface itself.

## Solution

1. Create a **wrapper scene tree per window** (`Window.scene_tree`).
2. Make the XDG surface a **child** of that wrapper (`Window.surface_tree`).
3. Layout / animation moves the **wrapper** to the slot target (full output width for peeks).
4. The **chrome overlay** and dim rect are children of the wrapper and therefore cover the full window bounds.
5. Only the **focused slide** is configured to the target size and has `setSurfaceDestSize()` applied.
6. For side peeks, keep the client surface at its natural buffer size and **offset** `surface_tree` inside the wrapper so the correct edge aligns with the visible sliver:
   - Left peek: surface is pulled right so the buffer’s right edge aligns with the wrapper’s right edge (visible sliver is the rightmost part).
   - Right peek: surface stays left-aligned so the visible sliver is the leftmost part.
7. Add a full-slide **background fill rect** behind the surface. Client content often does not reach the geometry edge (CSD padding, title-bar margins, etc.), leaving a gap between the border and the surface. A `wlr.SceneRect` covering the whole layout target and filled with `theme.color_background` closes the gap for focused windows and keeps peek slivers filled. It must be created **before** the XDG surface so it renders behind it.

## Code anchors

In `src/window.zig`:

```zig
pub const Window = struct {
    scene_tree: *wlr.SceneTree,   // wrapper, full window bounds
    surface_tree: *wlr.SceneTree, // XDG surface, can be offset
    ...
};
```zig
// Background fill is a sibling before the surface so it renders behind it.
const bg_rect = try scene_tree.createSceneRect(1, 1, &server.theme.color_background.toF32());
const surface_tree = try scene_tree.createSceneXdgSurface(toplevel.base);
```

In `setLayoutTarget()`, resize and recolor the background rect so it always matches the current slot:

```zig
if (self.bg_rect) |rect| {
    const color = self.server.theme.color_background.toF32();
    rect.setSize(@intCast(w), @intCast(h));
    rect.setColor(&color);
}
```

The surface offset and destination size are updated as before:

```zig
// Only apply destination size to the surface child, not the wrapper.
window.surface_tree.node.forEachBuffer(...);

// Offset the surface child relative to the wrapper.
window.surface_tree.node.setPosition(x, y);
```

In `src/server.zig` / `applyLayout()`:

```zig
const is_focused = slide_idx == output.deck.focused_index;
const peek_edges = if (slide_idx < output.deck.focused_index)
    chrome_renderer.EdgeMode.left_peek
else
    chrome_renderer.EdgeMode.right_peek;

window.setLayoutTarget(target.x, target.y, target.width, target.height);

if (is_focused and size_changed) {
    _ = window.toplevel.setSize(@intCast(target.width), @intCast(target.height));
}

if (is_focused) {
    window.setSurfaceDestSize(@intCast(target.width), @intCast(target.height));
    window.setSurfaceOffset(0, 0);
} else {
    window.setSurfaceOffsetForPeek(peek_edges);
}
```

And in `handleCommit()`:

```zig
if (!window.chrome_edges.eql(chrome_renderer.EdgeMode.all)) {
    window.setSurfaceOffsetForPeek(window.chrome_edges);
}
```

The commit-time re-offset is important because clients may commit a new buffer size after the layout pass ran, and without re-applying the offset the sliver can drift off-screen again.

## Edge offset logic (current implementation)

```zig
const buffer_w = @max(0, @as(i32, @intCast(surface.current.width)));
const tree_w = @intFromFloat(self.animation.target_w);
const x = if (!edges.left and tree_w > buffer_w) tree_w - buffer_w else 0;
const y: i32 = 0;
self.setSurfaceOffset(x, y);
```

This uses the raw buffer width. If future clients show unwanted CSD shadow padding in the visible sliver, switch to using `toplevel.base.geometry` to align the **content area** instead of the raw buffer edge.

## Pitfalls

- **Do not call `setSurfaceDestSize()` on peeks.** That scales the surface to the tiny peek target and squashes/misaligns the content. Only apply it to the focused slide.
- **Re-apply the offset in `handleCommit()`.** Clients commit new buffer sizes after the layout pass; without re-offsetting, the sliver can drift off-screen.
- **Background rect order matters.** If the `wlr.SceneRect` is created after the XDG surface, it will paint on top and cover the window. Always create it first under the wrapper.
- **An empty-looking peek is not necessarily a bug.** A terminal's content is left-aligned, so the rightmost sliver of a left peek may have no text. Verify with a client that has content spanning the width (e.g., a browser or nano menu bar).

## Verification

- Build: `zig build`
- Tests: `zig build test --summary all`
- Deploy to VM and cycle focus; both left and right peeks should show the correct edge of their content.
- Check that the focused window and peek slivers have **no gap between the inner border edge and the window background**. If a gap is visible, the background fill rect is missing, incorrectly ordered, or not sized to the layout target.
- If a peek looks empty, verify with a client that has content near that edge (e.g., a browser page or a nano menu bar spanning the width). An empty-looking terminal sliver just means there is no text in that exact strip.
