# Horizontal gold-on-glass dock overlay (2026-07-14)

Branch: `corner-bg-fix` after the keybinds + bottom-left plank-dock commits.

## What this is for

A compositor-internal tray/dock that:
- renders above every window (including the focused SlideDeck slide),
- spans from the left output edge to the left side of the focused slide,
- uses gold-leaf text on black glass buttons,
- shows previews above the buttons that can overlap the main focused slide,
- does **not** push the left-peek or focus slide when opened/closed.

## Implementation notes

### 1. Dedicated overlay scene tree

Create a separate `wlr.SceneTree` for the tray so it can always be raised above client windows:

```zig
const overlay_tree = try server.scene.tree.createSceneTree();
server.overlay_tree = overlay_tree;
server.tray = try ui.Tray.init(server.allocator, host, overlay_tree);
```

After every `window.scene_tree.node.raiseToTop()` in `focusWindow` / `applyLayout`, also do:

```zig
server.overlay_tree.node.raiseToTop();
```

This is the compositor-side equivalent of a layer-shell overlay.

### 2. Compute the dock width from the SlideDeck split

For each output:

```zig
const left_w: i32 = @intFromFloat(@as(f32, @floatFromInt(box.width)) * output.deck.split.left_peek);
const focus_left = box.x + left_w;
```

The visible bar width becomes `focus_left - box.x`. This makes the dock touch the focused slide with no gap.

### 3. Buffer larger than the visible bar

The tray's `wlr.SceneBuffer` is sized to:

```zig
const total_w = panel_width + preview_width + 20;
const total_h = visibleHeight + preview_overhead;
```

Only the left portion is drawn as the black glass bar; the rest is transparent so preview cards can protrude over the focused slide without being clipped.

### 4. Request a frame, not a layout

Toggling the tray must not recompute SlideDeck positions. Instead of `requestLayout()`, schedule a repaint:

```zig
var it = server.outputs.iterator(.forward);
while (it.next()) |output| output.wlr_output.scheduleFrame();
```

### 5. Pointer hit region must include the preview

When the cursor moves from a button into the floating preview above it, the tray should stay active. Include the preview rectangle in `handlePointerMove` and `handlePointerClick`, not just the bar row.

```
hover zone = bar rectangle + preview rectangle of the hovered/selected item
```

This lets the user slide the pointer from the button up through the preview and onto the main slide without the action disengaging in a gap.

## Keyboard controls

- `Mod4+Left/Right` — navigate the horizontal dock.
- `Mod4+space` — activate the selected item.
- `Mod4+a` — cycle animation preset.

These bindings live in `src/input/keyboard.zig` and are editable in `~/.config/kidulwm/keybinds.conf`. Keep keyboard fallback for any future tray controls, because SPICE/VM pointer capture cannot be relied on.

## Pointer diagnostics

Pointer log lines go to the service stdout file configured in the unit (`/tmp/kidulwm-service.log`), not necessarily the systemd journal. The unit uses:

```
StandardOutput=file:/tmp/kidulwm-service.log
StandardError=inherit
```

So search `/tmp/kidulwm-service.log` for `KidulWM: pointer device discovered` or pointer motion diagnostics. If the device is discovered but the cursor does not move, the problem is likely in KidulWM's cursor update, not in VM input wiring.

## Result

- Left-peek stayed in place when the tray opened.
- Focused slide was not displaced.
- Tray sat visually on top.
- Keyboard nav used `Mod4+Left/Right` for selection, `Mod4+space` to activate.
