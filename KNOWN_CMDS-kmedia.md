# KidulWM — kmedia / PipeWire (slice)

Read only for kmedia work. Host core is KNOWN_CMDS.md.

## kmedia / PipeWire notes (fresh-one)

- The VM has no audio hardware. A null sink lives at
  `~/.config/pipewire/pipewire.conf.d/kidul-sink.conf` (adapter factory
  `support.null-audio-sink`, media.class `Audio/Sink`, monitor.passthrough).
  Do NOT use `libpipewire-module-null-sink` — not shipped on this setup.
- `pipewire-audio` package is required (pw-cat, SPA audio factories).
- wireplumber is the session manager (installed + enabled as user service).
- `kmedia-test` binary prints live band levels for debugging:
  `XDG_RUNTIME_DIR=/run/user/1000 /tmp/kmedia-test`
