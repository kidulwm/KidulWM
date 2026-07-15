---
name: kidulwm-development
description: Recurring workflow, design rules, and debugging discipline for developing the KidulWM Wayland compositor.
category: software-development
---

# KidulWM development

Project repo: `/home/dad/dev/KidulWM`. Read `HANDOFF.md` each session for current branch and stable commit.

## Trigger policy

`>>>CoderBob<<<`, `coderBob`, or `Fable 5` invokes the coderBob-Fable 5 specialist for Zig/wlroots protocol/ABI/performance blockers.

## First move each session

- Re-read `/home/dad/dev/KidulWM/HANDOFF.md`.
- Re-read `/home/dad/dev/KidulWM/KNOWN_CMDS.md`.

## Design rules

- Window matrix performance first; no window tabbing.
- Default compositor background `#222425`.
- Tokens live in `src/core/style.zig`.
- **Internal trays for remote-desktop friendly shells.** Mission-critical shell UI (settings tray, app launcher, volume/brightness, system status, animation chooser) is a compositor-internal Zig surface (`src/ui/tray.zig`) so it travels as state+damage, not as a separate Wayland surface. GTK4/rkt-dashboard dials, weather, news, and media stay local-only on the host. Details and current API: `references/internal-tray-and-remote-desktop-2026-07-13.md`.
- **Horizontal gold-on-glass dock geometry.** A bottom-left panel can reach from the left output edge to the focused slide's left edge, buttons rendered in gold text on black glass, with hover previews that extend over the main slide. Keep it on a dedicated overlay scene tree so it never pushes SlideDeck peeks. See `references/tray-horizontal-gold-overlay-2026-07-14.md`.
- **Settings-stack tray.** A bottom-anchored settings menu inside the left-peek panel: a single "Settings" button in black glass with gold text sits near the bottom, just inside the right border. Hover or click expands a vertical stack of buttons above it; each button spans the left-peek width up to the focused slide. Stack height is clamped to about five items in the lower third of the peek, and excess items scroll. The background is transparent so only buttons show. Keep the tray on the overlay scene tree and anchor it to the output bottom so it expands upward. See `references/tray-settings-stack-2026-07-14.md`.
- FHS paths: `/usr/bin/kidulwm`, `/etc/kidulwm/`, `/usr/share/kidulwm/`, `~/.config/kidulwm/`.
- **User-editable keybindings live in one file.** `~/.config/kidulwm/keybinds.conf` drives all compositor shortcuts; if it is missing or has a bad line, KidulWM falls back to compiled-in defaults and logs why. The repo ships a default at `config/keybinds.conf` and `build.zig` installs it to `/usr/share/kidulwm/keybinds.conf`. Details and action list: `references/keybinds-config-2026-07-13.md`.
- **Compositor-owned chrome** is now available in addition to client-side decoration. When KidulWM must own the corner shape across apps or output scales, render a Cairo ARGB32 overlay into a custom CPU `wlr.Buffer` and attach it as a `wlr.SceneBuffer`.
- If the overlay is inside the per-window `scene_tree`/`surface_tree` and the client still paints its own CSD frame/shadows on top, the compositor border/color changes become invisible. Move the chrome node into the **server `overlay_tree`** and raise it with `tree.node.raiseToTop()` so it floats above the window scene tree; position it at the window's world coordinates each frame. Placing it directly under the root `server.scene.tree` can leave it below a raised focused window depending on creation order, so prefer `overlay_tree`. Update its position in both `Window.setLayoutTarget()` (snap) and `Window.tickAnimation()` (transition) so it tracks window movement. See `references/chrome-overlay-global-tree-2026-07-15.md` and `references/peek-glass-final-recipe-2026-07-15.md`.
- **CachyOS vs Gentoo editions.** The CachyOS build ships a practical, rounded-corner KidulWM with `corner_style = .classic` and no chamfer code. The `.cut` chamfer implementation is archived at branch `archive/chamfer-cachyos` and tag `chamfer-final-cachyos` for a future Gentoo premium build. Any wlroots patch for true 45-degree chamfer clipping belongs to that Gentoo edition, not the CachyOS branch. Details and archive pointers: `references/cachyos-gentoo-editions-2026-07-13.md`; technical wargame: `references/wlroots-chamfer-clip-wargame-2026-07-13.md`. If you need to revive the archived branch for a quick experiment, it may fail to build because the current `zig-wlroots` bindings lack `Renderer.createPixman()`; see `references/chamfer-archive-build-pitfall-2026-07-13.md`.

- Authoritative chrome geometry lives in the repo at `/home/dad/dev/KidulWM/references/chrome-geometry.md`. Read it before changing `.classic`/`.none`/`border_width`/`corner_depth`.
- A new XDG client surface should not be visible until it has committed a real buffer. Hiding the `surface_tree` node at creation/map and revealing it on the first non-zero commit can work, but only if the surface still receives a valid `setSize()` configure while hidden; otherwise the client may commit a tiny/zero buffer and remain blank. The safer default is to keep the surface node enabled, let the client commit its natural buffer, and cover any transient gap with a full-target `wlr.SceneRect` behind the surface. See `references/surface-reveal-on-commit.md`.
- Chrome for SlideDeck side peeks must be a **full-window overlay**. Do not render only the visible sliver or pass a screen-space visible rect to `Window.updateChrome`; that moves the hidden seam edge into view and clips the top/bottom borders.
- **Keep peek surfaces at their natural size; offset, don't scale.** Side peeks should not call `setSurfaceDestSize()` or `toplevel.setSize()` for the peek slot. Create a wrapper scene tree for the full window bounds, attach the XDG surface as a child, and offset the child so the visible sliver shows the correct edge. Details: `references/peek-surface-geometry.md`.
- Fill the slide bounds behind the surface with `theme.color_background`. Client content (and CSD shadows/padding) often leaves a gap between the inner border edge and the actual surface. A `wlr.SceneRect` covering the full layout target works for square-cornered styles, but **a square background rect leaks grey through the transparent interior of a rounded chrome overlay** when `.corner_style` is `.classic`. For `.classic` either drop the per-window `bg_rect` and let the chrome overlay's outer shape do the fill, or render a rounded background mask. Removing the per-window `bg_rect` also enables client-requested transparency because there is no longer an opaque grey layer behind the client surface. See `references/chrome-bg-rect-leak-2026-07-13.md`. **Do not scale or distort the focused client surface to fit the target; offset it by the client geometry and let the background fill plus compositor chrome cover the rest.** Details: `references/peek-surface-geometry.md`.
- **Clean up per-window `wlr.SceneRect`/chrome/dim nodes on unmap.** A `chrome_tree` or `dim_rect` that outlives the client surface leaves a visible slide-shaped ghost after the window closes. In `handleUnmap`, destroy `chrome_tree` and `dim_rect` nodes and null their fields. Re-create them lazily on the next `updateChrome`/`updateDim`. Do not rely on a single permanent wrapper node to cover this; if the wrapper is disabled on unmap it will also be disabled on the next map and the new window will never appear.
- When drawing the `.cut` frame, the inner polygon is a **parallel offset** of the outer chamfer polygon: straight edges move inward by `border_width`, each 45° diagonal moves inward by `chamfer_border_width`, and adjacent offset edges intersect to form the inner polygon. Do not pre-shrink the inner chamfer depth with constants such as `(border + chamfer_border) * 0.5`; that produces a too-thin border.
- **Mask outer covers full window bounds; ring outer is edge-aware.** For side peeks the mask uses `squareRect(0,0,w,h)` so it covers the entire off-screen window bounds and hides client rounded corners / shadows. The border ring still uses `chamferRect(..., depths)`. Since the overlay is full-window, the hidden-edge clear strips fall off-screen and do not clip visible borders. Using a chamfered mask outer would expose client rounded corners in the triangles cut off by the chamfer.
- **Mask inner must follow the content shape, not the border inner edge.** For `.cut` (chamfer) the content area is a rectangle inset by `border_width`; the chamfer triangles between that rectangle and the chamfered border ring must be filled with `theme.color_background` so the client background never bleeds through the cut corners. For `.classic` the mask inner is a rounded rectangle; for `.none` it is a plain rectangle. The border ring's inner polygon remains a parallel offset of the outer chamfered/rounded path so the frame thickness stays uniform. See `references/chrome-mask-content-rectangle.md`.
- Corners must be **shaped from `EdgeMode`**, not only by trimming edge strips. A corner is chamfered only if both adjacent edges are visible; otherwise it is square so the visible straight edges meet the hidden edge cleanly. `right_peek` hides its right edge, so top-right/bottom-right are square while the seam-side corners stay chamfered.
- Hidden edges are cleared with `CAIRO_OPERATOR_DEST_OUT` after filling the ring. This only removes border in the off-screen portion of a full-window overlay; never add gap-fill redraws to compensate for a too-small visible-sliver buffer.
- **`kidulwm-control` must also parse `set_theme`** for runtime theme changes. The server-side handler alone is not enough; an unparsable CLI command returns `UnknownCommand` even though the server would have accepted the update.
- SlideDeck side peeks should show the border edge that **abuts the focused window** and hide the edge that points off-screen (`left_peek` shows its right edge; `right_peek` shows its left edge), framing the focus with borders on both sides.
- **Peek slides get a black-glass overlay + gold program label.** The overlay must read as **more black than any other color by a long shot**: near-black body at ~0.92–0.97 alpha for top/bottom strips that make labels and the settings button legible, and a more translucent middle (~0.45–0.60 alpha) so the slide content still shows. Only a thin inner rim glow and a thin gold inner-seam glow sell the glass material. The overlay covers the **background only** and is clipped to the **inner content shape** (rounded rect inset by `border_width`). It is drawn **before** the original border ring so the border remains untouched. Do **not** extend the glass into the border area, recolour the border, or change `border_width`, `corner_style`, or `corner_depth`. If the border disappears or reads grey, revert `src/render/chrome.zig` to the last known-good commit and re-apply the overlay-only change cleanly, keeping the glass inside the content shape.
- For the exact draw order, alpha tokens, and "do not" list, see `references/peek-glass-black-recipe.md`.
- For a worked example of what happens when the wrong source tree is modified, see `references/vm-source-mismatch-bob-is-a-douche-2026-07-15.md`.
- **When a VM has its own source tree, patch and build inside the VM.** The `bob-is-a-douche` VM runs `/home/kidul/KidulWM`, not the host repo. Deploying a host-built binary from a different branch drops VM-only code such as `TrayManager` / `SettingsTray` and can crash on boot. Copying a host binary is only safe when the host commit and the VM binary are provably the same source snapshot.
- **If there is no active compositor border/corner geometry, a shape-matched glass overlay is impossible without inventing one first.** In `bob-is-a-douche`, video output is a scene graph of plain rectangles and XDG surfaces; the shader stub is not compiled or attached. Nibbling rectangular glass into pixels is the safe first pass and can be refined interactively with the user.
- For how the 2026-07-15 decision was made (and why the rectangular approach was chosen), see `references/black-glass-vm-source-decision-2026-07-15.md`.
- For the glass look principles and generic Cairo patterns, see `references/glass-look` (the KidulWM recipe supersedes those numbers for peek windows).
- **Title-bar toggle.** `src/core/style.zig` has `show_title_bars`; `src/server.zig` already negotiates `xdg-decoration_manager_v1` SSD/client mode per that flag; runtime changes are accepted via `kidulwm-control set_theme show_title_bars true/false`. Existing windows keep their negotiated style; only new windows pick up the new mode. This is the safe, non-breaking behaviour.
  - The toggle also needs to control the toolkit environment for child apps. When `show_title_bars = false`, KidulWM should export `GTK_CSD=0`, `GDK_DEBUG=no-csd`, and `QT_WAYLAND_DISABLE_WINDOWDECORATION=1` in the compositor environment so apps launched from the compositor inherit them. When toggled on, unset those variables.
  - **GTK4 / libadwaita often ignore both `xdg-decoration` SSD and `GTK_CSD=0`**. If title bars and client-rounded frames remain visible, the thing on screen is CSD, not the compositor chrome. Env vars alone are not sufficient for GTK4/libadwaita; add user-level GTK CSS overrides or configure each toolkit explicitly. See `references/title-bar-toggle-and-csd-pitfall-2026-07-15.md`.
  - **Diagnostic:** if changing the compositor chrome's `corner_style`, `border_width`, or border color produces no visible change, the visible frame is almost certainly client CSD. Temporarily set the compositor border to a bright color; if it still does not appear, the overlay is on the wrong scene layer. Move it to the **server `overlay_tree`**, raise it with `tree.node.raiseToTop()`, and retest.
  - **Second pitfall:** `server.overlay_tree` only keeps chrome above windows if the node is explicitly raised each time focus changes or a new window appears. Root `server.scene.tree` can sit below a raised window scene tree, so use `overlay_tree` and raise. Once chrome is in `overlay_tree` and positioned every frame, the colored rim will render above the focused client surface.
  - **`show_title_bars` toggles environment for future windows only.** It does not reconfigure existing toplevels. Restart the app after toggling, or set the CSS/files before the compositor starts. Existing windows keeping their negotiated style is the safe, non-breaking behaviour.
- **CSD shadows leak past chrome masks.** Even with SSD requested, clients may paint shadows beyond the content geometry. The safe fix is to leave geometry untouched and clip the XDG `surface_tree` to the **wrapper bounds** while leaving the chrome overlay on its own unrelated scene tree. Add `applySurfaceClip()` in `Window` and call it after `updateChrome()` in `applyLayout()`. The clip box must be in surface-tree local coordinates. Clipping relative to the surface origin `(0,0)` shifts content if the client has CSD margins; clipping relative to the XDG content offset (`geom.x`, `geom.y`) keeps the visible content aligned with the wrapper. The chrome overlay is never clipped. See `references/chrome-csd-content-clip.md` and `references/chrome-csd-shadow-bleed.md`.
- **Desktop wallpaper / background image pipeline.** Load a PNG with Cairo's `cairo_image_surface_create_from_png`, wrap the ARGB32 pixels in a wlroots `Buffer` using `DataBuffer`, and attach it as a `wlr.SceneBuffer` directly to the root scene tree. Always call `dupeZ` on the path before passing it to Cairo, update both position and destination size on output-layout changes, and retain a fallback solid-colour `wlr.SceneRect`. Details and full recipe: `references/wallpaper-background.md`.
- **No built-in wallpaper code in `29b8c55` or later.** The wallpaper implementation only exists in git history (`774aaa8`/`385b318`). If it is missing from the working branch, either cherry-pick/merge that commit, or temporarily change `color_background` in `src/core/style.zig` for diagnostic visibility. Do not try installing `swaybg` as a workaround; there is no default wallpaper layer and installing a background daemon can fail due to SSH session lifetime.
- **The visible "chamfer bleed" may actually be the mask fill.** If `theme.color_background` matches the terminal background, the solid corner triangles look like client content. To diagnose, temporarily set `color_background` to a bright color; if the triangles become that color, the mask is working and the issue is cosmetic fill.
- **True chamfer clipping is not supported by `wlr_scene`.** `wlr_scene_subsurface_tree_set_clip` only supports axis-aligned rectangles. Non-rectangular corner hiding must be done by masking/overlay, by sampling the wallpaper into the mask, or by a future wlroots patch. Because the CachyOS build has dropped `.cut` chamfers, a wlroots clip patch is only relevant to the Gentoo premium build. See `references/wlroots-chamfer-clip-wargame-2026-07-13.md` for the source-level wargame.

## Environment defaults

- Terminal: **Ghostty only**. Never foot/alacritty.
- Ghostty font size: **19** (`ghostty --font-size=19`).
- Base programs: Nano, Ghostty, Helium Browser.
- KidulWM dev follows Ghostty's Zig update schedule.

## Workflow discipline

- **One change at a time. Wait for explicit approval before starting the next one.** A user saying "that looks good" or "ok good" accepts only the current change. Do not pile on extra fixes, refactors, or polish without explicit direction.
- **Checkpoint good states before rethinking.** When the current build is promising and the user wants to explore a different direction — or says "lock that in" — `git add` and `git commit` the working source first. This avoids losing a known-good placement while iterating on polish such as corners or shading.
- **Stop means stop.** If the user interrupts with "STOP", halt immediately, report current file/branch/build state, and wait for direction. Do not finish a pending build, deploy, or patch pass first; leave the working tree and deployed binary exactly as they were when STOP arrived.
- **Do not deploy while the user is still reviewing a previous change.** Wait for an explicit "ok", "go", or "deploy that" before swapping the VM binary. A deployed half-measure can overwrite the known-good state the user is still evaluating.
- **After deploying a visual change, stop and let the user review.** Do not pile on additional edits while they are still looking at the screen. Wait for an explicit "your good to go" / "go ahead" before the next patch, because their feedback is the source of truth for rendering fixes.
- **Pace yourself to the user's reading speed.** If the user says a response was too fast to read, slow down: state one thing at a time, confirm the current step, and avoid rapid-fire patches or explanations.
- **Recover from context loss with `session_search`, not by asking.** If the conversation context compacts or you lose track mid-task, use `session_search` to retrieve the latest active instruction. Treat historical summaries as reference only; the most recent user message is the single source of truth. Then dispatch the next tool action immediately; do not leave the user waiting after they say "carry on" or "gods speed".
- **When the user rejects a direction, revert immediately.** If you made an unapproved change and the user objects, stop work and restore the last known-good commit before doing anything else.
- **A broken chrome/border effect is a regression, never a design request.** When the user reports messed-up borders, a missing frame, leaks, or ghost lines, do **not** assume they want the feature removed or changed. State the symptom, name the likely commit/change area, and offer to revert or patch. Wait for explicit direction before touching code.
- **When the user says "the chamfers are messed up / get the chamfers sorted / chamfers gone", the CachyOS build has no chamfers.** On CachyOS, `.corner_style` is either `.classic` (rounded) or `.none` (square). If a user asks for chamfers, that is a Gentoo premium feature; do not chase chamfer fixes in the CachyOS branch. The archived chamfer code lives at branch `archive/chamfer-cachyos` / tag `chamfer-final-cachyos`.
- **When the user says the geometry is perfect, only clip content.** Do not touch `corner_style`, `border_width`, `corner_depth`, or any offset/placement code. The safe fix for CSD bleed is to mask more aggressively inside the wrapper or to clip the XDG `surface_tree` to the content area while leaving the chrome overlay on its own scene tree untouched. See `references/chrome-csd-content-clip.md` and `references/chrome-mask-inset-attempt-2026-07-13.md`.
- **Keep an iteration log for chrome/border work.** Before each deploy, record commit hash, working-tree status, symptom, expected fix, and screenshot path. After the VM check, append observed result, regressions, and next suspected cause. Do not call a commit "known-good" without a fresh VM verification screenshot; a HEAD from a previous session is not automatically the last good build.
- **Chrome/border verification is done by the user, not by vision tools.** Deploy the binary and let Barticus judge the screen. Never accept or reject a chrome change based on `vision_analyze` output alone.
- **CoderBob hands back a patch; bobDotrix builds and deploys it.** coderBob should not deploy to the VM or declare a visual fix good. After reviewing coderBob's diff, rebuild, deploy, and ask the user to look. Do not let coderBob change code in the deployment step.
- **When archiving a feature branch, create both a branch and a tag.** Then remove the feature from the active branch. This leaves the feature easy to revive and impossible to lose. Example: chamfer was archived as `archive/chamfer-cachyos` and tag `chamfer-final-cachyos` before removal from the CachyOS branch.
- **When bisecting, start from a clean working tree.** `git stash` or discard uncommitted changes before checking out older commits; a dirty tree can produce a binary that does not match the commit being built.
- **When user says 'do what we did last time', retrieve the prior implementation from git history first.** Check `git log --all --oneline <good_commit>..HEAD`, inspect relevant commits with `git show <commit> -- <files>`, then apply only the needed parts to the current good commit. Do not offer colors, external tools (e.g. `swaybg`), or alternative approaches as a substitute for the user's stated prior implementation.
- **When recovering code from a known-good commit or feature WIP, do not check out the entire commit.** A commit like `774aaa8` may bundle the desired wallpaper code with broken geometry/chrome changes. Extract only the needed files (e.g. `git show 774aaa8:src/render/image.zig > src/render/image.zig`), apply the minimal server diff manually, and leave `src/render/chrome.zig` and `src/window.zig` untouched. Verify with `git diff -- src/render/chrome.zig src/window.zig` that no geometry logic changed before running `zig build`. See `references/wallpaper-cherry-pick-29b8c55.md` for the exact recipe.
- **When comparing multiple rendering fixes, build the variants on the host and deploy to isolated states.** Do not repeatedly overwrite a single running binary with guesses. Tag the known-good state, then produce each candidate binary and switch between them cleanly. See `references/wallpaper-chamfer-iteration-2026-07-13.md`.
- **Respect explicit scope.** When the user says "only change X, nothing else", edit exactly that — no refactors, no "while I'm here" cleanups, no adjacent file changes.
- **When recovering code from a known-good commit or feature WIP, do not check out the entire commit.** A commit like `774aaa8` may bundle the desired wallpaper code with broken geometry/chrome changes. Extract only the needed files (e.g. `git show 774aaa8:src/render/image.zig > src/render/image.zig`), apply the minimal server diff manually, and leave `src/render/chrome.zig` and `src/window.zig` untouched. Verify with `git diff -- src/render/chrome.zig src/window.zig` that no geometry logic changed before running `zig build`. See `references/wallpaper-cherry-pick-29b8c55.md` for the exact recipe.
- **Do not loop the same tool call while fishing for prior context.** If `session_search()` (or any retrieval tool) returns the same list/summary twice, stop repeating it. Switch to a content-reading shape (e.g., `session_search(session_id=...)`) or ask the user for the session title/date. Repeated identical calls waste turns and frustrates the user.
- **Recover a lost handoff note by reading session content, not re-listing sessions.** When the user refers to a message from the previous session, read the most recent session directly instead of issuing repeated empty browse queries.
- **If a mutation tool returns the same validation error more than twice, stop looping it.** When `patch` repeatedly rejects parameters, the fields are probably malformed or the file view is stale. Re-read the file, switch to `execute_code` or `write_file` for the same edit, or ask the user. Tool-looping wastes turns and blocks progress; diagnose or change tools.
- **Deploy visual changes only after confirming the target VM and waiting for user review.** State `TARGET: <vm-name> PORT: <port>` before every deploy. A visual fix is not good until the user says so; do not pile on additional edits while they are still evaluating the screen.

## VM workflow

- VM: `cachyos-kidulwm` on `qemu:///system`. Default `virsh` uses `qemu:///session` and fails; always specify `-c qemu:///system`.
- Host access: `ssh -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1`. If the port forward is missing (after VM start/reboot), re-add it: `virsh -c qemu:///system qemu-monitor-command cachyos-kidulwm --hmp 'hostfwd_add tcp::2222-:22'`.
- Key file for SSH: `~/.ssh/id_ed25519_kidulwm` (injected long ago via guest agent).
- Runtime log: `journalctl -u kidulwm -n 40 --no-pager` inside the VM.
- Test scripts such as `/tmp/kidulwm-test.sh` are user-owned: do not overwrite without explicit consent.
- Offline binary swap: see `references/vm-binary-deploy.md`.
- **Never experiment on the known-good running VM.** When the user wants a visual comparison or a risky rendering change, clone the running disk into a disposable VM first. This preserves the known-good state and lets two builds run side by side. Recipe: `references/live-vm-clone-side-by-side.md`.

### Adopting a new latest untouchable

The running good state periodically becomes the new clone source.

- Promote the current good master VM to a name like `kidulwm-latest` (or `untouchable-latest`) and treat it as read-only.
- Rename or archive the outgoing master first (e.g. `old-64gb-good`) so it remains recoverable but is no longer accidentally cloned from.
- Do all new work in disposable clones of `kidulwm-latest`, each with its own SSH/SPICE port.
- Target disk size is 15 GiB virtual, with the qcow2 sized to 16 GiB so the 15 GiB root partition plus 512 MiB ESP fit. (Actual sparse usage stays ~8–9 GiB, making USB backup feasible.)

For the 2026-07-14 cycle, the source of truth was `old-64gb-good` (a copy of `cachyos-kidulwm-rounded-fun`), the promoted untouchable is named `kidulwm-latest`, and experiments run in `kidulwm-glass`. Details, XML clone recipe, and hostfwd setup: `references/kidulwm-latest-cycle-2026-07-14.md`.

### Resizing a master VM disk for USB/archival backup

A 64 GiB virtual disk is sparse on the host, but the virtual size bloats the guest view and any non-sparse copy. Compact it to about 15 GiB before promotion.

Recipe (VM must be shut off):

```bash
sudo qemu-nbd --connect=/dev/nbd0 /var/lib/libvirt/images/old-64gb-good.qcow2
sleep 1
sudo e2fsck -f -p /dev/nbd0p2
sudo resize2fs /dev/nbd0p2 14G
echo ',15G' | sudo sfdisk --no-reread -N 2 /dev/nbd0
sudo qemu-nbd --disconnect /dev/nbd0
```

Caveats:
- The filesystem must be shrunk before the partition table; never shrink the partition below the filesystem.
- If `sfdisk` fails because another process has the file locked, look for a stale `qemu-nbd` process or a virt-manager pool scan; disconnect `/dev/nbd0` and retry.
- **Root UUID drift on new images.** After `qemu-img convert` to a new qcow2, the CachyOS initramfs may still reference the old root filesystem UUID and drop to emergency mode. Fix by booting a live ISO and updating `/etc/fstab`, `/etc/kernel/cmdline`, and bootloader entries to the new UUID, or switch the kernel command line to `root=/dev/vda2` before cloning. Details: `references/vm-shrink-and-uuid-drift.md`.
- Keep the old archive copy until the new `kidulwm-latest` boots and is verified.

### Disposable VM clones for side-by-side comparison

When comparing a current good build against an experimental build (e.g., transparency, chamfer revival, renderer swap):

1. Leave the good VM running.
2. Live-clone its disk with `qemu-img convert --force-share`.
3. Copy the NVRAM file and define a new VM with a fresh UUID, MAC, and SPICE port.
4. Build the experimental binary and deploy to the clone.

Full commands and XML adjustments are in `references/live-vm-clone-side-by-side.md`.

### Quick disposable clone from a known-good VM

For experiments that do not need side-by-side viewing, you can also `virt-clone` the good VM into a disposable copy with its own SSH port.

1. Ensure the base VM is **not running** (the Untouchable stays untouched).
2. Clone: `virt-clone --connect qemu:///system --original cachyos-kidulwm --name cachyos-kidulwm-rounded-fun --file /var/lib/libvirt/images/cachyos-kidulwm-rounded-fun.qcow2`
3. Start the clone: `virsh -c qemu:///system start cachyos-kidulwm-rounded-fun`
4. Open a unique local SSH port while the clone runs: `virsh -c qemu:///system qemu-monitor-command cachyos-kidulwm-rounded-fun --hmp 'hostfwd_add ::2224-:22'`
5. Deploy with the clone's port: `scp -P 2224 ...` and connect with `ssh -p 2224 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1`

The port forward is tied to the running QEMU process; after stopping/undefining the clone, the port goes away. Compute a fresh per-clone port so it never collides with an Untouchable. Recipe and teardown notes: `references/disposable-clone-quickstart.md`.

For ongoing day-to-day work, prefer the **Untouchables** discipline: keep the known-good VMs `cachyos-kidulwm` (rounded-best) and `cachyos-kidulwm-chamfer` (chamfer-best) shut off or read-only, and do all experiments in named disposable clones with unique SSH ports. See `references/vm-untouchables-discipline.md`.

### Untouchable VMs

- `cachyos-kidulwm` = **rounded-best / never deploy experiments here**. SSH port 2222.
- `cachyos-kidulwm-chamfer` = **archived chamfer-best**. SSH port 2223.

Before every deploy, verify VM name, SSH port, and build variant match the intended target. A wrong-port copy can overwrite a known-good Untouchable. The archived chamfer best binary is saved at `/home/dad/kidul-archives/kidulwm-chamfer-best`.

### Pre-deploy verification

Before `scp` or `ssh` to a VM, **state the intended target out loud and confirm the port**. Do **not** start a VM or run a deploy unless the name, port and purpose all match. A common mistake is to see a KidulWM task, reach for port 2222 and start `cachyos-kidulwm`, when the user is actually working in a different VM such as `kidulwm-glass` (port 2225).

- **Active work VM** → use the VM's actual SSH port; confirm with `virsh -c qemu:///system list --all` and, if needed, `ps aux | grep '[q]emu' | grep <vm-name>` to find the right target before touching anything.
- **Do not default to port 2222 just because the task is KidulWM.** Port 2222 is the **rounded-best untouchable**; start/deploy there only after explicit user direction.
- rounded-best clone experiments → use the clone's own port (e.g., 2224), not 2222.
- chamfer archive restore → port 2223 with `/home/dad/kidul-archives/kidulwm-chamfer-best`.
- rounded reference check → port 2222 only after explicit user direction.

**Hard rule for visual/chrome/glass experiments:**
- The active work VM can change mid-session. When the user says "lock that in" or names a VM, update the current target and verify its SPICE/SSH details before deploying. Do not assume the previous default work VM still applies.
- Before every visual deploy, echo `TARGET: <vm-name> PORT: <port>` in the command and verify it matches the currently locked-in VM.
- If you are about to deploy a visual/chrome/glass experiment anywhere else, stop and ask the user first.
- If you realize you already deployed to the wrong VM, stop immediately: do not build another VM, do not ask if it's OK, and do not leave the bad binary running. Halt the affected service and restore the known-good binary before doing anything else. Details: `references/visual-glass-deploy-rules-2026-07-14.md`.
- If the VM identity is uncertain, use the recovery recipe in `references/vm-identity-recovery.md`.

If you have already deployed to the wrong VM, stop immediately: do not build another VM, do not ask if it's OK, and do not leave the bad binary running. Halt the affected service and restore from the known-good commit before doing anything else.

### Restoring a contaminated untouchable

If an untouchable VM accidentally receives an experimental binary, act immediately:

1. Stop the affected VM's service so the experimental binary is no longer memory-mapped and cannot keep running.
2. Build a clean restore binary from `HANDOFF.md`'s listed `Last stable commit` or `Fallback commit`, not from the current experimental branch. Stash or save the experimental working tree first, then check out the stable commit, run `zig build`, and keep the stable binary on the host.
3. Copy the stable binary to the VM, overwrite `/usr/bin/kidulwm`, and start the service. Verify with `md5sum` and `systemctl is-active kidulwm` before considering the VM restored.
4. Only after the untouchable is restored should you return to the actual work VM.

Example recovery (rounded-best on port 2222):
```bash
cd /home/dad/dev/KidulWM
git stash
git checkout <fallback_commit>
zig build
cp zig-out/bin/kidulwm /tmp/kidulwm-stable
git checkout corner-bg-fix
git stash pop
ssh -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 'sudo systemctl stop kidulwm'
scp -P 2222 -i ~/.ssh/id_ed25519_kidulwm /tmp/kidulwm-stable kidul@127.0.0.1:/tmp/kidulwm.stable
ssh -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo cp /tmp/kidulwm.stable /usr/bin/kidulwm && sudo chmod 755 /usr/bin/kidulwm && sudo systemctl start kidulwm && systemctl is-active kidulwm'
```

### Chamfer revival in a disposable clone

The archived `archive/chamfer-cachyos` branch predates recent renderer workarounds and may fail to build until `Renderer.createPixman()` is restored in the local `zig-wlroots` bindings. Always test revived chamfer code in a **disposable clone** (`cachyos-kidulwm-chamfer`) on a distinct SPICE/SSH port so the rounded-corner `cachyos-kidulwm` VM stays untouched. See `references/chamfer-archive-build-pitfall-2026-07-13.md`.

### Live deploy while the VM is running (preferred now)

```bash
cd /home/dad/dev/KidulWM
zig build
scp -P 2222 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm.new
ssh -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm.new /usr/bin/kidulwm && sudo chmod 755 /usr/bin/kidulwm && sudo systemctl start kidulwm && systemctl is-active kidulwm'
```

**Stop the service before overwriting `/usr/bin/kidulwm`.** A running binary is memory-mapped and copying over it yields `Text file busy`. Stopping `kidulwm` releases the executable before swapping it. Disabling the systemd unit alone is not enough; the binary must not be in use.

### Spawn test windows from the host

```bash
ssh -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'for i in 1 2 3; do WAYLAND_DISPLAY=wayland-1 /usr/bin/ghostty & done; echo spawned'
```

### Cycle focus from the host

```bash
ssh -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'XDG_RUNTIME_DIR=/run/user/1000 /usr/bin/kidulwm-control focus_next'
```

## SlideDeck layout rules

- Show only the rightmost sliver of the left neighbour and the leftmost sliver of the right neighbour.
- Peek windows should butt up to the focused window with no gap other than the configured inset.
- Navigation does **not** wrap.  Focus can rest on a virtual empty slot before the first slide or after the last slide, leaving the view completely empty.
- New windows opened from an empty slot insert at that end; the nearest existing slide becomes the peek from that side.
- Deeper slides (distance >= 2 from focus) must be parked just off the nearest edge, not at `delta * screen`. Otherwise focus changes make distant windows fly across the output and overlap the focused slide. See `references/spring-animations-slidedeck-clamp-2026-07-13.md`.
- Focus transitions should **snap windows to their correct SlideDeck positions at rest** and only animate position while the focus is actually changing. Position-only interpolation over ~120 ms with easeOutCubic keeps the final layout correct throughout the motion. See `references/slidedeck-focus-transition-2026-07-13.md`.
- Details and code recipe for the empty-slot behaviour: `references/slidedeck-empty-slots.md`.
Details and code recipe: `references/slidedeck-layout.md`.

### Empty-slot edge pitfall

If a phantom peek appears when moving out of an empty slot, the `empty_slot` state was reset before the next layout. The two most common reset sources are:

1. `applyLayout()` calling `focusWindow()` while in an empty slot.
2. `focusAtCursor()` / pointer click focusing a visible peek while in an empty slot.

Guard both: only refocus during layout if `deck.empty_slot == .none`, and early-return from `focusAtCursor()` when `currentDeck().empty_slot != .none`. This was the proven fix for the phantom boundary peek; other symptoms usually trace back to one of these two refocus paths. See `references/empty-slot-peek-debug.md`.

## SlideDeck layout polish order

Useful repo pointers:
- `/home/dad/dev/KidulWM/HANDOFF.md` — current branch, head commit, fallback commit.
- `/home/dad/dev/KidulWM/KNOWN_CMDS.md` — quick command index.
- `/home/dad/dev/KidulWM/references/chrome-geometry.md` — verified chrome geometry, EdgeMode table, mask/ring rules, anti-patterns.
- `references/peek-glass-black-finish-2026-07-14.md` — current corrected "black glass" tokens, draw order, and verification checklist (more black than any other color, glass inside the border, visible seam border).
- `references/xdg-toplevel-title-appid-bindings.md` — wlroots 0.20 XdgToplevel `title`/`app_id` shape and listener pattern.

## SlideDeck layout polish order

1. **Geometry / placement first.** Get the unfocused neighbour positions correct (rightmost sliver of left neighbour, leftmost sliver of right neighbour).
2. **Clip / boundary only if leakage occurs.** After placement is correct, remove the hard clip and check for stale-buffer leakage. If leakage happens, re-add a targeted clip; if not, leave it off.
3. **Corner / shading polish.** Round corners and depth-cue shading should only be tuned once geometry and boundaries are stable, because scene clips and overlay sizing directly affect them. Use the compositor-owned overlay-buffer approach in `references/compositor-chrome-buffers.md` when KidulWM must control the shape independent of client CSD.

## Scene clipping / layout boundary pitfalls

When a SlideDeck window transitions from focused (full-width buffer) to an unfocused neighbour slot, the client may not have committed a new buffer at the smaller size yet. The scene node will then draw the old full-size buffer at the new small-slot position, leaking behind the transparent focused window or past the output edge.

Fixes, in order of preference:
1. **Position slides so the visible sliver is already hidden behind opaque overlap or off-screen.** Correct off-screen placement often avoids the need for a hard clip.
2. **If leakage still occurs, call `wlr_scene_subsurface_tree_set_clip()`** on the scene node returned by `wlr_scene_xdg_surface_create()` after every layout pass, using the layout target width/height. Size any focus-dim overlay from the **surface buffer**, not the layout target, so rounded corners and client-side shading remain intact. Note that any remaining clip boundary will square off rounded corners/shading, so keep the clip only where its edge is not visible.

Details and code recipe: `references/scene-clipping.md`.

When visual verification is needed and `grim` fails (KidulWM does not implement `wlr-screencopy-v1`), use the QEMU monitor screendump fallback described in `references/visual-verification.md`.

- When chasing pixelation or lag, compare renderer configs systematically and record outcomes in `references/renderer-experiments.md`.
- See `references/tray-input-notes-2026-07-13.md` for tray pointer routing, keyboard fallback (`Mod4+t`/`Mod4+a`), and bottom-left geometry.

## Focused-window border regressions

See `references/focused-window-clip-regression-2026-07-13.md` for the 2026-07-13 case where clipping the focused XDG surface to its content geometry while leaving `surface_tree` at `(0,0)` caused a stray detached left border.

Useful probes: `grep -E 'renderer|new output' /tmp/kidulwm-service.log`; one-shot renderer tests via `WLR_RENDERER=pixman` or `WLR_RENDERER=gles2`.

## Newly learned chrome/border lessons

In `src/render/chrome.zig`, the `.cut` (chamfer) path needs two distinct outer paths:
- The **background mask** outer path must be the **full window bounding rectangle** (`squareRect(0,0,w,h)`). This paints every corner wedge with the compositor background colour and hides client-side rounded corners / shadows that extend past the chamfered frame.
- The **border ring** outer path stays the chamfered rectangle (`chamferRect(..., depths)`) so the visible frame keeps the signature cut-corner look.
Both paths share the same parallel-offset inner polygon. Using `chamferRect` for the mask outer leaves the corner wedges transparent, which lets client background bleed through. After the mask and ring are drawn, the hidden-edge `DEST_OUT` strips still remove off-screen border correctly, because the strip only clears content outside the visible seam.

- **Chrome overlay cache key must include `EdgeMode`.** `Window.updateChrome` caches the Cairo overlay by size, focus state, output scale and style generation. If `EdgeMode` is not part of that key, a window changing between `right_peek`, `left_peek` and `.all` can reuse the old overlay surface while keeping stale hidden-edge strips and corner shapes. Symptom: rounded background / missing seam border that clears after another redraw. Fix: store the last used `EdgeMode` and regenerate whenever it changes. Use an explicit `eql()` helper for Zig structs since `==` is not automatically available. Details: `references/chrome-cache-key.md`.

- **Peek black-glass overlay must not replace or mask the border ring.** It is drawn **before** the original border ring, and the ring stays unchanged on top. For **translucent** glass the overlay can fill the full outer shape; for **near-opaque** glass (top/bottom alpha ~0.97) clip it to the inner content shape (rounded rect inset by `border_width`) so the border ring and its background-colour band remain visible. See `references/peek-glass-black-recipe.md` for tokens/draw order, and `references/peek-glass-border-visibility-2026-07-15.md` for the near-opaque case.

- **Visual verification of chrome/glass/border is done by Barticus, not by Bob's vision tools.** Deploy the binary and wait for Barticus to judge the screen. Do not accept or reject a glass/border change based on `vision_analyze`.

- **Extending black glass to the edge with a user-changeable colored rim.** When the user wants the peek glass to reach the wrapper edge and add a colored 2–4 px border around it, use the recipe in `references/peek-glass-colored-border-recipe-2026-07-15.md`: move chrome to `server.overlay_tree`, stroke the rim with `CAIRO_OPERATOR_SOURCE`, and expose a theme token.

- **When a colored border around the peek glass is invisible, check three things before changing the theme color:** (1) the chrome node is in `server.overlay_tree` and raised above all windows; (2) the hidden-edge `DEST_OUT` trim is not wider than the border itself for square-corner peeks; (3) the stroke is drawn with `CAIRO_OPERATOR_SOURCE` so it stays opaque over the dark glass. A 2 px stroke just inside the wrapper bounds is enough. See `references/chrome-peek-stroke-visibility-2026-07-15.md`.

- **Final peek glass + colored rim recipe (2026-07-15).** When the user wants the peek glass to reach the wrapper edge plus a visible, themeable border, use the recipe in `references/peek-glass-final-recipe-2026-07-15.md`: full-wrapper black source fill, a hard 2 px `CAIRO_OPERATOR_SOURCE` stroke using `style.color_border`, hidden-edge `DEST_OUT` trim, chrome parented in `server.overlay_tree` and raised every frame, and the `border` theme key syncing `peek_glass_border_color`.

- **Stop means stop immediately; do not finish the current build or deploy.** If the user interrupts with STOP while a build/deploy/patch is in progress, halt without finishing it. Report current file/branch/build state and wait.

- **When the user is frustrated or says 'just fix it', stop explaining and stop piling on changes.** State the symptom, offer one concrete next action (revert or patch), and wait for explicit direction. Do not deploy without approval.
- **When the user is shouting, swearing, or expressing strong frustration about repeated failures, halt and revert immediately.** Do not propose another variant, explain the cause, or ask clarifying questions. Restore the last known-good commit/binary, report that the state is clean, and wait for a single, explicit instruction before touching code again. Continuing to iterate while the user is venting wastes tokens and deepens the regression.

- **When CSD content bleeds through chamfered corner triangles, stop thickening the chrome mask.** The correct "snip" is: remove the solid per-window `bg_rect`; stop drawing a solid background mask in the `.cut` chrome path (draw only the border ring and the hidden-edge DEST_OUT strips); and clip the XDG `surface_tree` to the wrapper rectangle in surface-tree local coordinates. See `references/wallpaper-and-chamfer-snip-2026-07-13.md`.

### Window dimming and per-window opacity

- The current implementation uses a black `wlr.SceneRect` overlay (`dim_rect`) sized to the surface buffer at 18% alpha. That works but adds overdraw and can square off rounded client corners/shadows.
- **Long term, replace the overlay with `wlr_scene_buffer_set_opacity()` on the client's scene-buffer node.** Focused window = `1.0`, unfocused peek ≈ `0.82` (matching the current 18% dim). Walk `Window.surface_tree` with `forEachBuffer`, call `SceneBuffer.setOpacity`, and keep the chrome overlay in a separate sibling tree so it stays opaque. See `references/scene-buffer-opacity-vs-dim-rect.md`.

### Peek surface content and visual balance

- A peek that shows only the compositor background fill is almost always offset incorrectly. The `wlr_scene_xdg_surface_create` tree positions the **XDG geometry top-left**; scene-tree position `(0,0)` already aligns the content area with the wrapper origin. Do not subtract `geometry.x` / `geometry.y` from the offset for natural-size peeks.
- The correct natural-size alignments for a full-width peek wrapper are:
  - *Left peek*: visible sliver is at the wrapper's **left** edge, so show the window's leftmost content: `x = 0`.
  - *Right peek*: visible sliver is at the wrapper's **right** edge, so show the window's rightmost content: `x = target_w - geometry.width`.
- The dim overlay on unfocused windows can make one side's peek look darker or uneven depending on which edge of the wrapper the visible sliver occupies and how the overlay is sized. If side peeks look uneven, test with the dim alpha set to `0.0` before chasing geometry.
- The focused inner glow stroke in `renderChrome` produced a thin interior line on focused windows that was mistaken for a chamfer-width mismatch. Removing the glow stroke eliminated the line; the line is not caused by `border_width` / `chamfer_border_width` differences.

### Focused surface scaling vs. natural size

- The focused slide used to call `setSurfaceDestSize(target_w, target_h)`, scaling the committed buffer to fill the wrapper. Side peeks were then reset to natural size with `setSurfaceDestSize(surface.current.width, surface.current.height)`. Switching dest size every time a window changed between focused and peek caused a visible re-render flicker, and at the no-go-zone the same window flipped between states without a fresh commit, leaving a stuck misaligned frame.
- Removing the focused `setSurfaceDestSize` and leaving the surface at its natural committed size eliminated the flicker. The client still receives `toplevel.setSize(target)` and will commit at the requested size when ready.
- When the focused buffer is still smaller than the wrapper during a transition, center the content inside the wrapper so the background fill is symmetric. Recipe and caveats: `references/focused-surface-centering-2026-07-12.md`.

### Re-enabling the built-in spring animations

- Real motion already exists in `src/core/animation.zig` (`WindowAnimation` spring integrator with position/size/opacity), and `Output.handleFrame` calls `Window.tickAnimation()` every frame. The animation is disabled because `Window.setLayoutTarget()` snaps `cur_*` to `target_*` immediately and `Window.tickAnimation()` also snaps instead of integrating.
- To enable smooth focus changes, leave `cur_*` unchanged on subsequent `setLayoutTarget()` calls, let `tickAnimation()` call `WindowAnimation.tick(now_us)`, apply `cur_x/cur_y` to the wrapper scene node, and drive chrome + focused surface size from `cur_w/cur_h`.
- Enabling animation exposes a SlideDeck placement bug: `targetForSlide()` places deeper slides at `delta * screen`, so focus changes drag distant windows across (or off) the screen. Clamp `|delta| >= 2` targets to one screen-width past the adjacent peek so only the focused slide and its immediate neighbours animate.
- **For production use, prefer the focus-triggered position-only interpolation** described in `references/slidedeck-focus-transition-2026-07-13.md`. It snaps windows to their correct SlideDeck slot at rest, animates only while focus is changing, and avoids the per-frame chrome regeneration and size-integration problems of the spring approach.
- Full code diff and caveats: `references/spring-animations-slidedeck-clamp-2026-07-13.md`.
