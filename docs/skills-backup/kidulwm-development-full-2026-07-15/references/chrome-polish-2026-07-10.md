# KidulWM chrome polish session — 2026-07-10

Live iteration notes from tuning the SlideDeck compositor-owned chrome.

## User-exact palette

- Focused border: `#948e7b`  
- Unfocused border: `#5e5a4c`

These replace the interim gold/blue defaults in `src/core/style.zig` (`color_border_focused`, `color_border`, `color_gold`, `color_gold_dim`, `color_glow`).

## Geometric lessons

1. **Inner square cutout makes chamfer legs look thinner.**  
   Don't punch the interior with a plain `cairo_rectangle`. The border ring between the outer chamfer and the inner square is non-uniform. Result: sides look thick, chamfer legs look thin, faint lines appear at the inner corner.

2. **Inner chamfer must be parallel to outer chamfer.**  
   Inner depth = `max(0, d - inner_inset)`, with `inner_inset = border + extra`. The extra inset (start with `1.5` logical px) compensates for the visual thinning of diagonal legs without distorting the frame.

3. **Hidden/internal edges need chamfer-aware trimming.**  
   Simply omitting an edge from an outer-path shift leaves diagonal stubs at the seam. Draw the full ring, then clear hidden edges with `CAIRO_OPERATOR_DEST_OUT` using a strip width of `depth + border + 1`. This squares off the hidden seam cleanly.

4. **Client content will bleed past a chamfered inner hole.**  
   The rectangular client surface draws behind the overlay. Filling the corner triangles between the client rectangle and the inner chamfer with `style.color_background` prevents the "square content behind the cut" look.

5. **GTK4 apps ignore `zxdg_decoration_manager_v1` server-side mode.**  
   Set `GTK_CSD=0` and `GDK_DEBUG=no-csd` in the environment clients are launched from, or the title bar/header stays visible above the compositor frame.

## Build/test/deploy

- `zig build`
- `zig build test --summary all`
- VM offline binary swap via qcow2/nbd: `KNOWN_CMDS.md`
- Visual verification via QEMU monitor screendump; `grim` does not work because KidulWM lacks `wlr-screencopy-v1`.
