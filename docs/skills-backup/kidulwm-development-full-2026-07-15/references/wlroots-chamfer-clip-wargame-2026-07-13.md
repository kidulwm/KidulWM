# wlroots chamfer clip wargame (2026-07-13)

Question: can we patch wlroots 0.20 to support a 45-degree chamfer clip for KidulWM?

Findings
- KidulWM uses system `wlroots0.20 0.20.1-1.1` with `zig-wlroots` 0.20.1 bindings.
- `wlr_scene_subsurface_tree_set_clip()` only accepts a `struct wlr_box*` (axis-aligned rectangular clip).
- Internally the clip is stored in `struct wlr_scene_subsurface_tree` and applied by moving the `wlr_scene_buffer` node and setting `scene_buffer->src_box` (see `types/scene/subsurface_tree.c:68` and `types/scene/surface.c:253-273`).
- The render loop in `types/scene/wlr_scene.c:1443` already uses `pixman_region32_t` clip regions for `wlr_render_pass_add_texture()`.

What a chamfer-capable patch would require
1. Extend `struct wlr_scene_surface` clip storage from `struct wlr_box` to `pixman_region32_t` (or add a parallel region field).
2. Add a new public API: `wlr_scene_subsurface_tree_set_clip_region(struct wlr_scene_node*, const pixman_region32_t*)`. Keep the old box API as a wrapper.
3. In `subsurface_tree_reconfigure_clip()`, translate the region through child offsets instead of moving a single box.
4. In `surface_reconfigure()`, keep `src_box` at the region's bounding box but feed the actual region into the render pass `.clip` field.
5. Update opaque-region and input hit-testing to respect the shape.
6. Update `zig-wlroots` bindings to expose the new function and region type.

Costs and risks
- Build: compile and install a patched `libwlroots-0.20.so` on every host, VM, and future install.
- Maintenance: rebase the patch every wlroots release until upstream accepts it.
- Risk: subtle regressions in damage tracking, direct scanout, input hit-testing, and subsurface transforms.

Conclusion
- For CachyOS we avoided the patch by switching to `.classic` rounded corners.
- For a future Gentoo premium build, the patch is viable but should be treated as a last resort after cheaper masking/overlay variants fail.
