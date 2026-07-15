# KidulWM chrome iteration lessons

Condensed notes from the live 2026-07-10/11 polish pass. Use this when returning to compositor-owned chrome / SlideDeck borders.

## Where we landed (checkpoint 2026-07-11)

The `chrome-2x` branch (off `cc61090`) deployed to the VM with a corrected chamfer inset.

- Focused border: `#948e7b`  
- Unfocused border: `#5e5a4c`
- Default border width tested good at **2 px**.

## What worked

- Cairo ARGB32 overlay into a custom CPU `wlr.Buffer`, attached as `wlr.SceneBuffer` per window.
- EdgeMode constants for SlideDeck side peeks:  
  - `left_peek` shows the edge that abuts the focused window (right edge) and hides the off-screen edge (left).  
  - `right_peek` shows the edge that abuts the focused window (left edge) and hides the off-screen edge (right).  
  This frames the focused window with borders on both sides while keeping the outer edges of peeks clean.
- `zxdg_decoration_manager_v1` with SSD default forces server-side decoration for most clients; Ghostty/GTK4 additionally needs `GTK_CSD=0` and `GDK_DEBUG=no-csd`.
- **Chamfered corner legs match straight sides** when the inner chamfer depth is inset by **3.2 × border**. The base parallel-offset factor is ~1.6×; doubling it compensates for the way a 45° diagonal shares extra width between two adjacent straight sides.
- Runtime theme IPC for `border_width`, `corner_style`, etc., via `kidulwm-control set_theme <key> <value>`.

## What did not work / got reverted

- **Outer-path edge shifting** (`ox/oy/ow/oh` adjusted by hidden edges) caused side-peek borders to be drawn on the wrong side or trimmed incorrectly. Fix: draw the full ring, then erase hidden edges.
- **Clearing only `border + 1`** left chamfer stubs on internal seams, which looked doubled/messy. Clearing `depth + border + 1` was too aggressive and cut visible top/bottom borders short of the screen edge. A chamfer-aware edge mask is still needed.
- **Inner square cutout** made chamfer legs look thinner than the sides and produced faint lines at the inner corner.
- **Background-colour matte between a square rectangle and the inner chamfer** made the inner corners *look* square again, defeating the purpose.
- **Fixed "+1.5 px" inner inset** did not scale with border width. The correct compensation is proportional to border width.

## Geometry rules

1. Outer and inner cutouts must be **parallel offsets** of the same corner shape.
2. For **chamfered** corners, shrink the inner chamfer depth by `3.2 * border` while keeping the straight-edge inset at exactly `border`. This makes diagonal legs visually the same thickness as straight sides.
3. To prevent client content from showing square behind the chamfer, either clip the client surface (requires shader, wlroots scene cannot do shaped clip) or cover the corner triangles with the frame colour.
4. For hidden/shared edges in SlideDeck, erase the entire border strip *and* the adjacent chamfer wedge. A single big rectangle is not precise enough.

## Verification

- `zig build && zig build test --summary all`
- Offline binary swap into `cachyos-kidulwm` via qcow2/nbd.
- QEMU monitor screendump; `grim` does not work because KidulWM lacks `wlr-screencopy-v1`.
- Launch Ghostty with `GTK_CSD=0 GDK_DEBUG=no-csd`.
- Runtime: `kidulwm-control set_theme border_width 2` etc.

Details and the math behind the 3.2× inset are in `references/chrome-chamfer-inset-2026-07-11.md`.
