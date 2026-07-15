# Border fill and geometry-fit experiments (2026-07-12)

Session: testing ways to make focused SlideDeck windows fill the KidulWM border while avoiding leaks past the chamfers.

## What was tried

1. **Background rect (`bg_rect`) covering full slide target, surface scaled to target.**
   - Result: gap inside border was filled, but client CSD/background leaked past the chamfered border and ghost slides appeared after close.

2. **Surface at natural size, offset by client geometry.**
   - Goal: push CSD shadow/padding under the KidulWM border ring by moving the surface so its content area starts at the wrapper origin.
   - Result: still leaked at chamfered edges; not enough masking.

3. **Geometry-fit scaling with `sx/sy` to make content geometry exactly fill wrapper.**
   - Goal: scale the surface so its XDG geometry content box maps to the wrapper bounds, shoving CSD padding under the border ring.
   - Result: broke unmap handling and produced blank/black slides on close; reverted.

4. **Hiding `surface_tree.node` until first commit.**
   - Goal: avoid the top-left sweep during Ghostty startup by not showing the surface until a real buffer was committed.
   - Result: surfaces stayed blank permanently because the surface was not configured to a useful size while hidden.
   - Lesson: keep the surface node enabled and rely on the client to commit properly.

## What worked

- Keeping the surface node enabled at all times.
- Using a `bg_rect` behind the surface for the focused window fill.
- Cleaning up `bg_rect`, `chrome_tree`, and `dim_rect` on `handleUnmap` to avoid ghost slides.
- The empty-slot boundary peek fix (guard `applyLayout` refocus and `focusAtCursor` when `deck.empty_slot != .none`).

## Open problems

- Left peek is still visually misaligned / smaller than expected.
- Top-left sweep on window open (less critical than fill).

## Pitfalls captured in SKILL.md

- Do not hide the surface tree before the first commit; it can stay blank.
- Destroy per-window compositor nodes on unmap to prevent ghost slides.
- One change at a time; wait for visual review before the next patch.
