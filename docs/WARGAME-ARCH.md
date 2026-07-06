# KidulWM Architecture Wargame

This document explores the high-risk architectural decisions for KidulWM: a from-scratch Wayland compositor and window manager written in **Zig**, with **GTK4** for widgets/animations, and **secure remote desktop** as a first-class subsystem. Niri is referenced only as a source of UX inspiration.

## 1. Non-Negotiable Product Behaviors

From `docs/DESIGN-INPUTS.md`:

1. **Default layout `8%-94%-8%`**: focused column takes 94% of output; side columns peek 8% from each edge.
2. **Window gaps** are uniform and user-configurable.
3. **Chamfered/cut corners** on all window decorations; style/depth user-configurable.
4. **Side columns recede** via opacity/scale/edge-fade.
5. **Hover does not change focus**; navigation by screen-edge gesture or floating button.
6. **No traditional bar**; widgets and the slide-out GTK4 settings tray live beside the focused column.
7. **Keyboard bindings optional**.
8. **Remote desktop is central** for connecting low-power clients back to the home PC/Bob.

## 2. Strategic Options for the Compositor Core

The real question is not "which framework" but **how much of the low-level stack Zig owns**.

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A. Zig + wlroots | KidulWM logic in Zig on top of `zig-wlroots`/`wlroots`. | Proven: `river` does this. Hardware enablement, renderer, DRM, libinput handled. Fastest path to a bootable compositor. | Some abstraction leaks; tied to wlroots release cadence. |
| B. Zig + raw KMS/DRM/libinput | Custom Zig code for everything from GPU buffers up. | Maximum control; no dependency opinion. | 3-5× effort; must reimplement plane allocation, atomic commits, input quirk handling, VRR, HDR, etc. |
| C. Hybrid A→B | Start on wlroots, replace subsystems (renderer, allocator) incrementally. | Learn while shipping; can fork subsystems where wlroots blocks the UX. | Complex boundary maintenance. |

## 3. Recommendation

**Adopt Option A — Zig + wlroots — but structure the code so subsystems can be replaced later.**

Rationale:
- `wlroots` is a modular library of compositor building blocks, not a finished WM. KidulWM remains a from-scratch Zig window manager.
- `river` proves this exact combination is production-capable.
- The hard parts that are not KidulWM-specific (DRM leases, direct scanout, tablet/stylus, Xwayland) are solved problems in wlroots.
- Going fully raw would defer the actual KidulWM UX by years.
- The remote-desktop and GTK4 widget layers are orthogonal to the backend choice; wlroots gets us to those layers sooner.

## 4. Subsystem Breakdown

### 4.1 Driver / Core (Zig)
- **State machine** — `SystemState`, `OutputState`, `WorkspaceState`, `WindowSlotState`.
- **Event loop** — libwayland display dispatch, wlroots event loops.
- **Layout engine** — Zig; computes column/window geometry in logical coordinates.
- **Input dispatch** — keyboard, pointer, touch, tablet → internal commands.
- **Seat/session management** — logind/seatd integration via wlroots.

### 4.2 Rendering (wlroots + optional custom GLES)
- Use `wlr_scene` for basic composition.
- **Window gaps:** the layout engine subtracts gap spacing from each tile's target geometry before handing it to `wlr_scene`.
- **Chamfered corners:**
  - **Phase 1:** implement as a stencil/mask using `wlr_scene` geometry and an opaque surface (subsurface or shaped buffer). Acceptable proof-of-concept.
  - **Phase 2:** if gapless, anti-aliased, perfectly-rendered cut corners are required, switch to a custom GLES fragment shader in `wlr_render_pass` that clips the window texture to a rounded/chamfered SDF.
  - **Critical lesson from prior Niri chamfer attempts:** the SDF corner function must be shared by the **window-content clip**, **border**, and **shadow** shaders with the same geometric definition. If the border shader computes an inner corner using a different formula than the outer clip, the diagonal stroke becomes thinner or disappears. Compute the inner inset as a true parallel offset of the chamfer line, not as a smaller rounded radius.
- **Perspective-raise / side-column fade:**
  - Phase 1 via `wlr_scene` scale + opacity.
  - Phase 2 via custom pass if needed.
- Keep fractional-layout physical-pixel snapping identical to the info4Bob guidance.

### 4.3 WM Logic (Zig)
- **Column model** — each column contains 1+ windows. Focused column width default = 94% of working area; side columns peek at 8% from edges.
- **Layout targets** — produce target geometry per window; subtract gap spacing; apply chamfer metadata; interpolate changes via the animation system.
- **Layout config** — centre split, peek widths, gap size, and minimum visible side-column amounts live in `Config` and are mutable from the settings tray.
- **Focus policy** — pointer crossing is ignored for focus; only explicit navigation commands change focus.

### 4.4 Settings Tray (GTK4)
- Slide-out panel anchored to the focused column.
- Reads/writes `KIDULWM_CONFIG_DIR` TOML/JSON live.
- Sections:
  - **Layout:** sliders for peek widths and focused-column percentage; gap spinner.
  - **Corners:** radio for `cut`/`classic`/`none`; depth/radius spinner.
  - **Theme:** colour pickers mapped to design tokens.
  - **Remote:** session toggle, one-time-code display, audit log.
- Settings apply immediately with live preview; no restart required.
### 4.5 Input (Zig + wlroots)
- Edge gestures captured as small hot zones (configurable px width).
- Floating button is a top/left layer-shell window that sends a `FocusNext`/`FocusPrev` command over the local socket.
- Keyboard bindings optional and driven by config.

### 4.6 Widget Layer (GTK4 + layer-shell)
- Separate process(es) using GTK4 and `gtk4-layer-shell` (via `wlr-layer-shell-unstable-v1`).
- Compositor tells each panel:
  - which output it belongs to,
  - the current focused-column geometry,
  - workspace state, volume, brightness, theme tokens, etc.
- Widgets render their own animations; the compositor only updates the data model.
- **Developer-friendly SDK:**
  - `examples/widgets/` with templates in Python, Zig, and Rust.
  - Widget manifest schema in JSON.
  - Pub/sub to compositor topics.
  - Event emission (e.g. `VolumeUp`, `WorkspaceSwitch`) routed through the compositor action system.

### 4.7 Remote Desktop (Zig core + PipeWire + custom streamer)
A dedicated subsystem, not a plugin:

- **Capture:** `xdg-desktop-portal-wlr` DMA-BUF frames, or direct `wlr-screencopy`.
- **Encode:** hardware-accelerated h264/AV1 via VA-API; software fallback.
- **Stream:** UDP+DTLS or QUIC-based protocol with delta/damage updates and forward-error correction.
- **Control:** commands sent back over the encrypted control channel.
- **Auth:** keypair enrollment, TOTP/FIDO2, per-session capability grants.
- **Containment:** remote session gets its own `wl_seat` and clipboard gates; can be denied file access entirely.

## 5. Key Wargame Scenarios

### 5.1 Can wlroots deliver the KidulWM visual signature?
- **Question:** Gaps, cut corners, focused 94% column, side-column fade, perspective-raise.
- **Verdict:** Gaps + column transforms are straightforward with `wlr_scene`. Perfect chamfers require a custom GLES SDF shader; wlroots allows this via `wlr_render_pass`. Not a blocker, but Phase 2 is necessary for the "perfectly rendered" requirement.

### 5.2 Is the `8%-94%-8%` layout stable across multi-monitor?
- **Question:** Mixed scale factors and output sizes may cause the 8% peek to become too small or too large.
- **Verdict:** Store split as percentages but enforce a **minimum peek pixel size** and a **maximum focused-column width**. User override per output.

### 5.3 Settings tray live-update complexity
- **Question:** Changing layout/colours/corners without restart from a GTK4 client.
- **Verdict:** Tray writes config buffer; compositor inotify/reloads or accepts IPC `ConfigUpdate`. Both are well-trodden. GTK4 side gets live preview immediately; compositor applies on next layout tick.

### 5.2 Does separating widgets into GTK4 layer-shell clients hurt performance?
- **Question:** Extra process + two Wayland clients + synchronization.
- **Verdict:** Acceptable for v0.x. The rkt-dashboard prototype already does this. If latency becomes visible, merge widgets into the compositor scene later.

### 5.3 Remote desktop latency on a LAN vs. internet
- **Question:** Can a tablet feel responsive when streaming from the home PC?
- **Verdict:** LAN can be excellent with hardware encode/decode. Internet needs adaptive bitrate, predictive cursor, and optional fallback to still-frame + region-of-interest updates.

### 5.4 Security of remote-first design
- **Question:** Does making remote desktop central increase attack surface?
- **Verdict:** Yes, but it is addressable with network-level WireGuard, strong auth, session containment, and audit logging. The benefit (AI at home, thin client elsewhere) justifies the effort.

## 6. Decision Record

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Compositor/WM in Zig from scratch | Product vision and language choice. |
| 2 | wlroots as backend layer | Proven path; gets us to KidulWM-specific code quickly. |
| 3 | GTK4 layer-shell panels for widgets | Reuses rkt-dashboard work; decouples widget iteration from compositor stability. |
| 4 | Niri reference for UX only | No Niri code dependencies; KidulWM layout/input logic is Zig. |
| 5 | Remote desktop as core subsystem | Drives auth, containment, and capture design from day one. |
| 6 | Phase 1 rendering via `wlr_scene`; custom shaders for gaps/chamfers/perspective | Reduces initial risk; accepts custom pass where required. |
| 7 | Chamfered corners via custom GLES SDF shader | Required for gapless, anti-aliased "perfect" cut corners. |
| 8 | Settings tray live-update, no restart | Users expect instant feedback when dragging sliders. |
| 9 | Widget SDK in `examples/widgets/` | Makes third-party and internal widget iteration fast. |

## 7. Milestones

1. **Boot proof (4-8 weeks):** Zig process that starts from TTY, opens a DRM output, displays a solid color.
2. **Surface proof (4-8 weeks):** Display one `wl_shell`/`xdg_shell` client, map pointer/keyboard.
3. **Layout proof (4-6 weeks):** Implement 8%-94%-8% default split + gaps + side-column fade.
4. **Chamfer proof (2-4 weeks):** Perfectly rendered cut-corner SDF shader.
5. **Input proof (2-4 weeks):** Edge zones + GTK4 floating button navigate focus.
6. **Settings tray proof (2-4 weeks):** GTK4 slide-out tray changes layout/gaps/colours/corners live.
7. **Widget proof (4-6 weeks):** GTK4 panel anchors to focused column; dev SDK example runs.
8. **Remote proof (8-12 weeks):** PipeWire capture → encode → encrypted stream → view on another device.
9. **Daily-driver alpha:** Replace Niri on one machine for one user workflow.

## 8. Open Risks

- wlroots API churn; need to pin a version.
- `zig-wlroots` and `zig-wayland` Zig version compatibility.
- GTK4 layer-shell under a custom compositor may need debugging.
- Perspective transform / SDF chamfer shader may require more renderer control than expected.
- Remote-desktop auth is security-critical and must be designed with privilege separation.

## 9. Files

- `docs/DESIGN-INPUTS.md` — requirements.
- `docs/WARGAME-ARCH.md` — this architecture/wargame document.
- `docs/WIDGET-PROTOCOL.md` — to be drafted.
- `docs/REMOTE-DESKTOP.md` — to be drafted.
