# Compositor-owned window chrome via Cairo overlay buffers

When KidulWM needs to draw its own window borders/corners/shape instead of relying on client-side decorations (CSD), render the chrome into a CPU Cairo ARGB32 surface and upload it as a `wlr.Buffer` attached to a `wlr.SceneBuffer` child of the window's scene tree. This gives the compositor exact control over the visible shape and works with the existing wlroots scene graph.

## When to use this pattern

- Override/supplement client-side rounded/shadowed decorations with a consistent compositor shape.
- Implement runtime-switchable corner styles (chamfered / rounded / square).
- Draw focus/activity borders that are independent of client content.

## Files added for this pattern

- `src/render/buffer.zig` — custom CPU-backed `wlr.Buffer` implementation.
- `src/render/chrome.zig` — Cairo drawing helpers for cut/rounded/square border rings and unfocused shading.
- `src/window.zig` — `updateChrome(focused)` caches/regenerates the overlay.
- `build.zig` — main compositor module links `cairo` because non-dm code now uses it.

## Custom CPU `wlr.Buffer`

`src/render/buffer.zig` implements the minimal `wlr.Buffer.Impl` callbacks for a static, CPU-owned ARGB8888 image. wlroots reads the pixel pointer on demand; no DRM or SHM fd is required.

Key points:

- Pixel format `DRM_FORMAT_ARGB8888` matches Cairo `CAIRO_FORMAT_ARGB32` (native pre-multiplied BGRA on little-endian).
- `destroy` frees the allocation created in `create`.
- `beginDataPtrAccess` returns the stored pointer/stride/format.
- Use `std.heap.page_allocator` for the allocation; it is freed explicitly by the buffer destroy callback.

## Rendering a shaped border ring

`src/render/chrome.zig::renderChrome(style, width, height, focused, scale, edges)`:

1. Creates an ARGB32 Cairo surface at `width * scale` by `height * scale`.
2. Clears to transparent.
3. Draws the **outer shape** (chamfer/rounded/square) with the border color.
4. Punches out the **inner shape** using `CAIRO_FILL_RULE_EVEN_ODD` so only the border ring remains opaque.
5. Clears hidden/shared edges with `CAIRO_OPERATOR_DEST_OUT` so internal window edges don't double-draw borders. Use a strip wide enough (`depth + border + 1`) to clip the corner chamfer at the seam, otherwise a diagonal stub from the hidden edge remains visible and looks messy.
6. Adds an extra inner glow line for focused windows.
7. Returns the surface; the caller copies pixels and wraps them in `DataBuffer`.

### Uniform border thickness across chamfers

The inner shape must be a **parallel offset** of the outer shape. For a chamfered outer corner with depth `d`, the inner chamfer depth must be `max(0, d - border_width)`. If the inner cutout is a simple rectangle, the border thins where the outer chamfer meets the inner square, producing a faint line and uneven frame.

Example for `.cut` chamfer:

```zig
const outer_depth = depth;
const inner_inset = border;
const inner_depth = @max(0.0, depth - inner_inset);
chamferRect(cr, ox, oy, ow, oh, outer_depth);
chamferRect(cr, ox + inner_inset, oy + inner_inset, ow - 2*inner_inset, oh - 2*inner_inset, inner_depth);
```

Diagonals can still look slightly thinner than straight edges because of pixel projection, even when the geometry is parallel. If the user reports "chamfer legs are thinner than the sides", increase the inner inset by 1–2 logical pixels (`inner_inset = border + 1.5`) while keeping the inner shape parallel. This pushes the inner chamfer further inward, thickening the visible corner legs without visibly ballooning the straight sides.

### Hiding shared/internal edges

For hidden edges, the destination-out strip must also remove the associated corner chamfer. A plain `border`-width strip leaves diagonal stubs poking toward the shared seam, which is the "messy" look on SlideDeck side peeks. Use `depth + border + 1` for the strip width, and always draw the full outer shape before trimming — do not pre-shift the outer polygon, because shifting it distorts the visible corners and leaves internal ghost borders.

### Client content does not fill the chamfered corners

Because the transparent interior of the overlay reveals the rectangular client surface behind it, the terminal/app content will fill past the inner chamfer unless something covers those corner triangles. Two practical fixes:

1. **Make the chrome occupy the corner region:** Use a parallel inner shape for the border ring and, if needed, an additional background-color matte fill between the client rectangle and the inner chamfer so the visible content boundary follows the cut.
2. **Suppress client CSD:** For GTK clients this means setting server-side mode via `zxdg_decoration_manager_v1` **and** exporting `GTK_CSD=0` / `GDK_DEBUG=no-csd` before launching the client, otherwise the app draws its own title bar/header under/around the frame.

```bash
export GTK_CSD=0
export GDK_DEBUG=no-csd
ghostty &
```

To keep the overlay crisp on scaled outputs, `scale` is taken from the window's `Output.wlr_output.scale`.

## Wiring into a window

```zig
// In Window.updateChrome(self, focused):
const tree = self.scene_tree.createSceneTree() catch return;
const surface = chrome_renderer.renderChrome(style, w, h, focused, scale) orelse return;
defer c.cairo_surface_destroy(surface);
const pixels = chrome_renderer.surfacePixels(surface);
const buffer = DataBuffer.create(pixels.pixels, pixels.width, pixels.height, pixels.stride) catch return;
const scene_buffer = tree.createSceneBuffer(buffer) catch {
    wlr.Buffer.drop(buffer);
    return;
};
wlr.Buffer.drop(buffer);     // scene owns the only reference
scene_buffer.setDestSize(w, h);
```

The child scene tree moves with `scene_tree`, so the overlay tracks window layout automatically.

## Runtime switching

Add a style-generation counter to `Server` and bump it when the theme changes. Each `Window` tracks the generation it last rendered with and regenerates when stale. IPC request:

```bash
kidulwm-control set_theme corner_style cut            # signature chamfer
kidulwm-control set_theme corner_style classic        # rounded
kidulwm-control set_theme corner_style none           # square
kidulwm-control set_theme show_title_bars true        # allow client CSD
kidulwm-control set_theme show_title_bars false       # default: compositor SSD
```

## Pitfall: do not fill the interior opaque

The chrome overlay sits above the client surface in the scene graph. If the interior is filled with an opaque color it will hide the client's content. Render the interior as transparent and only keep a translucent shading gradient if deliberate dimming is desired.

## Pitfall: Cairo link dependency

Once `src/render/chrome.zig` is imported into the main compositor, `build.zig` must add `root_mod.linkSystemLibrary("cairo", .{})` so the `kidulwm` executable resolves the Cairo symbols.

## Trade-off vs. GPU SDF shader

Cairo buffers are quick to implement and style, but they allocate CPU memory per window per size change and must be regenerated on resize. A GPU SDF shader (see `src/render/chamfer.zig` stubs) is the longer-term path for output-perfect, anti-aliased chrome at any scale without per-size allocations. Use this buffer approach for rapid iteration and switch to SDF once the visual design is finalised.
