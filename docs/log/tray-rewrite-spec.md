# KidulWM Tray Rewrite — One-shot Spec for coderBob

## 1. Goal
Replace the current settings-tray implementation in `src/ui/tray.zig` with a minimal, correct, maintainable tray that satisfies both WM-keyboard users and casual mouse users. The tray must be a solid foundation for eventually adding Barry the bulldog as the MAIN button.

## 2. Fresh Start Base
- Repo: `/home/dad/dev/KidulWM`
- Branch: `corner-bg-fix`
- Start from commit: `16763dd` ("tray: strip UI to API stub, prepare for fresh rewrite")
- This commit intentionally contains a no-op tray stub with the public API intact. `src/ui/tray.zig` is currently empty of rendering and pointer logic; server, keyboard, and pointer still build and run.
- Fallback/ref state: `c7c1392` ("Fix tray visibility at boot: refresh output geometry and raise overlay tree above background") boots cleanly with a visible tray and background.

## 3. Build & Deploy
```bash
cd /home/dad/dev/KidulWM
zig build
# Copy into the guest VM (bob-is-a-douche, SSH forwarded on port 2225):
scp -P 2225 -i /home/dad/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm.new
ssh -p 2225 -i /home/dad/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
    'sudo killall -9 kidulwm; sleep 1; sudo cp /tmp/kidulwm.new /usr/bin/kidulwm; sudo chmod 755 /usr/bin/kidulwm; sudo systemctl start kidulwm'
```

## 4. Files Involved
- `src/ui/tray.zig` — primary implementation (rewrite this, but keep method signatures)
- `src/server.zig` — owns `Server.tray`, frame/update callback, output layout
- `src/input/keyboard.zig` — maps key actions to tray methods
- `src/input/pointer.zig` — forwards pointer move/click to tray
- `src/core/style.zig` — colour tokens
- `src/config/keybinds.zig` — key action enum names

## 5. Tray External API (keep stable)
Server keeps `tray: ui.tray.Tray`. The following methods are called from outside `tray.zig`:

```zig
tray.init(allocator, host, root)  // called once during Server.init
tray.deinit()
tray.toggle()                    // bound to Mod4+t
tray.selectPrev()                // bound to Mod4+Up
tray.selectNext()                // bound to Mod4+Down
tray.activateSelected()          // bound to Mod4+Return / click
tray.handlePointerMove(px, py)   // from pointer handler
tray.handlePointerClick(px, py)   // from pointer handler
tray.update()                    // called each frame
```

Do not change signatures or names.

## 6. Data Model
```zig
const TrayItem = struct { id: []const u8, label: []const u8, action: Action };

items: []const TrayItem = &.{
    .{ .id = "term",  .label = "Terminal", .action = .{ .spawn = "" } },
    .{ .id = "files", .label = "Files",    .action = .{ .spawn = "" } },
    .{ .id = "browser", .label = "Browser", .action = .{ .spawn = "" } },
    .{ .id = "motion", .label = "Motion", .action = .cycle_animation },
};

main_item: TrayItem = .{ .id = "main", .label = "All The Things", .action = .toggle_tray };
hide_item: TrayItem = .{ .id = "hide", .label = "Hide",          .action = .toggle_tray };
```

Key rule: index 0 is the MAIN/Hide slot. Indices 1..N map to `items[0..N-1]`.

State:
- `open: bool`
- `selected_index: usize` — 0..items.len
- `hover_index: ?usize`
- `pinned: bool` — leave plumbing, normal use is false
- `scroll_offset: f32` — for when stack is taller than peek height

## 7. Closed State
- Panel height = `button_height + bottom_margin`.
- Panel anchored at output bottom.
- One visible button at the bottom of the panel: label "All The Things".
- `selected_index` = 0, `hover_index` = null.
- MAIN/Hide button never has an underline.
- Barry note: later this becomes Barry laying down.

## 8. Open State
- Panel height = `button_height + bottom_margin + stack_height`, capped by output height so it never disappears off the top.
- Stack grows upward from the MAIN/Hide button.
- The MAIN/Hide button label becomes "Hide".
- `selected_index` starts at 1 (first app, visually top of the stack).
- The Hide button is reachable by pressing Up from the first app.
- Focus underline is drawn only on the currently selected stack item.
- The MAIN/Hide button never shows an underline.

## 9. Keyboard Navigation
Keybindings (do not change `keyboard.zig`):
- `Mod4+t`         => `tray.toggle()`
- `Mod4+Up`        => `tray.selectPrev()`
- `Mod4+Down`      => `tray.selectNext()`
- `Mod4+Return`    => `tray.activateSelected()`

Behaviour:
- Closed + `selectPrev()` or `selectNext()` => open tray, set `selected_index = 1`.
- `selectPrev()`: clamp `selected_index > 0`; decrement. Moving from 1 to 0 selects Hide.
- `selectNext()`: clamp `selected_index < items.len`; increment.
- `activateSelected()`:
  - index 0 => `toggle()` (close)
  - index 1..N => run `items[index-1].action`

## 10. Pointer Interaction
- Hover over MAIN/Hide => `hover_index = 0`.
- Hover over stack item i (0-based) => `hover_index = i + 1`.
- Click MAIN/Hide => toggle close.
- Click stack item => activate selected index, run action.
- Moving pointer over the tray while closed should open it and set `selected_index = 1`, tracking hover.
- Moving pointer outside the tray closes it unless pinned.

## 11. Visual Design
- `button_height = 44`, `button_gap = 8`, `bottom_margin = 10` (existing constants from previous tray).
- Tray panel background: transparent.
- Button style: simple rounded dark/glass button using `src/core/style.zig` tokens.
- Text: white-ish from theme, horizontally centred within the button.
- Selected stack item: underline or small accent border under the label.
- MAIN/Hide button: no underline/focus accent.
- Visual order: top of open tray is `Terminal`, then `Files`, `Browser`, `Motion`, then `Hide` at the bottom.

## 12. Rendering Hints
- The tray renders into an ARGB Cairo surface uploaded as a wlroots scene buffer.
- Use `c.cairo_image_surface_create_for_data()` and the existing `DataBuffer` helper in `src/render/buffer.zig`.
- Each output has a `PerOutput` entry with a scene tree and scene buffer.
- `updatePerOutput()` runs each frame; recreate the buffer only when geometry or state changes.
- Panel x = output `x`; panel y = `output.y + output.height - panel_height`.
- If the rendered panel appears vertically flipped on screen, ask before changing coordinates. Test orientation with a temporary coloured rectangle if needed.

## 13. Barry Integration (future)
Leave a hook for Barry state:
```zig
const BarryState = enum { laying, sitting, standing };
fn updateBarryState(self: *Self, state: BarryState) void;
```
For this task, keep the MAIN/Hide button as centred text. Once the tray is solid, we will replace it with a PNG icon set:
- laying  -> closed tray
- sitting -> open tray, no scroll / at rest
- standing-> open tray with active scroll, or security alert

Do not chase Barry artwork in this task. Just ensure the MAIN/Hide drawing path is isolated in one function that can be swapped later.

## 14. What NOT To Do
- Do not mutate labels on `TrayItem` to switch between "All The Things" and "Hide".
- Do not remove tray from server wiring; keep the API alive.
- Do not add a GTK or layer-shell tray.
- Do not over-engineer scroll; with only 4 apps, they can all fit above Hide.
- Do not change `keyboard.zig`, `pointer.zig`, or keybinds.

## 15. Acceptance Criteria
1. `zig build` passes.
2. Deployed binary starts KidulWM; background shows and tray is visible at boot.
3. Closed tray shows "All The Things" at the bottom, no underline.
4. Press `Mod4+t` -> opens tray showing Hide + Terminal/Files/Browser/Motion above it.
5. `Mod4+Down` moves focus down the stack; `Mod4+Up` moves focus up.
6. Up from Terminal reaches Hide.
7. Activate on Hide closes tray.
8. Activate on Motion cycles animation.
9. Pointer hover and click behave like keyboard focus/activate.
10. Opening a new window while the tray is open does not corrupt layout or labels.
