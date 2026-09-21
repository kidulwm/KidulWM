# GodCodeMode — the present-path unification (LOCKED 2026-09-21)

Status: LOCKED (Barticus 2026-09-21). This is B&B's god code — the name for
where every finding to date converges, not a new phase and not a big-bang
rewrite. It supersedes docs/law/render-path.md (folded as Card A/B below).

## The statement

One present path that classifies every surface THIN (face-rendered) or THICK
(buffer passthrough) and routes it deterministically. Today the compositor has
one undifferentiated path (handleFrame -> full scene commit) that paints thick
tentacles as if they were thin cards — the single root of the idle 36% CPU and
"not buttery smooth" playback.

## Three pillars

  P1 SLIDE PROTOCOL  — our own Wayland extension (like kidul-settings-tray-v1).
      A client declares "I am thin (use kslate)" or "I am thick (here is my
      buffer + focus key)". Carries I3's face; retires the verdict-47 "where
      am I" wound as a typed protocol instead of a pile of callbacks.

  P2 SHARED PAINTER  — "kslate" (was "kpaint", renamed per naming law §7).
      One painter + thin-tentacle SDK for all face-rendered content (cards,
      peek, tray, chrome, CFC text); CFC scale, house text-size token (per-
      output, integer-scaled), typography, and the chamfer SDF defined once.

  P3 SCANOUT-BY-DEFAULT — a thick tentacle hands a buffer (I4) and is scanned
      out directly when it covers the output; only face content composites.
      Frame gating is P3's other half (commit nothing when nothing is dirty).

## The four axes + derived present mode (I6: law becomes a type)

  KIND       client declares:  thin | thick        (stream folds into thick)
  GEOMETRY   compositor owns:  fullscreen | standard | split
  FOCUS      compositor owns:  focused | peeked | parked
  MOTION     transient:        stationary | animating

  PRESENT MODE is a PURE FUNCTION of the four, never stored:
    scanout   = thick x fullscreen-cover x chromeless x focused x stationary
    composite = thin, or not scanout-eligible (kslate + scene, chamfer-clipped)
    gated     = output-level: no damage x no animation x no pending layout

Apps DECLARE kind + intent; they never select present-mode. Adding a future
state = adding an axis value, not re-deriving the mapping.

## The fork reality (recon 2026-09-21 — this shrinks the whole thing)

Verified in tree + headers (wlroots pinned 0.20.2):
  - Scanout is ALREADY native (SceneBuffer.OutputSample.direct_scanout,
    SceneOutput.buildState, wlr_output_is_direct_scanout_allowed) — linked,
    unwired. Card A is wiring, not a patch.
  - Present-mode selection is OUR compositor logic (the four axes). No patch.
  - Slide protocol is OUR extension (scanner-sourced). No patch.

  => The ONLY wlroots change is the CHAMFER corner-clip. wlroots 0.20.2 has no
     corner primitive at all (only wlr_scene_subsurface_tree_set_clip, which is
     RECTANGULAR). Our chamfer today is a cairo RING overlay, so thick
     tentacles' square corners punch "through the keeper."

Carry as a PATCHSET against pinned wlroots, never a fork: one concept per
commit, generic naming, rebased each release, dropped on upstream merge.

## The chamfer patch (sole wlroots change — generic, shaped for upstream)

Corner profile enum: none | square | round(r) | chamfer(d). Hits:
  1. scene buffer struct + setter (profile + depth).
  2. GLES renderer composite shader: corner SDF mask.
  3. pixman renderer: corner polygon clip (required — software path must match).
  4. scene output commit: thread the profile through the render pass.
  5. zig-wlroots bindings: expose setter + enum.

Retire the 6 cairo chamfers (chrome.zig, card_frame.zig, files_card.zig,
media.zig, dm/render.zig) + the dead GLSL stub (chamfer.frag.glsl) into one
path consuming the profile. Keep border/shadow/glow as OUR artistic render,
shared depth param. Upstream the chamfer AFTER kidulStyle is recognisable;
the painter + protocol + derivation stay in-house forever (our design).

## Cards (order — render-path first, then the patch, then our unification)

  Card A  scanout reachability (stock wlroots, IMMEDIATE): on focused
          fullscreen video, disable overlay_tree + hide wallpaper/card so
          kplayd's buffer is the sole opaque cover; verify direct scanout
          engages (log + ~2-5% CPU).
  Card B  frame gating: handleFrame skips commit on no-damage + no-animation
          + no-pending-layout; kills idle 36% without touching a client.
  Card C  chamfer patch to wlroots (the sole fork) + retire the 6 cairo chamfers.
  Card D  slide protocol (our extension) + present-mode derivation.
  Card E  kslate shared painter + house text-size token (I6).

## What dies / survives

  Dies: the undifferentiated full-scene commit; per-client chasing of the
  "thick tentacle fights the slide model" symptom; the verdict-47 placement
  wound; the kfiles font-ramp crumb; docs/law/render-path.md as a standalone law.
  Survives: the slow composite path for thin content; CFC scale law; chamfer
  SDF lesson (WARGAME-ARCH §4.2); chromeless fullscreen law (verdict 49);
  kplayd as sole player/decoder/clock (I4 in kmedia).

## Acceptance

  1. Fullscreen video: kidulwm CPU ~2-5%, RSS flat, VA-API + dmabuf scanout
     active, no jitter.
  2. Idle (terminal open, nothing changing): kidulwm CPU < ~5%, render loop
     asleep between real damage.
  3. One shared painter: all CFC text reads the house token through kslate;
     text-size token is a type, not a law.
  4. One slide protocol: zero bespoke placement/spawn framing left.
  5. Chamfer is a native wlroots primitive; no surface punches a square corner.
  6. No regression to chrome/peek/tray, focus/fullscreen laws.

## Out of scope

  - ghostty/browser forks (client-side END GAME, separate workstream).
  - presentation-timing / vsync-grid lane (verdict 44) — closed until the loop
    stops wedging.
  - Phase 1 supervisor / Phase 5 init — orthogonal.
  - NVIDIA re-cable + park — hardware hygiene, independent (re-cable verified
    done; park still owed).