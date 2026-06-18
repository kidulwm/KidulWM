# Kidul Window Manager (KidulWM)

A 3D-raised, edge-aware column window manager for Wayland.

KidulWM starts from the layout ergonomics of [Niri](https://github.com/YaLTeR/niri) — focused window at 2/3 width, side columns receding into the background — but replaces hover-to-focus and the status bar with intentional edge gestures and integrated side widgets.

## Goals

- **Prominent focused column** — centered, 2/3 width, perspective-raised, with softened spring animations.
- **Receding side columns** — lower opacity / scale / fade toward the screen edges.
- **No accidental focus changes** — hover over a side column does *not* move focus.
- **Two ways to navigate** — touch the screen edge or click a small floating button.
- **No bar** — widgets live on the side of the focused column, rendered cleanly in the compositor.
- **Open source** — Rust-based, built on or alongside Niri, with upstream contributions in mind.

## Status

Currently in architecture & renderer feasibility phase. We are evaluating whether Niri's renderer can support the perspective-raise + edge-fade effects without a full rewrite.

## Repository

- Issues: https://github.com/kidulwm/KidulWM/issues
- Discussions: https://github.com/kidulwm/KidulWM/discussions

## License

MIT — see [LICENSE](LICENSE).
