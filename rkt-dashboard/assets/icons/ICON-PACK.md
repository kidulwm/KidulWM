# RKT Dashboard SVG Icon Pack

A cohesive, Cairo/GTK4-ready SVG icon set for **rkt-dashboard**.
Theme: *Ratu Kidul + Atlantis* — futuristic, professional, classy, with a soft
royal purple / royal blue / turquoise palette. Burnt-orange is reserved for
warnings and the sun.

---

## Color Palette

All icons use only these colours. Values are sampled from the reference
RKT / Bob / Trident logos.

| Token            | Hex     | Usage                                             |
|------------------|---------|---------------------------------------------------|
| Royal Purple     | `#7C3AED` | Primary accent, Bob hat band, security, dashboard tiles |
| Royal Blue       | `#2563EB` | Secondary accent, clouds, shields, lock bodies    |
| Turquoise        | `#06B6D4` | Highlights, rain, play buttons, search glass, coder symbols |
| Soft Lavender    | `#A78BFA` | Muted fills, fog, snow clouds, user avatar        |
| Deep Indigo      | `#1E1B4B` | Thunder clouds, dark contrast details             |
| Ice              | `#E0F2FE` | Snow flakes, subtle highlights                    |
| Pearl White      | `#F1F5F9` | Bob faces, lock keyhole, menu strokes             |
| Pure White       | `#F8FAFC` | Hat crowns, logo centre, crisp accents            |
| Ink              | `#0F172A` | Glasses, outlines, smile lines                    |
| Burnt Orange     | `#F97316` | Warnings only — sun, lightning, artist palette, admin wrench, close X |

---

## Naming Scheme

```
rkt-icon-<category>-<name>[-<modifier>].svg
```

Examples:

- `rkt-icon-weather-sunny.svg`
- `rkt-icon-bob.svg`
- `rkt-icon-security-bob.svg`
- `rkt-icon-coder-bob.svg`

The root folder contains the canonical **24×24** version. Per-size renders live
under `24/`, `32/`, `48/`, `64/`.

---

## Directory Layout

```
assets/icons/
├── ICON-PACK.md              <- this file
├── 24/                       <- 24×24 renderings
├── 32/                       <- 32×32 renderings
├── 48/                       <- 48×48 renderings
├── 64/                       <- 64×64 renderings
└── rkt-icon-*.svg            <- canonical 24×24 source files
```

All SVGs share the same `viewBox="0 0 24 24"`; only the `width`/`height`
attributes change per size.

---

## Rendering Rules

1. **Vector only** — every icon is built from `<path>`, `<circle>`, `<rect>`,
   `<line>`, `<polyline>`, and `<ellipse>`. No bitmaps, no gradients, no
   filters, no external references.
2. **No fonts or emoji** — all glyphs are drawn as geometry.
3. **Transparent background** — icons assume a dark GTK surface; colours are
   chosen for contrast on deep navy/indigo dashboards.
4. **Cairo/GTK4 safe** — SVG 1.1 markup, inline `fill`/`stroke`, no CSS custom
   properties in rendered attributes.
5. **Minimal paths** — icons are intentionally flat and simple so they remain
   crisp at 24×24.
6. **Orange = warning / solar** — do not use `#F97316` for primary actions.

---

## Icon Index

### Weather

| File                          | Description                 |
|-------------------------------|-----------------------------|
| `rkt-icon-weather-sunny.svg`          | Sun with rays               |
| `rkt-icon-weather-cloudy.svg`         | Single cloud                |
| `rkt-icon-weather-partly-cloudy.svg`  | Sun behind cloud            |
| `rkt-icon-weather-rain.svg`           | Cloud with rain streaks     |
| `rkt-icon-weather-thunderstorm.svg`   | Dark cloud + lightning bolt |
| `rkt-icon-weather-snow.svg`           | Cloud + snowflakes          |
| `rkt-icon-weather-fog.svg`            | Three wavy fog lines        |

### Bob / Agent Variants

| File                          | Description                         |
|-------------------------------|-------------------------------------|
| `rkt-icon-bob.svg`            | Main white-hat hacker Bob           |
| `rkt-icon-security-bob.svg`   | Bob inside a shield                 |
| `rkt-icon-media-bob.svg`      | Bob + play button                   |
| `rkt-icon-artist-bob.svg`     | Bob + paint palette & brush         |
| `rkt-icon-coder-bob.svg`      | Bob + code brackets                 |
| `rkt-icon-admin-bob.svg`      | Bob + wrench                        |
| `rkt-icon-search-bob.svg`     | Bob + magnifying glass              |
| `rkt-icon-chat-bob.svg`       | Bob + speech bubble                 |
| `rkt-icon-cloud-bob.svg`      | Bob + cloud                         |

### Application

| File                          | Description                 |
|-------------------------------|-----------------------------|
| `rkt-icon-logo.svg`           | Stylised trident / RKT mark |
| `rkt-icon-dashboard.svg`      | 2×2 dashboard grid          |
| `rkt-icon-settings.svg`       | Gear with turquoise centre  |
| `rkt-icon-lock.svg`           | Closed padlock              |
| `rkt-icon-menu.svg`           | Hamburger menu              |
| `rkt-icon-close.svg`          | Warning-orange X            |
| `rkt-icon-user.svg`           | Generic user silhouette     |

---

## Recommended GTK4 / Cairo Usage

```c
// Load a size from the theme folder
gtk_image_set_from_file(GTK_IMAGE(icon),
    "assets/icons/48/rkt-icon-bob.svg");

// Or let Cairo scale the 24px canonical version
cairo_surface_t *s = cairo_image_surface_create_from_png(...);
```

For crisp results use the exact-size folder that matches the widget allocation.
Keep the aspect ratio locked (`GTK_ASPECT_FIT`) and prefer a dark background.

---

## Regenerating the Pack

The authoritative generator is `scripts/generate_icons.py`. It draws every icon
on the 24×24 grid and emits the four size folders plus root copies. Run it with
a Python interpreter that has the standard library only (no third-party
packages required).
