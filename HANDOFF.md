# KidulWM Handoff

## Current state

- Branch: `main`
- Last commit: `36bfa70 kidulButton` (deployed, locked in)
- Working tree: `src/ui/weather.zig` modified; untracked `config/weather.conf.example`, `scripts/fetch-weather.py`

## What happened this session

- `kidulButton` commit was completed and deployed successfully.
- Tried to fix a perceived "double moon" / "cheap" look in the left-peek weather widget.
- `src/ui/weather.zig` and `src/ui/media.zig` were reverted and re-touched multiple times; the working copy ended back at the committed `kidulButton` state with the changes stashed.
- Added `Environment=HOME=/home/kidul` to the VM's `/etc/systemd/system/kidulwm.service` so the weather widget can resolve its cache path.
- Manually wrote a real weather cache to the VM at `~/.cache/kidulwm/weather/home.json` with **Toowoomba, QLD** data (current temp ~12°C, code 1, night).
- The widget's moon phase uses system Unix time (`time(null)`), which was correct.
- The visual issue was mostly caused by the widget rendering default/zero data (no cache found) and the bottom condition icon overlapping visually with the moon.

## Weather icon size change (in progress)

- `src/ui/weather.zig` line 187: condition icon base radius bumped from `68.0 * scale_f` to `96.0 * scale_f`.
- `src/ui/weather.zig` line 188: icon bottom margin bumped from `1.0 * scale_f` to `2.0 * scale_f`.
- Moon renderer and layout untouched per user direction.
- **Not yet built or deployed** — host `zig build` fails on clean `main` due to C header fortification errors in `media.zig`/`network.zig`.

## Build/deploy blocker

- Host `zig build -Doptimize=ReleaseSafe` fails on `main` with glibc `_FORTIFY_SOURCE` macro errors translating `/usr/include/bits/fcntl2.h`.
- VM `fresh-one` SSH reachable at `kidul@127.0.0.1:2260`, but `/home/kidul/KidulWM` source tree is stale and lacks the current weather widget code.
- Existing binary at `/usr/bin/kidulwm` on VM is the deployed `kidulButton` build.

## VM state

- VM: `fresh-one` (kidul@127.0.0.1:2260)
- Service file now contains `Environment=HOME=/home/kidul`
- Deployed binary: `/usr/bin/kidulwm`
- Weather cache: `~/.cache/kidulwm/weather/home.json` (Toowoomba)

## Pending decisions

1. Resolve build environment so the weather icon change can be compiled and deployed.
2. Keep or drop the stashed weather/media tweaks (`git stash drop` or `git stash pop`).
3. Keep or remove the untracked `scripts/fetch-weather.py` and `config/weather.conf.example`.
4. Decide the intended look of the weather peek widget (moon + condition icon vs moon only) once the screenshot/data flow is confirmed.
