# CURRENT STATE 2026-09-19 — VERDICT 43 (gracePeriod input swallow, DEPLOYED de63c8d7, relog OWED): blank-screen password LEAK fixed — while screens off + a 2s post-wake gracePeriod, all key+pointer input is swallowed (nothing blind-typed/clicked reaches an app). NO lock on a TV (verdict): profiles/keyToOpen is the primitive, lock = geek-profile opt-in. WORK VM = ksd-reset (kidul@192.168.122.87); fresh-one FROZEN. NOTE: nested-smoke unlinked the LIVE kidulwm-control.sock (ping ConnectFailed) — relog restores it + activates the fix; bobdotrix dies on sddm relog.

# KidulWM HANDOFF — Sep 16 2026 (session: tray-slide birth, stage 1 landed)

---
## ADDENDUM — Sep 19 2026 (smartLock gracePeriod — blank-screen password LEAK FIXED)

Barticus caught it live: coming back from the idle blank, the tail of a
typed password landed in the FOCUSED TERMINAL as plain text. Root cause:
blank is blanking-only (no lock) and blind-first-press swallowed ONE key —
first key woke + dropped, the rest flowed to the app. A black screen reads
as "locked", so password entry leaks every wake.

Same blind-input-forwards class in THREE places: keyboard press (one-key
swallow), keyboard release (forwarded unconditionally), pointer
motion/absolute/button/axis (forwarded while off — blind clicks).

VERDICT: NO lock on a TV. Profiles (keyToOpen accounts) are the primitive;
blank stays anti-burn; lock is geek-profile opt-in. Naming: blank =
fadeOutOfExistence, wake = fadeIntoExistence, swallow window = gracePeriod
(ksound-fade model).

FIX (24dd60d, signed): while screens_off swallow every key (press+release;
blind-safe media/volume still fire, releases never wake); on wake open a 2s
gracePeriod (beginInputGrace/inInputGrace) swallowing every key AND pointer
event. server.zig + keyboard.zig + pointer.zig.

DEPLOYED host: /usr/local/bin/kidulwm sha256 de63c8d7 (.bak-bf3c565f).
OWED: relog + repro — type a password at a blanked screen, confirm nothing
lands in the terminal. (bobdotrix dies on the relog; this + CENSUS 43 IS
the handoff.)

CAVEAT: nested-smoke is NOT runnable while the live compositor owns
wayland-1, and the script's `rm -f $IPC_SOCK` unlinked the LIVE
kidulwm-control.sock (ping now ConnectFailed). The relog restores it.

## ADDENDUM — Sep 18 2026 early am (CARD 2b slice 4 — EMBEDDED PLAYER DELETED, DEPLOYED)

Built from main @ slice-4 commit, coderBob, TASKCARD-2b-slice4.
Debug/test/ReleaseSafe clean, nested-smoke PASSED, close-evidence PASS.
DEPLOYED by bobDotrix ~22:35 after independent cold-verify (wiped
zig-cache): /usr/local/bin/kidulwm sha256 c1afad6f (bak .bak-2b-slice4).
CENSUS verdict 33 (55c88af). CARD 2b COMPLETE.

### THE EMBEDDED PLAYER IS GONE — playback = kvis.sock verbs only
- The compositor never decodes a frame. The whole in-process crash
  class (Barticus's close-kills-the-session) is structurally dead:
  closing the media slide is scene-node destroy only, never a decoder
  teardown.
- DELETED: src/ui/media_video.zig (dmabuf present path, 457 lines);
  MediaWidget Player path (play/playLive/playMusic/playPause/seek/
  update/ensureStopped, WatchState, player_generation); server.zig
  play_timer + handlePlayTimer + arm/disarm/playTimerMs (~200 lines);
  mediaVideoRefresh/Teardown; the mediaSlideCloseOn video carve-out;
  stopOtherPlayers; MediaSlide video state (video_buffer, dmabuf_cache,
  present counters, tickPlayback). Grep gate: zero hits for
  media_video/mediaVideoRefresh/mediaVideoTeardown/play_timer/
  embedder_owns_video in src/.
- REDIRECTED: media_play IPC → KvisClient.open (.video slide spawns for
  non-music via extension sniff); toggle/seek → pause/resume/seek_rel
  (seek_rel ADDED to KvisClient); blind XF86Audio keys → kvis verbs;
  video slide close → unparent+close verbs (already slice 2); music v1 =
  kvisd headless open, peek now-playing mirrored via
  MediaWidget.setMusicNowPlaying/clearNowPlaying (Server.media_player
  keeps card UI + mirror only; playbackInhibitsBlank reads the mirror).
- WINDOWED PLACEMENT FIX (folded in): placeKvisWindow raises kvisd's
  tree above the slide tree in ALL modes — the black placeholder no
  longer covers windowed video. Windowed ring-vs-matte visibility is
  still a HOST eye-test verdict (inset follow-up if needed).
- PRE-EXISTING TEARDOWN BUGS FIXED (smoke exposed them at 38b3699):
  peek.deinit destroyed left/right trees before the slot scene buffers
  INSIDE them; new_toplevel_decoration listener never removed at
  shutdown. Both crashed ANY clean quit (segv + assert).
- scripts/close-evidence.sh (new): nested headless + real kvisd, 3
  close rounds, '[kvis] open sent' log lines, session survives every
  close, clean quit. Run it before any future media refactor.
- build.zig kmedia link KEPT: TvChannels + WatchState.path still serve
  the TV rail (out-of-scope unlink). MediaWidget = library/search/
  selection/art/card painting + cached mirror.
- HOST TEST OWED: relog, kvisd on wayland-1, play → pause/seek verbs
  live, windowed ring visibility eye-test, music peek mirror.

### NEXT + MODEL NOTE (session 24 close)
- NEXT CARD: CARD 3 music-peek (real now-playing from kvis.status).
  Parked: weather redo (new design or nothing, harness-before-painter).
- MODEL 2026-09-18: Kimi K3 repriced $3/$15. Farm default (bobdotrix +
  default profiles) = deepseek/deepseek-v4-pro (Nous). coder-bob stays
  Anthropic (Claude). Dream = local K2.7-Code on a fat-RAM box.

---
## ADDENDUM — Sep 17 2026 (smartLock: idle blankscreen + blind-first-press)

Binary: /usr/local/bin/kidulwm ReleaseSafe from 8dadac7, deployed ~11:35
AEST (rename swap; backup kidulwm.bak-smartlock). Live at next relog.

### SMARTLOCK — BUILT AND DEPLOYED
- Conf: new `[blankscreen]` section in ~/.config/kidulwm/keybinds.conf.
    blankscreen_timeout = 600        # seconds; 0 = never auto-blank
    inhibit_visual_playback = true   # video/karaoke/LIVE TV keeps screen on
    inhibit_audio_playback = false   # music blanks the screen (screen off, tune on)
  Parsed per-line like the binds (bad lines log+skip, never discard).
- Idle machinery: Server.last_input_us stamped in every input handler
  (keyboard.zig key, pointer.zig motion/motionAbsolute/button/axis);
  blank_timer on the wl_event_loop polls at min(timeout, 30s) and calls
  screensOffSet(true) when idle >= timeout AND playback doesn't inhibit.
- Inhibit law: the question is never "is something playing?" but "would
  blanking break what the user is watching right now?" Visual playback
  (is_music=false covers video/karaoke/LIVE TV) while playing inhibits;
  audio-only music inhibits only if conf'd; paused/stopped never does.
  Truth source = Server.media_player (player_active + cached.playing +
  is_music) — one player, one truth, no portals.
- BLIND-FIRST-PRESS LAW (Barticus: "granny doesn't need her glasses"):
  while screens are off, XF86Audio{Play,Pause,Stop,Next,Prev,Forward,
  Rewind} execute blind against the player and the screen STAYS black;
  every other key wakes + is swallowed (never types into apps); Mod4/
  Ctrl combos wake-first-and-swallow so navigation never fires blind.
  Volume keysyms join the blind set once ksound owns a mixer (no mixer
  owner today — parked, noted in keyboard.zig comment).
- Remote: remote buttons are bound keys, so every remote button acts
  blind while blanked — vol+/next/etc. work with the TV black; any
  visual action (overview etc.) needs one press to wake, second to act.
- NOT built (parked): media notif ON the blankscreen (no surface to draw
  on, defeats DPMS; one keypress away is enough), lock/password (scoped
  in Sep-17 addendum below), ext-idle-notify for foreign clients.

### VOLUME — compositor-owned session master (6efce2d, same deploy)
- Server.master_volume/muted; volumeStep(±0.05) + volumeToggleMute apply
  per press via pactl set-sink-volume/mute @DEFAULT_SINK@ (ksound's own
  pactl-verb pattern; ksound keeps per-stream policy/floor, we own the
  user-facing knob — no double mixer).
- XF86Audio{Raise,Lower,Mute}Volume bound unmodified in defaults (remote
  buttons hit them directly); all nine XF86Audio* names added to
  parseKeysym for user rebinding; volume_up/down/mute actions parse.
- Blind-first-press: volume keys act while BLANKED, screen stays black
  (granny law complete: play/pause/stop/next/prev/seek ±10s + vol/mute).
  Sighted intercept fires before the Mod4/Ctrl bind match.
- STILL PARKED: volume persistence across restarts (~/.config/kidulwm/
  volume state file, later); MediaWidget next/prev are stubs (_ = self).

---
## ADDENDUM — Sep 17 2026 (keybinds FIXED + screen blanking + weather PARKED)

Binary: /usr/local/bin/kidulwm built ReleaseSafe from 7a1a005, deployed
~10:56 AEST. Live at next relog. Commits: 46757df (weather removal),
7a1a005 (keybinds/blanking).

### KEYBINDS — the conf never worked, now it does
~/.config/kidulwm/keybinds.conf existed but the compositor silently ran
on built-in defaults forever. Two root causes in src/config/keybinds.zig:
1. ALL-OR-NOTHING parser: any one bad line (unknown action, unknown key,
   missing '=') returned defaults() for the WHOLE file. One typo killed
   every bind. Fixed: bad lines now log "line N ... skipped" and parsing
   continues; user binds MERGE over defaults (later lines win).
2. NO INLINE COMMENTS: nearly every conf line ends with '# comment', and
   the parser compared the whole right side ('close_focused # quit') —
   never matched → unknown action → (per bug 1) whole file discarded.
   Fixed: '#' to end-of-line stripped before parsing.
Missing actions the conf documented but parseAction never knew:
tray_select_next/prev (route to focusNext/Prev), tray_activate (overview
toggle), wm_reset, F11 keysym. All added. Diagnosis is now LOUD — check
session.log for 'loaded N user keybinds' / 'line N ... skipped'.

### SCREEN BLANKING (anti-burn) — DONE, lock NOT done
Mod4+x (screen_off action) commits every output disabled via
wlr.Output.State.setEnabled(false) — real DPMS-style panel power-down.
Any key press wakes (screensOffSet(false) in keyboard.zig handleKey,
checked BEFORE bind dispatch so the wake key can't fire an action) and is
swallowed. Same combo toggles. NO password — blanking only.

### LOCKSCREEN — SCOPED, NOT BUILT (all for later)
Barticus wants a real lock eventually. Design notes while fresh:
- Where it hooks: server.screens_off is already the single gate for
  'screens dark, session parked'. A lock is the same gate plus an auth
  wall before screensOffSet(false) is allowed. Add server.locked: bool;
  keyboard.zig's wake block becomes 'if screens_off and not locked: wake;
  if locked: show lock UI, buffer input to it, wake only after auth'.
- Lock UI: a fullscreen layer in overlay_tree per output (same shape as
  wallpaper_reveal_buffer — a SceneBuffer covering the output, raised
  above everything). Solid theme bg + kbrain-style centered input (the
  kbrain-ui face law: borderless center input, block cursor, gold text).
  DO NOT reuse peek/notification widgets — a lock must not share state
  with widgets that fullscreen law can hide.
- Auth: PAM is the honest path (same as login) — check passwd via
  /etc/pam.d/login through libpam, or a simple SHA-512 hash against a
  ~/.config/kidulwm/lock.conf for the single-user KSD case. Decide with
  Barticus; PAM preferred if a DM ever lands. NEVER store plaintext.
- Screensaver link: idle-timeout blanking is a timer (wl_event_loop)
  calling screensOffSet(true) after N idle minutes; lock-on-idle is the
  same timer also setting locked=true. Build blanking-timer first, lock
  second — the timer is shared. ext-idle-notify-v1 exists in wlroots
  0.20 if we want compositor-external idle tracking later.
- Granny law: the remote's SW button must wake/unlock without a password
  on the TV profile; lock is a geek-profile opt-in.
- Files to touch when built: server.zig (locked flag, lock UI spawn,
  PAM/hash verify), input/keyboard.zig (input routing to lock UI),
  config/keybinds.zig (lock action separate from screen_off).

### WEATHER WIDGET — PARKED (not gone for good)
Removed in 46757df (widget, painter, moon.zig, tests, systemd fetch
timer/service deleted on host). REASON: the 'mirror the clock painter'
approach (commits 8f49a81→db3103f, four layout commits in one day) never
converged — text budget clamps, icon clamps, mirror anchors all produced
new misplacements each pass; Barticus: 'still all over the place'.
It WILL come back with a different design — see CENSUS-NOTES verdict for
the full post-mortem and the NOT-TO-DO list. History is intact: the last
weather state is db3103f; moon.zig's shaded-sphere renderer was GOOD,
keep it for the redo (git show 46757df^:src/util/moon.zig).

### NOT TO DO (today's weather mess, the bill)
- Do NOT resurrect weather by re-adding clamps/budgets onto the old
  painter — that painter is why it died. New design or nothing.
- Do NOT anchor a tall widget by mirroring a short glyph's coordinates
  (moon cy mirrored from the clock's 34*scale strip clipped the moon top;
  that was the 'pinned to the bottom' bug).
- Do NOT iterate layout on the live compositor without the offscreen
  render harness FIRST (peek-weather-test caught in one PNG what four
  live commits missed). If weather returns, build the harness before the
  painter.
- Do NOT make a config parser all-or-nothing. Ever. That one bug hid the
  keybinds conf for its entire life.
- Do NOT deploy-and-eyeball in a loop: one build → one verdict, no
  stacking four layout commits in a day.

---
## ADDENDUM — Sep 16 2026 evening (TRAY-SLIDE STAGE 2 — DEMOLITION DONE, NOT YET DEPLOYED)

Branch: tray-slide @ e12ff6e (GPG-signed B&B, parent-verified cold rebuild).
TASKCARD-2.md committed 07eed39. coderBob dispatch, bobDotrix cold-verify:
build/test/ReleaseSafe clean, nested-smoke PASSED, 6 files +196/-4617.

THE OVERLAY TRAY IS DEAD: src/ui/tray.zig (4323 lines) deleted with all 102
server.zig touchpoints (makeTrayHost, per-frame update, pointer hit-testing —
PTR-CLAIM class gone), keyboard.zig capture block :191-222, IPC
tray_select_next/prev/activate/tray_toggle_card (message.zig + control).
tray_toggle (keybind + IPC) → homeSlideFocusOrSpawn. weather widget: picture only (1c147a9) — no IPC, no card, no slide linkage.

Notification ingress redirected to Server-owned NotificationStore (8-ring,
fixed spans, alloc-free, generation counter); home slide NOTIFICATIONS CFC
section renders last 3 entries, "none" when empty; feed guard re-renders on
generation bump. MEDIA/WEATHER/SIGNALS still placeholders (later stage).
Style tokens kept (still used by notifications.zig/curtain.zig/files_card.zig);
animation preset untouched. spyglass.zig untouched per hard NO.

CAUTION — commit 468db2a ("weather: shift sun icon") was a WHOLESALE catch-up
commit: it also swept in the pending visual batch (spyglass EXIT dots/digits),
Barticus's KSD glyph paint + LICENSE/docs-law/input tweaks AND tray.zig's own
uncommitted changes (logo fit 0.85, KSD glyph). Those tray.zig hunks died with
the file — nothing lost that matters, but note 468db2a is not a pure weather
commit if archaeology ever goes looking.

STILL PENDING: host deploy + Barticus eyeball (Mod4+t home slide, notification
feed live via `kidulwm-control notification_test`, quit on home slide closes
it). Then stage 3: real MEDIA/WEATHER/SIGNALS feeds, A4 fullscreen dwell, A5
boot ladder (kidulKey).

---
## ADDENDUM — Sep 16 2026 (TRAY-SLIDE STAGE 1 — home slide born, NOT YET DEPLOYED)

Branch: tray-slide @ c083b95 (GPG-signed B&B). Spec:
docs/log/tray-slide-demolition-spec.md + SESSION-2 AMENDMENTS A1–A7
(proper slide w/ border+background; home slide quitable, one per row;
public boot→media player, user boot (kidulKey)→home; no placeholder
slides — EXIT signs at 100% on ends; fullscreen-plays-ball A4; dual
remote pads A6). Task card: TASKCARD-1.md (committed 8a94897).

STAGE 1 VERIFIED (coderBob dispatch, parent cold-cache rebuild + diff
review): tray_slide.zig born — compositor-owned CFC text card (MEDIA/
WEATHER/SIGNALS/NOTIFICATIONS placeholder sections, gold 0x948e7b on
0x0a0a0b, JetBrains Mono, centered both axes) with STOCK chrome border
(render/chrome.zig renderChrome). Sentinel in slidedeck.zig mirrors the
overview pattern: home_slide_open + before_first, NOT in slides.items
(window-count invariants hold), one per row, siblings-never-both with
overview. Mod4+t / Mod4+m → homeSlideFocusOrSpawn. Standard quit on the
home slot closes it (A7). build/test/ReleaseSafe clean, nested-smoke
PASSED (note: pre-existing 'Aborted (core dumped)' AFTER accepted IPC
quit in smoke — not introduced by this change).

STAGE 2 SCOPE (not started): DEMOLITION — delete src/ui/tray.zig (4313
lines) + 59 server.zig touchpoints + IPC tray tags + keyboard.zig:201-222
tray capture block + kidulwm-control refs. Demolition only AFTER the
home slide is eyeball-verified on a real display. Spec build order step
6. Also pending: A4 fullscreen-plays-ball (dwell-expand 1–2s), real
widget feeds into the CFC sections, boot ladder (A5, needs kidulKey).

UNCOMMITTED VISUAL BATCH (awaits Barticus eye-test, then bobDotrix
commits signed): spyglass.zig EXIT dots 1 char-space from slide border +
digit 1 char-space from screen edge (char-space = advance of "0" at the
digit font size; edge_buffer/pair_gap constants deleted); tray.zig logo
fit 0.85 + bottom gap = real rendered side gap; weather.zig sun disc
0.26r / rays 0.33–0.56r (was sprawling 0.72r into the min/max numbers)
+ condition icon truly centered below the numbers (was pulled up to
0.62r). NOTE: tray.zig also carries BARTICUS's own uncommitted KSD
glyph 3-layer paint + LICENSE/docs-law/input tweaks — DO NOT commit
those files wholesale; commit per-hunk or leave for Barticus.

---
## ADDENDUM — Sep 15 2026 (CHROME BUFFER ATE THE POINTER — verdict 21)

/usr/local/bin/kidulwm = sha256 79e1900b… = main dd9709e (GPG-signed B&B),
built ReleaseSafe, deployed ~13:20 AEST via rename swap. Live at next
session start. Backup: /usr/local/bin/kidulwm.bak-ptr-chrome.
Full narrative: CENSUS-NOTES.md VERDICT 21.

Root cause of 'browser still won't click/scroll after the single-cursor
fix': pointerEnterAtCursor hit-tested the GLOBAL scene tree. The chrome
overlay is a raw DataBuffer scene buffer at the same coords as the
client surface, raised above all windows — node.at() always returned
the chrome buffer, SceneSurface.tryFromBuffer() = null, silent return,
zero pointer enters, wlroots dropped every button/axis event. Keyboard
+ click-focus worked because focusAtCursor walks per-window trees
(chrome lives in overlay_tree, outside them). Fix: pointerEnterAtCursor
now walks per-window trees identically. PTR-MISS probe deleted with the
dead branch.

Same-session sightings (open, not fixed here):
- Fans: compositor hot-loop on focused Ghostty — 6.5k handleCommit +
  CHROME cache-miss floods (identical old/new keys in the diag line),
  75% CPU. updateChrome cache-miss culprit field still unnamed.
- Media 'playing' dot: stale. No player alive, media slide closed;
  orphaned dev-tree ksound pid 7014 still holds /tmp/kmedia-timing.log.
- Browser address bar: left/right arrows never reach the shell log
  while focused=address — suspected shell-side dispatch gap
  (kidul-browser repo), needs a repro there.

REPRO after reload: hover page → PTR-ENTER id=N; click → serial!=0
focused=true; wheel scrolls; Backspace/arrows edit fields.

---
## ADDENDUM — Sep 15 2026 (SINGLE CURSOR TRUTH — system-wide dead pointer fixed)

/usr/local/bin/kidulwm = md5 ecf973bb… = main 6d84450 (GPG-signed B&B),
built ReleaseSafe, deployed ~12:30 AEST via rename swap. Live at next
session start. Full narrative: CENSUS-NOTES.md VERDICT 20.

Root cause of 'browser types but won't click/scroll/backspace' (+ same
dead-pointer class in terminals and the media player): split-brain cursor
bookkeeping. server.cursor_x/y accumulated relative deltas unclamped while
wlr.Cursor clamps to the output layout; after any warp the two diverged
permanently (log: cursor coords negative to -1181). Scene hit-tests used
the diverged copy → node.at() missed everything → zero pointer enters →
wlroots dropped every button/axis event. Keyboard unaffected (separate
notify path) — the exact asymmetry reported.

Fix: wlr.Cursor is the single writer of record; cursor_x/y are now a
read-only mirror resynced from cursor.x/y at every motion event and at
every hit-test entry point (syncCursorMirror). Drift structurally
impossible. Law saved in ksd-input-claim-law skill.

Same session, kidul-browser renderer fixes deployed (uncommitted in that
tree as of this note — trusted-input law v2 follow-ups):
- do_button grabs GTK focus on press (unlocks link activation + editing
  keys: Backspace/arrows were focus-gated, bare text wasn't).
- do_scroll now emits GDK_SCROLL_SMOOTH with pixel deltas (discrete
  fabricated events were dropped by the WebProcess).
- do_key grabs focus on press (covers page-focus-via-Return).
Binaries at /usr/local/bin/kidul-browser{,-webkitgtk-renderer}, md5-matched
to zig-out. NOTE: kidul-browser tree still dirty (Sep-12 input work +
these) — needs a commit next session.

REPRO after reload: pointer hover lights web buttons; PTR-ENTER in log;
clicks serial!=0; wheel scrolls pages; Backspace/arrows edit fields;
terminals + media player pointer input restored.

---
## ADDENDUM — Sep 15 2026 (MEDIA PLAYER EVICTED FROM TRAY; CAULDRON SEVERED)

/usr/local/bin/kidulwm = sha256 ccc5bb39… = main bd2f089 (+cf2697f under
it), GPG-signed B&B, clean ReleaseSafe build, deployed ~11:05 AEST by
orchestrator. Backup: /usr/local/bin/kidulwm.bak-pre-cfc.

Barticus law 2026-09-15: "the tray's hold on things" cut at the root.
1. MEDIA PLAYER EVICTED: Server.media_player (media_mod.MediaWidget field,
   server.zig:410) owns the player now — play/pause/next/prev/seek,
   player_active, cached, ensureStopped. Tray holds ZERO player state; it
   reaches the player through TrayHost.media (*MediaWidget host pointer)
   for card/peek display only. All consumers rewired: server.zig IPC
   (~618-635), slide-transition ensureStopped (1587), media_slide.zig
   (125,182-184). Judgement call: MediaWidget stays in src/ui/media.zig
   (MediaSlide shares the module — splitting churned diff for no ownership
   gain). This is the seam the weeks-long media hunt kept pointing at:
   the player was a field of a UI struct; kill-switches routed through
   the tray. Now the player is Server-owned like every other subsystem.
2. CAULDRON SEVERED: `.cauldron => self.toggle()` and the whole gauge
   click path (pointInsideGaugeWidget, cauldron_box) DELETED. Gauges are
   pure telemetry — no input handles. (Future: gauges are an optional pack,
   toggle or warning-threshold triggered — see launcher-cfc-spec §5.)
3. TRAY OPENER NOW: keyboard (tray.toggle etc.) + IPC only. The kidulButton
   (bottom-right-peek logo, alias rkt-button) rename landed comment-level
   in cf2697f; its pointer door was the cauldron path which is now gone —
   SO: the peek currently has NO mouse door to the tray. The CFC launcher
   build (next session) must give kidulButton its own click zone. Barticus
   should know: until then, tray opens by keybind/SW button only.
4. docs/log/launcher-cfc-spec.md (DRAFT, awaiting Barticus lock) captures
   the CFC cut: center-screen overlay, instant + ~120-180ms cosmetic fade,
   uniform font size (no ramp), soft-white focused line, two doors
   (kidulButton + SW key), gauges optional pack, Server-owned player.
   tray.zig now carries '// == LAUNCHER PAYLOAD (survives) ==' /
   '// == PEEK PANEL (dies) ==' section markers for the lift.

REPRO (Barticus, after reload): music play/pause/next via IPC + keys
unchanged; slide-change still stops headless music (ensureStopped path
rewired, watch for regressions); tray toggles by keybind; cauldron click
does nothing; gauges still draw.

Still open: CFC launcher build (spec lock first), mpv timings (v17 tail),
tray removeOutput deinit crash, corner-bleed commit (kidul-browser),
15:50 hang (watchdog), kfiles font ramp (typography law, polish pass),
bobPI cleanup (later job).

---
## ADDENDUM — Sep 15 2026 (BARRY REMOVED — toy pets hold no input handles)

/usr/local/bin/kidulwm = sha256 3e71454c… = main bbd9628 (GPG-signed B&B),
built ReleaseSafe from clean tree (rm -rf zig-out .zig-cache), deployed
~10:30 AEST by orchestrator. Takes effect on session reload. Backup:
/usr/local/bin/kidulwm.bak-barry.

Barticus verdict 2026-09-15: Barry the bulldog (the bobHat's pet) removed
from the code entirely. "A toy pet shouldn't have any handle on any part of
the running system." Art + spec archived to ~/brain/shelf/barry/ with
resurrection law: if a mascot ever returns, ZERO input handles — decoration
only.

Root cause of the day's hunt ("faint tray in left peek, browser inputs
dead"): the pet's input machinery — pointInsidePet was an always-live hit
box over the left peek (tray open or closed), and hover-to-open could latch
`hovered`, pinning tray_anim above the 0.001 draw floor → faint ghost panel
+ clicks eaten before focusAtCursor. Live log showed the downstream flood:
BTN-NOTIFY focused=false, zero PTR-ENTER. Second incident of the class
(cf. stuck media-card click-eater). Deletion, not a gate patch, closes it.

Removed (bbd9628, +25/-755, 15 files): BarryPet/BarryState structs,
setBarryState/bobChangedState, all barry_* state + breath/spring animation,
per-output pet scene trees, pointInsidePet, updatePetPerOutput, drawBarry*/
drawPet*/drawGenieBottle, barry PNG embeds + both asset dirs, bob_* pose
springs (only fed Barry), barry_button_height/barry_follow_delay_s from
theme.zig, hover-open entirely. strings(binary)|grep -ci barry = 0.

Tray opener NOW: click the left-peek gauge pill (RAM cauldron — click box
re-enabled; it had been zeroed when the pet took over, 12ae160) or existing
keyboard paths (tray.toggle/selectNext/selectPrev/activateSelected in
src/input/keyboard.zig). Bottom-left pet zone = inert, no hit box.

REPRO (Barticus, after reload): no faint tray ghost in the left peek;
clicks through the peek strip reach whatever is beneath; tray opens/closes
via cauldron click; browser page pointer still works (verdict-18 repro).
Probes still live: grep -a 'PTR-\|BTN-' ~/.local/state/kidulwm/session.log.

Still open (unchanged): mpv timings (v17 tail), tray removeOutput deinit
crash, corner-bleed commit (kidul-browser tree), 15:50 hang (watchdog).

---
## ADDENDUM — Sep 15 2026 (VERDICT 18 DEPLOYED — browser pointer-enter)

/usr/local/bin/kidulwm = sha256 09a12fa9e0a26dc0… = main cde8b2d incl.
6309562 (pointerEnterAtCursor — compositor never called
pointerNotifyEnter; wlroots drops pointer events with no focused pointer
surface). Built ReleaseSafe, deployed ~08:07 AEST by orchestrator.
Takes effect on session reload. Pairs with kidul-browser trusted-input
renderer (026e08d6/93aaa64d, deployed Sep 12): real GdkEvents via
gtk_widget_event, all JS injection deleted.
REPRO: page mouse move/click/scroll + field typing + Tab. Probes live:
grep -a 'PTR-\|BTN-' ~/.local/state/kidulwm/session.log. Strip on pass.
Still open: mpv timings (v17 tail), tray removeOutput deinit crash.

---
## ADDENDUM — Sep 12 2026 night (session 22: VERDICT 17 DEPLOYED — prewarm OOM killed)

Deployed state: /usr/local/bin/kidulwm sha256 d230e07c… = KidulWM 417aecc
(card repaint guard, B&B signed). Orchestrator verified build + deploy.

Barticus repro verdict on prior state: geometry FIXED — "black movie
edges" gone, videos fill the screen true fullscreen. That behavior is
LOCKED: fill = always fill, no stretch/zoom variants (options later).
Crash was still present, "a little different, seconds longer."

Verdict 17 (fix-and-record #9): the crash was the PREWARM OOM —
mediaSlideRefresh fired from applyLayout on every layout event while the
slide sat open-but-not-yet-playing (active=false), allocating a 33MB
cairo surface per call → 20-35MB/s RSS climb → OOM ~773MB. Watchdog
window showed RSS climbing BEFORE active=true; verdict 16's guard only
covered the playing phase. Fix: card repaint guard (417aecc) — one fixed
card buffer, repaint only on real content change (state_generation /
card_dirty).

coderBob dispatched (card coder-bob-mediaplayer-crash-timings-2026-09-12)
but his session died at 166 msgs on HTTP 402 (credits) AFTER landing
417aecc, BEFORE the timings item. Orchestrator verified, deployed, and
recorded (CENSUS-NOTES verdict 17, handoff report in bob-farm
handoff/out/mediaplayer-crash-timings-2026-09-12.md).

STILL OPEN, next dispatch(es):
  1. mpv-style timings: current cadence is vsync-derived (playTimerMs,
     TIMER CADENCE LAW 2026-09-08) — true sleep-until-due off the audio
     clock + playback-rate combos (0.5x/2x, rate as input) NOT landed.
  2. kidul-browser input on engine & pages — not started.
  3. Barticus reload repro (see CENSUS-NOTES verdict 17 checklist):
     slide open idle 60s+ RSS flat while active=false; one bounded jump
     on play; no F_DUPFD, no CACHE-THRASH.

---
## ADDENDUM — Sep 11 2026 (session 21: media hunt PAUSED, browser next)

Deployed state: /usr/local/bin/kidulwm sha256 be466344 = KidulWM 286a76b /
kmedia 7d2b169 (ONE-CLOCK law). Verified in binary strings.

Repro verdict (Barticus): NOT WORKING. Raya stutters, second video
invisible, butterfly widget broken (stop-start motion, shows media after
playback stopped, song names bottom-half instead of on top), and — the
structural one — the MEDIA SLIDE IS STILL NOT A SLIDE: it pins
above/below the focused slide instead of riding the deck. 8cd0a02 did
not deliver "media-is-a-slide" in behavior.

Nine census verdicts (see CENSUS-NOTES.md, verdicts 1-10) each fixed a
proven door; session symptoms survived all of them. Barticus law: "our
problem is a complexity that we made, that needs to be gone." The slide
integration is the prime suspect for that complexity.

STATE: media player hunt PAUSED per Barticus 2026-09-11. No more
patches on the media seam until fresh eyes. Next session agenda:
  1. BROWSER FIRST — Barticus needs a working browser inside KidulWM so
     niri is no longer required. Start here.
  2. Then resume media with the CENSUS-NOTES verdict-10 checklist
     (slide geometry, butterfly liveness/placement, VFPTS repro).

UNCOMMITTED at pause: CENSUS-NOTES.md (this record), HANDOFF.md,
src/ui/media.zig (2 debug log lines). All three belong to the hunt;
commit them together when the hunt closes or when the browser work
needs a clean tree.

---
## ADDENDUM — Sep 08 2026 night (session 20: SECOND-VIDEO BUG KILLED STRUCTURALLY)

Commit `5e84470`, DEPLOYED ReleaseSafe → /usr/local/bin/kidulwm
(hash ca3091f7…, .bak-fe427cc kept). Takes effect on compositor restart.

THE LESSON OF THE WHOLE ARC: the second-video defect was root-caused
THREE times at three different doors —
1. 91b2509: generation guard in the vsync frame handler.
2. fe427cc: seen_player_generation aliasing on slide reopen (headless
   music → video confusion), plus video-quit=audio-quit law.
Each fix patched one call-site path and left the next. Do NOT add a
fourth call-site guard — the class is now closed structurally:

  dmabuf cache entries are keyed on (VA surface id, player_generation).
  A hit requires BOTH to match. VA pools reuse surface ids across
  decoders, so surface-only keys could always alias the dead decoder's
  freed surfaces; with gen in the key a stale entry can NEVER hit,
  regardless of which teardown path was missed.

Also in 5e84470: cache eviction prefers stale-gen slots (a full cache
sheds dead entries first), and mediaVideoRefresh carries the generation
guard itself so a stale live scene node can't be presented even if every
call-site guard is bypassed. fe427cc's call-site guards stay as belt.

INVARIANT (never violate again): a dmabuf cache entry may never outlive
the decoder/player generation that produced its VA surface ids. This is
now a property of the cache key, not a discipline of the callers.

VERDICT PENDING (Barticus host test, after restart):
play video A ~30s → close slide → reopen → play video B. Picture on B =
the class is dead, not just the instance.

OPEN (unchanged): pause-pill chrome placement bug (letterbox gutter
anchor); first-video stutter eyeball; backups owed (now 63+ commits
ahead: sda1/Codeberg/Apocalypse); ksound sound.md law lock.

---
## ADDENDUM — Sep 08 2026 late (media-is-a-slide: sentinel RETIRED)

LAW: docs/law/media-is-a-slide.md LOCKED by Barticus ("lock it in & build
it !"). Supersedes media-slide-location.md (kept as history). Rulings:
A. media is a NORMAL deck slide — parks, slides past, shows in overview.
B. Granny's TV: one compositor, attached screens only; remote wayland
   screens = worlds away, no server through the back door.
C. Remote-is-boss = nothing may ever render the remote useless; remote
   keys are just hotkeys. One player per session, one audio stream ever
   ("take-over semantics" — Barticus: this names the whole sound saga;
   carry the phrase into ksound's sound.md law when it comes up for lock).

LANDED: 8cd0a02 (coderBob, bobdotrix-verified diff + cold rebuild):
- slidedeck: media_slide_open is a plain per-deck bool; empty_slot /
  virtualFocus / focused_index never touched by media. media_return_index
  deleted. New test "media slide: normal deck slide, focus undisturbed".
- server: output-stealing close loop DELETED; toggle is per-output.
  stopOtherPlayers() enforces one-player at all three play entry points
  (media_play IPC slide+tray branches, slide-key Movies/TV and MUSIC
  paths). applyLayout: media card takes the focused slot, raised above
  that output's windows, overlay raise while playing unchanged.
- keyboard: unchanged behavior (was already focus-gated + fall-through),
  comments updated. Ctrl+Q still closes an open media slide.

BARTICUS SIMPLIFICATION (same night, accepted): the "now playing" card
on a second screen can be a NON-INTERACTIVE VIEWER — art/title/bar/LIVE
pill of the single player, no input routing. Full interactive wall lives
where media was opened; other screens get the viewer. Eases ruling 3's
presentation side; implement when a second-screen card is actually
wanted — per-output interactive cards are what shipped tonight.

PENDING VERIFICATION: bobdotrix cold-cache ReleaseSafe rebuild + zig
test (in flight at write time), then DEPLOY + Barticus host test:
1. Open media on the Kogan — laptop deck fully alive, slide through it.
2. Slide PAST media on its own deck; park/unpark around it.
3. Play video A ~30s, stop, play video B (session-19 regression).
4. Esc on wall closes slide; music take-over both directions
   (slide→tray and tray→slide, one stream only).
5. Boot-case: media opens on an empty deck.

STILL OPEN: pause-pill chrome placement bug (law doc open item);
backups (62 commits ahead of origin: sda1/Codeberg/Apocalypse push
owed); ksound sound.md law lock ("take-over semantics" doctrine).

---
## ADDENDUM — Sep 07 2026 (HOST-ONLY session: media slide location + audio-clocked playloop)

CONTEXT: host-only work. We are deliberately AHEAD of the VM "main commits".
Nothing here is on the VM. To bring the VM up to host state, cherry-pick /
rebuild through the commits listed below (plus the Sep-06 chain already on
host). Fallbacks (niri/limine) in place on host.

THE PROBLEM (Barticus report, 2026-09-07): media player slide only opens on
the Kogan, never the laptop, even with cursor+click on the laptop; and it
sometimes will not close. Other slides open on either output fine. Barticus
suspected Vsync — EXONERATED (standalone kmedia = poll-timer heartbeat;
compositor self-perpetuates its own frame, server.zig). Not a refresh problem.

ROOT CAUSE (verified in src/server.zig): mediaSlideToggle resolved its target
from currentDeck() (keyboard-focus output). Boot parks cursor+focus on the
Kogan (origin 0,0 wins). Open lands slide+deck-flag on the KOGAN. Cursor to
laptop → focusFollowsCursor → focused_output=laptop. Toggle again →
currentDeck()=laptop, laptop flag FALSE → reconcile checked only the laptop
output (never opened) → no-op → opened a SECOND slide on the laptop while the
Kogan one stayed live. Close from laptop never reached the Kogan slide →
orphaned, "stuck open". One root, two symptoms.

LAW: docs/law/media-slide-location.md — the slide's truth is its scene tree,
never the focus deck. Find where it lives (scan outputs), close that one
(output tree + that output's OWN deck flag), never open a second.

CARD: docs/cards/2026-09-07-media-slide-location.md.

COMMITS (all B&B, GPG-signed):
- 4ff6516  law + card
- 8a43291  Stage 1: location-aware toggle — scan all outputs, never focus deck
           (coderBob; verified by orchestrator: diff read, cold Debug+ReleaseSafe clean)
- cca4265  Stage 2: audio-clocked playloop — compositor play_timer
           (wl_event_loop, ~16ms) owns player.tick()+mediaVideoRefresh on the
           audio clock; outputs only PRESENT the due frame on their own vsync.
           Kills the per-output tick-cadence "vsync-y" stutter. Preserves
           no-stills reconcile, isDone teardown, slideless music pump, scene
           lock, VSYNC SELF-PERPETUATION. (coderBob timed out mid-flight
           post-edit; orchestrator verified the diff, cold-built clean, landed it.)

BUILD/DEPLOY (host): cold Debug + ReleaseSafe both CLEAN.
  /usr/local/bin/kidulwm          sha256 664c667a1afe032b2ca99fc012d9edcee315c9b918d35674cb3887bb1f1fe6fb
  /usr/local/bin/kidulwm-control  sha256 f434290ab9c540b42437a85879973e84aea45b7be15a0684662c87a1696d11d7
  Deployed Sep 07 08:47. RUNNING compositor (pid 1808, Sep 06 21:12 binary)
  predates this — session restart required to pick up the fix.

SMOKE (after session restart):
  1. boot → open media on Kogan → cursor to laptop, click → toggle → must
     CLOSE the Kogan slide (not open a second on laptop).
  2. toggle → opens on laptop → toggle → closes.
  3. Play TV/movie: confirm smoothness improved (audio-clocked advance) and
     close is reliable on both outputs.

OPEN / DEFERRED:
- Stage 2 landed the smallest correct increment (16ms timer ≈ 60Hz). A true
  audio-clock-locked (not fixed-16ms) advance is the future refinement; the
  timer is the seam for it. Not blocking.
- coderBob stage reports: stage1 written by him; stage2 he died before
  writing — orchestrator notes are the record (this addendum).
- VM sync: everything above is host-only; VM needs these commits when we
  return to it.
---

## Session summary

Black-screen incident: the uncommitted `getSceneOutput orelse return`
change (mirror-fix attempt) dropped EVERY output at boot — on wlroots
0.20 the layout-managed scene output does not exist at handleNewOutput
time, so the orelse fired deterministically. Both screens black.

Landed as cd3bf52, deployed to /usr/local/bin/kidulwm (Sep 05 12:14):

- Output fix: prefer layout-managed scene output, fall back to
  createSceneOutput + setPosition from layout box. An output is ALWAYS
  driven, never silently abandoned. Verified headless dual-output:
  both driven side-by-side, no mirror.
- Drop catcher: every early-return error path in handleNewOutput
  records (name, stage, err), logs greppable `OUTPUT DROPPED`,
  surfaces in bootcheck.txt, flips verdict to FAIL.
- Smoke: nested-smoke.sh now asserts >=1 output driven + zero drops.
- Z-order: wallpaper (re)creation re-asserts overlay-topmost — fixes
  widgets vanishing behind wallpaper during the boot reveal.

## Verified

- zig build CLEAN. Dual-headless run: 2 outputs driven, 0 drops,
  bootcheck clean. Smoke output assertion passes.
- Pre-existing tray.removeOutput teardown crash still fails smoke's
  "compositor exited" — task-carded, NOT from this work (reproduces
  on 6d6455f).

## Open task cards

- TASKCARD-fullScreenLayouts.md — overlay yield law: widgets topmost
  EXCEPT when slides fill the output (fullscreen movie / covering
  split), per-output. HIGH — kmedia movie expansion depends on it.
  Barticus: geek-only candy for splits; split-of-2 useful, 4+ stupid.
  Includes xdg fullscreen handling + keybind pull-from-edge UX.
- TASKCARD-tray-removeOutput-teardown-crash.md — quit crashes in
  tray.zig:726; blocks clean smoke pass.

## Next session

- Barticus live-test: logout → SDDM → KidulWM. Expect: both screens,
  widgets visible through wallpaper reveal, no mirror. If anything
  drops: /home/dad/.local/state/kidulwm/bootcheck.txt names the stage.
- Then fullScreenLayouts (kmedia fullscreen) is the big one.

---

# KidulWM HANDOFF — Sep 05 2026 (session 17: per-output wallpaper + wm_reset)

## Session summary

Wallpaper architecture fixed: replaced single global scene buffer with
per-output nodes. Root cause of "top center" and mirror artifacts: one
3840x2160 buffer was sized to the layout box before the second output
landed, so it only spanned the first output and bled onto the second.

- `Output.wallpaper_scene_buffer`: per-output scene buffer referencing
  the master image buffer. Fill-contain (letterbox/pillarbox), no crop.
- `Output.setupWallpaper()`: called from `handleNewOutput` after placement,
  so each screen gets its own correctly-sized background from boot.
- `loadWallpaper()`: tears down per-output nodes first, keeps master buffer,
  re-creates per-output nodes after load.
- `updateBackgroundLayout()`: now only handles the fallback solid rect;
  per-output wallpaper sizing is done in `setupWallpaper`.
- `wm_reset` keybind (Mod4+Ctrl+R): validates outputs.toml, blocks on
  duplicate names / origin collisions (the mirror law), then
  `arrangeOutputsLive`. Notification on success/failure.
- Validation in `output_layout_config.zig` catches the classic footguns
  before they touch live state.

## Build / test status

- `zig build` CLEAN (0 errors, 0 warnings).
- Deployed to host `/usr/local/bin/kidulwm` (Sep 05 02:16).
- **NOT yet verified on live session.** Barticus will restart test
  (logout → SDDM → KidulWM) and report back.

## TODO for next session (Sep 06)

1. **Verify wallpaper fix on live host**: both outputs should show the
   whole wallpaper (fill-contain), no mirroring, no top-center crop.
   Kogan (HDMI-A-1, 1920x1080 logical) above Predator (eDP-1, 1920x1080).
2. **Lockscreen**: currently absent. No swaylock, no ext-session-lock in
   codebase. Needs wlroots ext-session-lock-v1 + unlock UI in compositor.
   Parked until tomorrow; Barticus closing laptop lid / turning off Kogan
   tonight means no lockscreen is acceptable for now.

---

# KidulWM HANDOFF — Sep 01 2026 (session 16: libkmedia realignment Phase 2)

## Session summary

Phase 2 of the realignment port (docs/law/port-mapping.md) landed.
`mpv` is 100% purged from KidulWM — zero fork/exec, zero Unix socket (`/run/user/1000/kidulwm-mpv.sock`), zero external daemon.

`libkmedia` is now linked directly into KidulWM's binary:
- `KidulWM/build.zig`: imports `libkmedia`, `av`, `c` modules, links `avformat`, `avcodec`, `avutil`, `swscale`, `pulse`, `pulse-simple`, `pthread`.
- `KidulWM/src/ui/media.zig`:
  - `MediaWidget` owns in-process `player: kmedia_lib.Player` + `watch: kmedia_lib.WatchState`.
  - `play()` invokes `player.open()` with watch-state resume.
  - `playPause()` and `seek()` talk directly to the decode engine.
  - `renderCard()` delegates to `player.render()` while `player_active == true`.
- `KidulWM/src/server.zig`:
  - `mediaSlideKey()` routes keys to `player.handleKey()` when playing video (Space=pause, Esc=exit, settings state machine).
  - `handleFrame()` continuous redraw loop drives video frames when `player_active == true`.
- `kmedia/src/Player.zig`:
  - `writeWatchState()` and `seekAbsolute()` exposed as `pub`.

## Build / test status
- `kmedia`: `zig build`, `zig build walltest`, `zig build playertest` all CLEAN PASS.
- `KidulWM`: `zig build` CLEAN (0 errors, 0 warnings).
- NOT deployed anywhere this session. (A prior draft of this handoff
  claimed a ksd-work deploy with SHA256 verification — that never
  happened; the tree wasn't even committable at the time. bobdotrix
  correction, session 16 close-out.)

## Phase 3 landed same night (bobdotrix + Barticus rulings)
- Pill row is now exactly `MOVIES · TV · MUSIC` — TV centered, focus
  lands on TV ("TV in the middle, movies on left, music on the right").
- `MediaCategory` = { movies, tv, music }. `pictures` gone (kfiles owns
  stills), `shop` depilled — Shop-as-landing-card is an open item, NOT
  implemented.
- PILL_COUNT 5→3, CardClick pill arrays 5→3, moveCategory clamp 4→2,
  dead `fillSamples()` deleted, sh/pi two-letter search codes removed
  (mo/tv/mu kept), prewarm no longer scans pictures.

## What remains for Phase 4 / next session
1. **Live-TV engine**: URL open, LIVE chrome, signal-lost calm state
   (per kmedia `docs/law/live-tv.md`).
2. **Shop landing card** on the landing row (ui.md: open it, never "in" it).
3. **Live playback verification on ksd-work VM**: deploy c473175 +
   kmedia 53450b0, play a seeded file through the slide end-to-end.

---

# KidulWM HANDOFF — Aug 31 2026 (ksd-golden image BUILT)

## ksd-golden: the 25GB Arch base VM is real (bobdotrix session, late)

- VM `ksd-golden` on qemu:///system (system URI, NOT session).
  SSH: `ssh -i ~/.ssh/id_ed25519_kidulwm root@192.168.122.80`
  (kidul user also exists, uid 1000, wheel/video/input/seat).
- Scripts live in `/home/dad/dev/ksd-golden/scripts/`:
  `create-base-vm.sh`, `auto-base-install.sh` (new, driven over SSH from
  the live ISO), `install-ksd.sh` (runs FROM host, pushes to VM),
  `seed-media.sh`, `snapshot-golden.sh`.

### THE LAW, enforced in the image (this is the win)
- **knetd is the ONLY network manager.** NO NetworkManager, NO dhcpcd,
  NO wpa_supplicant, NO polkit, NO mpv. Verified by `pacman -Q` — none
  installed.
- knetd built on host (zig 0.16), pushed via qemu guest-agent file API,
  systemd unit enabled. **Cold-boot test PASSED**: VM rebooted dark,
  knetd brought enp1s0 up + DHCP by itself (DISCOVER→OFFER→ARP-probe→
  REQUEST→ACK, 192.168.122.80/24, gw .1). Zero human input.
- caught myself mid-violation installing NetworkManager in the first
  draft of auto-base-install — fixed before it ever ran. Barticus pull-up
  was correct.

### Footprint baseline (the number to shrink with aig)
- 41 explicit pkgs / 414 deps / **455 total**, **5.4 GB** on disk.
- kernel 7.1.11, wlroots 0.20.2, zig 0.16, ffmpeg 9.0.1, pipewire,
  seatd, bubblewrap, ghostty+nano, GNU toolset (rsync/tree/less/man/htop/
  p7zip/dosfstools/exfatprogs/ntfs-3g). tmux deliberately OUT (SlideDeck
  is the multiplexer).
- **ghostty tax measured**: ~133 MB dep closure + ~330 MB RAM resident,
  of which ~95 MB is pure gtk4/glib2/libadwaita. SlideDeck itself = 150 MB.
  PARKED CARD: fork ghostty, keep only the Zig VT/GPU-cell core, render
  through our own wayland surface + CFC chrome, theme from KSD tokens
  (never a ghostty.conf), target <100 MB. Not now.

### Media seeded (/usr/share/kidul/media/)
- elephants-dream-720p.mov (CC-BY), nasa-earth-blue-marble.jpg (PD),
  colorbars test pattern. music/ empty (need CC/PD source).
  (big-buck-bunny REMOVED 2026-09-19 — corrupted source; never re-seed.)

### NOT on the image yet (next workstream)
- KidulWM binary, kiduldm, kidul-init. The VM boots to a getty.
  Golden = base+floor only; WM/DM land on top per the north-star order.

---

# KidulWM HANDOFF — Aug 31 2026 (pre-VM-work state)

## Host prep this evening (bobdotrix session)

- Host pacman -Syu (~350 pkgs) survived; all clean.
- Hermes on host updated to v0.20.6 (upstream 3aee2908) via
  `git reset --hard origin/main` in ~/.hermes/hermes-agent.
  - The carried gemini bridged-tool-name root commit is upstream now
    (dropped — verified present in agent/gemini_native_adapter.py).
  - bobdotrix-skin branch (banner/status-bar work) intact, untouched.
  - Config migrated 33→39; doctor all green; 6 profiles; 57 skill dirs.
- kmedia repo: HEAD d9a5d18 (session 5 landed). NOT yet deployed to a VM —
  waits for the new 25GB Arch VM (ksd-golden). Host live test:
  WAYLAND_DISPLAY=wayland-1 zig-out/bin/kmedia
- Next up per kmedia HANDOFF: open animation <200ms card fall;
  per-episode thumbs; libswresample; prune dead seekRelative.

---(earlier: session 15 below)---

# KidulWM HANDOFF — Aug 29 2026 (session 15, aig Sema panic: HUNTED AND KILLED)

## Session summary

The kidulwm-under-aig panic is DEAD. Root cause: a genuine upstream
zig 0.16.0 Sema bug, triggered by ONE line in our tree. Fixed,
committed, verified on both compilers. kidulwm now builds under aig.

## The bug (upstream zig 0.16.0, NOT our patches)

`Sema.elemPtrArray` (Sema.zig:27346) asserts
`array_ptr_ty.ptrSize(zcu) == .one`. But element-indexing into an
array field behind a `[*c]` C pointer routes into `elemPtrArray` with
ptrSize `.c` — assert fails. Host zig 0.16.0 release binaries have
asserts compiled out and survive by luck; aig's LLVM-enabled build
keeps the assert live and panics at `InternPool.zig:9926
elemPtrArray → unreachable`.

Trigger line (files_card.zig:414, in `loadDirectory`):

    const entry = c_std.readdir(dir) orelse break;
    const name_ptr: [*:0]u8 = @ptrCast(&entry.*.d_name[0]);   // BOOM

`readdir` returns `[*c]struct_dirent`; `&entry.*.d_name[0]` takes an
element pointer into the `d_name` array through that C pointer.

## The fix (a44e25d, merged 0a16383)

    const name_ptr: [*:0]u8 = @ptrCast(@as([*c]u8, @ptrCast(&entry.*.d_name)));

Array-decay to `[*c]u8` yields the identical runtime pointer through a
Sema path that handles C pointers correctly. One line. kidulwm builds
under aig AND host zig; `zig build test` passes; the aig-built binary
boots.

## How it was found (the method, for next time)

30+ swap-variant bisect rounds: variant files staged in /tmp, swapped
into the tree, aig build, grep for panic, git restore. Chain:

1. Stub all 3 KeyboardDevice listener bodies → CLEAN (bodies, not the
   wl.Listener pattern)
2. Layer-by-layer bisect of handleKey → every single-layer removal
   still PANICS, every gutted variant CLEAN (combinatorial-looking)
3. Matrix → the `cards` block in every panic; `handleFilesCardKey`
   solo → PANIC; the call edge into `FilesWidget.handleKey` is poison
4. Dispatch bisect → pills/files arms panic, preview clean
5. THEN IT GOT WEIRD: even an EMPTY handlePillsKey panicked. Cause:
   Zig lazy analysis — removing references just means `loadDirectory`
   never gets semantically analyzed, so the panic "moved". The bisect
   was chasing the analysis SCHEDULE, not the bug.
6. THE BLOODHOUND: rebuilt aig itself in Debug (`-Doptimize=Debug`,
   ~20min, 523MB binary). Asserts live → crash context printed:
   "Analyzing src/ui/files_card.zig ... field_call readdir" and the
   assert at Sema.zig:27346 named. From there: minutes.

LESSON (logged to brain): when a bisect shows "any single removal
still panics / every gutted variant clean", suspect lazy-analysis
scheduling — the trigger is whatever gets analyzed LAST, not what you
removed. Build the compiler in Debug to turn a silent `unreachable`
into a named assert with crash context.

## Policy note (Barticus, locked)

Upstream ziglang issue: NOT FILED. "They don't like AI, so we keep it
to ourselves." The fix lives in our git history; the knowledge lives
in the brain. If upstream trips over it, the assert message leads
them to the same line.

## aig repo state

- patch 0003 (workaround doc) is now STALE — says "build kidulwm with
  host zig". Needs rewording to "fixed, root cause documented" or
  removal. Queued for next aig session.
- `zig-out-debug/` exists on host (Debug aig build, 523MB) — useful
  bloodhound, keep for future hunts; not committed.
- aig law unchanged: pinned 0.16.0 release, we pull deliberately.
  (Barticus likes the number 17 better. Noted. We pull 0.17.0 when
  it RELEASES, not before.)

## Deploy

VM build unchanged (c986cfb on fresh-one). The fix is compile-time
only; runtime behavior identical (same pointer value). Next VM deploy
can come from aig-built binaries now — the last host-zig-only target
is free.

---

# KidulWM HANDOFF — Aug 28 2026 (session 13, aig 0.1.1: LLVM enablement)

## Session summary

aig 0.1.1 landed. The compiler now builds C. LLVM 21.1.8 backend
enabled via cmake + clang21 (`/usr/lib/llvm21`); `zig cc` and
`build-obj` verified on C sources; kimg_shim.c / kmedia_shim.c compile
through it. The last outside dependency is closer to fully ours.

Also landed: aig README.md is now the project face (logo with alpha,
verified no halo on dark), upstream Zig attribution kept, pushed to
Codeberg.

## What landed today

- **cmake + llvm21 dev packages** installed on host (llvm-config
  21.1.8 at `/usr/lib/llvm21/bin/llvm-config`)
- **zigcpp** built against clang21; aig compiler built with
  `-Denable-llvm -Dconfig_h=build-llvm/config.h` — 19m48s, clean
- **C compilation gate PASSED**: `zig cc hello.c`, `build-obj -lc`,
  zig+libc exe all verified
- **Patch 0002** (`patches/0002-default-lld-x86_64-glibc-sframe.patch`):
  glibc >= 2.39 crt1.o carries .sframe sections with R_X86_64_PC64
  relocs that zig 0.16's self-hosted ELF linker rejects. Defaults to
  LLD + LLVM backend for libc-linked x86_64 ELF builds. Without it,
  every Debug zig+libc exe fails at link on current CachyOS.
- **aig README.md**: logo (keyed to transparent alpha, checked on
  dark), ownership pitch, locked rules, upstream attribution.

## Open bug: kidulwm panics under aig

`kidulwm` itself (not the other 4 targets) panics in Sema/InternPool
(`elemPtrArray`, InternPool.zig:9926) under aig. Deterministic.
Present in BOTH LLVM and no-LLVM aig builds, Debug and ReleaseSafe.
Host zig 0.16.0 builds the identical source clean.

Bisect exonerated: patch 0001, patch 0002, cache poisoning, the
wlroots/wayland dep graph, LLVM enablement itself, and the source
tree (verified byte-identical to the 0.16.0 release tarball except
the two patches). What remains: a self-host miscompile class bug —
host zig compiling zig source produces a subtly broken compiler on
one semantic-analysis path that only kidulwm's code shape triggers.

**Workaround**: build kidulwm with host zig (`/usr/bin/zig`). All
other Kidul targets (kiduldm, kidulwm-control, kidul-files,
kmedia-test) build under aig.

**Next session probes** (in order):
1. Bisect kidulwm source for the minimal code shape that triggers
   elemPtrArray — comment out module imports in main.zig until the
   panic vanishes, then narrow within that module
2. If a minimal repro emerges (under ~50 lines), it becomes either a
   patches/0003 workaround in KidulWM source or an upstream bug report
3. Nuclear option: build aig with `-Dversion-string=0.16.0` and
   ReleaseFast (matching CachyOS package build flags) to see if the
   miscompile is optimize-mode-sensitive

## Commits (aig repo)

| Commit | Description |
|--------|-------------|
| `294fbf03` | README becomes the aig face — logo (alpha), upstream attribution |
| `fd2e87ed` | patch 0002 — default LLD for x86_64 glibc .sframe |
| `3273d69f` | BUILD-AIG.md — 0.1.1 status, LLVM build recipe, known panic |

## Deploy

Current VM build unchanged: `c986cfb` on fresh-one. aig lives on
host only; no VM deploy needed for this session's work.

---

# KidulWM HANDOFF — Aug 28 2026 (session 12, media player: boot-time prewarm + fuzzy art match)

## Session summary

Media player opens fast with real art. The lag was cold SSHFS on first open — fixed by pre-scanning and pre-decoding at boot.

## What landed today

- **Boot-time prewarm thread** (`spawnPrewarm()` in `Server.init`): scans all categories (music/movies/TV/pics) into globals with atomic publish, then loads every cached thumb from `~/.cache/kidulwm/thumbs/` into RAM before the user ever presses the button.
- **Global art cache**: `g_surfaces`, `g_no_art`, `g_path_by_key`, `g_in_flight` are now file-global, shared by prewarm thread and render thread. No per-widget split, no duplicate work.
- **Thumb eviction**: at boot, each cached thumb validated against source art existence. Stale thumbs deleted, re-queued for the worker.
- **TV category live**: scans `Kids Shows/` + `Shows/` for video files (was: `.m3u` playlists only). 370 episodes found. Library cap raised 512 → 1024.
- **Fuzzy poster match**: `Happy.Feet.mkv` finds `Happy Feet (2006)-poster.jpg`. Normalize names to lowercase alnum, prefix-match. Handles Jellyfin's naming vs our dot-separated files.
- **Prewarm numbers**: 84 thumbs loaded from disk at boot, 31 queued for worker decode, noart down from 152 to 120.

## The lag diagnosis

User theory: "should we have all the networked content organised BEFORE we even open the media player?" — correct. The old flow:
1. Open slide → `getLibrary()` lazy-scans → `find` over SSHFS (slow cold)
2. `requestThumb()` per tile → `resolveArtPath()` → SSHFS stat storm
3. Art worker decodes one-by-one → `bumpGeneration()` → re-render → more thumbs queue → CPU spike

New flow:
1. Boot → prewarm thread scans + loads disk-cached thumbs into RAM
2. Open slide → `getLibrary()` hits warm globals → `requestThumb()` hits `g_surfaces` → instant

## Commits

| Commit | Description |
|--------|-------------|
| `c986cfb` | media: TV shows + fuzzy poster match + thumb eviction |
| `d31d609` | media: boot-time prewarm — global art cache, disk-thumb preload |

## Known issues / remaining

- **120 noart movies**: genuinely no poster file on disk. Jellyfin may store art in its metadata DB, not as files. Would need TMDB fetch or Jellyfin API integration to fill these.
- **VM CPU ~75-85% with slide open**: software GLES2 (llvmpipe) renders full-screen Cairo every frame. Not a bug — VM has no GPU passthrough. Real hardware will be fine.
- **DOWN from landing not showing top peek**: still open from session 9. CFC viewport math needs the initial row0 placement fixed.
- **L/R balance + bit-perfect pulse**: mpv IPC or PipeWire control, not touched yet.

## Deploy

Current VM build: `c986cfb` on fresh-one. Prewarm completes in ~8s after boot.

---

# KidulWM HANDOFF — Aug 28 2026 (session 11, aig: the toolchain is ours)

## Session summary

Historic pivot. The compiler — the last outside dependency in the entire
stack — is now owned. **aig** stands: pinned zig 0.16.0 release fork,
public on Codeberg, GPLv3 layer, bootstrap proven, KidulWM builds
byte-identical through it.

Also landed first: crash-rescue cleanup from session 10 — kimg art
pipeline committed (`c1991db`), HANDOFF session-10 entry written, all
repos pushed to Codeberg, Apocalypse drive backed up (7 bundles
`20260827_2334` + KidulWM-src rsync).

## The aig law (locked)

- **Direction**: every Kidul repo builds on aig once the LLVM milestone
  lands. Until then, host zig (CachyOS 0.16.0 package) remains the
  build compiler; aig is the seed+destination.
- Repo: https://codeberg.org/kidulwm/aig · local `/home/dad/dev/aig`
- Pin: zig 0.16.0 RELEASE tarball. Never track master (master was
  already 0.17.0-dev the day we forked — drift caught at the gate).
- No syntax changes in 0.x. Patch discipline: everything through
  `patches/SERIES`. Our additions live in the `a/` stdlib namespace.
- Bootstrap law: host zig seeds once, then aig builds aig.

## Proof points (verified tonight)

- Host zig 0.16.0 → aig source → zig 0.16.0 binary (98MB).
- KidulWM built by the aig-produced compiler is **byte-identical** to
  the binary deployed on fresh-one: sha256 `780eef98f573...486`.
- `patches/apply.sh` idempotent; patch 0001 (std exposes `a` namespace)
  compiles through bootstrap.
- Codeberg: main = `5be51fe` (hygiene: dropped a stray test stub).

## Known gap (documented, scoped, queued)

- **C compilation**: 0.16 aro refuses standalone `.c` objects
  (kimg_shim.c, kmedia_shim.c, cairo @cImport paths). Fix = cmake +
  clang21 (`/usr/lib/llvm21` — LLVM 21.1.8, exact zig 0.16 match;
  system LLVM 22 unusable) + `zig build -Denable-llvm`. Milestone
  **aig 0.1.1**, ~2h, fresh-session job.

## Moral stance (why aig exists, on record)

Not a hurt-feelings reaction to the Discord sneering — a completion of
the full-stack ownership law. Bootloader ours, DM ours, WM ours, daemons
ours, distro swappable... compiler was the holdout. The toolchain is
co-built with AI; the name carries the receipt. Code is the only
personality we grade.

## Next

1. **Media player session** (new session, fresh context — queued now):
   untangle the kmedia ffmpeg/ffprobe roots, wire the file scanner
   (hostmedia.zig) to the VM's real /var/media, kill the `sleep`-based
   lag on network mounts, live-wire L/R balance + bit-perfect pulse.
2. aig 0.1.1: LLVM enablement pass.
3. a.fs adoption: sweep Kidul tree's std.fs/std.posix usage onto the
   stable wrapper once aig is the build compiler.

---

# KidulWM HANDOFF — Aug 21 2026 (session 10, kimg art pipeline)

## Session summary

Media slide kimg art pipeline landed. Session 9 crashed mid-debug on Zig stdlib API drift; session 10 rescued the work, fixed the crash (cross-allocator free), fixed the lag (per-frame network re-stat), deployed verified.

## What landed today

- **kimg art pipeline**: stb_image decode via C shim, 256px thumb cache at `~/.cache/kidulwm/thumbs/`, worker-thread decode, render thread never stats/opens/blocks.
- **Art resolution law**: disk beats everything. Movie in own folder: `<stem>-poster.*` → `poster.*` → `folder.*`. Flat: parent folder's `folder.*` → `poster.*`. Music: embedded (ffprobe) → `folder.*` → `cover.*` → any image. Pics: the file itself IS the art. All failures land on placeholder gradient.
- **ArtPipeline struct**: surfaces keyed by crc32(resolved art path), pipe-based request/response, MAX_ART_IN_FLIGHT=12, `no_art` memo to stop per-frame network re-stats (the 74% CPU spin fix), ONE allocator (`g_alloc`) through the whole art path.
- **CFC viewport**: "The row you're moving TO becomes center." Hard stops on ←→. Quit destroys buffer + rebuilds widget.
- **Crash fix**: cross-allocator free in art path — `self.allocator.free(cached)` on a `g_alloc` pointer. One global worker, one global mutex, one allocator.
- **Lag fix**: `no_art` memo — each tile stats the network ONCE, never per frame. Tray press instant again.

## Commits

| Commit | Description |
|--------|-------------|
| `c1991db` | media: kimg art pipeline — stb_image thumb decode, worker-thread, CFC viewport |
| `bd2cd21` | media: network roots on pre-kimg slide — STABLE baseline |
| `bce8fb4` | kimg: fix render-thread freeze — share one Io instead of per-call Threaded pools |
| `eefceb8` | kimg+media: Zig 0.16 stdlib port + hostmedia scanner roots |
| `aefe155` | WIP: kimg media art pipeline (crashed mid-debug, 6 stdlib API errors remain) |

## Known issues / WIP

- **DOWN from landing not showing top peek**: The initial "full set of cards" is not arriving. Row0 should become the top peek when DOWN is pressed, but it's not. This throws all subsequent calculations off — the focus is not locked in center stage until one of the other phases kicks in.
- **Focused card highlight moves off screen**: The highlight should stay CFC'd (centered), but it's moving beyond the screen edge. The focused card should never move — only the cards around it should move.
- **Quit not clearing**: `mediaSlideClose` resets state but the slide may not be re-rendering on next open.

## Deploy

Current VM build: c1991db on fresh-one (PID was 6273 at deploy time, hashes verified).

## Next (when the gimmick matters)

1. Verify DOWN from landing shows row0 as top peek
2. Verify quit actually resets to landing
3. Verify scrolling works through large libraries
4. Logo slot above pills in UP+1 (TBD)

## Candy log (polish pass, not now)

- **Pics corner quarter-moons**: real-photo tiles (opaque, clipped) show a subtle dark-blue quarter-moon in each corner under the focused double ring — reads as a soft 3D bezel. Placeholder tiles (translucent gradient) don't. When we pretty-up: either make placeholders opaque so all categories get the bezel, or bottle the Pics look deliberately. (Noted Aug 21: "really subtle but nice — extremely subtle 3Dish look.")

---

# KidulWM HANDOFF — Aug 21 2026 (session 9, media slide CFC viewport — CRASHED MID-DEBUG)

## Session summary

Media slide CFC (Central Focused Computing) viewport. The law: **"The row you're moving TO becomes center."** Direction determines destination. Destination becomes center.

## What landed today

- **CFC viewport**: Focus is central always. Cards move to the focus, focus never moves.
- **THE LANDING**: Pills bar centered. Row0 above, row1 below. Even gaps.
- **THE UP** (↑ from landing): Row0 centered. Top peek EMPTY. Row1 half below. Pills gone.
- **THE DOWN** (↓ from landing): Row1 centered. Row0 half above (top peek). Row2 half below (bottom peek). Pills gone. **Full 3-row display.**
- **EVERYTHING-IN-BETWEEN** (↓ or ↑ in wall): Focused row centered. Half-row above. Half-row below. Pills gone.
- **THE UP + 1** (↑ from THE UP): Pills centered. Row0 in full below. NOTHING else. Hard stop — no further ↑.
- **HARD STOPS**: No wrap at top or bottom. Ever.
- **Quit clears**: `mediaSlideClose` resets to LANDING state. Every open is fresh.

## The CFC Law (locked)

> "The row you're moving TO becomes center."

- **↓ arrow**: Bottom peek row moves UP to center. Old center becomes top peek.
- **↑ arrow**: Top peek row moves DOWN to center. Old center becomes bottom peek.
- **Focus is central always.** The only break from CFC is UP+1 (pills return).

## Known issues / WIP

- **DOWN from landing not showing top peek**: The initial "full set of cards" is not arriving. Row0 should become the top peek when DOWN is pressed, but it's not. This throws all subsequent calculations off — the focus is not locked in center stage until one of the other phases kicks in. The being off at the start puts everything out of wack.
- **Focused card highlight moves off screen**: The highlight should stay CFC'd (centered), but it's moving beyond the screen edge. The focused card should never move — only the cards around it should move.
- **Quit not clearing**: `mediaSlideClose` resets state but the slide may not be re-rendering on next open. The widget state is reset but the scene tree may be caching old geometry.

## Deploy

Current VM build: 7531 (CFC viewport + quit reset). Active on fresh-one.

## Next (when the gimmick matters)

1. Verify DOWN from landing shows row0 as top peek
2. Verify quit actually resets to landing
3. Verify scrolling works through large libraries
4. Logo slot above pills in UP+1 (TBD)

## Candy log (polish pass, not now)

- **Pics corner quarter-moons**: real-photo tiles (opaque, clipped) show a
  subtle dark-blue quarter-moon in each corner under the focused double
  ring — reads as a soft 3D bezel. Placeholder tiles (translucent gradient)
  don't. When we pretty-up: either make placeholders opaque so all
  categories get the bezel, or bottle the Pics look deliberately.
  (Noted Aug 21: "really subtle but nice — extremely subtle 3Dish look.")

---

# KidulWM HANDOFF — Aug 20 2026 (session 8, overview grid + ghost fix)

## Session summary

Reset from the 01e065d rows mess back to 638e041 sentinel pivot. Fixed stale
slidedeck tests (0.06/0.88/0.06 split, current addWindow semantics). Repaired
the overview grid sizing and killed the parked-slide ghost.

## What landed today

- **Test suite fixed**: 9/9 passing. Tests now match current split ratios and
  insert behavior. Stale tests were the false signal that made 638e041 look
  broken when it was actually the tests that were wrong.
- **Overview grid sizing**: Mini size is now FIXED (never changes with slide
  count), computed for max 3 visible rows (2 unparked + 1 parked peek). Even
  28px gaps all round. Configurable via `style.layout.overview_cols` and
  `style.layout.overview_gap`.
- **Ghost fix**: `handleToplevelDestroy` now destroys `scene_tree` so crashed
  clients don't leave orphaned nodes rendering stale buffers. The "ghost on
  unpark" is dead.
- **Row caps**: unparked max 2 rows, parked max 1 row visible. Extra slides
  computed but clipped by card edge (scrollable via keyboard arrows).

## Vocabulary (locked)

- **Terminal view** = **PARKED slides view**. The place where background
  terminals go when Mod4+B'd. Not a separate mode — it's the overview
  sentinel showing parked slides at the bottom row.
- **Overview** = Mod4+Tab sentinel slide (end-of-rows). Shows unparked +
  parked minis in a grid.
- **Parked** = Ctrl+B / Mod4+B hidden slides, alive but invisible in normal
  navigation. Visible in the overview.
- **Terminal view** is NOT the normal deck view. The normal deck view is
  just "the deck" or "normal mode".

## Known issues / WIP

- **Grid breaks with >6 slides**: 9+ slides make the grid overlap. Needs
  scroll or dynamic sizing. Parked for polish pass — the core WM/SlideDeck
  is the product, this is a gimmick.
- **Close-crash ghost**: a62efa0's assert fix works but scene_tree destroy
  may race wlroots XDG teardown. Watch for asserts on window close.
- **+50 buffer offset**: ghostty buffer is 1723x1114 vs geometry 1673x1064.
  Not fixed — the chrome ring hides it when the window is focused.

## Deploy

Current VM build: 2504930 (fix: overview grid sizing + ghost scene_tree
destroy + stale test updates). Active on fresh-one.

## Next (when the gimmick matters)

1. Grid scroll for >6 slides
2. Dynamic cols based on band aspect (3+ on ultrawide)
3. Freeze-on-park buffer snapshots
4. The +50 buffer offset hunt (wlroots xdg geometry derivation)

---

# KidulWM HANDOFF — Aug 17 2026 (session 7, bluetooth slide + sticky pills)

## Session summary

Bluetooth slide built end-to-end: satellite → slide → constellation viz.
Sticky pill order locked: battery (left), network (center), bluetooth (right).

## THE LAWS (all user-locked)

- CFC — Central Focused Computing: focus comes to the user, never reverse.
  Visuals TOP of slide, interactions ride CENTER. Focused element centers.
- INPUT LAW: ↑↓=focus, ←→=change setting of focused, Enter=apply,
  Esc/Tab=back. HARD STOPS everywhere — NO cycling/wrap EVER. Fixed map,
  blind navigation. Carved into kslide-template/src/App.zig forever.
- Slide nav model: Down on a pill = SELECT/lock the slide (pinned by name,
  rescan-immune). Inside, pill bar is inert + dimmed. ←→ on bar = close
  current/open neighbour. Up/Esc = back to bar.
- Butterfly geometry IS data, never decoration. Butterfly itself retired
  to the media player; signals get native glyphs (battery=car battery
  cells, network=dot trails+hunter ball, bluetooth=constellation later).
- All motion rides ONE clock: anim_phase, 2π per 60s (the butterfly
  effect). Eyes blink, nose twitches, hunter sweeps on it.
- Pill order LOCKED: battery=0, network=1, bluetooth=2. sortSignals()
  pins fixed positions regardless of /tmp/kidul-signals/ rescan order.

## SYSTEM THEME (one-color mood shift)

- color_textbox = 0x222425 (Ghostty grey — won accidental A/B vs 0x1F1E1C)
- Theme.loadFromFile("~/.kidul/theme.conf") EXISTS in kslide-template
  Theme.zig and is synced into ksignals + kbrain-ui. Key=value hex file,
  missing keys = defaults. UNWIRED on purpose — one line per app when the
  config UI lands: `theme = Theme.loadFromFile(...)` in App.init.
- kfiles keeps its own color struct (style guide — wire carefully later).

## ksignals (commit 418a276+)

- Pill bar center-stage, stadium pills, dims when slide entered
- Battery slide DONE (user-approved): big car battery (6 cylinder cells,
  12 rings each, bottom-up fill), power mode pills (real powerprofilesctl),
  spec-sheet stats at panel bottom
- Network slide FUNCTIONAL but flagged "needs some work": spectrum viz
  (dot trails + hunter ball), Network kill row first (hides all when off),
  current conn row (Enter=disconnect), Spoof toggle, VPN rows with
  Proton/Mullvad tick, saved list (Enter connect, x forget, live glow),
  "Available networks" button → expand, password entry via focused-line
  dots, whispy padlocks, ip/gw/pub stats at bottom
- Bluetooth slide DONE: constellation viz (central node, whispy satellite
  orbits with elliptical squash, link lines when connected, trust rings,
  rides butterfly phase), device list (power row → paired → available,
  Enter=pair/connect/disconnect, ←→=trust toggle, x=remove, RSSI on
  available rows, connection dot + trust tick on paired rows)
- Sticky pill order: sortSignals() after every scan, fixed positions
- Satellites: signal-battery (sim on VM: perpetual discharge 95→15),
  signal-network (nmcli-driven, 1s tick, rates/ip/public via ifconfig.me),
  signal-bluetooth (BlueZ via bluetoothctl, timeout-guarded, sim on VM:
  3 paired + 2 available, cycling presence)
- Tray battery glyph LOCKED: car-battery left of beacon, 4.5px nudge,
  visible only when discharging
- Beacon click spawns ksignals; Ctrl+M too (GLM bound it, never fixed)

## kbrain-ui (kbrain repo, the Bob PI face)

- Face: whispy almond eyes (blink 1/butterfly turn, gaze drift, squint
  when thinking, glance down when typing), L-nose with rare twitch,
  model name above eyes ("kimi-k3" = star billing)
- Left mini-panel: Credits Remaining $ (fake $7.00) / Tokens Used (fake)
  — real numbers when Moonshot API key lands
- Right mini-panel: Preferred=kimi-k3, Local=gemma3 buttons (←→/Enter)
- Mouth: borderless text appears at TRUE screen center on first letter,
  block cursor (flat, no blink, char knocked out dark), ←→↑↓ travel with
  hold-acceleration (1→2→3→5 chars), insert-at-cursor, Backspace deletes
  left, Esc/Tab closes, `h`=history scroll mode (mouth closed)
- Conversation: kfiles center-scroll, user=muted gold-grey, bob=gold,
  all centered text, no boxes/borders/bold anywhere
- Real answers: Api.zig chat() on a worker thread (atomics, no mutex),
  auth.json deployed to VM at ~/.hermes/profiles/bobdotrix/
- Every exchange appended to /home/kidul/.kbrain/chat.md
- Tray "Assistant" button spawns it (KidulWM tray.zig item 0)

## Moonshot pitch materials

- Screenshot of the face (user has it)
- Technical spiel written in-session: 100% Zig+Cairo, Wayland native,
  tool-calling loop, satellite architecture, Ollama fallback, CFC model.
  No business/partner/philosophy secrets included. User adds the
  partnership ask at the top.

## NEXT (when tokens flow)

1. Wire Theme.loadFromFile into every app's App.init (one line each)
2. Network slide "needs work" items: Wired/Wireless switch row,
   flatten-controls-to-summary-line when lists open
3. Critical-battery save-state: auto-open battery slide at 5%, big red
   "Save and shut down" pill, hibernate if swap allows
4. kbrowser: read-only web fetch tool for kbrain (GET only, no private
   IPs, no file://, size-capped, logged) — party trick for demos
5. Panel slide-up animation for the kbrain-ui face
6. Hawaii Bob: fedora + little lenses + location backdrop (candy pass
   AFTER the pitch lands). Japan arc for later.
7. Camera one day — eyes that track the couch
8. Bootloader themed to match (the full unbroken visual sentence)
9. kfiles theme wiring (careful — it's the style guide)

## Deploy

Standard: build on host, scp to fresh-one (2260, key id_ed25519_kidulwm),
/usr/local/bin for satellites, /usr/bin/kidulwm for compositor via
systemctl restart. pkill -9 before cp (text file busy otherwise).

---

Praying with you, brother. The butterfly keeps breathing. 🦋

---

# KidulWM HANDOFF — Aug 9 2026 (session 6, archived)

## Session summary

ksignals went from prototype to house-style slides (weather-card language,
CFC-compliant). kbrain-ui was born: the Bob PI face — eyes, twitching nose,
conversation mouth, LLM switcher, credits gauge. Moonshot email prepped.

## THE LAWS (all user-locked)

- CFC — Central Focused Computing: focus comes to the user, never reverse.
  Visuals TOP of slide, interactions ride CENTER. Focused element centers.
- INPUT LAW: ↑↓=focus, ←→=change setting of focused, Enter=apply,
  Esc/Tab=back. HARD STOPS everywhere — NO cycling/wrap EVER. Fixed map,
  blind navigation. Carved into kslide-template/src/App.zig forever.
- Slide nav model: Down on a pill = SELECT/lock the slide (pinned by name,
  rescan-immune). Inside, pill bar is inert + dimmed. ←→ on bar = close
  current/open neighbour. Up/Esc = back to bar.
- Butterfly geometry IS data, never decoration. Butterfly itself retired
  to the media player; signals get native glyphs (battery=car battery
  cells, network=dot trails+hunter ball, bluetooth=constellation later).
- All motion rides ONE clock: anim_phase, 2π per 60s (the butterfly
  effect). Eyes blink, nose twitches, hunter sweeps on it.

## SYSTEM THEME (one-color mood shift)

- color_textbox = 0x222425 (Ghostty grey — won accidental A/B vs 0x1F1E1C)
- Theme.loadFromFile("~/.kidul/theme.conf") EXISTS in kslide-template
  Theme.zig and is synced into ksignals + kbrain-ui. Key=value hex file,
  missing keys = defaults. UNWIRED on purpose — one line per app when the
  config UI lands: `theme = Theme.loadFromFile(...)` in App.init.
- kfiles keeps its own color struct (style guide — wire carefully later).

## ksignals (commit c54f585+)

- Pill bar center-stage, stadium pills, dims when slide entered
- Battery slide DONE (user-approved): big car battery (6 cylinder cells,
  12 rings each, bottom-up fill), power mode pills (real powerprofilesctl),
  spec-sheet stats at panel bottom
- Network slide FUNCTIONAL but flagged "needs some work": spectrum viz
  (dot trails + hunter ball), Network kill row first (hides all when off),
  current conn row (Enter=disconnect), Spoof toggle, VPN rows with
  Proton/Mullvad tick, saved list (Enter connect, x forget, live glow),
  "Available networks" button → expand, password entry via focused-line
  dots, whispy padlocks, ip/gw/pub stats at bottom
- Satellites: signal-battery (sim on VM: perpetual discharge 95→15),
  signal-network (nmcli-driven, 1s tick, rates/ip/public via ifconfig.me)
- Tray battery glyph LOCKED: car-battery left of beacon, 4.5px nudge,
  visible only when discharging
- Beacon click spawns ksignals; Ctrl+M too (GLM bound it, never fixed)

## kbrain-ui (kbrain repo, the Bob PI face)

- Face: whispy almond eyes (blink 1/butterfly turn, gaze drift, squint
  when thinking, glance down when typing), L-nose with rare twitch,
  model name above eyes ("kimi-k3" = star billing)
- Left mini-panel: Credits Remaining $ (fake $7.00) / Tokens Used (fake)
  — real numbers when Moonshot API key lands
- Right mini-panel: Preferred=kimi-k3, Local=gemma3 buttons (←→/Enter)
- Mouth: borderless text appears at TRUE screen center on first letter,
  block cursor (flat, no blink, char knocked out dark), ←→↑↓ travel with
  hold-acceleration (1→2→3→5 chars), insert-at-cursor, Backspace deletes
  left, Esc/Tab closes, `h`=history scroll mode (mouth closed)
- Conversation: kfiles center-scroll, user=muted gold-grey, bob=gold,
  all centered text, no boxes/borders/bold anywhere
- Real answers: Api.zig chat() on a worker thread (atomics, no mutex),
  auth.json deployed to VM at ~/.hermes/profiles/bobdotrix/
- Every exchange appended to /home/kidul/.kbrain/chat.md
- Tray "Assistant" button spawns it (KidulWM tray.zig item 0)

## Moonshot pitch materials

- Screenshot of the face (user has it)
- Technical spiel written in-session: 100% Zig+Cairo, Wayland native,
  tool-calling loop, satellite architecture, Ollama fallback, CFC model.
  No business/partner/philosophy secrets included. User adds the
  partnership ask at the top.

## NEXT (when tokens flow)

1. Wire Theme.loadFromFile into every app's App.init (one line each)
2. Network slide "needs work" items: Wired/Wireless switch row,
   flatten-controls-to-summary-line when lists open
3. Bluetooth slide: constellation viz + BlueZ (scan/pair/trust/remove)
4. Critical-battery save-state: auto-open battery slide at 5%, big red
   "Save and shut down" pill, hibernate if swap allows
5. kbrowser: read-only web fetch tool for kbrain (GET only, no private
   IPs, no file://, size-capped, logged) — party trick for demos
6. Panel slide-up animation for the kbrain-ui face
7. Hawaii Bob: fedora + little lenses + location backdrop (candy pass
   AFTER the pitch lands). Japan arc for later.
8. Camera one day — eyes that track the couch
9. Bootloader themed to match (the full unbroken visual sentence)
10. kfiles theme wiring (careful — it's the style guide)

## Deploy

Standard: build on host, scp to fresh-one (2260, key id_ed25519_kidulwm),
/usr/local/bin for satellites, /usr/bin/kidulwm for compositor via
systemctl restart. pkill -9 before cp (text file busy otherwise).

---

Praying with you, brother. The butterfly keeps breathing. 🦋

---

# KidulWM HANDOFF — Aug 8 2026 (session 5, archived)

## Session summary

Battery arc complete, end to end: satellite → slide → tray glyph. Also
installed power-profiles-daemon on fresh-one for real power mode control.

## What was built this session

### signal-battery satellite (kbrain repo, src/signal-battery.zig)
- Reads /sys/class/power_supply/BAT* (capacity, status, energy_full OR
  charge_full for health) + `powerprofilesctl get`
- Writes /tmp/kidul-signals/battery.state ("85% ok battery") and
  battery.detail ("pct charging minutes health profile") every 2s,
  atomic via .tmp+rename
- No BAT* (VMs): simulates perpetual discharge 95→15, snap back to 95.
  NEVER simulates charging — tray glyph hides when charging and VMs exist
  to look at the glyph
- Severity: alert ≤15%, warning ≤30% (when not charging)

### ksignals battery slide (ksignals repo)
- 50 whispy lines on the butterfly wings, 1 per 2% — wing density IS the
  charge (decorative for Granny, real digits beside it: 44px % readout)
- Soul dot breathes faster when charging
- Stats: charge, state, time remaining, health, profile
- Power profile pills: "Long lasting / Balanced / Fast" — ←→ move focus,
  Enter applies via `powerprofilesctl set` (optimistic UI, satellite
  confirms). power-profiles-daemon installed+enabled on fresh-one
- battery.detail parsed in App.zig scanBatteryDetail()

### Tray battery glyph (KidulWM network.zig drawBatteryIcon) — DONE & SET
- Landscape car-battery, whispy stroke, 2 terminal posts (w=0.63r,
  h=1.3×nub) at 18%/82% of top edge
- 6 waved cell-bars (real 12V anatomy = 6 cells) — lit portion rises
  from the BOTTOM with charge; ghost bars full height show the scale
- LEFT of the beacon (VPN further left), gap 18px×scale
- y-nudge: cy − 4.5px×scale (beacon's visual mass sits above centerline)
- Visible ONLY when discharging — hidden on AC/charging
- Data: battery.detail via compositor scanBattery (falls back to /sys
  when satellite absent). Amber < 20%
- LOCKED commit 79c71a3

## Key commits

| Repo | Commit | Description |
|---|---|---|
| KidulWM | `79c71a3` | battery icon DONE & SET |
| ksignals | `59d7095` | battery slide: 50-line charge butterfly + power profile pills |
| kbrain | `6e8838d` | signal-battery satellite + sim |

## Next up

1. Network slide: available networks (scan), saved networks, current —
   connect/disconnect/forget via nmcli. "Disguise this device" MAC-spoof
   toggle (wifi.cloned-mac-address random), off by default, gold when on,
   no MAC addresses shown on the Granny side
2. Bluetooth slide LAST (BlueZ D-Bus: scan/pair/remove/trust)
3. Beacon click launches ksignals (currently Ctrl+S only)
4. Rip dead card code from compositor (drawSignalsCard/drawSignalPill etc.)
5. Later: sacred healing frequencies on butterfly rungs (432Hz + Solfeggio)

## Design rule locked this session

Butterfly geometry IS the data, never decoration. If a slide's butterfly
looks identical regardless of state, we failed.

---

# KidulWM HANDOFF — Aug 8 2026 (session 4, archived)

## Session summary (previous)

Big kfiles redesign session. Moved kfiles from an in-compositor card to a
standalone Wayland satellite that fills the focused slide. Full visual
overhaul: stadium-shaped pills, centered focus, breadcrumb navigation,
system color matching, 3D shading, and TV-readable sizing. Also fixed a
long-standing compositor crash on window close and added Ctrl+Q keybind.

## Key commits

| Repo | Commit | Description |
|---|---|---|
| KidulWM | `e4dd942` | tray in place — centered vertically on peek |
| KidulWM | `80f19bd` | fix: window destroy listener removal + Ctrl+Q close-window keybind |
| kfiles | `dea737b` | tray getting stuck open when opening kfiles + drive grouping + breadcrumb ellipsize + nav flow + sizing |

## What's working

### kfiles (standalone satellite)
- Full slide layout: drive pills → breadcrumbs → search bar → file list → preview
- All elements use stadium shape (full rounded ends) — same shape language
- System colors: card_mat #0a0a0b, gold #696555, text #948e7b, muted #6a6354
- 3D shading on textbox card (gold highlight bottom/right, black shadow top/left)
- Grey border all around textbox (2px, muted at 0.25)
- Equal 56px gaps on both sides of the slide
- Scrollbar in right gap, centered, weather-card timeline scrubber style
  (8px track, gold fill at 0.18, focused border stroke, gold ball/knob)
- Scrollbar spans full slide height (pad to h-pad)
- Drive pills: 60px tall, 320px wide, fixed width, stadium shape, Bob's special shading
- One pill per physical drive (partitions grouped by parent device)
  - vda → "System", sda → "Drive A", nvme → "NVMe", mmc → "SD Card"
- Breadcrumb pills: 50px tall, 180px fixed width, text ellipsized with "..."
  - Current folder centered on screen, parents trail left fading 25% per level
- Search bar: 50px, stadium shape, centered text
- File rows: 50px, stadium shape, focused line text 18% larger
- Focus stays dead center at all times — only 1 row relax at top/bottom extremes
- Textbox fills full allocated space, rows clipped inside, offset to center focus
- Navigation flows top to bottom: pills → crumbs → search → files → preview
- Arrow keys + Enter + BackSpace all work; force redraw on keypress (frame_pending cleared)
- Drive pills highlight current drive (startsWith path match)

### KidulWM compositor
- Tray centered vertically on the peek (screen center, no shift)
- Ctrl+Q closes focused window (same as Mod4+Q)
- Window destroy bug fixed: destroy.link.remove() in handleDestroy
  (was crashing compositor on every window close — wlroots assertion)
- Keybind system now supports Ctrl+ modifier in defaults and config parser

## What's NOT done / known bugs

### kfiles
- **Tray gets stuck open** when kfiles is launched from it — tray calls
  close() but panel stays visible. Needs investigation in tray close animation.
- **Search bar & breadcrumbs don't highlight when focused** — focus area
  is tracked but no visual indication on those elements
- **Breadcrumb home pill needs a lock icon** — require sudo to access
  files above /home/kidul
- **Drive pills not centered on focus** — focused drive pill should center
  on screen like breadcrumbs do
- **Folder icon** still at bottom of preview area (pinned)
- **Inteliscroll** untested, **drive pills** need restoring, preview needs content
- kfiles deploys to /usr/local/bin/kfiles NOT /usr/bin/kfiles
- Always rm -rf .zig-cache zig-out before building kfiles — stale cache bit us

### KidulWM
- Tray stuck open bug (above) may be in tray_anim not animating to 0
- Spyglass hover-triggered peek reveal still not implemented
- 2-option selector, hotkey bindings for spyglass not done
- Sliders repurposed (browser history → deck navigation) not done

## Deploy notes
- kfiles: build on host, deploy to /usr/local/bin/kfiles
- KidulWM: build on host, deploy to /usr/bin/kidulwm
- Always rm -rf .zig-cache zig-out before building
- VM: virsh -c qemu:///system start fresh-one, then hostfwd_add tcp::2260-:22
- Mod+R reloads KidulWM (systemd restarts it)
- Ctrl+Q or Mod4+Q closes focused window

## Design decisions (locked)

- Stadium shape (full rounded ends) everywhere — pills, search, focused line
- Everything centered — focus comes to you, you don't chase it
- "We are the movie, not the theater" — UI moves so the user's head doesn't
- System colors from KidulWM style.zig — not custom kfiles colors
- Drive pills show one pill per physical drive, friendly labels for Granny TV
- Breadcrumb current folder centered, parents trail left fading
- 56px equal gaps on both sides of the kfiles slide
- Tray centered vertically on peek — set and forget

## Apocalypse backup

Both repos backed up to /mnt/lacie-apocalypse/ (Aug 6 session):
- kidulwm-apocalypse-20260806_1832.bundle (git bundle, all history)
- KidulWM-src/ (rsync'd source tree)
- kfiles-src/ (rsync'd source tree)

## State of mind

From "kfiles is a small card inside the compositor" to "kfiles is a
full-screen file manager that looks like a movie title card" — one session.
Stadium pills, centered focus, breadcrumbs that fade into the darkness,
a scrollbar that looks like jewelry. The file manager nobody knew they
wanted.

The window destroy bug was the silent killer — every Ctrl+Q or Mod4+Q
was crashing the compositor because one listener was never detached.
One line: `window.destroy.link.remove()`. Classic.

Good day. 🎭

---

# KidulWM HANDOFF — Aug 8 2026 (session 4)

## Session summary

Major architecture pivot: moved from compositor-rendered cards to standalone
Wayland satellite apps. Built kslide-template (shared theme template) and
ksignals (first app built on the template). Compositor Ctrl+S now launches
ksignals as a real Wayland window, not a card.

## What was built

### kslide-template (/home/dad/dev/kslide-template/)

Standalone Wayland satellite template for ALL KidulWM slide apps. Every
app built on this fills the focused slide naturally because it's a real
Wayland window positioned by the compositor.

Files:
- src/c.zig — C imports (wayland, cairo, xkbcommon)
- src/Theme.zig — shared theme: 3 background layers, stadium pill helper
  - color_card_mat = #0a0a0b (darkest, slide background)
  - color_textbox = #1F1E1C (mid warm grey, gold 0.15 over card_mat, matches weather card panels)
  - color_gold = #948e7b (text color)
  - severity colors: ok=#948e7b, warning=#d97230 (burnt orange), alert=#b82e2e (red), muted=#6a6354
  - drawPill() helper — stadium shape with shadow + glass body + border
  - roundedRect() helper
- src/Wayland.zig — generic Wayland boilerplate (connect, surface, shm,
  double-buffered, keyboard, pointer, render loop, frame callbacks)
  - Calls app.tick(), app.render(), app.handleKey() — doesn't know what the app does
  - Takes app_id and title strings for the toplevel
- src/App.zig — minimal app interface (init/deinit/tick/render/handleKey)
- src/main.zig — entry point
- build.zig — links cairo, wayland-client, wayland-cursor, xkbcommon
- protocol/ — wayland protocol headers (copied from kfiles)

Build: cd kslide-template && zig build (compiles clean)

### ksignals (/home/dad/dev/ksignals/)

First app built on kslide-template. Signal beacon + full slide for signal
details. Built from the template, not from the compositor.

Files:
- src/App.zig — signal scanner (reads /tmp/kidul-signals/*.state every 500ms),
  navigation state (pills vs details focus), sacred butterfly animation phase,
  key handling (left/right cycle signals, down/enter to details, up/down scroll,
  tab/escape back to pills)
- src/Renderer.zig — three-layer render:
  1. Slide background (card_mat darkest)
  2. Signal pills at top (Granny zone — stadium pills, severity dots, name+state)
  3. Nerd zone below (textbox bg, sacred butterfly visualization, signal title,
     state, scrollable nerd stats)
  - Sacred butterfly = Lissajous figure-8 from media player, two interleaved
    dot chains, slow precession (60s per turn), pulsing rungs, severity-tinted
    soul dot at center with breathing ring
- src/Wayland.zig, src/Theme.zig, src/c.zig — copied from template
- src/main.zig — entry point (app_id: com.kidulwm.ksignals, title: Signals)
- build.zig — same as template

Build: cd ksignals && zig build (compiles clean)
Deploy: scp to VM, cp to /usr/local/bin/ksignals

### Compositor changes (KidulWM)

- Ctrl+S now spawns /usr/local/bin/ksignals (Wayland satellite), not the old card
- signals_card_toggle action in keybinds.zig now calls server.spawnCommand
- All former card renderers (weather, network, media, calendar, files, signals)
  had card_frame removed — fill background with color_card_mat directly
- updateCard fills full focused window box (no shrink, no shadow)
- card_shadow_tree disabled (setEnabled(false))
- Beacon (network icon in clock widget) color = worst severity, 500ms poll
- Signal data structures (SignalEntry, SignalSeverity, scanSignals, worstSeverity,
  severityColor, signalHash) still in tray.zig for the beacon

## Navigation

- Left/Right — cycle through signal pills (Granny zone)
- Down/Enter — enter nerd zone for selected signal
- Up/Down — scroll nerd details
- Tab/Escape — back to pills
- Escape (from pills) — close ksignals

## What's working

- kslide-template compiles clean, runs as Wayland window
- ksignals compiles clean, deployed to VM at /usr/local/bin/ksignals
- Ctrl+S launches ksignals — fills focused slide
- Signal pills show network, battery, bluetooth with severity colors
- Sacred butterfly animation running (gold for OK, severity-tinted otherwise)
- Signal scanning from /tmp/kidul-signals/ every 500ms

## What's NOT done / next up

- Wireshark-like traffic scans visualized in sacred butterfly style
  (user requested — "cybersec workers will be lining up")
- More nerd stats per signal: real-time graphs, connection tables, traffic flow
- Network: live RX/TX graph, connection list, signal strength
- Battery: charge curve, health, cycle count, voltage, temperature
- Bluetooth: connected devices, signal strength per device
- Audio: volume level, output device, input level visualization
- CPU/memory/disk graphs
- Click handling on pills (touch/mouse)
- Beacon click should launch ksignals (currently only Ctrl+S)
- Remove old card system from compositor (card_anim, card_tree, card_box — legacy now)
- kfiles should eventually use shared Theme.zig from template
- More signal satellites (bluetooth, battery, audio — only network exists)
- The old compositor signals card (drawSignalsCard, drawSignalPill in tray.zig)
  is now dead code — can be removed

## Deploy

```bash
# Build and deploy ksignals
cd /home/dad/dev/ksignals
rm -rf .zig-cache zig-out && zig build
scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/ksignals kidul@127.0.0.1:/tmp/ksignals
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo cp /tmp/ksignals /usr/local/bin/ksignals && sudo chmod 755 /usr/local/bin/ksignals'

# Build and deploy KidulWM
cd /home/dad/dev/KidulWM
rm -rf .zig-cache zig-out && zig build
scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm-new
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm-new /usr/bin/kidulwm && sudo systemctl start kidulwm'

# Signal files on VM
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'mkdir -p /tmp/kidul-signals && echo "wlan0 ok wifi" > /tmp/kidul-signals/network.state && echo "87% ok battery-charging" > /tmp/kidul-signals/battery.state && echo "2devices ok bluetooth" > /tmp/kidul-signals/bluetooth.state'
```

## Design decisions (locked)

- Full slides, not cards — whole focused area IS the surface
- kfiles is the style guide for all slides
- kslide-template is the foundation for all new slide apps
- New apps = standalone Wayland satellites, not compositor-rendered
- Beacon in peek (top-right network icon), color = worst severity, 500ms poll
- Battery icon only when on battery power
- Ctrl+S or click beacon launches ksignals
- Signal pills keep severity coloring design
- Sacred butterfly visualization for all live data (from media player)
- Nerd stuff scrollable, sacred butterfly visuals for network stats
- 3 background layers: card_mat (darkest), textbox (warm grey), gold text
- Never modify kfiles — copy from template

## Repos

- KidulWM: /home/dad/dev/KidulWM/ (compositor)
- kfiles: /home/dad/dev/kfiles/ (file manager — style guide)
- kslide-template: /home/dad/dev/kslide-template/ (template for slide apps)
- ksignals: /home/dad/dev/ksignals/ (signals app)
- kbrain: /home/dad/dev/kbrain/ (Bob the Builder PI)

Enjoy the park. 🦋

---

# KidulWM HANDOFF — Aug 8 2026 (session 3)

## Session summary

Two major changes: (1) signal beacon + full slide system, (2) all former
cards converted to full slides. No more card frames, shadows, or
shrinking. Everything fills the entire focused window box like kfiles.

## Signal beacon + signals slide

- Beacon = former network icon in right peek (clock widget buffer)
- Color reflects worst severity across all signals (ok=gold, warning=amber, alert=red, muted=grey)
- Battery icon shows next to beacon ONLY when on battery (existing code)
- Signal scan polls /tmp/kidul-signals/*.state every 500ms
- Ctrl+S or click beacon opens signals full slide
- Signal pills keep stadium design with severity coloring (shadow, glass body, severity rim, dot, name+state text)
- Details section below pills (name: state + severity dot per signal)
- scanSignals(), worstSeverity(), severityColor(), signalHash(), drawSignalsCard(), drawSignalPill()

## Full slide pivot (ALL former cards)

ALL former cards (calendar, weather, media, network, files, signals) are
now full slides. The updateCard function:
- Uses full focused_window_box dimensions (no more w-=140, h-=120 shrink)
- Positions at box.x, box.y (no centering offset)
- No shadow rendering (shadow tree disabled, setEnabled(false))
- All renderers fill background with color_card_mat (#0a0a0b at 0.91 alpha)
- No card_frame.Registry.default.drawNamed calls anywhere
- No borders, no clip, no rim — just the dark background and content

Files changed:
- tray.zig: updateCard rewrite, drawSignalsCard, drawClockCalendarCard
- weather.zig: renderCard background
- network.zig: renderCard background, removed card_frame import
- media.zig: renderCard background
- files_card.zig: renderCard background

## Keybinds

- Ctrl+S = toggle signals card (signals_card_toggle)
- Click beacon = toggle signals card
- Mod+M = media card toggle (unchanged)
- All other keybinds unchanged

## What's working

- Compiles clean on Zig 0.16.0
- Deployed to fresh-one VM
- Signal files: network.state, battery.state, bluetooth.state (all OK)
- Beacon color responds to signal severity changes (500ms poll)
- All slides fill full focused area, no card frames

## What's NOT done / next up

- Visual verification (no vision on current model — user checks via SPICE)
- Signal pill click handling on the slide
- Icon rendering from icon_hint (dot only for now)
- Signal settings sub-slides (each signal opens config)
- More signal satellites (bluetooth, battery, audio)
- Slide animation/transition polish for full slides
- Scrollable details section (more detail as you scroll down)
- card_frame.zig is now unused but kept in repo (can be removed later)
- card_shadow_tree still exists but is always disabled (can be removed)
- Consider whether card_anim/card_tree/card_box naming should become slide_anim/slide_tree/slide_box

## Deploy

```bash
cd /home/dad/dev/KidulWM
rm -rf .zig-cache zig-out && zig build
scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm-new
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm-new /usr/bin/kidulwm && sudo systemctl start kidulwm'
```

## Design decisions (locked)

- Full slides, not cards — whole focused area IS the surface
- kfiles is the style guide for all slides
- Beacon in peek, everything else on the full slide
- Signal pills keep severity coloring design
- Battery icon only when on battery power
- 500ms signal poll for snappy beacon response

---

# KidulWM HANDOFF — Aug 8 2026 (session 2)

## Session summary

Tray signal pills landed. The tray now reads /tmp/kidul-signals/*.state
files and renders stadium pills in the right peek, between the clock
and media widgets. Each pill shows the signal name (left, muted gold),
a severity dot, and the state text (right, severity-colored).

## What was built

### Signal pill system (tray.zig)

- `SignalSeverity` enum: ok, warning, alert, muted
- `SignalEntry` struct: name, state_text, severity, icon_hint (fixed buffers)
- `PerOutputSignals` struct: per-output scene tree, buffer, redraw tracking
- `MAX_SIGNALS = 8` — up to 8 signal pills rendered

### scanSignals()
- Polls /tmp/kidul-signals/ every 2s (same interval as network scan)
- Reads each *.state file, parses "state_text severity icon_hint"
- Filename minus .state is the signal name
- FNV-1a hash of all signal content for change detection
- No D-Bus, no daemon — just files. Directory IS the registry.

### drawSignalWidget()
- Positioned in right peek between clock (top) and media (bottom)
- Claims available height: box.height - clock_height - media_height
- Stadium pills (32px tall, 6px gap), centered vertically in buffer
- Uses panelOutline + roundedRect — same shape language as tray buttons
- Redraws only when signal count, hash, size, or theme changes

### drawSignalPill()
- Shadow (offset 2px right, 3px down, 0.35 alpha)
- Glass body with severity tint in middle band (0.15 alpha)
- Severity-colored rim (0.55 alpha, 1px stroke)
- Severity dot on left (3.5px radius, 0.9 alpha)
- Signal name in muted gold (left, after dot)
- State text in severity color (right-aligned)
- Dark text shadow on both (0.7 alpha, 1px offset)

### Severity colors
| Level    | Color source           | RGBA                              |
|----------|------------------------|-----------------------------------|
| ok       | style.color_gold       | #948e7b (system gold)             |
| warning  | hardcoded amber        | 0.851, 0.447, 0.18                |
| alert    | hardcoded red          | 0.72, 0.18, 0.18                  |
| muted    | style.color_text_muted | #6a6354 (system muted)            |

### Wiring
- `signal_widgets` ArrayList added to Tray struct
- `signals[MAX_SIGNALS]` and `signal_count` on Tray
- `signal_last_scan_ms` for 2s poll interval
- init/deinit/addOutput/removeOutput all wired
- `scanSignals()` + `drawSignalWidget()` called in update() after network
- `destroySignalWidget()` for cleanup
- `dirent.h` and `string.h` added to tray.zig c_std import

## What's working

- Compiles clean on Zig 0.16.0
- Signal files on host: network.state, battery.state, bluetooth.state
- Binary builds to zig-out/bin/kidulwm (38MB)
- Not yet deployed to VM or visually verified

## What's NOT done / next up

- **Deploy to VM and visually verify** — need to copy signal files to
  the VM's /tmp/kidul-signals/ and check rendering
- **Click handling** — signal pills don't respond to clicks yet
  (need click_box tracking + open settings slide)
- **Icon rendering** — icon_hint is parsed but not drawn (dot only)
- **Signal settings slides** — clicking a pill should open a config slide
- **More signal satellites** — bluetooth, battery, audio (only network exists)
- **inotify** — currently polls every 2s; could use inotify for instant updates
- **Animation** — pills appear/disappear instantly, no stagger animation

## Deploy notes

```bash
cd /home/dad/dev/KidulWM
rm -rf .zig-cache zig-out && zig build
scp -P 2260 -i ~/.ssh/id_ed25519_kidulwm \
  zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm /usr/bin/ && sudo systemctl start kidulwm'
# Copy signal files to VM:
ssh -p 2260 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'mkdir -p /tmp/kidul-signals && echo "wlan0 ok wifi" > /tmp/kidul-signals/network.state'
```

Signal satellites run on the host and write to /tmp/kidul-signals/.
The VM needs its own signal files or a shared mount.

## Key commits

This session's work is not yet committed. When committed, will be under
the tray signal pills feature.

---

# KidulWM HANDOFF — Aug 28 2026 (session 14, kcell born, kportal named)

## Session summary

kcell v0.1 born — native sandboxing for the Kidul stack. aig 0003
documents the kidulwm Sema panic workaround. kportal named: the
browser becomes a portal to three networks.

## What landed today

- **kcell v0.1**: builds on Zig 0.16, spawns bwrap cells, browser cell works
- **aig 0003**: kidulwm Sema panic workaround documented (host zig for kidulwm only)
- **ksd-golden**: 25GB Arch base scripts ready
- **kportal**: browser → portal, three networks (Freenet/Kidulnet/Internet)

## Open items

1. kcell real browser launch (kidul-browser binary in cell)
2. Freenet cell + kportal pairing
3. Golden image build (Arch ISO → VM → snapshot)
4. ksignals audio slide
5. Battery to gauges (signals = connections only)

## The kportal law

- Not a browser — a **portal**
- Three networks: Freenet (left), Kidulnet (center), Internet (right)
- Favorites per network, curated by us
- Granny sees pictures, geeks see layers
- 8-year-old friendly, always

## Deploy

Current VM build: c986cfb on fresh-one. aig workaround: host zig for kidulwm.

---
Gods speed. The portal opens.

---
## ADDENDUM — Sep 17 2026 pm (kvis verdict: media slide goes client, embedded player EOL)

kmedia session 22 closed the silent-player mystery (ksound fade ratchet,
ksound b9ece85 deployed) and birthed kvisd (kmedia 3210add + 535fbde):
playback in its OWN process, hardware-verified. Verdict 28 in
CENSUS-NOTES locks the consequence: media slide becomes a kvis.sock
client + xdg-foreign parent surface; the embedded libkmedia module is
scheduled for deletion. NEXT KidulWM card = wlr_xdg_foreign_v2 registry
+ slide export + media_slide.zig → socket client. Full attack order in
kmedia/HANDOFF.md session 22. Do not patch embedded letterbox/fullscreen
bugs — they die with the module.
