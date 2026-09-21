# Render path law — presentation & scanout (LOCKED 2026-09-21)

Status: LOCKED (Barticus 2026-09-21). Scanout first, then gating. The slide
protocol / shared painter / "GodCodeMode" is a SEPARATE spec, wargamed after
this law lands.

## The problem (why "not buttery smooth" + CPU hammering are the SAME bug)

The compositor has exactly one present path:

  Output.handleFrame -> tick animations -> scene_output.commit(null)

Every output frame walks the ENTIRE scene graph and re-composites it through
the GPU renderer. There is no direct-scanout fast path and no frame gating:
wlroots 0.20.1 already exposes direct scanout (`wlr_output_is_direct_scanout
_allowed`, `SceneBuffer.OutputSample.direct_scanout`, `SceneOutput.buildState`)
— the compositor uses none of it.

Consequences, all traced to this one seam:

  1. Fullscreen video (kplayd) still composites through the renderer every
     frame instead of being scanned out. No zero-copy passthrough -> the
     "watchable but not buttery smooth" jitter, and full CPU during playback.
  2. Any client commit wakes the render loop, and every wake = a full-scene
     composite of BOTH outputs. ghostty (GTK4, stock) commits ~14/s at idle,
     so idle CPU is ~36% and i915_irqs ~64/s with nothing visibly changing.
     That is the "thick tentacle fighting the slide model" — named in CENSUS,
     but the compositor amplifies it by re-rendering everything on every wake.
  3. There is no "nothing is dirty, skip the frame" gate. The loop runs hot
     on client commits that change zero pixels we care about.

This is the tier-model violation (§2.1): thick tentacles (ghostty, browser,
kplayd video) are being composited as if they were thin face-rendered cards.
They should be handed a buffer (I4) and passed through, not re-painted.

## The target (what we build, frozen)

Two fast paths in front of the existing composite, in this order:

  FAST PATH 1 — DIRECT SCANOUT (I4, zero-copy)
    When one opaque client surface covers the output edge-to-edge with ZERO
    compositor chrome above it (fullscreen video slide — CHROME LAW already
    guarantees zero chrome — or a fullscreen terminal), the output commits the
    client's buffer straight to the display via direct scanout. No scene walk,
    no renderer, ~2% CPU. This is the "buttery smooth" destination.

  FAST PATH 2 — FRAME GATING (I5, single-threaded control plane)
    handleFrame becomes: if no scene damage AND no active animation AND no
    pending layout, do NOT commit. Only tick the clock. The render loop stops
    running hot on idle client commits. A client commit marks its buffer dirty
    and schedules ONE frame; it does not force a full re-composite.

  SLOW PATH — the existing composite (unchanged, for everything else)
    Thin tentacles (cards, peek, tray, chrome) and any scene with compositor
    chrome over a client keep the scene-graph composite. This is correct and
    stays.

## Why this order

Scanout first because it is the quality bar Barticus named ("match the big TV
makers") AND the biggest CPU win for playback. Frame gating second because it
kills the idle 36% without touching a single client. Both are wlroots-native
features we are simply not using yet — this is wiring, not invention.

## Laws this retires / re-points

  - I4 "one resource owner" lands as the scanout path (buffer lifetime owned
    by the output, not the scene walk).
  - The "thick tentacle" symptom stops being a bug to chase per-client and
    becomes a property of the fast path: thick tentacles get scanout, thin
    tentacles get composite.
  - The verdict-50 "damage-clipped commit is a non-fix" finding is confirmed
    and retired: wlroots tracks damage internally; the real fix is to STOP
    committing when there is no damage (gating), not to pass damage regions.

## Acceptance

  1. Fullscreen video: kidulwm CPU ~2-5% during playback, RSS flat, frames
     presented zero-copy (verify VA-API + scanout active), no jitter.
  2. Idle (ghostty open, nothing changing): kidulwm CPU < ~5%, i915_irqs flat
     (no ~64/s climb), render loop asleep between real changes.
  3. No regression to chrome/peek/tray (slow path unchanged) and no regression
     to the focus/fullscreen laws (verdict 49).

## Out of scope (do not tangle)

  - The ghostty fork (strip GTK4 -> thin tentacle). It is the client-side END
    GAME, a separate workstream. Scanout + gating make stock ghostty cheap
    enough in the meantime.
  - The cross-GPU staging wedge (verdict 51) — deferred to the USB-C re-cable.
  - Presentation-timing / vsync-grid lane (verdict 44) — stays closed until
    the render loop stops wedging.
