# SESSION & DECK SPEC — the two-species law (2026-09-16, Barticus-locked)

Status: LOCKED. Supersedes the sentinel architecture in
`tray-slide-demolition-spec.md` (the home-slide "sentinel overlay" design
died in testing: it re-pins to the focused slot every applyLayout and can
never co-exist with other slides). The demolition list and widget
deletion of that spec STAND; what changes is what replaces them.

## The two-species law

Everything on screen is exactly one of:

1. SLIDES — walkable, quittable entries in `deck.slides`. Apps, the media
   player, fullscreen video, the home launcher. If you can WALK to it, it
   is a slide. No exceptions, no sentinel flags, no overlay citizens.
2. BANDS — permanent per-output edge furniture (left + right peek bands).
   EXIT dots, slide counts, widget readouts (clock, weather, signals,
   session charge), and their click targets. If you can SEE it but never
   walk to it, it is band. Never hidden, never focused, never walked to,
   rendered from the first frame on every output, empty deck or full.

Rubble (deleted species): overlay tray, spyglass pack as a named widget
pack, home sentinel, media sentinel, notification popover, the
widgets-off-in-fullscreen law. The fullscreen law is DELETED, not amended:
a fullscreen slide is just a wide slide; the bands stay.

Bands internally: one surface, one click router, two painters — signage
(EXIT/counts, refreshes on walk) and widgets (refresh on data change:
clock seconds, weather minutes, signals on event). Two painters because
their clocks differ wildly; one band because the user sees one thing.
Widgets are furniture, not slides: they get no walk stop, no chrome, no
quit handling, no focus transitions. A widget is a readout + one click
target; the click spawn-or-focuses its full slide (weather slide, network
slide, kmedia). Peek shows the summary; click promotes to the slide only
when asked. Bands paint at boot before any client exists (first-to-load,
always crisp) and sleep between data changes (least power).

## Ephemeral launchers

A launcher that stays open after launching is litter.

- HOME SLIDE: a real `deck.slides` entry at index 0 (compositor-owned
  surface, stock chrome per A1 of the prior spec). Walks, peeks, parks,
  quits like anything else — the "stays in the background" bug is
  impossible by construction because there is no re-pin path.
  `home_slide_open` / `empty_slot = .before_first` sentinel machinery and
  the `traySlideRefresh` re-pin are DEMOLISHED.
  - Click/activate an item → spawn/focus that slide → home slide
    destroys itself (slide flag `ephemeral = true`; the only self-closing
    slide, one flag, not an architecture).
  - Re-appears ONLY on row change (up/down onto a row with none) or
    tray_toggle. Never on a timer, never respawned behind the user.
- MEDIA PLAYER: same law. It is a normal app slide. Clicking a video
  spawns a fullscreen-video SLIDE immediately right of the player; the
  deck walks onto it; the player slips left into the peek, alive and
  visible. Quit the video slide → it destroys → the deck settles back
  onto the player. No return-index bookkeeping: the walk IS the state
  machine. The `openMediaSlide` "flag only, deck undisturbed underneath"
  sentinel is DEMOLISHED. PAUSE-ON-ASIDE (Barticus, 2026-09-21, overrides
  A4's "rides at windowed rect"): walking off a PLAYING video slide PAUSES
  it — the deck walks away, playback freezes at the windowed rect instead of
  riding. Walking back RESUMES it (live catch-up-to-edge is a follow-on when
  the IPTV rail lands).
  - Video slide spawns RIGHT of the player always, so the player is
    always one Mod4+j away and "back" is always the same direction.

## Boot & key ladder (kidulKey)

- Keyless boot → MEDIA PLAYER appliance (A5). First frame, first focus.
  No home slide exists.
- Key inserted → session unlocks → home slide auto-spawns at index 0 and
  the deck walks to it from ANYWHERE (unlock = context reset; the close
  path remembers return position anyway). Emerge transition: when the
  player was focused, the home card springs FROM the player's rect into
  its slot — the player visibly becomes the launcher, teaching the
  ladder. Stock spring integrator + one from-rect override; fallback is
  a plain peek-side spawn if the morph reads wrong. Animation only when
  the player was focused; otherwise a plain walk.
- Key stays in → session stays open. Key in = your computer; key out =
  the TV. The physical key IS the session boundary — no software lock
  screen pretending to be security.

### Charge, not leash

The key is a SESSION BATTERY, not a dongle-leash:

- Plug in → session unlocks, charge timer starts (per-user: kids 1h,
  Granny until key-out/idle, Barticus off).
- REMOVE the key → nothing bad happens; the session runs down its
  charge. The key STARTS time; it does not hold it. The key lives on a
  hook by the TV, not in the machine.
- Charge expires → PARK (below), not logout. Plug back in → resume
  exactly where you left off. A kid never loses work; a parent never
  negotiates.
- Remaining charge shows in the band next to the clock (permanent
  signage), with a warning at 5 min. No surprises, no abrupt cutoff.
- Remote gets a LOGOUT button: one press = park NOW, with the "knock at
  the door" animation — user slides dim and slide off, the appliance
  comes forward, ~2s, no confirmation dialog (nothing is lost, so no
  "are you sure" is honest). Same button is the kill switch /
  insta-pause ("Dinner.").
- Multi-user: plugging a different key while a session is live PARKS
  the current user and opens theirs (park-and-switch). Same freeze
  mechanism, so switching is free. Refusal breeds workarounds; switching
  breeds fairness.

### Park = zero energy (the four-step freeze)

1. Unmap the user's scene trees → wlroots stops rendering them → no GPU
   work, no damage, no frames.
2. SIGSTOP the user's session processes (SIGCONT on resume). Frozen
   processes consume exactly zero CPU and keep all RAM state: video
   paused mid-frame, terminals, scrollback, everything. No suspend
   dance, no client cooperation, works on misbehaving apps because the
   kernel enforces it. (Known-harmless edge: a STOPPED client can back
   up its Wayland socket; it flushes on SIGCONT. kmedia gets a cork —
   it is ours and listens.)
3. luksClose the user's volume → master key leaves the kernel keyring →
   the data is ciphertext even if the machine is seized running.
4. `keyctl` purge of the user session keyring.

Resume = key-in → open, map, SIGCONT. "Where they left off" is free
because nothing died. True resume-after-REBOOT (clients genuinely die)
is v2 — not promised now.

## Tiers of lockdown (need-for-key hierarchy)

- Tier 0 — appliance: no key. Media player, signage. Nothing to protect.
- Tier 1 — session: key was plugged, charge running. Apps, files,
  general computing. The park/switch tier.
- Tier 2 — ceremony: key PHYSICALLY PRESENT plus a fresh proof on the
  key (fingerprint preferred, PIN fallback — the proof is the token's
  job, not ours). Banking, purchases, password store, system settings.
  Tagged at the launcher / browser-shell level (our browser — enforced
  in the shell, not the honor system). No key → the slide spawns showing
  INSERT KEY. Key removed while open → THAT slide freezes instantly
  (same unmap + SIGSTOP, per-app — the kid's video does not die because
  Granny pulled the key after paying a bill). Re-proof on idle or per
  transaction, bank-style.
- Tier 2+ — continuous presence: same tier family, one boolean
  difference (presence: on-entry vs continuous). The VAULT (crypto
  seeds, GPG material): key must STAY in; removal = luksClose NOW,
  mid-session, vault slide freezes showing INSERT KEY. Plaintext exists
  only while the object is in the slot — you cannot leave the vault
  open by walking away, because walking away with your key closes it.

Threat-model honesty: the tiers defend the HOUSEHOLD (kids, visitors,
walk-aways, casual snooping). luksClose-on-park + encrypted swap (or no
swap — unencrypted swap silently defeats all of it) covers the stolen
powered-off machine. RAM-resident plaintext of parked slides is a
cold-boot/evil-maid residual: documented non-goal for v1. Fingerprint
is not doing the encryption's job; the two layers answer different
questions.

## Why this is not Qubes

Convergence acknowledged: tiers of lockdown. Divergence in mechanism:
Qubes multiplies machines (a VM per trust level plus the apparatus to
make them usable together); we divide TIME and PRESENCE on one machine
(charge, park, ceremony, continuous presence). Their cost is gigabytes
of RAM and a UX only sysadmins tolerate; ours is a SIGSTOP and a dongle
on a hook. kidulKey as a first-class session object (presence-sensed,
charge-issuing, vault-holding) is only possible because one codebase
owns the USB event, the deck, the LUKS volume, and the signage. And the
signage IS the security UX: charge countdown, INSERT KEY, the knock —
the user always knows what state the machine is in. Comprehension is a
security property. No hypervisor isolation is claimed or planned.

## Demolition list (code)

- slidedeck.zig: `home_slide_open`, `homeSlideTarget`, `empty_slot =
  .before_first` home path, `openMediaSlide`/`media_slide_open` sentinel
  path. Home + media become real `deck.slides` entries (compositor-owned
  surface kind, `ephemeral` flag on home).
- server.zig: `traySlideRefresh` re-pin → normal slide layout;
  `spyglass` field, `activateSpyglass`, spyglass PTR-CLAIM branches →
  band click router; widgets-off-in-fullscreen checks → deleted.
- ui/spyglass.zig → reborn as the band module (EXIT dots + counts +
  widget painters + one click router). Skins table survives as band
  skins. Spyglass as a server citizen dies.
- ui/tray_slide.zig → becomes the home slide's content painter (CFC
  sections), rendered by the slide path, not the overlay path.
- media sentinel wiring in core/kmedia.zig, ipc/message.zig,
  config/keybinds.zig → normal slide spawn/quit; video spawns a real
  fullscreen slide right of the player.
- NEW: session manager (charge timers per user, park/resume four-step,
  key presence events, park-and-switch), tier tags in the launcher and
  browser shell, vault volume with continuous-presence luksClose.
- Swap policy: encrypted or none.

Build order and host-deploy law unchanged (KNOWN_CMDS.md; host,
ReleaseSafe, signed B&B).
