# Tray Calendar, Clock, and Shared Theme System — Implementation Plan

> **For Hermes:** Use `subagent-driven-development` or delegate focused passes to coderBob. This plan is designed so each numbered task can be shipped independently.

**Goal:** Build a compositor-internal calendar/clock surface in KidulWM's tray that opens over the focused slide, driven by a shared `theme.toml` token file that also feeds the existing rkt-dashboard GTK4 panels.

**Architecture:** Extract all style tokens from `src/core/style.zig` into an external `theme.toml`. Zig reads it at startup and on `kidulwm-control set_theme`. The tray already owns Cairo overlay buffers; extend it with a new `TraySurface` or `TrayCard` abstraction sized to the focused window's `layout_target`. Keep everything in Zig until a feature genuinely needs GTK4 (forms, file thumbnails, web rendering).

**Tech Stack:** Zig 0.14, wlroots 0.20, Cairo, TOML, GTK4 for existing rkt-dashboard only.

---

## Phase 0 — Theme Token Extraction

### Task 0.1: Audit current style tokens

**Objective:** Make an exhaustive list of every hard-coded color, font, metric, and animation constant used by the tray, chrome, and dashboard.

**Files:**
- Read: `src/core/style.zig`
- Read: `src/ui/tray.zig`
- Read: `src/render/chrome.zig`
- Read: `rkt-dashboard/src/theme.css` or equivalent
- Read: `rkt-dashboard/src/*.rs` for color constants

**Commands:**
```bash
cd /home/dad/dev/KidulWM
grep -nE '#[0-9a-fA-F]{6}|rgba?\(|font_size|border_width|corner|tray_' src/core/style.zig src/ui/tray.zig src/render/chrome.zig
```

**Output:** A markdown table mapping each token to a semantic name and current value.

**Verification:** Table reviewed with Barticus; no code changes yet.

---

### Task 0.2: Design `theme.toml` schema

**Objective:** Define the shared token file format that Zig and GTK4 can both consume.

**Create:** `config/theme.toml`

**Proposed schema (start minimal, grow later):**

```toml
# /etc/kidulwm/theme.toml
# /usr/share/kidulwm/theme.toml fallback
# ~/.config/kidulwm/theme.toml user override

[metadata]
name = "KidulWM Default"
version = "1.0.0"

[colors]
background = "#222425"
gold = "#C9A227"
gold_dim = "#9A7B1A"
text_body = "#E5D7A8"
text_muted = "#8A7B5A"
text_focused = "#F5E7B8"
black_glass = "rgba(10, 10, 10, 0.92)"
black_glass_mid = "rgba(10, 10, 10, 0.60)"
rim_light = "rgba(255, 255, 255, 0.08)"
border = "#9A7B1A"
urgent = "#BF616A"
info = "#88C0D0"
purple = "#B48EAD"
turquoise = "#8FBCBB"
blue = "#5E81AC"

[typography]
font_mono = "Fantasque Sans Mono"
font_size_s = 13
font_size_m = 17
font_size_l = 22

[spacing]
button_height = 48
button_gap = 6
char_buffer_m = 16.0
corner_radius = 8
icon_size = 24
icon_gap = 8

[animation]
tray_open_ms = 320
tray_close_snap_ms = 125
tray_settle_pulse_ms = 170
underline_spring_stiffness = 80.0
barry_follow_delay_s = 3.0
```

**Verification:** Barticus approves the naming and initial value set.

---

### Task 0.3: Add TOML parsing to KidulWM

**Objective:** Load `theme.toml` at startup and store values in runtime style state.

**Files:**
- Modify: `src/core/style.zig`
- Modify: `build.zig` (add `libtomlc99` or vendored Zig TOML)
- Modify: `src/server.zig` (call load on init)

**Recommended parser:** `https://github.com/Gonzih/toml-zig` or similar pure-Zig TOML parser. Avoid C dependency if possible.

**Implementation approach:**
1. Add a `Theme` struct in `src/core/style.zig` to hold runtime values.
2. Keep existing constants as fallback defaults.
3. Add `theme.loadFromFile(allocator, path)` returning error if malformed.
4. Search order: `~/.config/kidulwm/theme.toml` → `/etc/kidulwm/theme.toml` → `/usr/share/kidulwm/theme.toml`.
5. Add `theme.initDefaults()` to seed fallback values.

**Code sketch:**

```zig
// src/core/style.zig
pub const Theme = struct {
    colors: ColorTokens,
    typography: TypeTokens,
    spacing: SpacingTokens,
    animation: AnimationTokens,
    generation: u32 = 0,

    pub fn load(self: *Theme, allocator: std.mem.Allocator, path: []const u8) !void {
        // parse TOML, fill fields, then bump generation counter
        self.generation +%= 1;
    }

    pub fn reload(self: *Theme, allocator: std.mem.Allocator) !void {
        // try override paths in order, fall back to defaults
    }
};
```

**Verification:**
```bash
cd /home/dad/dev/KidulWM
zig build
./zig-out/bin/kidulwm --check-theme
```
Exit code 0 and log shows parsed values.

---

### Task 0.4: Plumb theme into tray drawing

**Objective:** Replace hard-coded tray constants with theme lookups.

**Files:**
- Modify: `src/ui/tray.zig`

**Step 1:** Add `theme: *const Theme` reference to `Tray`.

**Step 2:** Replace every literal color/font/metric in `drawStackButton`, `drawBarryButton`, etc. with `theme.*` access.

**Step 3:** When `theme.generation` changes, mark the tray buffer dirty.

**Verification:**
1. Build passes.
2. Tray still draws gold text on transparent background.
3. Closing `theme.toml` change triggers reload via `kidulwm-control set_theme` (Task 0.5).

---

### Task 0.5: Runtime theme reload via `kidulwm-control`

**Objective:** Allow live theme updates without restarting the compositor.

**Files:**
- Modify: `src/control.zig` or existing IPC handler
- Modify: `src/server.zig`
- Modify: `kidulwm-control` CLI

**Implementation:**
1. Add `set_theme` command that accepts either key=value pairs OR `reload`.
2. On reload, call `server.theme.reload(allocator)`.
3. Bump `theme.generation`.
4. Mark all outputs' tray buffers and chrome overlays dirty.

**Code sketch (control handler):**
```zig
// server side
if (std.mem.eql(u8, cmd, "reload_theme")) {
    server.theme.reload(server.allocator) catch |err| {
        log.err("theme reload failed: {}", .{err});
        return;
    };
    server.damageAll();
}
```

**Verification:**
```bash
# inside VM after deploy
kidulwm-control reload_theme
```
Tray text color changes within one second.

---

### Task 0.6: Optional theme bridge for existing rkt-dashboard (Rust/GTK4)

**Status:** Optional compatibility shim only. New shell UI is all Zig.

**Context:** `rkt-dashboard` is the existing Rust/GTK4 side-panel process. It is not the target architecture for the new calendar/clock/tray cards. However, until those panels are rewritten as Zig surfaces, we can let GTK4 read the same `theme.toml` so colors stay consistent without manual CSS edits.

**Files:**
- Create: `rkt-dashboard/src/theme.rs`
- Modify: `rkt-dashboard/src/main.rs`

**Implementation:**
1. Use the `toml` crate or simple line-based parser.
2. Search same paths as Zig.
3. On startup (and optionally on SIGHUP), parse `theme.toml`.
4. Generate CSS from tokens:
   ```css
   @define-color rkt-gold #C9A227;
   @define-color rkt-black-glass rgba(10, 10, 10, 0.92);
   @define-color rkt-text-body #E5D7A8;
   /* etc */
   window.background, .rkt-panel { background-color: @rkt-black-glass; }
   .rkt-gold-text { color: @rkt-gold; }
   ```
5. Load CSS provider at `STYLE_PROVIDER_PRIORITY_USER`.

**Verification:**
```bash
cd /home/dad/dev/KidulWM/rkt-dashboard
cargo build --release
systemctl --user restart rkt-dashboard.service
```
Side panels render with colors matching the Zig tray.

**CoderBob note:** Do not block the Zig work on this task. If it causes friction (crate dependency, compile issues), drop it and keep the Zig-only tokens moving.

---

## Phase 1 — Focused-Slide Calendar/Clock Surface

### Task 1.1: Add focused-window geometry access to tray

**Objective:** Let the tray compute the focused slide's current layout rectangle.

**Files:**
- Modify: `src/ui/tray.zig`
- Modify: `src/server.zig` (if needed)

**Implementation:**
1. Add a helper on `Server` or `Output`:
   ```zig
   pub fn focusedLayoutTarget(server: *Server) ?wlr.Box {
       const window = server.seat.keyboard_state.focused_window orelse return null;
       return window.layout_target;
   }
   ```
2. Expose `Output.focusedWindowTarget()` that returns the focused window's target box in output-local coordinates.
3. Add `TrayCard` struct to hold target geometry and open animation spring.

**Verification:** Log the focused box on every `Mod4+t` and confirm it matches the visible focused window.

---

### Task 1.2: Create `TrayCard` reusable overlay

**Objective:** Build a generic "open over the focused slide" container that other apps can reuse.

**Files:**
- Create or modify: `src/ui/tray.zig` (add `TrayCard`)

**Concept:**
```zig
const TrayCard = struct {
    target: wlr.Box,
    open_amount: f64,
    content: Content, // union: calendar, clock, notifications, etc.
    surface: ?*cairo.Surface,
    scene_buffer: ?*wlr.SceneBuffer,
};
```

**Rendering rules:**
- Background uses `theme.colors.black_glass`.
- 1px gold rim with `CAIRO_OPERATOR_SOURCE`.
- Content inset by `border_width` + `corner_radius`.
- Spring open animation: same integrator as tray panel.

**Verification:** With no content, pressing a test keybinding draws an empty gold-rimmed glass rectangle exactly over the focused window.

---

### Task 1.3: Clock glyph surface

**Objective:** Draw a compositor-native clock in Cairo.

**Files:**
- Modify: `src/ui/tray.zig`

**Design:**
- 7-segment or simple analog clock face.
- Render hour/minute/second hands with theme colors.
- Digital fallback text below or inside the face.
- Use Fantasque Sans Mono for digits.
- Read `time(NULL)` once per second; mark dirty when seconds roll over.

**Geometry modes (chosen by focused window aspect ratio):**
- Square/tall focused window → analog clock centered.
- Wide focused window → horizontal digital strip across the top.

**Verification:** Card opens over focused window and shows the correct local time.

---

### Task 1.4: Calendar grid surface

**Objective:** Draw a month calendar inside the card.

**Files:**
- Modify: `src/ui/tray.zig`

**Design:**
- Header: month/year in gold.
- Grid: Su Mo Tu We Th Fr Sa in muted text.
- Today highlighted with a gold rim or filled lozenge.
- Selected day (cursor) with underline.
- Week numbers optional.
- Events/dots from notifications (Phase 2).

**Layout:**
- Tall focused window → calendar fills vertically with larger cells.
- Wide focused window → compact header + horizontal week rows.

**Verification:** Open card shows the current month; today's cell is visually distinct.

---

### Task 1.5: Clock + calendar state machine

**Objective:** One keybinding or tray action opens a unified card with clock (top) and calendar (bottom) or side-by-side depending on aspect ratio.

**Files:**
- Modify: `src/ui/tray.zig`
- Modify: `src/input/keyboard.zig`

**Implementation:**
1. Add `TrayCard` instance to `Tray`.
2. Add action `.open_clock_calendar` (or reuse a tray item).
3. On activate, compute focused box and snap the card spring target to `1.0`.
4. On `Escape` or clicking outside, close it (`target = 0.0`).
5. When the focused window changes while the card is open, retarget geometry to the new focus over ~120 ms.

**Verification:**
- `Mod4+t` to open tray.
- Activate clock/calendar item.
- Card animates over focused window.
- Moving focus to another slide retargets the card.

---

### Task 1.6: Hover preview behavior

**Objective:** Applications in the tray preview on hover, take focus on click.

**Files:**
- Modify: `src/ui/tray.zig`

**Implementation:**
1. Add hover state to `TrayItem`.
2. On hover, open a small `TrayCard` sized to a preview area (e.g., 60% of focused window) showing app info.
3. On click, launch/focus that app and close the preview.
4. Use the same card renderer so visual style is identical.

**Verification:** Hovering "Files" shows a compact preview card; clicking opens the file manager.

---

## Phase 2 — Notifications & System Status

### Task 2.1: Notification store in server state

**Objective:** Centralize notifications so tray, dashboard, and security popups share one source of truth.

**Files:**
- Create: `src/notifications/store.zig`
- Modify: `src/server.zig`

**API:**
```zig
pub const Notification = struct {
    id: u32,
    app_name: []const u8,
    summary: []const u8,
    body: []const u8,
    urgency: Urgency,
    timestamp_us: i64,
};

pub const Store = struct {
    list: std.ArrayList(Notification),
    next_id: u32,
    pub fn add(self: *Store, n: Notification) u32;
    pub fn dismiss(self: *Store, id: u32) void;
    pub fn recent(self: *Store, limit: usize) []const Notification;
};
```

**Verification:** Unit test add/dismiss/list; build passes.

---

### Task 2.2: Notification card UI

**Objective:** Render a vertically scrolling list of notifications inside `TrayCard`.

**Files:**
- Modify: `src/ui/tray.zig`

**Design:**
- Each row: app icon (if available), summary, age (e.g. "2m").
- Urgent rows use `theme.colors.urgent`.
- Info rows use `theme.colors.info`.
- Dismiss via swipe or key.

**Verification:** Inject a test notification from `kidulwm-control notify test` and see it appear.

---

### Task 2.3: Security popup migration

**Objective:** Move existing security alerts into the notification store/card.

**Files:**
- Locate existing security popup code (search `security` in `src/`).
- Modify: relevant file + `src/ui/tray.zig`

**Verification:** Simulated security event appears in the notification card with correct urgency color.

---

## Phase 3 — Quick Toggles & App Launcher

### Task 3.1: Toggle buttons

**Objective:** Add Wi-Fi, Bluetooth, Do Not Disturb, Night Light toggles in a grid inside a card.

**Files:**
- Modify: `src/ui/tray.zig`

**Implementation:**
1. Extend `TrayCard.Content` with `.toggles`.
2. Draw a grid of square buttons with icons and labels.
3. Click flips state and re-renders.

**Verification:** Toggle visual state changes on click.

---

### Task 3.2: App launcher grid

**Objective:** Full app launcher as a card over the focused slide.

**Files:**
- Modify: `src/ui/tray.zig`

**Implementation:**
1. Read `.desktop` entries from `/usr/share/applications` + `~/.local/share/applications`.
2. Cache names/icons.
3. Render scrollable grid.
4. Click launches via `wlr.xwayland` or `wlr.foreign-toplevel`.

**Verification:** Launcher opens, contains Ghostty, Browser, Files; clicking launches correct app.

---

## Phase 4 — Integration & Cleanup

### Task 4.1: Unify tray input for cards

**Objective:** Keyboard and pointer events route correctly whether the tray panel or a card is open.

**Files:**
- Modify: `src/ui/tray.zig`
- Modify: `src/input/keyboard.zig` or `src/input/cursor.zig`

**Rules:**
- If a card is open, pointer click outside closes it first.
- If tray is open and no card open, navigation moves through stack.
- `Escape` closes topmost card, then closes tray.

**Verification:** Manual interaction test in VM; no stuck cards.

---

### Task 4.2: Theme reload end-to-end

**Objective:** Changing `theme.toml` updates Zig tray, chrome, and GTK4 dashboard live.

**Verification:**
1. Edit `~/.config/kidulwm/theme.toml`.
2. Run `kidulwm-control reload_theme`.
3. Tray and dashboard both change within 2 seconds.

---

### Task 4.3: Performance budget

**Objective:** Cards must not cause frame drops.

**Metrics:**
- Clock tick: 1 Hz max.
- Calendar render: only on month/day change or focus retarget.
- Card surface cache: reuse if target size + focus state hasn't changed.
- Avoid re-reading `.desktop` every frame.

**Verification:** `wmstat` or manual visual smoothness; no visible stutter opening/closing cards.

---

## Wargame Notes (coderBob attention)

### Surface lifetime
`TrayCard` uses a `wlr.SceneBuffer` attached to `server.overlay_tree`. We must handle:
- Output disconnect → destroy buffer.
- Output scale change → recreate scaled surface.
- Focus window unmaps while card is open → fade out or retarget.

### Coordinate spaces
The focused window's `layout_target` is in **layout coordinates**. The tray operates in **output-local coordinates**. Convert via `Output` transform/position. Do not assume single-output.

### Multi-output
Card should appear on the output that currently hosts the focused window, not always `server.outputs.first`.

### wlroots scene order
Tray card must be parented in `server.overlay_tree` and raised above all windows. If it is not raised, the focused window's chrome can paint over it.

### Cairo surface cache key
Include in cache key: output scale, target width/height, corner radius, theme generation, content kind. Otherwise resizing the focused window reuses a stale buffer and the card stretches.

### Don't mutate labels
Keep existing tray rule: text labels are immutable once the item is created. Cards render their text from internal content state, not from `TrayItem.label`.

### Keep Bob/Barry idle
Opening/closing cards counts as tray movement; Bob and Barry can do their settle pulse. But window focus retarget alone should **not** trigger a Barry pose change.

---

## Suggested Build Order for coderBob

1. **Task 0.1 → 0.3:** Token audit and TOML parser integration.
2. **Task 0.4:** Tray colors from theme.
3. **Task 1.1 → 1.2:** Empty `TrayCard` over focused slide.
4. **Task 1.3:** Clock surface.
5. **Task 1.4:** Calendar surface.
6. **Task 1.5:** Unified open/close state machine.
7. **Deploy and review.**
8. Continue with notifications/toggles only after the base card is accepted.

---

## Open Questions

1. Do you want calendar to support mouse selection of a day, or read-only for now?
2. Should clock be analog, digital, or configurable via `theme.toml`?
3. Should notification center replace the existing security popups entirely, or run alongside them during a migration period?
