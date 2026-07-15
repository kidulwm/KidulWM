# KidulWM chamfer inset correction — 2026-07-11

Session outcome: the inner chamfer inset must scale with border width to keep diagonal legs from looking thinner than straight sides.

## The insight

For a 45° chamfer, the straight sides and the diagonal corner share the border thickness, but each adjacent straight side only contributes half of the extra width to the diagonal leg. A simple parallel offset of `border` leaves the chamfer leg visually thinner.

The fix is to inset the inner chamfer by **twice** the perpendicular border width:

```zig
const inner_inset: f64 = 2.0 * border;
inner_style.corner_depth = @max(0.0, depth - inner_inset);
```

This gives each straight side its full width while the diagonal absorbs the combined half-contributions, making the chamfer legs look the same thickness as the straight edges.

## Later refinement

After the 2× fix the user still wanted the inner chamfer about 1–2 px deeper. We combined the visual target with a 1.6× base parallel factor, then doubled that to **3.2× border**:

```zig
const inner_inset: f64 = 3.2 * border;
```

Result: focused corners look correct; inner cut is slightly more interior/squarish but acceptable. 2 px border width emerged as the best balance between subtlety and legibility.

## Working calculation

```zig
border      = style.border_width * output_scale
inner_inset = 3.2 * border
inner_depth = max(0, corner_depth * scale - inner_inset)
inner_rect  = (x + border, y + border, w - 2*border, h - 2*border)
```

Note: the straight-edge inset stays at `border` so sides keep their intended width. Only the **chamfer depth** is reduced by `inner_inset`.

## Anti-patterns to avoid

- Fixed-pixel extra insets (e.g. `+1.5 px`) do not scale with border width and become wrong when the user changes it.
- Using the same `inner_inset` for both the rectangle position and the chamfer depth shrinkage distorts the inner shape or makes the straight sides too thick.
- A simple `depth - border` produces visually thinner diagonal legs on chamfered windows.

## Reproduction in the VM

```bash
ssh -p 2222 kidul@127.0.0.1 'WAYLAND_DISPLAY=wayland-1 kidulwm-control set_theme border_width 2'
ssh -p 2222 kidul@127.0.0.1 'WAYLAND_DISPLAY=wayland-1 kidulwm-control set_theme corner_style cut'
```

Then QEMU monitor screendump as described in `references/visual-verification.md`.

## Related

- `references/chrome-iteration-lessons.md` — what worked and what didn't across this chrome pass.
- `references/compositor-chrome-buffers.md` — overlay-buffer recipe and runtime theme IPC.
