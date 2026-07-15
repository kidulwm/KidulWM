# Focused-window clip/offset regression (2026-07-13)

**Symptom:** The focused slide shows only a stray left-edge line instead of a complete KidulWM chrome border. Side peeks had broken geometry: right peek hung below border, center slide shifted up/left, left peek showed past the chamfer.

**Root causes:**
1. `applySurfaceClip()` clipped the XDG surface starting at `toplevel.base.geometry.x/y` while `setSurfaceOffset()` for focused windows left the surface tree at `(0,0)`. This shifted the visible client content away from the wrapper, so the chrome ring was either drawn outside the visible area or appeared as a detached line.
2. coderBob's second attempt clipped to `geom.width/height` at `(0,0)` for peeks, throwing away the buffer region the visible sliver needs and destroying slide alignment.
3. A third attempt changed `corner_style` from `.cut` to `.none`, removing the approved chamfers entirely.

**Confirmed fix:**
Clip the XDG `surface_tree` (not the chrome tree) to the wrapper bounds `(0, 0, target_w, target_h)` in `applyLayout()` only. Do **not** re-apply the clip from `handleCommit()` or `setSurfaceOffset()`. Keep the chrome overlay on its own scene tree so its geometry remains intact. The existing chrome overlay already has a full-bounds background mask, so the surface clip removes any remaining CSD pixels outside the wrapper.

**Lessons:**
- When the user says the geometry is perfect, only clip content. Never change `corner_style`, `border_width`, `chamfer_border_width`, `corner_depth`, or placement/offset code unless asked.
- Apply the clip once from the top-level layout pass, not from per-commit or per-offset hooks that run in different coordinate spaces.
- Keep a clean working tree when bisecting; dirty changes can produce binaries that do not match the commit being tested.

**Reference commits to avoid as-is:**
- `e6da1ab` (`chrome: clip XDG surface to content geometry and overdraw mask 1px inward`)
- coderBob's 2026-07-13 follow-up to that clip (modified `src/window.zig` only and shifted peek geometry)
