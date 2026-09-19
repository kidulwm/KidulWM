# Agent Reference for KidulWM

When working on this repository, treat these files as authoritative before guessing or searching the wider filesystem.

## VM / deploy / test workflow

Source of truth: `KNOWN_CMDS.md` in this repository.

- Reset work (Phase 0→5) happens IN the ksd-reset VM. Host runs niri as the
  workbench, not kidulwm. Build ReleaseSafe on host, deploy to ksd-reset,
  `systemctl restart kidulwm`.
- **ksd-reset** (work VM): SSH `kidul@192.168.122.87` (plain NAT, port 22),
  key `~/.ssh/id_ed25519_kidulwm`. kidulwm runs as a SYSTEM service on tty1,
  `WLR_RENDERER=pixman` (software renderer). sudo password = `kidul`.
- **fresh-one** (FROZEN reference — widget sizes): SSH `kidul@192.168.122.96`.
  DO NOT TOUCH. It runs pre-tray-demolition code (Aug 28) whose widgets are
  the perfect-size reference. Revert any accidental change.
- **cachyos-kidulwm**: shut off; the `127.0.0.1:2222` hostfwd is stale.
- Old `127.0.0.1:2260` (fresh-one) hostfwd is stale — use real IPs via
  `virsh -c qemu:///system domifaddr <vm>`.

## Secrets / credentials

- SSH key is at `~/.ssh/id_ed25519_kidulwm`
- GitHub credentials are in `~/.hermes/secrets/github`
- Social platform credentials are in `~/.hermes/secrets/social`
- Never type credentials in chat; read them from the restricted files above.

## UI / visual polish

- Do not analyze screenshots or run vision tools unless Barticus explicitly asks.
- Make only the exact requested UI change; do not widen scope.
- Weather/moon widget is flagship eye-candy — minimal, surgical changes only.

## Build / environment notes

- If host `zig build` fails with glibc `_FORTIFY_SOURCE` / `__builtin.object_size` errors, add `@cDefine("_FORTIFY_SOURCE", "0");` at the top of the affected `@cImport` blocks (e.g., `src/ui/media.zig`, `src/ui/network.zig`).
- Weather widget needs `Environment=HOME=/home/kidul` in its systemd service so the cache path resolves correctly.

## When in doubt

Read `KNOWN_CMDS.md` first. If it's not there, check `HANDOFF.md` in this repository.
