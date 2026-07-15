# Square grey leak through rounded corners — per-window `bg_rect` culprit

## Symptom

A square patch of `theme.color_background` grey peeks through the rounded interior of a window, most visible near the corners. The chrome border itself looks right, but the fill behind the client looks squared off.

## Root cause

`Window.create()` was adding a full-size `wlr.SceneRect` called `bg_rect` behind the client surface and sizing it to the layout target on every `setLayoutTarget()`:

```zig
const bg_rect = try scene_tree.createSceneRect(1, 1, &server.theme.color_background.toF32());
```

`wlr.SceneRect` has no rounded shape. The chrome overlay drawn on top has a transparent inner area (the content rectangle). Through that transparency the square `bg_rect` was visible.

This was masked whenever the client surface filled the wrapper, but many windows (especially those with CSD margins or before their first resize) left a gap that exposed the square background.

## Fix

Remove the per-window `bg_rect` entirely:

1. Drop the `bg_rect` field from `Window`.
2. Remove its creation in `Window.create()`.
3. Remove its resize/recolor in `Window.setLayoutTarget()`.
4. Remove its destruction in `Window.handleUnmap()`.

The chrome overlay already fills the outer shape with `theme.color_background` and clears the inner content area. Anything inside the content area is either the client surface or the desktop background/wallpaper behind the window.

## Side effect

Removing `bg_rect` also removes the opaque layer behind client surfaces, so **client-requested transparency now works**: unset or alpha pixels show the desktop/wallpaper instead of grey.

If you want the old opaque interior back for a specific style, fill the chrome overlay's inner region with `theme.color_background` instead of leaving it transparent, rather than reintroducing a square rect.

## Applies to

Both `.classic` rounded corners and `.cut` chamfer styles. The `.none` square style does not expose the corner shape, but the extra `bg_rect` and its cleanup overhead are unnecessary there too.
