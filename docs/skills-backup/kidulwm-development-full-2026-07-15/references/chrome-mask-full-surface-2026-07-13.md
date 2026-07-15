# Chrome mask: cover the full client surface to stop CSD shadow bleed

## Symptom

Client shadows/background extend past the chamfered border into the wallpaper gap. `wlr_scene_subsurface_tree_set_clip` either does not apply to the main surface in the current wlroots build, or the geometry shift makes the clip miss the shadow region. The bleed survives mask overdraw and shows up as a 10–20px dark band on the right/bottom edges.

## Root cause

GTK/libadwaita clients render CSD shadows outside the content geometry. The chrome overlay is historically rendered at the wrapper size (`target_w` × `target_h`), so it only covers the wrapper. Shadows on the right/bottom of the surface leak because the mask is not drawn on that area.

## Fix

Render the chrome overlay at the full client surface dimensions (`surface.current.width/height`) instead of the wrapper size, and offset the chrome tree by `-geometry.x, -geometry.y` so the wrapper content still lands at the wrapper origin. Inside the buffer, draw the mask over the full surface and the border ring at the wrapper position.

## Recipe

### `Window.updateChrome` changes

```zig
const style = self.server.theme;
const surf = self.toplevel.base.surface;
const surf_w: i32 = @intCast(surf.current.width);
const surf_h: i32 = @intCast(surf.current.height);
const geom = self.toplevel.base.geometry;

const surface = chrome_renderer.renderChrome(
    style,
    w, h,                       // wrapper logical size
    surf_w, surf_h,             // full client surface logical size
    geom.x, geom.y,             // offset of content geometry inside surface
    focused, scale, edges,
) orelse {
    tree.node.destroy();
    self.chrome_tree = null;
    return;
};

// ... create DataBuffer / SceneBuffer ...

scene_buffer.setDestSize(surf_w, surf_h);

// Align full-surface buffer with client surface top-left.
tree.node.setPosition(-geom.x, -geom.y);
```

### `renderChrome` changes

```zig
pub fn renderChrome(
    style: Style,
    width: i32,
    height: i32,
    surface_width: i32,
    surface_height: i32,
    surface_offset_x: i32,
    surface_offset_y: i32,
    focused: bool,
    scale: u32,
    edges: EdgeMode,
) ?*c.cairo_surface_t {
    if (width <= 0 or height <= 0) return null;
    const s = @max(1, @as(i32, @intCast(scale)));
    const bw = width * s;
    const bh = height * s;
    const full_w = @max(bw, surface_width * s);
    const full_h = @max(bh, surface_height * s);

    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, full_w, full_h) orelse return null;
    const cr = c.cairo_create(surface) orelse return null;
    defer c.cairo_destroy(cr);

    const offset_x: f64 = @as(f64, @floatFromInt(surface_offset_x * s));
    const offset_y: f64 = @as(f64, @floatFromInt(surface_offset_y * s));
    const w = @as(f64, @floatFromInt(bw));
    const h = @as(f64, @floatFromInt(bh));
    const full_wf = @as(f64, @floatFromInt(full_w));
    const full_hf = @as(f64, @floatFromInt(full_h));

    // clear transparent...

    if (use_variable) {
        // ... compute mask_inner and inner as before ...

        // Mask now covers the whole client surface; inner cutout is the wrapper content shape.
        squareRect(cr, -offset_x, -offset_y, full_wf, full_hf);
        drawPolygon(cr, mask_inner[0..mask_inner_count]);
        setSource(cr, style.color_background, 1.0);
        c.cairo_fill(cr);

        // Border ring stays at the wrapper position/origin.
        chamferRect(cr, 0.0, 0.0, w, h, depths);
        drawPolygon(cr, inner[0..inner_count]);
        setSource(cr, border_color, 1.0);
        c.cairo_fill(cr);
    }

    // Hidden-edge clear strips remain wrapper-relative because the visible
    // border ring is drawn within the wrapper bounds.
    // ... (unchanged)
}
```

## Key details

- `bw`/`bh` are still the wrapper pixel size; they are only used for the inner border ring and mask inner polygon.
- `offset_x`/`offset_y` scale by output scale `s`, not wrapper size.
- The mask outer rectangle extends from `(-offset_x, -offset_y)` for `full_wf × full_hf`, covering the actual surface buffer.
- The visible border ring stays inside the wrapper at `(0,0,w,h)`; hidden-edge strips operate on the same wrapper rectangle.
- Do **not** set the full surface size on the wrapper width/height variables (`bw`/`bh`) — that was the mistake that broke the border ring in an earlier attempt.
