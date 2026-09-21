# TASKCARD-3 — two-species demolition (2026-09-16)

Spec: `docs/log/session-and-deck-spec.md` (f518ac3, LOCKED). Branch:
`tray-slide` @ f518ac3. Parent of record: this HANDOFF addendum.

Touchpoint census (measured 2026-09-16, parent session):
- home sentinel: server.zig 53, slidedeck.zig 9, keyboard.zig 4
- media sentinel: server.zig 32, slidedeck.zig 19, media_slide.zig 2
- spyglass citizen: server.zig 17, pointer.zig 1
- widgets-off-in-fullscreen: server.zig 1
- overview sentinel: slidedeck 17, server 8 — KEPT this card (do not
  touch; home must NOT mirror the overview sentinel pattern — that
  pattern is what we are killing).

Every touchpoint gets classified DELETE or REDIRECT in the subagent's
report — never "cleaned up references". Demolition discipline:
`~/.hermes/profiles/bobdotrix/skills/kidulwm-development/references/demolition-discipline.md`.

## STAGE 1 — BAND BIRTH (spyglass reborn, spyglass citizen dies)

- NEW `src/ui/band.zig`: permanent per-output edge bands, left+right,
  rendered from first frame on every output REGARDLESS of deck state.
  Content v1: EXIT dots + slide counts (port the exit_dots skin and its
  geometry law from spyglass.zig — peek_fraction 0.06, EXIT dots 1
  char-space from slide border, count digit 1 char-space from screen
  edge) + ONE click router (click = walk to neighbor on that side).
- Bands NEVER hide. Delete no visibility toggling elsewhere yet (that is
  stage 3's widgets-off kill) but the band module itself must have no
  hide API.
- Widget painters: land the CLOCK painter only (readout, no target),
  refreshed on the minute, painted into the right band. Weather/signals/
  session-charge painters are later cards — leave clearly labeled
  placeholder hooks, wire nothing.
- THEN spyglass-as-citizen dies: `Spyglass` server field, create/destroy,
  updateOutput/setNeighbors calls, activateSpyglass, PTR-CLAIM spyglass
  branches in server.zig (17) and pointer.zig (1). spyglass.zig FILE
  stays for now (skins are referenced by band.zig) but nothing on Server
  may hold or call a `Spyglass` — grep gate: zero `spyglass` hits in
  server.zig / pointer.zig / keyboard.zig after.
- Overlay-topmost re-assert comment at server.zig:174 mentions
  widgets/spyglass — reword or drop to match reality.
- GATE: nested-smoke PASS; bands show EXIT signage identical to today's
  behavior on walk; clock readout in right band; zero spyglass citizens.

## STAGE 2 — HOME = REAL SLIDE (sentinel dies)

- NEW compositor-owned slide kind in `deck.slides` (slidedeck.zig):
  `kind = .home` (or a compositor-surface enum), `ephemeral = true` on
  home only. It is a REAL slides.items entry at index 0 — walks, peeks,
  parks, quits through the stock paths. window-count invariants that
  assumed sentinel-not-in-items must be re-checked (overview sentinel
  still uses the old pattern — do NOT disturb it this stage).
- DELETE: `home_slide_open`, `openHomeSlide/closeHomeSlide/
  toggleHomeSlide/homeSlideOpen/homeSlideTarget`, `empty_slot =
  .before_first` home path (slidedeck 9); `traySlideOpen/traySlideClose/
  traySlideRefresh` re-pin + `output.tray_slide` field + its deinit
  branch (server 53); keyboard.zig 4 home/sentinel branches.
- REDIRECT: tray_toggle / weather_card / media_card keybinds +
  homeSlideFocusOrSpawn → "focus the home slide if this row has one,
  else spawn one at index 0 and focus it". Standard quit destroys it
  (A7); no auto-respawn ever.
- EPHEMERAL LAW: activating a home-slide launcher item spawn/focuses the
  target slide, then the home slide destroys itself. (v1: the launcher
  is keyboard-only CFC — the click itemization comes with the band/row
  work; wire the SELF-EJECT on any successful launch so the law exists.)
- tray_slide.zig render code (CFC sections, notification feed,
  renderChromeToBuffer) SURVIVES as the home slide's content painter —
  it moves from "overlay painted at re-pinned rect" to "slide content
  painted at the slide's layout rect". NotificationStore ingress +
  generation repaint guard stay as-is (they are the discipline's
  redirect-before-delete pattern, already landed).
- GATE: nested-smoke PASS; Mod4+t spawns home at index 0; adding another
  slide pushes home LEFT into the peek (the reported bug — verify by
  code path: home position comes from deck layout like any slide);
  launch self-ejects; quit on home destroys it with no respawn; zero
  home_slide_open/before_first hits remain.

## STAGE 3 — VIDEO = REAL SLIDE (media sentinel dies)

- DELETE: `media_slide_open` + openMediaSlide/closeMediaSlide sentinel
  paths (slidedeck 19), the "flag only, deck undisturbed underneath"
  render substitution in server.zig (32), media_slide.zig sentinel glue
  (2). The media PLAYER becomes a normal app slide (compositor-owned
  slide kind `.media_player`), spawned at boot per A5.
- REDIRECT: starting playback spawns a fullscreen compositor-owned
  `.video` slide IMMEDIATELY RIGHT of the player slide and walks focus
  onto it; the player slips left into the peek, alive. Quit on the
  video slide destroys it; the deck settles back onto the player
  naturally — NO return-index bookkeeping.
- A4 applies to the video slide via the stock path: walking away drops
  it to its windowed rect mid-row, dwell re-expands. Reuse the A4
  machinery; do not special-case.
- DELETE the widgets-off-in-fullscreen check (server.zig, 1) — bands
  never hide; the law is repealed.
- kmedia/mpv integration (stage-2 GL/vaapi, real playback into the
  video slide's surface) is NOT this card. This card is the DECK
  mechanics: spawn-right, walk, peek, quit-settles-back, using the
  existing media placeholder/card as the player's content and a black
  (or poster) surface as the video content. Wire real playback later.
- GATE: nested-smoke PASS; play → video slide right of player, focus on
  it; walk left → player peeks; quit video → focus settles on player;
  zero media_slide_open hits remain; no widgets-off check remains.

## HARD NOs (this card)

- Do NOT touch the overview sentinel pattern (it gets its own card
  later, if ever).
- Do NOT start session machinery (park/SIGSTOP/LUKS/kidulKey) — TASKCARD-4.
- Do NOT wire real kmedia playback, weather, signals feeds.
- Do NOT "improve" band visuals beyond porting the exit_dots skin +
  clock. Minimal, surgical (AGENTS.md).
- Host law: build ReleaseSafe on host; NO deploy, NO VM. Parent
  verifies cold and Barticus deploys/eyeballs.
- `zig build`, `zig build test`, ReleaseSafe, nested-smoke all from a
  cold cache claim — report commands + outputs verbatim.
