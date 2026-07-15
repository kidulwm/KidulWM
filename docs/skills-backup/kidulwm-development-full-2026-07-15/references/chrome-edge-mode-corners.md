Chrome edge-mode corner shaping

File: `src/render/chrome.zig`

When a SlideDeck neighbour is rendered as a side peek, its `EdgeMode` marks the off-screen edge hidden (`right_peek` hides the right edge; `left_peek` hides the left edge). The original renderer built a symmetric chamfer ring for `.cut` style and then only trimmed rectangular strips off hidden edges. That left visible top/bottom borders chamfered on both ends and produced corner squares/artifacts at the hidden seam.

Fix: derive per-corner chamfer depths from the edge mode. A corner gets a chamfer only when both adjacent edges are visible. Hidden-edge corners are square, so the visible straight edges run all the way to the seam.

Key pieces
- `ChamferDepths` holds `tl/tr/br/bl` depths.
- `ChamferDepths.fromEdgeMode(depth, edges)` zeros a corner if either adjacent edge is hidden (for nested `ColorStyle`, that means style fields). The check is: `.tl` needs `top && left`, `.tr` needs `top && right`, `.br` needs `bottom && right`, `.bl` needs `bottom && left`.
- `chamferRect` accepts per-corner depths and drops the diagonal move for square corners (`depth == 0`), otherwise it emits the familiar `move_to/line_to` octagon path.
- `chamferInnerPolygon` accepts per-corner depths and builds a CCW outer polygon where square corners are just duplicated start/end points of the adjacent straight edge.
- `renderChrome` computes:
  - `depths = ChamferDepths.fromEdgeMode(depth, edges)` for the outer ring.
  - `inner_depths` from each outer depth shrunk by `(border + chamfer_border) * 0.5`, because the inner polygon is constructed from intersected offsets rather than a simple scaled copy.
- Background mask uses a full-rectangle outer path (`squareRect`) so client content never bleeds into the empty triangles outside a chamfered window. The border ring then uses the edge-aware `chamferRect` outer path in even-odd fill against the same inner polygon.
- Focused windows use `EdgeMode.all`, so all four corners stay chamfered.

Result: right-peek top/bottom borders now chamfer only on the left side and run straight to the right edge. Left-peek is the mirror. The VM screendump/vision check should show narrow side peeks with square corners at the screen edge and chamfered corners facing the focused slide, with no border bleed.

Verification recipe
1. `zig build && zig build test --summary all`
2. Deploy binary to VM and restart kidulwm.
3. Spawn several Ghostty windows (`GTK_CSD=0 GDK_DEBUG=no-csd` so decorations are compositor-owned).
4. Capture screendump: `virsh -c qemu:///system qemu-monitor-command cachyos-kidulwm --hmp 'screendump /tmp/vm-verify.ppm'`.
5. Convert and inspect: `magick /tmp/vm-verify.ppm /tmp/vm-verify.png`.
6. Confirm far-left/right peeks have square corners on the hidden edge and chamfered corners on the inner/visible edge.

Related: `references/chrome-variable-borders.md`, `references/compositor-chrome-buffers.md`, `references/chrome-iteration-lessons.md`.
