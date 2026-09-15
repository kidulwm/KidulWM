# KidulWM Tray — Creative Spec for coderBob

> **Addendum 2026-09-15 — Barry removed (Barticus verdict).** Barry the
> bulldog tray pet has been completely removed from the codebase: toy pets
> hold no input handles. The tray is now opened by clicking the RAM cauldron
> zone in the left-peek gauge pill, or via the existing keyboard toggle
> paths. All sections below that mention Barry are historical record only.

## 1. Goal

Build a beautiful, smooth, classy settings tray for KidulWM centered around a 3D-feeling animated line-art bulldog logo named Barry. The tray must feel premium: transparent background, black-glass stack buttons, gold-leaf lettering, and a subtle animated gradient sheen. The MAIN/Hide button is Barry — not a text label. The stack above it is reorderable and can fall back to alphabetical or preset order.

## 2. Starting State

- Repo: `/home/dad/dev/KidulWM`
- Branch: `corner-bg-fix`
- Base commit: `d389447` — "tray: strip UI to API stub, prepare for fresh rewrite"
- `src/ui/tray.zig` is an API-only stub. Public method signatures exist; rendering and pointer logic are gone.
- Reference commit: `c7c1392` — the last known booting tray with visible background and working scene-buffer plumbing.
- `zig build` currently passes from the stub. Keep it passing.

## 3. External API — do not change

Server/keyboard/pointer call these methods. Preserve exact names and signatures:

```zig
tray.init(allocator, host, root)  // Server.init
tray.deinit()
tray.addOutput(output_ctx)
tray.removeOutput(output_ctx)
tray.toggle()
tray.selectPrev()
tray.selectNext()
tray.activateSelected()
tray.handlePointerMove(px, py) -> bool
tray.handlePointerClick(px, py) -> bool
tray.scroll(delta)
tray.update()
tray.isOpen() -> bool
tray.requestUpdate()
```

## 4. Creative Vision

### 4.1 Barry the bulldog logo

- Barry lives in the MAIN/Hide button at the bottom of the tray.
- Render him as a procedural vector/line drawing with a subtle 3D feel: thick confident stroke, dimensional overlap, maybe a soft inner shadow or gradient-filled silhouette behind the lines.
- He must read as a bulldog: broad shoulders, short muzzle, slightly grumpy charm.
- Three animated states:
  - `laying` — tray closed. Slow breathing (chest rise/fall, ears relax). Occasional tiny tail wag.
  - `sitting` — tray open, idle. Sits up smoothly, ears perk, attentive.
  - `standing` — tray open + scroll active, or security alert. Stands alert, tail up, maybe a small paw-lift loop.
- Transitions between states should use spring physics; no instantaneous pops.
- Looping micro-animations must be time-based, cheap, and frame-rate-appropriate.

### 4.2 Color palette

- Use the existing style tokens in `src/core/style.zig` as the source of truth:
  - purple `0xa259ff`
  - electric blue/cyan `0x00f0ff`
  - turquoise `0x00ffc8`
  - gold `0x948e7b` and gold-dimmer `0x5e5a4c`
- Tray gradient rule: horizontally, approximately 25% purple on the left, 50% blue in the middle, 25% turquoise on the right.
- Use the gradient as a subtle animated sheen behind Barry, beneath black glass, and as the selected-item accent.
- Text/lettering: render labels in a gold-leaf tone (`color_gold` / `color_gold_dim`) with a thin dark shadow so it is always legible over any wallpaper.
- Center text horizontally inside each stack button.

### 4.3 Black glass stack

- Tray panel background is fully transparent.
- Each stack button is a rounded black-glass pill:
  - very dark fill with moderate alpha
  - subtle border in the same gold family
  - inner gradient sheen that shifts gently with selection/hover
  - soft drop shadow, not a hard edge
- The currently selected stack item gets an underline/accent using the gradient colors (blend purple → blue → turquoise) and a slightly brighter fill.
- MAIN/Hide Barry button is visually distinct: larger, no underline, no glass pill; Barry sits in/on a dark circular or rounded lozenge badge with the same gradient glow.
- Underline style should be "black glass" — dark inner core with a thin colored rim — rather than a flat neon line.

### 4.4 Motion quality

- Panel open/close uses a spring or high-quality ease, not linear `slide_rate`.
- Stack buttons stagger in as the panel opens: the bottom-most item (Hide/Barry) appears first, then each item above it slides/fades in with a small delay.
- Selection movement is a sliding underline that travels between items rather than jumping.
- Hover states animate background brightness.
- Barry transitions between laying/sitting/standing have clear anticipation and follow-through.
- Target 60 fps. No per-frame heap allocations. Cache surfaces and reuse them; mark dirty only when state/geometry changes.

## 5. Stack Data Model

```zig
const Action = union(enum) {
    toggle_tray,
    cycle_animation,
    spawn: []const u8,
    settings_page: []const u8,
    none,
};

const TrayItem = struct {
    id: []const u8,
    label: []const u8,
    action: Action,
};
```

- `main_item` represents Barry/Hide. It is never in the `items` array.
- Index `0` = MAIN/Hide slot.
- Indices `1..N` map to `items[0..N-1]`.
- `selected_index: usize` ranges `0..items.len`.
- `hover_index: ?usize` mirrors the same index space.

### 5.1 Ordering modes

- `manual` — the user can reorder items via drag-and-drop in the tray. Persist order in memory only for now (a config file is future work).
- `alphabetical` — sort `items` by `label` ascending. Keep a mode flag so the user can toggle.
- `preset` — a curated default order used on first run / when the user resets.

Default preset order for shipping:

```text
Terminal
Files
Browser
Motion
```

Add the mode to tray state:

```zig
pub const OrderMode = enum { manual, alphabetical, preset };
order_mode: OrderMode = .preset,
toggle_order_mode()  // cycle manual -> alphabetical -> preset
```

Toggling order mode re-sorts immediately and requests a redraw. For now, expose `tray.toggle_order_mode()` and bind it only if the user later asks; it does not need a default keybind.

## 6. Behaviour

### 6.1 Closed state

- Panel shows only the MAIN/Hide Barry button at the bottom.
- `selected_index = 0`, `hover_index = null`.
- Barry is in `laying` state.
- Moving the pointer over the button opens the tray and sets `selected_index = 1`.

### 6.2 Open state

- Panel grows upward from Barry.
- Barry switches to `sitting`.
- The first stack item (index 1) is selected by default.
- Stack items appear above Barry in visual order: topmost = `items[0]`, then `items[1]`, etc., with Barry at the bottom.
- Pressing Up from index 1 moves to index 0 (Barry/Hide).
- Pressing Down from index 0 moves to index 1.
- Pressing Down at the last item clamps.
- Selection underline is drawn only on the selected stack item, never on Barry.

### 6.3 Keyboard navigation

Existing keybindings (do not change `keyboard.zig`):

- `Mod4+t`      => `tray.toggle()`
- `Mod4+Up`     => `tray.selectPrev()`
- `Mod4+Down`   => `tray.selectNext()`
- `Mod4+Return` => `tray.activateSelected()`

Behaviour:

- Closed + `selectPrev()` or `selectNext()` => open and select `1`.
- `activateSelected()`:
  - index 0 => `toggle()` (close)
  - index 1..N => run `items[index-1].action`

### 6.4 Pointer interaction

- `handlePointerMove` returns `true` when inside the tray area to consume input.
- Hover over Barry => `hover_index = 0`.
- Hover over stack item i (0-based) => `hover_index = i + 1`.
- Click Barry => toggle close.
- Click stack item => set `selected_index = hover_index`, then `activateSelected()`.
- Moving pointer inside the tray while closed opens it.
- Moving pointer outside closes it unless `pinned`.

## 7. Rendering Constraints

- The tray renders into an ARGB32 Cairo surface uploaded via `DataBuffer` in `src/render/buffer.zig`.
- Reuse `render/buffer.zig` and the existing scene-buffer plumbing.
- Each output has a `PerOutput` entry with a `*wlr.SceneTree`, `?*wlr.SceneBuffer`, and cached buffer.
- Call `DataBuffer.create(pixels, width, height, stride)` with the raw Cairo surface data.
- Destroy old buffer before creating a new one; drop references with `wlr.Buffer.drop()`.
- Set destination size with `scene_buffer.setDestSize(w, h)`; position with the scene tree node.
- Only recreate the buffer when geometry, output scale, or tray state meaningfully changes. Track a dirty flag.
- Panel x = output `x`; panel y = `output.y + output.height - panel_height`.
- If the rendered result appears vertically flipped, ask before changing coordinates. Test orientation with a temporary solid rectangle if necessary.

## 8. Geometry Constants

Keep these close to the previous tray unless a better value is justified:

```zig
button_height: i32 = 44
button_gap: i32 = 8
bottom_margin: i32 = 10
hmargin: i32 = 8
tray_font_size: f32 = 16.0
```

Barry button can be slightly taller (e.g. 56 px) to give the illustration room. Panel width can be modest; do not let the tray dominate the screen.

## 9. Barry Implementation Notes

- Draw Barry using Cairo paths and gradients. You are free to use helper functions that build the shape from parameterized points so the animation can bend ears, tail, chest, etc.
- For "3D line drawing", use thick strokes with rounded caps, overlapping shapes, and a soft directional shadow behind the main outline.
- Keep the drawing code isolated in one or two functions so it can be iterated without touching the rest of the tray logic.
- Do not load PNG assets. Everything must be procedural.
- Use `std.math.sin`/`cos` and wall-clock time (microseconds) for looping motion. Keep the time values cached per update.

## 10. What NOT to Do

- Do not change `keyboard.zig`, `pointer.zig`, `keybinds.zig`, or `server.zig`.
- Do not introduce GTK, layer-shell, or external image dependencies.
- Do not add unbounded allocations on every frame.
- Do not let the tray block workspace layout or hide behind the wallpaper.
- Do not over-engineer scroll; with 4 preset items, all should fit.

## 11. Acceptance Criteria

1. `zig build` passes.
2. Deployed binary starts KidulWM; background visible, tray visible at boot.
3. Closed tray shows Barry laying at the bottom.
4. `Mod4+t` opens the tray; Barry sits up; stack appears; Barry label "Hide" is no longer text.
5. `Mod4+Down` moves selection down; `Mod4+Up` moves selection up; Up from first app reaches Barry.
6. Activate Barry closes the tray.
7. Activate Motion cycles animation.
8. Pointer hover and click match keyboard behaviour.
9. `tray.toggle_order_mode()` works: cycles preset -> alphabetical -> manual ordering.
10. Open/close and Barry transitions are visibly smooth at 60 fps in the VM.
11. Opening a new window while the tray is open does not corrupt layout or labels.

## 12. Build & Deploy

```bash
cd /home/dad/dev/KidulWM
zig build
scp -P 2225 -i /home/dad/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm.new
ssh -p 2225 -i /home/dad/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
    'sudo killall -9 kidulwm; sleep 1; sudo cp /tmp/kidulwm.new /usr/bin/kidulwm; sudo chmod 755 /usr/bin/kidulwm; sudo systemctl start kidulwm'
```

Do not deploy to the VM unless the user explicitly approves.
