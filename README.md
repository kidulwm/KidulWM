# Kidul Window Manager (KidulWM)

A cinematic black-gold Wayland compositor with sliding column layouts, edge gestures, and integrated on-screen widgets.

KidulWM takes the layout *ergonomics* of [Niri](https://github.com/YaLTeR/niri) — prominent focused column, receding side columns — but is implemented as its own compositor, not as a Niri fork or patch. Hover-to-focus is replaced by intentional edge gestures, and the status bar is replaced by a unified notification stream and side widgets rendered inside the compositor.

## Implementation

- **Compositor core:** [Zig](https://ziglang.org/) on [wlroots](https://gitlab.freedesktop.org/wlroots/wlroots) 0.20.
- **Dashboard reference:** `rkt-dashboard/` contains a local Rust/GTK4 prototype used purely for visual reference; it is not part of the shipped KidulWM system.

## Goals

- **Prominent focused column** — centered, 2/3 width, perspective-raised, with softened spring animations.
- **Receding side columns** — lower opacity / scale / fade toward the screen edges.
- **No accidental focus changes** — hover over a side column does *not* move focus.
- **Edge-driven navigation** — touch the screen edge or use the floating navigator.
- **No traditional bar** — widgets, notifications ("Snippets"), and system status live in the compositor chrome.
- **Solid, Safe & Secure** — no secrets or private material committed; credential handling stays outside the repo.

KidulWM is created by [Barticus & Bob](AUTHORS).

## Repository

Primary home:
- Issues / Discussions / Code: https://codeberg.org/kidulwm/KidulWM

Archive:
- https://github.com/kidulwm/KidulWM

## License

MIT — see [LICENSE](LICENSE).
