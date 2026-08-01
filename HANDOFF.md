# KidulWM Handoff

## Current state

- Branch: `main`
- Last commit: `03aadff gauge: add RAM ampoule, widen left peek, refactor metric reads, archive wave gauge`
- Working tree: clean
- Build: `zig build -Doptimize=ReleaseSafe` passes on host

## Left peek gauge layout (in progress)

Current composition in `src/ui/gauge.zig`:

- **Top**: GPU / CPU mercury thermometers
  - Thin glass tubes, round bottom bulb, liquid fill
  - Fill color: border color at 55% alpha
  - Empty space: % tint of border color
  - Outline: unfocused border color, 3 px thick, 85% alpha
  - Labels: GPU, CPU below each gauge
  - Warning levels tint fill/outline burnt orange at 85%/90%/95%

- **Middle**: RAM chemistry ampoule
  - Round-bottom flask / sealed ampoule shape
  - Fills from bottom with same liquid style
  - Label: RAM

- **Bottom**: reserved for disk "vault" / treasure-chest silhouettes (not started)

Archived: original wave-gauge implementation is preserved under `src/ui/gauge/archive/`.

## VM state

- VM: `fresh-one` (kidul@127.0.0.1:2260)
- Deployed binary: `/usr/bin/kidulwm`
- Service: `kidulwm.service`
- Left peek split is widened to 6%/88%/6% via `src/core/style.zig`

## Build/deploy workflow

```bash
cd /home/dad/dev/KidulWM
zig build -Doptimize=ReleaseSafe

scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm \
  zig-out/bin/kidulwm zig-out/bin/kidulwm-control \
  kidul@127.0.0.1:/tmp/

ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm /tmp/kidulwm-control /usr/bin/ && sudo systemctl start kidulwm'
```

## Pending decisions

1. Disk gauge design: minimal vault / strongbox silhouettes for D1/D2 at bottom of left peek.
2. Font: consider custom KidulWM typeface (classy, clear, slightly Fantasque Sans Mono / JetBrains inspired).
3. Final polish pass on gauge colors, label sizing, and vertical spacing.
