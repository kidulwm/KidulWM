# Media Player Peek Constraints — 2026-07-22

Target: bottom-right media peek widget + music card.

## Layout
- Position: bottom-right of the screen, anchored against right edge and bottom edge.
- Peek height: ~1/6 of total display height.
- Peek width: matches existing weather peek width (the non-focused strip area on the right).
- Most of the right-edge vertical space must remain free for future notifications panel.

## Visual
- Double-helix ambient glyph in border color, with small periodic-table-style markers at the cross-connections.
- Two states:
  - **Idle/no audio**: slow 12–20s ambient drift, low alpha (~0.6).
  - **Music playing**: audio energy drives curve amplitude/pitch; markers pulse on beats, accent color (gold) highlights.
- Transport controls and progress live inside the expanded card, not the peek — keep the peek minimal.

## Scope
- Music card only for this milestone.
- No video frame, no slideshow.
- No corner/edge/chrome geometry changes.

## Backend
- mpv as external process via `--input-ipc-server`.
- Zig IPC client talks to mpv over Unix socket.
- Expose `kidulwm-control media_play <path>`, `media_toggle`, `media_next`, `media_prev`, `media_seek <seconds>`.
