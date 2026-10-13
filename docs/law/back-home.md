# LAW — BACK and QUIT are two axes, never one button (LOCKED 2026-10-13, Barticus present)

A TV remote has two buttons left of the crosspad: back-through-app (NW) and
back-to-home (SW). They are different verbs and must never collapse into one
key.

## The two verbs

- BACK (through app) — walk UP one level inside the current app. Hard stop at
  the app's own root: no cycling, no wrap, no fall-through to home.
- QUIT / HOME (back to home) — close the focused slide and reveal the deck
  (the launcher). Destructive: the slide is gone.

## Key mapping (standard HID — input-trust.md stands)

- BACK = Escape (HID keyboard 0x29). The NW button. Already the "dismiss/back"
  key everywhere (overview close, search cancel, media card).
- QUIT = XF86HomePage (0x1008ff18). The SW button — the standard "home" key a
  TV remote emits. Same verb as Mod4+Q.
- Mod4+Q / Ctrl+Q = QUIT (close_focused). Keyboard users keep the chord.
- text-edit (BackSpace / Delete / Home / End) = a SEPARATE axis, scoped to
  text fields ONLY, never navigation. The `Home` keysym (0xff50) is
  caret-to-line-start in search — it is NOT the home button and must never be
  rebound to it.

## Media slide ladder (BACK = up one level)

  fullscreen → card      (RETIRE, card persists — fullscreen.md §3)
  search → cancel        (already cancelSearch)
  subcategory → category (closeSubcategory)
  top level → hard stop

Esc never closes the media slide. Only QUIT (XF86HomePage / Mod4+Q) does.
fullscreen.md RETIRE ≠ QUIT stands: Esc from fullscreen retires the video to
its card; QUIT tears the slide down.

## What changed

- server.zig mediaSlideKey: `Escape` no longer calls mediaSlideToggle (quit).
  It walks the ladder above.
- keyboard.zig: unmodified XF86HomePage → close_focused (the remote's home).

## Resolves

- kidul-remote "Home button: dedicated, or is Esc enough?" — dedicated: the SW
  button, XF86HomePage. Esc is BACK, not home.
