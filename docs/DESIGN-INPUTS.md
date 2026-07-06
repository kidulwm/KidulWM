# KidulWM Design Inputs

KidulWM is a from-scratch Wayland compositor and window manager written in **Zig**. GTK4 is used for the widget layer and animations. Niri is referenced **only as a UX baseline**, never as code to reuse.

## 1. Core Product Definition

KidulWM is a **Wayland tiling window manager / compositor** written in Zig with these defining behaviours:

- **Focused column** visually **perspective-raised** and dominant on screen.
- **Default layout** is `8%-94%-8%`: the focused column occupies **94%** of the output, while the left and right adjacent columns peek **8%** from each edge (these strips overlap the focused column's under/side plane).
- **Side columns recede** via opacity/scale/edge-fade.
- **Window gaps** are uniform between all visible tiles; gaps are a **must-have**.
- **Chamfered (cut) corners** on all window decorations; chamfer style is a **must-have** and user-configurable.
- **Hover does not change focus**; only intentional screen-edge gestures or a floating button navigate columns.
- **No traditional bar**; widgets live on the side of the focused column, alongside the **slide-out GTK4 settings tray**.
- **Keyboard bindings optional**.
- **Secure remote desktop is a first-class feature**, not an afterthought.

## 2. Platform Stack

| Layer | Technology | Notes |
|-------|------------|-------|
| Language | Zig | Manual memory management, C interop, compile-time code gen. |
| Wayland protocol | `zig-wayland` | Scanner + libwayland bindings. |
| Compositor backend | `wlroots` via `zig-wlroots` | DRM/KMS/libinput/renderer abstraction. KidulWM logic is Zig; wlroots is the hardware enablement layer. |
| Widgets/animations | GTK4 + layer-shell | Out-of-process panels anchored to the focused column. |
| IPC / config | Custom JSON/Unix socket + TOML | Separate from Wayland core. |
| Remote desktop | PipeWire + custom streaming protocol over WireGuard/TLS | See section 5. |

## 3. Architecture Inputs from info4Bob

### 3.1 Layout Defaults
- **Default screen split:** `8% / 94% / 8%` (peek/focus/peek).
- The focused column is **94%** of the output working area.
- Side columns peek at **8%** from each edge; focused column and side columns overlap in the 8% peek strips.
- These percentages are user-configurable per output or globally.

### 3.2 Chamfered Corners
- Each window decoration has a configurable chamfer style:
  - `classic` — traditional rounded rect.
  - `cut` — diagonal clip.
  - `none` — rectangular.
- Chamfer radius/cut depth is configurable per style.
- Default is `cut` with a fixed depth based on CSS-like design tokens.

### 3.3 Window Gaps
- Uniform gap between all visible window edges: vertical gap between columns, horizontal gap between windows in a column.
- Default **8 px logical** (rounded to physical pixels per output).
- User-configurable from the settings tray.

### 3.4 User-Configurable Colours
- Theme defined as design tokens: `electric_blue`, `royal_purple`, `turquoise`, `background`, `border`, `glow`, etc.
- Colours affect:
  - Window borders / focus ring.
  - Chamfer highlight/shadow.
  - Widget accents.
  - Settings tray chrome.

### 3.5 Settings Tray
- A slide-out GTK4 tray anchored to one side of the focused column.
- Provides controls for:
  - Layout split percentages and peek overlap.
  - Window gap size.
  - Chamfer style and depth.
  - Theme colours.
  - Remote desktop session status.
- Changes apply live preview.

### 3.6 Per-Output State Isolation
Each physical display (`wl_output`) keeps its own workspace matrix and window state. Moving a window between outputs:
1. Removes from source `OutputState`.
2. Recalculates layout on source.
3. Adds to target `OutputState`.
4. Recalculates layout on target.

### 3.7 Coordinate System Mapping
Tiling logic uses **relative coordinates** per output. The compositor translates to absolute pixel coordinates when committing surfaces. This is critical for multi-monitor with mixed scale factors.

### 3.8 Asynchronous Event Loop + Layout Workers
- Input and surface events become internal commands (`FocusChange`, `WindowMoved`, etc.) and are queued.
- Heavy layout recalculations run off the main thread to prevent jank.
- Rendering is vsync-aligned.

### 3.9 Layout Engine

Support at minimum:

- Single column / row.
- Grid (matrix).
- Master-stack.
- Kidul-specific **8%-94%-8%** focused-column layout.

### 3.10 Developer-Friendly Widgets
- Widgets are regular processes that speak a defined protocol over a Unix socket or Wayland protocol.
- Provide an SDK/QR-style quickstart:
  - `kidul-widget` Python/Go/Rust/Zig template.
  - JSON schema + capability manifest.
- Widgets declare:
  - Render surface size and anchor (left/right of focused column, floating, edge-gesture).
  - Events they emit (`MediaNext`, `VolumeUp`, etc.).
  - Data they want from the compositor (`focused_window`, `workspace_list`, `volume`, `brightness`).
- The compositor subscribes to widget events and routes them to configured actions.

### 3.11 Suggested Config Schema (TOML/JSON)

```toml
[layout]
split = [8, 94, 8]         # left-peek, focus, right-peek percentage
gap = 8                    # logical pixels
min_peek_px = 80           # guard for tiny outputs

[decoration]
corner_style = "cut"       # "cut" | "classic" | "none"
corner_depth = 18          # pixels for cut style; radius for classic
border_width = 2
border_color = "#1a2b3c"

[theme]
electric_blue = "#00f0ff"
royal_purple = "#a259ff"
turquoise = "#00ffc8"
background = "#0a0e17"
glow = "rgba(0, 240, 255, 0.18)"

[widgets]
anchors = ["right"]
settings_tray_anchor = "right"

[remote]
enabled = true
bind = "0.0.0.0:0"         # 0 means dynamic via WireGuard
require_fido2 = true
```

## 4. Widget, Animation & Settings Model

- GTK4 panels run as layer-shell clients under KidulWM.
- Panels anchor to the focused column using the compositor's layout metadata.
- **Settings tray** is a special anchored GTK4 panel with write access to theme/layout keys.
- Animations are authored in GTK4 where possible; the compositor only sends geometry/focus/theme updates.
- The widget protocol is JSON over a Unix socket (or Wayland sub-protocol later).
- Live theme/layout changes are pushed to all subscribed widgets so they re-render immediately.

## 5. Secure Remote Desktop

Remote desktop is central to the product vision: connect from a low-power laptop or tablet back to the home PC running KidulWM and Bob/AI.

### 5.1 Threat Model
- Network is untrusted.
- Client device may be lost, stolen, or shared.
- The host compositor must not expose other users' sessions.

### 5.2 Required Security Layers
1. **Transport:** WireGuard or TLS 1.3; no unencrypted pixel data.
2. **Authentication:** Public-key + WebAuthn/FIDO2 or TOTP; no passwords alone.
3. **Session containment:** Remote session runs in a separate seat/container; clipboard gated by explicit user consent.
4. **Least privilege:** Remote user can be restricted to a single workspace/output or view-only mode.
5. **Audit logging:** Login, disconnect, clipboard, file-transfer events logged.

### 5.3 Technical Path
- Capture: PipeWire `xdg-desktop-portal-wlr` or `wlr-screencopy` DMA-BUF.
- Encode: VA-API/h264 or AV1 if available; software fallback (`x264`).
- Stream: custom lightweight protocol with delta encoding; not RDP/VNC for v1.
- Client: GTK4 or native app on the tablet/laptop.

## 6. Niri as Reference Only

Niri informs the following UX, not the code:
- Focused-column-at-2/3 layout.
- Softened spring animations.
- Scrollable workspace feel.
- Per-output workspace scoping.

KidulWM's renderer, state machine, input handling, and remote-desktop subsystem are Zig/WLRoots, not Niri/Rust.

## 7. Open Questions

- Does wlroots' renderer expose enough transform hooks for perspective-raise, or do we need custom GLES shaders?
- GTK4 layer-shell clients under a custom compositor: do we need a custom layer-shell implementation or can we use `wlr-layer-shell-unstable-v1` directly?
- Integrate PipeWire portal inside the compositor or run it as a separate privileged helper?
- How are user secrets (keys, TOTP seeds) stored without tying the compositor to a specific desktop environment?

## 8. Suggested Documentation

- `docs/DESIGN-INPUTS.md` — this file.
- `docs/WARGAME-ARCH.md` — architecture trade-offs and decision record.
- `docs/WIDGET-PROTOCOL.md` — GTK4-compositor IPC spec.
- `docs/REMOTE-DESKTOP.md` — secure remote-desktop design.
