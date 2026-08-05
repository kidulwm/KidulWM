# Per-pixel chrome architecture — the big idea (parked 2026-08-05)

## The thought

Design the whole screen pixel by pixel, not in layers: for each pixel,
compute the final color directly — wallpaper → curtains → window → chrome
→ peek → kbottle → cursor evaluated as one function `color(x, y)` instead
of scene-graph → buffers → GPU blending.

## Precedent (is it done anywhere?)

1. **Shadertoy / demoscene fragment shaders** — exactly this model: one
   function per pixel, whole scene computed procedurally, no layers.
   Proof the model produces stunning visuals.
2. **Game HUD/UI in shaders** — entire UIs in a single fullscreen fragment
   pass. Still rasterizing shapes, not true per-pixel scene evaluation.
3. **Software renderers / wlroots pixman** — KidulWM already runs llvmpipe
   in the VM (pixels computed on CPU), but still *layer compositing*.

Nobody uses the per-pixel model for a whole compositor. The space is open.

## Where it sings vs. where it fights

**Sings:**
- Our decorative chrome is already procedural math (curtains, kbottle,
  helix, gauges, glass). A per-pixel evaluator for the **chrome layer**
  (everything except client window contents) is feasible today.
- Anti-aliasing, glow, consistent lighting — free when you own every
  pixel's math. One light source (the border color) shading ALL chrome
  consistently. "Bob's extra special shading", system-wide.
- The 10px design-grid overlay becomes a shader mode, free.

**Fights:**
- **Client windows.** Apps' pixels arrive as buffers/textures; you can
  only sample them. The end-state is necessarily HYBRID: procedural
  per-pixel chrome + sampled window content. (That's fine — every
  compositor is hybrid at the window boundary.)
- **Performance.** CPU per-pixel at 4K = 8.3M evaluations/frame. Needs
  either GPU fragment shaders (fast, shadertoy model) or disciplined
  Zig @Vector SIMD. llvmpipe already burns 300% CPU just blending.
- **Text.** Keep Cairo/FreeType for glyph rasterization; sample text
  surfaces like window textures.

## The two candidate paths

1. **GPU path (sane):** one fragment shader per output for chrome.
   Uniforms: theme colors, helix bands, tray state, grid mode. Client
   windows composited beneath as textures. A few hundred lines of GLSL
   + a wlroots GLES custom pass.
2. **CPU path (Ziggy):** `renderChromePixel(x, y, state)` in Zig with
   @Vector into one buffer per output; windows composited over. Slower,
   but pure Zig and unit-testable per pixel — visual regression tests
   become `assert(pixel(37,412) == gold)`.

## Why it matters for KidulSD

Every other compositor is a layer blender. This would make KidulWM the
first where chrome is *computed*, not assembled — one coherent visual
function instead of a pile of Cairo widgets that grew separately.
kbottle, curtains, helix, gauges, tray stop being independent widgets
and become one drawing with shared lighting and shared geometry rules.

## Step zero (tomorrow)

The 10px design-grid overlay (`kidulwm-control grid_overlay on|off`,
heavier lines every 100px, origin at screen corner) — it is the
coordinate system the per-pixel model will use. Build it first; use it
to finish the curtains by talking in grid cells instead of vibes.

## Status

PARKED — revisit after dogfooding KidulSD on the host ("meaty chunks"
first: host GPU/audio, kmedia phase 2, settings app).
