# Wallpaper plus corner "snip" recipe — 2026-07-13

## Context

On `29b8c55` geometry was good and the PNG wallpaper had been removed along with an earlier WIP. The user wanted the wallpaper back, *then* wanted all CSD bleed in the chamfered corner triangles gone. The wallpaper made the bleed visible because the old chrome mask filled the triangles with `theme.color_background`, not the desktop wallpaper.

What actually worked: bring back the wallpaper code from `774aaa8` onto `29b8c55` **without** the broken geometry/clip changes, then "snip" everything in the corner triangle space so the wallpaper shows through.

## Part 1 — Restore wallpaper on a clean good commit

Use the same steps as `references/wallpaper-cherry-pick-29b8c55.md`:

```bash
cd /home/dad/dev/KidulWM
git checkout 29b8c55 -- .
git reset --hard 29b8c55

git show 774aaa8:src/render/image.zig > src/render/image.zig
# then apply the minimal Server.background image changes in src/server.zig
```

Verify geometry files are untouched:

```bash
git diff 29b8c55 -- src/render/chrome.zig src/window.zig
# should produce no output
```

Build and deploy with the wallpaper copied to the VM:

```bash
zig build
ssh -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 'mkdir -p /home/kidul/Pictures/Wallpapers'
scp -P 2222 -i ~/.ssh/id_ed25519_kidulwm \
  ~/Pictures/Wallpapers/kidulBG01.png \
  kidul@127.0.0.1:/home/kidul/Pictures/Wallpapers/kidulBG01.png
scp -P 2222 -i ~/.ssh/id_ed25519_kidulwm \
  zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm.new
ssh -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm.new /usr/bin/kidulwm && sudo chmod 755 /usr/bin/kidulwm && sudo systemctl start kidulwm && systemctl is-active kidulwm'
```

## Part 2 — Snip the corner triangles so wallpaper shows

### 1. Remove the solid per-window background rect

In `src/window.zig`:

- In `create()`, do not create `bg_rect`; set `.bg_rect = null`.
- In `setLayoutTarget()`, remove the `if (self.bg_rect)` update block.
- `handleUnmap()` can stay as-is; it will only destroy if non-null.

Result: there is no opaque `color_background` rectangle inside the wrapper; the wallpaper shows through any space the client surface does not cover.

### 2. Stop filling the chamfer mask with solid color

In `src/render/chrome.zig`, in the `.cut` path (the `use_variable` block), delete the first fill block that draws `squareRect(0,0,w,h)` minus a mask inner polygon using `style.color_background`. Keep only:

- the transparent clear at the start,
- the border ring fill (`chamferRect` minus `inner` polygon, filled with `border_color`),
- the hidden-edge `CAIRO_OPERATOR_DEST_OUT` strips.

This makes the chrome overlay draw only the visible frame; the interior and corner triangles become transparent so the output wallpaper is visible.

### 3. Clip the client surface to the wrapper bounds

Add `Window.applySurfaceClip()` in `src/window.zig`:

```zig
pub fn applySurfaceClip(self: *Window) void {
    const surface = self.toplevel.base.surface;
    if (!surface.mapped) return;

    const w: i32 = @intFromFloat(self.animation.target_w);
    const h: i32 = @intFromFloat(self.animation.target_h);
    if (w <= 0 or h <= 0) return;

    const pos = self.surface_tree.node;
    const clip = wlr.Box{
        .x = -pos.x,
        .y = -pos.y,
        .width = w,
        .height = h,
    };
    self.surface_tree.node.subsurfaceTreeSetClip(&clip);
}
```

Call it from:
- `setSurfaceOffset()` immediately after setting position,
- `setSurfaceOffsetForPeek()` immediately after setting position,
- `handleCommit()` at the end.

Why `-pos.x, -pos.y`: the wrapper rectangle in `scene_tree` coordinates is `(0,0,w,h)`. The surface tree's top-left is at `pos.x, pos.y` relative to the wrapper. In surface-tree local coordinates the wrapper is `(-pos.x, -pos.y, w, h)`. Clipping there hides CSD shadows/rounded corners outside the wrapper without shifting the on-screen content.

## Result

- Desktop wallpaper shows through the chamfered corner triangles.
- Client terminal/chrome does not bleed into the triangles because the surface is clipped.
- The compositor-drawn border ring stays visible around the slides.
- Geometry remains the same as `29b8c55` because no placement or chrome-sizing logic changed.

## What not to do

- Do not install external wallpaper daemons like `swaybg`. The built-in solution already existed in git history.
- Do not change `theme.color_background` to a "more visible" color when the user asked for the wallpaper back.
- Do not keep thickening the chrome mask inset — that fills the corner with a solid color, which still differs from the wallpaper.
- Do not check out the entire `774aaa8` commit; it bundled broken geometry changes.
