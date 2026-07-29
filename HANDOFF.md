# KidulWM Handoff

Updated 2026-07-29 (end of session). Source of truth for resuming.

## Current state

| Item | Value |
|------|-------|
| Branch | `CachyOS-Candy` (worktree has local changes) |
| Work VM | `fresh-one` (kidul@127.0.0.1:2260) |
| Service log | `/tmp/kidulwm-service.log` |
| Deployed WM binary | `/usr/bin/kidulwm` |
| Shorthands | `Bob` = top-left tray logo ; `Barry` = bottom-left pet |

## What this session changed

### 1. Curtain overlay feature (active work)
- Added `src/render/curtain.zig` with `OutputCurtains` / `Panel` structures.
- Wired into `src/server.zig`: import, `Output.curtains` field, create/destroy/update calls in `handleNewOutput`, `Output.init`, `Output.deinit`, and `applyLayout`.
- Rendered below widgets/tray so widgets stay fully visible.
- Current implementation draws full-height side panels with black velvet folds and a border-color rope tie-back + small tassel.
- Temporary crash guard added in `handleNewToplevelDecoration` to skip `setMode(.server_side)` for uninitialized xdg surfaces; this kept the compositor alive during testing.

### 2. kidul-browser integration remains benched
- kidul-browser is on hold per user direction.
- Browser files unchanged this session.

## Critical design decisions locked in

- Curtains are **permanent tied-back** unless a peek exists on that side; when a peek exists the panel drops to full output height.
- No animations in this phase — static proof first.
- Colors: black velvet fabric (`tray_bg_color`), rope/tassel in user's mood/border color (`color_border_focused` / `color_border`).
- Rope must be the **thinnest** point of the curtain; fabric bulges outward above and below it.
- Rope sits ~1/5 from the top of the screen, just under top widgets and above future gauges.
- Curtain inner edge must stay ~5 px outside the focused slide so it never covers the main slide.

## Visual references on disk

| File | Meaning |
|------|---------|
| `/tmp/curtains8.png` | User screenshot: how the tied-back curtain currently looks (wrong) |
| `/tmp/curtains9.png` | User screenshot: **target shape** for the tied-back curtain (pixel-level copy target) |
| `/tmp/curtains4.png` | Additional reference: black stage curtain tied back with gold rope/tassel |
| `/tmp/curtains5.png` | Additional reference: tall gathered curtain with tie near bottom |
| `/tmp/curtains6.png` | Additional reference: red velvet tied-back with small tassels |

Use `/tmp/curtains9.png` as the primary silhouette target.

## Next session work

1. **Copy `/tmp/curtains9.png` silhouette pixel-for-pixel** into `src/render/curtain.zig` as the tied-back left panel, then mirror for the right panel.
2. Apply the design rules above (thinnest at rope, bulge above/below, 5 px gap from focused slide, rope at 1/5 top, black velvet, border-color rope).
3. Build/deploy/screenshot until the static tied-back shape is approved.
4. Then implement the **dropped** curtain state: mostly straight vertical folds all the way to the bottom, still 5 px outside the slide.
5. Verify peek-trigger transitions and remove/replace the temporary `handleNewToplevelDecoration` guard.

## Files changed (uncommitted)

- `src/render/curtain.zig` — curtain renderer.
- `src/server.zig` — curtain import, `Output.curtains` field, init/deinit/update wiring, temporary decoration guard.

## How to resume

```bash
cd /home/dad/dev/KidulWM
zig build
scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm \
  zig-out/bin/kidulwm \
  zig-out/bin/kidulwm-control \
  kidul@127.0.0.1:/tmp/
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1
sudo systemctl stop kidulwm
sudo cp /tmp/kidulwm /tmp/kidulwm-control /usr/bin/
sudo systemctl start kidulwm
```

Verify service is active, then capture screenshot and compare to `/tmp/curtains9.png`.
