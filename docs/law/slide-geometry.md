# Slide geometry — single authority (reconciliation target)

Status: target only, no code yet. Locks what the slide layout must be before
the reconciliation is cut. Golden reference: fresh-one VM
(kidul@192.168.122.96), src/core/layout.zig (three COLUMNS, one recompute).

## ONE geometry authority

One place computes every slide's rect from: output size, the gap, the split
ratios (left_peek / focus / right_peek), the focused slot, and ONE vertical
origin. Nothing else multiplies positions by hand.

## The row ends are STOPS, not slides

- empty-slide-left  = the before_first stop.
- empty-slide-right = the after_last stop.
- Always present, EXIT-signed, and focus may LAND on them — the walk stops
  one-past-the-last and never wraps.
- They are GEOMETRY, never reified into the slides array.

## Compositor surfaces ride a slot, they are not sentinels

media / overview / home are compositor-owned surfaces that occupy a slot. They
never share the end-stop's name, flag, or lifecycle. Retiring a compositor
surface must never erase an end-stop.

## Vertical origin includes the logo

The single vertical origin folds in the KSD logo height. EXIT signs, widgets,
and the focused surface all derive their y from that origin. (The bug: the
logo was added but its height was never folded in, so the entire slide shifted
up by the logo height — EXITs too high, weather shoved up-and-over.)

## Scene-tree ownership

park / close DETACHES the scene tree. Hidden == off the graph, not merely
off-screen.

CONFIRMED LIVE (Barticus, 2026-09-19): the media player's scene tree survives
QUIT — the close path never destroys it. The ghost renders over the background,
under the widgets, and persists after the slide is gone. `2504930` added a
"ghost scene_tree destroy" but it does NOT fire on the media-slide close path.
The concrete fix: mediaSlideClose / close-on-quit must destroy (not just
de-activate) the media slide's scene tree.

## Symptom -> root map

- EXIT gone from the row ends  -> end-stops reified into real slides (TASKCARD-3).
- walk no longer stops 1-past-last -> end-stops removed.
- hidden slides showing in the peeks -> peek geometry does not exclude parked.
- leak over bg / under widgets -> scene tree not detached on park/close.
- EXIT too high / weather pushed up -> logo height not folded into the origin.
- media slide never reaches full focus -> media surface as a 'real slide'
  plus the focus-gate skips it.

## Outstanding (needs Barticus's call before code)

- docs/law/media-is-a-slide.md + media-slide-location.md (Sep 8) assert media
  is a "normal deck slide" — this target RETIRES that assertion. Retire both
  laws when the reconciliation lands, not before.