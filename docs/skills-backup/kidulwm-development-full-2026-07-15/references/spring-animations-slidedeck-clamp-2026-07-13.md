# Enabling spring animations and fixing deeper-slide placement

Date: 2026-07-13
VM: cachyos-kidulwm-rounded-fun

## Current state

`src/core/animation.zig` already ships with a spring-based `WindowAnimation` struct (position + size + opacity). `src/server.zig Output.handleFrame` calls `Window.tickAnimation(now_us)` for every mapped window every frame, so the wiring is in place.

The animation is effectively disabled in two places:

1. `Window.setLayoutTarget()` in `src/window.zig` copies `target_*` into `cur_*` immediately, so there is never any distance for the spring to integrate over.
2. `Window.tickAnimation()` then just snaps `cur_*` to `target_*` instead of calling `WindowAnimation.tick()`.

## Minimal change to enable motion

1. In `setLayoutTarget()`:
   - Set `target_x`, `target_y`, `target_w`, `target_h`.
   - Only snap `cur_*` to `target_*` on the first layout call (`target_w == 0 && target_h == 0`).
   - Initialise `last_us` from `animation.nowUs()`.

2. In `tickAnimation()`:
   - Return early if the surface is unmapped.
   - Call `self.animation.tick(now_us)`.
   - Apply `@round(self.animation.cur_x)` / `@round(self.animation.cur_y)` to `self.scene_tree.node.setPosition`.
   - Regenerate chrome via `self.updateChrome(...)` so the overlay size follows the animated current size, not the final target.
   - For the focused slide only (`chrome_edges.eql(.all)`), scale the committed surface buffer to the animated current size with `setSurfaceDestSize(cur_w_int, cur_h_int)`. This keeps the client surface aligned with the wrapper while it is animating.

## Placement bug exposed by animation

Once motion is enabled, `SlideDeck.targetForSlide()` returns `delta * screen_width` (or height) for any slide whose distance from focus is two or more. When the focus changes, those distant windows must fly across the entire output to reach their new off-screen position, overlapping the focused slide and sometimes landing far outside the screen.

Fix: clamp deeper slides to the same single-screen off-screen slot as the adjacent peek side:

```zig
// horizontalTarget
-1 => -width + left_w,  // left peek, partially visible
 0 => left_w,           // focused
 1 => left_w + focus_w,  // right peek, partially visible
else => if (delta < 0) -width else left_w + focus_w,
// width always self.width except for focused
```

Use the same pattern in `verticalTarget`. This means only the focused slide and its immediate left/right neighbours ever move; deeper slides are parked just off the nearest edge.

## Performance caveats

- Regenerating chrome Cairo buffers every frame while a window's size is changing is expensive. On a VM using the Pixman renderer this may drop frames or feel choppy.
- If motion stutters, consider animating only position/opacity and snapping size, or cache/scale a single chrome buffer instead of redrawing per integer size step.

## Deploy notes for the rounded clone

- Build: `zig build`
- Copy: `scp -P 2224 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm.new`
- Swap: stop `kidulwm` before overwriting `/usr/bin/kidulwm` — a live binary is memory-mapped (`Text file busy`).
