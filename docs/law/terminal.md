# LAW — the terminal (khostty, the "smooth operator"): fork ghostty, strip the GTK, own the screen

PROPOSED 2026-10-28, Barticus present. Renderer default below is bobdotrix's call
(Barticus: "replace the GTK4 with cairo or Pixman, whatever you think is best").

Lane: the terminal — the LAST user-facing tentacle to make ours.
Related: theme (KSD tokens), chrome (CFC corner language), input-trust (arrows
nav / Enter commits), slide-process (it is a satellite app, not a slide),
fullscreen (deck-level), licensing (ghostty is MIT — fork is clean).

## Problem

The terminal is ghostty 1.3.1 (GTK4 + libadwaita + OpenGL). On the face it
flickers across both screens and idles at ~8-14 commits/s; ~330MB resident,
~95MB of which is pure gtk4/glib2/libadwaita (HANDOFF-diary-2026-09, measured).
Two causes, one symptom:

- GTK4 + libadwaita is a standing tentacle: heavy, own theme, own input stack.
- The OpenGL renderer does per-frame GPU presents with no stable frame timing
  under our compositor — the FLICKER (this is the live complaint, not the RAM).

Three wrong shapes are already ruled out:

- CONFIG-TRIM (a slimmer ghostty.conf): the trunk is GTK4 + feature-parity VT,
  not leaves — you cannot configure the tax away. (docket #18.)
- A WRAPPER SCRIPT / spawning ghostty differently: same binary, same tax.
- RE-SKINNING GTK: theming a tentacle, not replacing it.

## Concept — fork the Zig core, own the surface + renderer

ghostty is MIT and ~367K lines of Zig. The hard 80% — the VT emulation — is
already ours to reuse. The crap is the frontend + GPU renderer. So:

  KEEP    src/terminal   (VT parser, screen/grid, scrollback, kitty-graphics,
                          OSC/DCS) + src/font (fontconfig + freetype + shaping)
          + src/termio (io_uring PTY executor) + src/config (trimmed) +
          src/input (key engine, mapped to kidul keybinds) + src/unicode +
          src/datastruct.

  STRIP   src/apprt/gtk (GTK4 + libadwaita, ~40 files) + src/renderer/opengl +
          src/renderer/metal + src/cli (most) + src/benchmark + src/inspector +
          every X11/glib/libadwaita dep.

  BUILD   a new apprt (native Wayland satellite — the kslide-template pattern
          kfiles/kmedia already use) implementing ghostty's Surface interface,
          and a new software renderer implementing its renderer interface.
          Present via wl_shm (shared memory) — no GL, no dmabuf, no GPU timing.

The integration seam is real and clean: `apprt/surface.zig` (frontend) and
`renderer/backend.zig` (cell renderer) are the two interfaces we swap. The VT
core, termio, font and input all sit behind them unchanged.

## The renderer (bobdotrix's ruling)

Software-deterministic, no GL. Default = CAIRO (house style — kfiles already
draws text + chamfered corners in cairo and never flickers). Escalation path,
only if 4K cell redraw measures slow: swap the cell hot-path to a PIXMAN cell
blitter over a FREFETYPE glyph atlas (what foot/st do), keeping cairo for the
chrome. We do NOT build the atlas speculatively — cairo first, measure, then
optimise the hot path. This kills the flicker by construction: a CPU buffer
committed over wl_shm has no GPU frame-timing surface.

## The law (properties)

1. ONE TERMINAL (Card 1.5). khostty replaces ghostty as the single terminal
   concept everywhere on the face; ghostty is uninstalled, not kept as a
   fallback. No app_id special-casing (already stripped, docket #11) returns.
2. NO GTK, NO GL, NO LIBADWAITA. The terminal is a native Wayland satellite:
   our surface, our input, our render, our lifecycle (kushd cues it).
3. SOFTWARE-DETERMINISTIC. Cells are drawn into a CPU buffer and committed via
   wl_shm. No GPU frame-timing surface -> no flicker, ~0 idle commits.
4. CFC CHROME + KSD TOKENS. The terminal's own chrome (borders, the CFC
   instruction, the word-mark) themes from the theme law — never a ghostty.conf,
   never a .conf. Config is our own, minimal, and read once at launch.
5. <100MB RESIDENT target (from ~330MB), measured on REAL i915 TV hardware —
   never the no-GPU llvmpipe VM, whose numbers lie in both directions.
6. NAMED khostty (LOCKED 2026-10-28). It is "the terminal" / "the mouth" to
   Granny, who will never see it. "kterm" was rejected as crowded — a live
   2026 C emulation library and two Kindle terminals already use it. khostty
   carries the house k and flags the ghostty lineage honestly.
7. FORK, NOT REWRITE. We keep ghostty's VT core (MIT) and write only the
   frontend + software renderer. We do not re-implement the vt parser, kitty
   graphics, or OSC — that is the point of the fork.

## Rulings (this lock)

- Q.A  renderer default = cairo (not pure pixman, not GL). Pixman+freetype atlas
       is the measured escalation, not the first cut. (bobdotrix, Barticus
       delegated.)
- Q.B  presentation = wl_shm. No dmabuf, no GL, no GPU frame-timing. (kills the
       flicker by construction.)
- Q.C  the fork is a NEW in-house repo (khostty), ghostty kept only as an upstream
       reference in dev/reference/. We do not push a 367K-line mirror to Codeberg.
- Q.D  config is OURS and minimal (font, size, colours from theme) — not a
       ghostty.conf passthrough. (Card 1.5 "never a ghostty.conf".)
- Q.E  khostty adopts the AIG fork discipline (see the aig repo): a PINNED
       ghostty base (never a moving branch), every strip a file in patches/
       SERIES applied idempotently (nothing edited in place), our Wayland
       surface + cairo renderer + a/ namespace in-repo, upstream pulled only
       deliberately. Fork what MOVES or must DIVERGE; BORROW the dormant
       bedrock (cairo/pixman/fontconfig stay un-forked).

## Reversals

- Reverses "keep ghostty as-is / trim its config" (docket #18's rejected shape).
- Reverses "a terminal needs a GPU renderer to be fast" — software cairo/pixman
  is deterministic and more than fast enough at TV scale.
- Reverses the implicit "the terminal is a special citizen" — it becomes a plain
  satellite app like kfiles.

## Open (build-time, not blocking)

- Exact seam: new apprt inside the fork vs libghostty embed ABI — whichever the
  tree supports cleanly; the law fixes the KEEP/STRIP split, the build picks the
  seam.
- Whether kitty-graphics inline images are needed for kterm now (defer; the
  terminal's job is text first).
- Scrollback perf at 4K on i915 — this is what decides cairo vs the pixman atlas.
- Font shaping depth (harfbuzz vs freetype-only) — start with ghostty's font
  module as-is, trim only if it drags the dep closure.
