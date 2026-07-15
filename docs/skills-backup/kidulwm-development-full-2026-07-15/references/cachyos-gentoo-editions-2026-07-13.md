# CachyOS vs Gentoo KidulWM editions (2026-07-13)

Decision: keep the CachyOS build practical and easy to install; move the experimental chamfer/premium features to a future Gentoo build.

Current state
- CachyOS branch defaults to `.classic` rounded corners and removes the `.cut` chamfer code.
- Chamfer state archived in branch `archive/chamfer-cachyos` and tag `chamfer-final-cachyos`.
- Commit that removed chamfer from CachyOS: `5ec6836 cachyos: switch to .classic rounded corners; archive chamfer code for Gentoo`.

Files removed from CachyOS
- `src/core/chamfer.zig`
- `src/render/chamfer.zig`
- `.cut` case from `CornerStyle` in `src/core/style.zig`
- `chamfer_border_width` field from `Style`
- Chamfer-specific geometry logic in `src/render/chrome.zig`
- Chamfer IPC branch in `src/server.zig`

How to bring chamfer back (Gentoo)
- Start from `archive/chamfer-cachyos` or `chamfer-final-cachyos`.
- Apply a wlroots patch for true 45-degree clip if needed (see `wlroots-chamfer-clip-wargame-2026-07-13.md`).
- Maintain a Gentoo overlay with patched `wlroots` and Kidul tools.

Portability note
- What is built for CachyOS transfers cleanly to Gentoo as long as the code stays portable (no distro-specific paths or assumptions). The split is purely policy; the source remains the same where possible.
