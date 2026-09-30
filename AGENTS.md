# Agent Reference for KidulWM

When working on this repository, treat these files as authoritative before guessing or searching the wider filesystem.

## VM / deploy / test workflow

Source of truth: `KNOWN_CMDS.md` in this repository.

- Workbench is PHASE-DEPENDENT — SYSTEM.md is the arbiter ("1 file to rule").
  Phase 2 (RSS wedge) is GPU-only → HOST: kidulwm runs on the host's i915
  (GL, NOT pixman) via an sddm login. Everything else (software/pixman) stays
  in ksd-reset. Build ReleaseSafe on host; deploy to the active target.
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

Read `KNOWN_CMDS.md` first — that's the host core (build/deploy/control).
Command slices by lane, read only the one your lane needs:
`KNOWN_CMDS-vm.md` (VM), `KNOWN_CMDS-knetd.md`, `KNOWN_CMDS-aig.md`,
`KNOWN_CMDS-apocalypse.md`, `KNOWN_CMDS-kmedia.md`.
If not there, check `HANDOFF.md` in this repository.
