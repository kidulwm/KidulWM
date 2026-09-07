# Agent Reference for KidulWM

When working on this repository, treat these files as authoritative before guessing or searching the wider filesystem.

## VM / deploy / test workflow

Source of truth: `KNOWN_CMDS.md` in this repository.

- DEFAULT IS THE HOST (law, Barticus 2026-09-07): build ReleaseSafe on the
  host, deploy to `/usr/local/bin/kidulwm`. VM deploys only when Barticus
  explicitly asks.
- **fresh-one**: SSH to `kidul@192.168.122.96` (plain NAT, port 22; the old
  `127.0.0.1:2260` hostfwd is stale), key `~/.ssh/id_ed25519_kidulwm`
- **cachyos-kidulwm**: SSH to `kidul@127.0.0.1:2222`, same key

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
