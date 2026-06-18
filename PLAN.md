# KidulWM Development Plan

## 1. Renderer/Layout Evaluation

**Goal:** Determine whether Niri can serve as the base for KidulWM.

- Lock focused column width to exactly 2/3 of the output.
- Implement or prototype perspective-raise on the focused column.
- Implement edge-fade / opacity/scale falloff on side columns.
- Verify performance and animation integration.

## 2. Interaction Model

- Remove Niri's hover-to-focus behavior.
- Map "touch the edge of the screen" to column navigation (left/right).
- Add a small floating button for pointer-based navigation.
- Keep keyboard bindings optional but available.

## 3. Widget System

- Remove the traditional bar.
- Render widgets on the side of the focused column (clock, workspace state, volume, etc.).
- Define a widget IPC/protocol (capabilities TBD).

## 4. Upstream Story

- Start as a Niri fork with clean, upstreamable patches.
- Track Niri releases and minimize divergence.
- Long-term: either maintain afocused fork or upstream the desired effects as configurable options.

## Decisions

- **Language:** Rust (same as Niri).
- **Wayland compositor base:** Niri, pending renderer feasibility.
- **Fallback:** Smithay or wlroots if Niri's renderer is unsuitable.
