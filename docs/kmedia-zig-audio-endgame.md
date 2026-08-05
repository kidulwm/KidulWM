# kmedia — a Zig-native media/audio layer for KidulSD
## Notes for a conversation with Andrew Kelley (and the Zig community)

Context: KidulWM is a Wayland compositor written in Zig (wlroots 0.20 bindings).
The desktop family ("KidulSD") includes satellite apps — kfiles (file manager),
kbrowser, ktunes (music player) — all Zig, all sharing one palette/theme system.
The compositor already runs its own IPC (kidulwm-control over a unix socket),
its own widgets (tray, peeks, notification stream), and hand-rolled Wayland
protocol code. We hand-roll rather than bind big C frameworks wherever we can.

The question: what does the *right* endgame look like for audio — a media layer
("kmedia") that is as Ziggy as the rest of the stack, and could one day be a
reference for "how a Zig desktop does sound"?


## Where we are today

- A "double helix" music visual in the compositor's media peek widget:
  two sine strands + ball markers, amplitude faked from a sine envelope.
  Pretty, but it dances to nothing.
- Media control is MPRIS-via-shell-duct-tape; no audio data is captured anywhere.
- Goal for the visual: 7 strands = 7 frequency bands, driven by real audio.
  When nothing plays, it falls back to a slow ambient crossfade (60s cycle,
  one strand brightening at a time — alive but not distracting).


## The plan (as discussed)

### Phase 1 — foundations (~6 months)

1. **PipeWire capture, minimal libpipewire bindings in Zig (~200 lines):**
   capture the monitor of the default sink (mixed output of whatever plays:
   mpv, browser, games). Runs on its own thread inside the compositor.
2. **Small FFT in Zig** (radix-2, ~100 lines — we need 7–16 bands, not a
   spectrum analyzer) → band energies into a lock-free ring buffer that
   widgets read per frame at zero cost.
3. **IPC surface** on the existing control socket:
   - `media_bands subscribe` — stream band energies to any app (ktunes UI,
     future visualizers, lock screen)
   - `media_now_playing` — title/artist/art
   - `media_play/pause/next` — via MPRIS
   - `media_visual_mode <m>` — helix / bars / off, per widget
   ktunes becomes a *client* of kmedia, not the owner of audio state.
4. **MPRIS over D-Bus from Zig** — hand-rolled or thin bindings, so
   play/pause/metadata works for every player on the system with no
   per-player code.

### Phase 2 — kmedia as the system audio layer (~1 year)

- Per-app volume/mute from the tray (PipeWire per-stream control) — the tray
  card becomes a real mixer.
- Settings-app integration: visual mode, band count, sensitivity, monitored
  sink.
- The helix goes band-driven at 60fps; idle = ambient crossfade. Same shape
  language either way — only the data source changes.
- Satellite apps subscribe to `media_bands` and draw with shared theme tokens.

### Phase 3 — full Zig (beyond)

- Pure-Zig D-Bus library (protocol is documented; we already hand-roll Wayland).
- Pure-Zig FFT/DSP helpers as a reusable package.
- Long-term dream: a Zig PipeWire *session manager* — a wireplumber
  replacement. "Just" graph logic over the PW protocol. Ambitious, but it is
  the last C dependency between us and an all-Zig audio stack.
- kmedia becomes a public KidulSD API: any app reads audio state, shows
  visuals, flashes notification sounds, etc. `zig build` → compositor +
  media bus + widgets, zero runtime deps beyond PipeWire itself.


## Questions for Andrew / the community

1. **PipeWire from Zig:** has anyone published minimal pw_stream bindings
   worth building on, or is hand-rolling against libpipewire's C ABI the
   current best path? Any ABI pitfalls with SPA pods in Zig (alignment,
   bitfields, varargs)?
2. **FFT/DSP:** is there a canonical Zig FFT today? For 7–64 log-spaced
   bands, is radix-2 + windowing the sane minimum, or is there a Zig-idiomatic
   approach (comptime twiddles, @Vector SIMD) someone has already tuned?
3. **Real-time safety:** best practice in Zig for the audio callback —
   no-alloc zones, ring buffers to the main thread? Patterns from Andrew's own
   audio work (his music player history is why we're asking!) would be gold:
   buffer sizes, latency vs. smoothness tradeoffs for a 60fps visual.
4. **D-Bus:** is hand-rolling the D-Bus protocol in Zig a known-solved
   exercise (existing libs?) or should we expect to write the marshaller
   ourselves? MPRIS only needs a small subset.
5. **Session manager ambition:** how crazy is a Zig wireplumber replacement,
   really? What does the graph/policy surface actually involve? If the answer
   is "start with a policy-only daemon and let pw handle routing," we'd love
   pointers on the minimal useful subset.
6. **Community interest:** would a "kmedia" — a small, desktop-focused,
   Zig-native audio control + visualization bus — be useful beyond KidulSD?
   Happy to develop it in the open as a standalone repo if others want to
   build on it (river/hyprland folks need the same pieces).
7. **Ziglang synergies:** anything in std (or planned) we should lean on —
   atomics/ring buffers, thread pools, evented I/O — before we invent our own?


## Why we think this matters

Zig was born, in part, from wanting a better language for a music player.
A Zig compositor doing a Zig-native audio layer — capture, DSP, control,
visuals — feels like closing that loop. If it inspires even one other
desktop project to skip the C glue, it's worth doing in public.

— Bob & Barticus, KidulSD
  (kidulwm compositor: Zig + wlroots 0.20, Cairo widgets, hand-rolled IPC)
