# RKT Dashboard — Left Panel Specification

This document records the current "good" left-panel state so future changes do not accidentally undo size, colour, or behaviour work.

---

## 1. Window placement

- **Layer-shell**: anchored `Top + Bottom + Left` on every monitor, layer `Bottom`, exclusive zone `-1`.
- **Horizontal centre rule**: the panel is centred in the gap between the left screen edge and Niri's focused 2/3 column.
  - `gap = monitor_width / 6`
  - `left_margin = (gap / 2) - (panel_width / 2)` (allowed to be negative; compositor clamps to 0 if the gap is too small)
- **Panel width**: `360 px` (from `rkt-dashboard.json` → `left_panel.width`).
- **Panel height**: full monitor height.

## 2. Top logo area (Catchy / CachyOS logo)

- **Widget**: `widgets::logo::build(...)`
- **Image asset**: `left_panel.logo_path` in `rkt-dashboard.json`; falls back to `assets/control-center-logo.png`
- **Click action**: toggles control center / launcher via `control_center_command` configured in `rkt-dashboard.json`
- **Hover**: dims image and shows "CONTROL / CENTER" text.
- **Sizing**:
  - `avail_width = left_panel.width - 24`
  - `small_size = max(base_small, min(max_small_by_width, base_small * 1.5))`
  - `catchy_h = min(small_size, base_catchy + 15) * 1.7`
- **Base values per monitor height** (`left.rs`):

| Monitor height | base_large | base_small | base_catchy | spacing | small_spacing |
|----------------|------------|------------|-------------|---------|---------------|
| < 1300         | 120        | 55         | 55          | 6       | 6             |
| 1300–1800      | 140        | 65         | 65          | 8       | 6             |
| ≥ 1800         | 160        | 75         | 80          | 10      | 8             |

The `1.7` multiplier is the current "170% bigger" logo size; changing it scales the logo up/down while preserving fit.

## 3. Middle large-dial pager

- **Dial widget**: `widgets::dial::build(...)`
- **Dial slot height**: `large_size + 16 (padding) + spacing`
- **Visible viewport**: exactly 3 large dials tall.
- **Large dial radius/ring scale**:
  - `r = min(cx, cy) * 0.82`
  - track alpha: `0.14` white
  - hover glow behind the ball: `0.22` of the dial's current colour

### 3.1 Dial value text (centre number)

- **Value size**: `(r * 0.44) * 0.6` for large dials
- **Colour**: `(0.94, 0.94, 0.94, 0.65)` — soft white, not full brightness

### 3.2 Dial label text (below the ring)

- **Label size**: `max(12, r * 0.22)` for large dials
- **Colour**: `(0.94, 0.94, 0.94, 0.55)` — even softer
- **Rendered in lowercase** via `.to_lowercase()`.

### 3.3 Colour gradient for value indication

`colour_for_pct` stops (RGB):

| pct  | colour               |
|------|----------------------|
| 0.00 | teal `(0.00,1.00,0.78)` |
| 0.09 | cyan `(0.00,0.94,1.00)` |
| 0.45 | purple `(0.64,0.35,1.00)` |
| 0.90 | burnt orange `(0.80,0.33,0.00)` |
| 0.95 | red `(1.00,0.10,0.10)` |
| 1.00 | red clamped          |

## 4. Bottom small-dial bar

- **Three dials**: BAT, BRT (interactive), VOL (interactive).
- **Size**: `small_size × small_size`
- **Layout**: `label_below = true`, so labels sit under the ring.
- **Value size**: `clamp(14, r * 0.58, 17)`
- **Label size**: `clamp(14, r * 0.62, 18)`
- **Interactive dials**: scroll wheel and click-and-drag adjust BRT/VOL via `pactl` / `brightnessctl`.

## 5. Drag-and-drop reordering

- Large dials can be reordered by dragging.
- Drop inserts **before** if dropped in the top half of a slot, **after** if in the bottom half.
- Active drop target is rendered transparent; only a cyan hover outline is drawn.
- Order is persisted to disk via `save_order` / `load_order`.

## 6. Colours / CSS reference

| CSS class / source | Value |
|---|---|
| `.rkt-panel` | `background: transparent` |
| `.rkt-dial` | `background: transparent; border-radius: 16px; padding: 8px 6px` |
| `.rkt-dial-label` | `rgba(255,255,255,0.55); font-size: 16px; font-weight: 700; letter-spacing: 0.04em` |
| `.rkt-dial.active .rkt-dial-label` | `rgba(0,240,255,0.95); text-shadow: 0 0 6px rgba(0,240,255,0.45)` |
| `.rkt-logo` | `background: transparent; border-radius: 16px; padding: 6px` |
| `.rkt-catchy` | `rgba(255,255,255,0.55); font-size: 13px; font-weight: 700; letter-spacing: 0.25em` |
| track ring (Cairo) | `rgba(1,1,1,0.14)` |
| dial value text (Cairo) | `rgba(0.94,0.94,0.94,0.65)` |
| dial label text (Cairo) | `rgba(0.94,0.94,0.94,0.55)` |

## 7. Files involved

- `src/panels/left.rs` — layout, sizes, dial ordering, logo placement
- `src/widgets/dial.rs` — dial rendering, text sizes/colours, interactions
- `src/widgets/logo.rs` — logo rendering and click/hover behaviour
- `src/main.rs` — layer-shell anchoring and left-margin calculation
- `src/style.css` — CSS classes listed above
- `rkt-dashboard.json` — `left_panel.width` (currently `360`)

## 8. Things to preserve when changing the future

- Keep the **soft white** text colours; do not return dial numbers/labels to full `rgba(1,1,1,0.95)`.
- Keep the **170% logo multiplier** unless the user explicitly asks for a different size.
- Keep the **gap-centre anchoring** formula for the left panel on multi-monitor setups.
- Preserve drag-and-drop reordering and the persisted order file.
- Preserve logo click → Noctalia control centre.
- Preserve small-dial scroll/click interactions for BRT and VOL.
