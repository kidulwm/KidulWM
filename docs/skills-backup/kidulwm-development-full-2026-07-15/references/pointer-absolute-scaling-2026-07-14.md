# Pointer absolute coordinate scaling — 2026-07-14

## Problem

QEMU user tablets (`usb-tablet`) and `virtio-tablet-pci` send **normalized `[0,1]` absolute motion events**. Treating `event.x` and `event.y` as screen pixels leaves the cursor trapped near the top-left corner.

## Fix

In `src/input/pointer.zig`, scale absolute events to the output-layout extents before updating cursor position:

```zig
var box: wlr.Box = undefined;
server.output_layout.getBox(null, &box);
server.cursor_x = event.x * @as(f64, @floatFromInt(box.width));
server.cursor_y = event.y * @as(f64, @floatFromInt(box.height));
server.cursor.warpAbsolute(null, server.cursor_x, server.cursor_y);
```

## References

- `handleMotionAbsolute` in `src/input/pointer.zig`.
- `output_layout.getBox(null, &box)` is already used in `src/server.zig::handleOutputLayoutChange` and gives full layout width/height.

## When this matters

- VMs with virtual tablets instead of relative PS/2 mice.
- SPICE remote viewers forwarding absolute pointer position.
