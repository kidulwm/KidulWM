# MEDIA CENSUS — live hunt state (bobdotrix, started 2026-09-09)
# Read THIS FILE first in any new session during the media hunt. Update it
# after every repro/verdict. Delete/retire it into HANDOFF when done.


## 2026-09-18 VERDICT 34: kvisd classification + media focus gate (host test regressions)

Barticus host test of CARD 2b slice 4 exposed four symptoms, all ONE root:
black fullscreen, chrome/logos over the movie, kvisd-as-slide in the peeks,
and the media player holding focus when it was NOT focused.

ROOT CAUSE 1 — kvisd sets app_id AFTER toplevel creation (get_toplevel
precedes set_app_id by protocol order). handleNewXdgToplevel read
toplevel.app_id at creation → always null → never marked is_kvis → the
video surface was appended to the normal window list and became a deck
slide (black placeholder on the real video slide, chrome ring, peek
entry, focus grab). FIX: Server.classifyKvis() re-classifies on
set_app_id (window.zig handleSetAppId calls it) and unlinks the window
from the deck/windows list — no slide, no chrome, no focus.
handleToplevelDestroy now guards the double unlink (link.prev != null).

ROOT CAUSE 2 — mediaSlideKey routed keys whenever a media slide EXISTED
in the current deck, not when it was FOCUSED — media-is-a-slide.md
ruling 2 violation, re-locked by Barticus this session ("the media
player keeps focus when not in focus"). FIX: mediaSlideKey bails unless
the focused centre slide is .media_player (empty_slot check + kind
check).

ALSO: videoSlideSpawnRightOfPlayer now requestLayout() immediately so the
fullscreen flag (hide peeks, edge-to-edge, zero chrome) applies on the
same frame instead of lingering one beat behind.

KidulWM 4ea2bc7 (signed B&B). Debug/test/ReleaseSafe clean,
nested-smoke PASS, close-evidence PASS (3 close rounds). DEPLOYED
/usr/local/bin/kidulwm sha256 c0fbe08f (bak .bak-2b-focus = c1afad6f).

ENV NOTE (bobdotrix): close-evidence.sh runs `rm -f kvis.sock` then
spawns a throwaway headless kvisd — on exit it leaves the socket path
bound to a dead inode while the real kvisd listens orphaned. Symptom =
music won't play. Fix = kill orphan kvisd, `rm -f kvis.sock`, restart
kvisd on wayland-1. Verified after restart: FLAC open → playing=1 pos
advancing, ksound audio_live=1, Pulse RUNNING kmedia stream uncorked.

HOST TEST OWED (Barticus): relog → movie plays IN the fullscreen slide
(zero chrome/peeks edge-to-edge), walk deck → focus hands off instantly,
quit media slide → session + other terminal survive, music plays.

## 2026-09-17 VERDICT 33: CARD 2b slice 4 LANDED — embedded player DELETED

KidulWM (coderBob, TASKCARD-2b-slice4): the embedded libkmedia Player
path is GONE. Playback = kvis.sock verbs only; the compositor never
decodes a frame. Deleted: ui/media_video.zig (457 lines, dmabuf present
path), MediaWidget Player path (play/playLive/playMusic/playPause/seek/
update/ensureStopped + WatchState + generation machinery), server.zig
play_timer + handlePlayTimer/arm/disarm/playTimerMs (~200 lines),
mediaVideoRefresh/Teardown delegations, the mediaSlideCloseOn video
carve-out, stopOtherPlayers, and MediaSlide's whole video presentation
state (video_buffer/dmabuf_cache/present counters/tickPlayback).
REDIRECTED: media_play → KvisClient.open (+ .video slide spawn for
non-music via extension sniff); toggle/seek → pause/resume/seek_rel
(seek_rel ADDED to KvisClient); blind XF86Audio keys → kvis verbs;
slide close → nothing in-process (the crash class is structurally dead —
close is scene-node destroy only, never a decoder teardown); music v1 =
kvisd headless open with the peek now-playing mirrored via
setMusicNowPlaying/clearNowPlaying. Windowed placement folded fix:
placeKvisWindow raises kvisd's tree above the slide tree in ALL modes
(black placeholder no longer covers windowed video); windowed
ring-vs-matte visibility stays HOST-ONLY. Grep gate: media_video /
mediaVideoRefresh / mediaVideoTeardown / play_timer /
embedder_owns_video = 0 hits in src/. Debug/test/ReleaseSafe clean,
nested-smoke PASSED, close-evidence (scripts/close-evidence.sh, kvisd
live): 3 close rounds + real '[kvis] open sent' lines, session survived
every close, clean quit — THE acceptance point (Barticus's close-kill).
Also fixed two PRE-EXISTING teardown bugs the smoke exposed at 38b3699:
peek.deinit destroyed parent trees before child slot buffers, and the
xdg-decoration listener was never removed at shutdown (both crashed any
clean quit). build.zig kmedia link KEPT (TvChannels + WatchState.path
still used by the TV rail; unlink = out of scope). DEPLOYED by bobDotrix
2026-09-17 ~22:35 AEST after independent cold-verify from a wiped
zig-cache: Debug/test/ReleaseSafe all 0/0, nested-smoke PASS,
close-evidence PASS (3 close rounds survived), grep gate 0 hits.
/usr/local/bin/kidulwm sha256 c1afad6f (bak .bak-2b-slice4). Live at
next relog. Deploy note: ReleaseSafe output dir is zig-out/bin (the old
zig-out-release path is stale — KNOWN_CMDS should track this). Host test
owed: relog, kvisd on wayland-1, play → pause/seek verbs + windowed
ring eye-test.


## 2026-09-17 VERDICT 32: CARD 2b slice 3 LANDED — kvisd placement

KidulWM 6402578 (bobDotrix finished coderBob's cut-off dispatch; 402
credit death mid-run, work audited + completed in-session): kvisd video
toplevel (app_id com.kidul.kvis) tracked server-side OUTSIDE the deck —
no slide, no chrome, no focus; placeKvisWindow pins its scene tree over
the video slide rect on map / videoSlidePaint / applyLayout. Fullscreen
= raised edge-to-edge, ZERO chrome. Windowed = slide tree stays on top;
ring-vs-matte visibility is a HOST eye-test verdict (inset follow-up if
needed). Debug/ReleaseSafe/test clean, nested-smoke PASSED.
DEPLOYED /usr/local/bin/kidulwm sha256 f2f642ac (bak .bak-2b-slice3).
Host test owed: relog + kvisd on wayland-1 + play -> pixels IN the slide.
NEXT: slice 4 deletion (embedded libkmedia + media_video.zig present path).


## 2026-09-17 VERDICT 31: CHROME LAW locked + boot-open gated (host)

KidulWM 198d057: A5 boot ladder gated behind KIDULWM_BOOT_MEDIA. Host
default OFF — the media player slide does NOT open at boot here; it is
a Mod4+m slide like any other. TV-profile restores the boot ladder with
KIDULWM_BOOT_MEDIA=1.

KidulWM 228abf6: CHROME LAW (Barticus, LOCKED) — fullscreen video = ZERO
chrome. The chrome ring cost ~6% CPU (2→8) and painted over the picture.
videoSlidePaint now skips the ring entirely when the video slide is
fullscreen; windowed (peek/parked) keeps it. Deployed d2ae35f0.

Slice 3 (placement) gets a clean law to build against: fullscreen =
pixels edge-to-edge, zero chrome; windowed = chrome ring only, kvisd
surface UNDER the ring.

## 2026-09-17 VERDICT 30: CARD 2b slices 1+2 LANDED — internal client + slide lifecycle

KidulWM 5b0aff3 (slice 1): src/ipc/internal_client.zig — the compositor's
own Wayland client (socketpair → wl_client_create → connect_to_fd →
pumpRoundtrip → wl_compositor + xdg_wm_base + zxdg_exporter_v2).
DEADLOCK LAW (proven by strace, baked into the module): a same-thread
internal client can NEVER use blocking wl_display_roundtrip — the server
can't dispatch while the client blocks; libwayland-server never
auto-flushes (wl_display_run does flush_clients per iteration, we were
not in run()); and client-side dispatch_pending starves without
prepare_read/read_events. pumpRoundtrip() is the single sync primitive:
flush → server loop dispatch(1ms) → dispatchIdle → flush_clients →
client prepare_read/read_events → dispatch_pending, until the sync
callback lands. Smoke test (KIDULWM_INTERNAL_CLIENT_TEST=1, headless):
export handle received, clean teardown, Debug + ReleaseSafe PASS.

KidulWM a065188 (slice 2): src/ipc/kvis_client.zig (SEQPACKET line
client, bounded 2s reply wait, event-broadcast skip) + video-slide
lifecycle wiring: spawn → host toplevel (com.kidul.video-slide-host) →
export → kvis.sock 'parent <handle>'; close → unparent + close + host
destroy. Harness (headless compositor + real kvisd + media_play):
export + parent verb delivered; kvisd replied err no_shell as designed
(its shell spawns on video open, and its GL probing failed against the
pixman headless backend — CARD 2a probing, not a slice-2 bug).

DEPLOYED /usr/local/bin/kidulwm sha256 7e7f29cf… (.bak-2b-slice2 kept),
takes effect on next compositor reload.

HOST TEST OWED (Barticus, next session, real GL compositor):
  1. kvisd running on the session (WAYLAND_DISPLAY=wayland-1).
  2. Play a video → video slide spawns → session.log should show
     'video host surface exported' + (if kvisd already playing)
     parent ok — else parent deferred until kvisd opens.
  3. Full A→B acceptance on the kvis path still owed (verdict 29).
NEXT: slice 3 (compositor placement: track kvisd toplevel by app_id,
pin scene tree to the video slide rect, chrome policy), then slice 4
(deletion card: gut libkmedia module + media_video.zig present path;
media_slide.zig becomes a pure kvis.sock client — verdict first,
separate commit).

## 2026-09-17 VERDICT 29: CARD 2b part 1 + CARD 2c (kvisd half) LANDED

KidulWM 6b73fc7 (DEPLOYED /usr/local/bin sha256 01889df1…, takes effect
on next compositor reload): XdgForeignRegistry + XdgForeignV2 created at
boot — the exporter/importer globals the slide's host surface will bind.
kmedia 17f45c8: kvisd binds zxdg_importer_v2, parentTo/unparent real,
'parent <handle>'/'unparent' live on kvis.sock.
ARCHITECTURE NOTE (replaces HANDOFF session-22's subsurface sketch):
xdg-foreign parents TOPLEVELS. kvisd's video surface stays a toplevel
child of the slide's host surface; the compositor positions it over the
.video slide rect by app_id com.kidul.kvis. kvisd letterboxes inside its
own surface — the §9a matte-overlap class dies structurally, the 20s
wedge + A→B freeze classes gain the process wall. All embedded-path
verdicts (19-21 freeze hunt, 5e84470 cache-key law) are EMBEDDED-ONLY —
they die with the module, not carried into kvisd. Fresh A→B owed on the
new path as the acceptance test.
NEXT: CARD 2b part 2 — internal client host surface per .video slide,
export, parent verb, placement. Full attack order in kmedia/HANDOFF.md
session 23. Karaoke SHELVED (Barticus 2026-09-17).

## 2026-09-17 VERDICT 27: weather widget PARKED + keybind conf FIXED + blanking born

1. WEATHER WIDGET PARKED (removed 46757df, NOT deleted from history).
   The mirror-the-clock layout (8f49a81, 56410bc, 1cfb590, f0062cc,
   db3103f — five layout commits in two days) never converged: every
   pass fixed one overlap and created another (stranded icon, bottom
   overflow, clipped moon top, off-center sun). Barticus verdict: 'still
   all over the place', removed ASAP. The systemd fetch timer/service
   (kidulwm-weather.*) was disabled + deleted on the host. IT IS NOT
   GONE FOR GOOD — it returns with a NEW DESIGN, not more clamps.
   Salvage for the redo: moon.zig shaded-sphere renderer was correct
   (git show 46757df^:src/util/moon.zig); cache format home.json was
   correct; the fetcher script was correct. What was wrong was ONLY the
   pill layout. REDO RULES: harness-before-painter (offscreen render at
   scale 1 AND 2 before any deploy); no mirroring anchors from glyphs of
   a different size; no text-budget/clamp hacks; one build → one
   verdict, never stacked commits.

2. KEYBINDS CONF — never worked since birth, fixed 7a1a005. Parser was
   all-or-nothing (one bad line → whole file discarded → silent
   defaults) AND couldn't strip inline '#' comments (present on nearly
   every conf line, so EVERY line was 'unknown action'). The conf sat
   there documenting binds the compositor never loaded. Fixed: per-line
   skip + loud warnings, inline comment strip, user binds MERGE over
   defaults with priority. Added missing actions tray_select_next/prev,
   tray_activate, wm_reset, F11. LESSON: any config parser that silently
   falls back is a bug farm — log loudly at load time what was used and
   what was skipped.

3. SCREEN BLANKING (anti-burn) born 7a1a005: Mod4+x toggles
   screens_off; all outputs commit setEnabled(false) (real DPMS-style
   off), any key wakes (checked before bind dispatch, wake key
   swallowed). No password — lock is SCOPED in HANDOFF 2026-09-17
   addendum (locked flag, overlay_tree lock UI, PAM-or-hash auth,
   idle timer shared with blanking, Granny remote wake opt-out).

## 2026-09-16 VERDICT 19: kmedia A→B probe test CLEAN + spyglass EXIT signs rebuilt + browser YT crash moved to WPE

SESSION (bobdotrix + Barticus, morning→midday):

1. KMEDIA A→B PROBE TEST (session-21 rig, KidulWM 34dd7a8 = a6ee7630
   verified as /proc/pid/exe before playback): short A (~1.2s, the
   morning's suspected trigger window) → close → B. NO WEDGE. All probes
   fired correctly: teardown/gen lines clean, refresh ticks, dmabuf MISS
   lines sane, watchdog heartbeat never went silent. The freeze door
   stayed shut this run. CAVEAT: the IPC media_play path routed to the
   HIDDEN tray widget (slide never opened — media_open=false in
   debug_status while audio played), so the test exercised the player +
   teardown but NOT the slide's video_buffer scene path. Verdict:
   "no wedge on tray-path A→B" — the slide-path repro is still owed, and
   it is blocked by the slide-not-a-slide bug (verdict 10, still PAUSED
   pending browser work).

2. SPYGLASS EXIT SIGNS REBUILT (Barticus spec, deployed d85a9cf2,
   .bak = kidulwm.bak-a6ee7630): EXIT dots + slide count are now ONE
   centered pair inside the peek band — surface covers the peek exactly,
   pair centered with 8px clearance both edges (pair drops the digit and
   keeps dots centered when it can't fit — this was the missing left
   number: it was anchored off-surface). Number size 1.2h → 0.9h
   (num_font_scale), gap = 2 text spaces (pair_gap = 16px), number
   inherits the EXIT source exactly (0.86 rest / 0.96 hover). Order
   faces the deck: left peek "n EXIT", right peek "EXIT n". Tunables are
   named constants at the top of src/ui/spyglass.zig. NOTE: the build
   also carried uncommitted rescue-era changes in server.zig, pointer.zig,
   input.zig, tray.zig — flag if behavior surprises.

3. BROWSER YT CRASH → WPE (detail in kidul-browser/HANDOFF.md pm entry):
   compositor side of verdict 18 confirmed clean end-to-end (PTR-ENTER +
   BTN-NOTIFY focused=true reaching the browser surface). The YT
   renderer crash was chased through coredumps to
   WebKit::AcceleratedBackingStore::update(LayerTreeContext) — upstream
   bug on NVIDIA (modrinth/code#7017, 2.42.9→2.52.6). Every env hammer
   bounced; renderer switched to WPE (FDO/SHM), which survived YT in
   harness and shell. YouTube itself now serves Google CAPTCHA to the
   headless client — their wall, parked for Barticus. kidulwm binary
   unchanged for this item.

## 2026-09-15 LAW DRAFT — PEEK UNIT: %-of-peek sizing for all peek widgets
Status: THEORY LOCKED IN WRITING, implementation parked for the
'fix linux scaling' polish pass (Barticus approved the deferral same day).

SYMPTOM THAT MOTIVATED IT: tiny butterfly on the laptop panel, HUGE
butterfly on the 4K output. Same root cause as the spyglass EXIT signs
being misplaced (fixed 2026-09-15): every peek widget still sizes itself
in hardcoded PX constants while the peek band itself is a FRACTION of the
output. Two screens of different widths therefore render different art.

CURRENT OFFENDERS (px constants that must become peek-derived):
- spyglass.zig: exit_dots_w=72, icon_size=20, num_buffer=2 — partially
  fixed 2026-09-15: EXIT dots now CENTER in the peek band via
  peek_fraction=0.06, but dot size/height are still px. Also peek_fraction
  is hardcoded; must come from the live deck_split (server owns it) so IPC
  split changes move the signs too.
- tray.zig gauges: gauge icon/grid px constants.
- tray.zig weather: widget px constants.
- tray.zig logo: margin=8px*scale (fit itself already derives from the
  peek box — the model to copy).
- drives/network/media peek widgets: audit for the same sin.

THE LAW (draft, for Barticus lock at polish time):
1. ONE unit per peek: peek_unit = peek_band_px / 16. All widget
   dimensions — dot radii, icon heights, digit font size, gauge strokes,
   margins, buffers — are integer multiples of peek_unit. Nothing in a
   peek may be sized in raw px.
2. The peek band px comes from the LIVE deck_split (server owns the
   authoritative split; splitFromRequest proves it). Widgets receive the
   band px in their layout call; they never read style.layout.* or
   hardcode the fraction themselves. This makes IPC split changes and
   future per-output splits propagate for free.
3. Scale (wlroots output scale) multiplies AFTER the unit math:
   device_px = logical_px * scale. Never bake scale into the unit.
4. Same visual proportion on every screen: a 1080p laptop and a 4K TV
   show the SAME art at the SAME fraction of the peek — only the px
   differ. "The peek is the canvas; the unit is the grid."
5. Where two widgets stack in one peek (weather over gauges, logo at
   bottom), each gets a share of the band HEIGHT in units too — vertical
   budget split in the same unit, not px.

IMPLEMENTATION SKETCH (when the pass starts):
- Server already hands each peek widget its box via host.left_peek_box /
  right_peek_box (tray.zig). Add peek_unit to that box (or a sibling
  accessor) computed from deck_split * output_width.
- Spyglass: replace exit_dots_w/icon_size/num_buffer with
  dots_w = 4.5*unit, icon_h = 1.25*unit, num_buffer = 0.125*unit
  (numbers eyeballed from current proportions — tune at render verdict).
- Delete peek_fraction from spyglass.zig; take the band from the box.
- Gauges/weather/logo: same treatment, one widget at a time, ReleaseSafe
  + host deploy + Barticus verdict each (per the iteration law).
- This pass should ALSO subsume the general fractional-scaling audit
  (laptop butterfly vs 4K butterfly is the same law at app level).

## 2026-09-15 VERDICT 26: logo shading pass 2 — deployed (ReleaseSafe,
host /usr/local/bin/kidulwm, sha256 36de1424…, .bak-pre-shading2 kept).
Barticus: size good, color reads too solid; shading invisible in pass 1.
All still UNCOMMITTED in tray.zig drawLogoWidget (on top of verdict-25
work). Tweaks:
- umbra: offset 0.012→0.03 glyph-h, luminance 0.35→0.25, alpha 0.45→0.6
  (real offset shadow, deep enough to read);
- body: alpha 0.80→0.70 (softer, lets umbra breathe — kills 'solid');
- crown: alpha 0.22→0.35 (top-40% sheen now visible).
Fit/margin untouched (0.92, 8px*scale) — size LOCKED per Barticus.
Open idea (his): 'bubbles' inside the fill to break up the mass — parked
until pass-2 verdict lands. Tuning levers: umbra 0.03/0.25/0.6, body
0.70, crown 0.35, clip 0.40.
AWAITING BARTICUS VERDICT after compositor reload.

## 2026-09-15 VERDICT 25: spyglass EXIT signs centered in peeks + KSD
logo shading, deployed (ReleaseSafe, host /usr/local/bin/kidulwm).
SPYGLASS (src/ui/spyglass.zig): EXIT dot-matrix was anchored 17px from
each screen edge — left sign drifted under the focused slide's left edge,
right sign sat ~120px under the slide ("not even in the peek"). Fix:
peek_fraction=0.06 (matches style horizontal_split), left EXIT x =
(peek_w-dots_w)/2, right x = out_w-peek_w+(peek_w-dots_w)/2 — both signs
dead-center in their peek bands. Hitbox math follows the dots.
SLIDE-COUNT DIGITS rewritten: no more gold-mask scratch surface (they
rendered yellow-ish at 100% color on black); now drawn directly in the
cairo source color = same tone/alpha as the EXIT dots incl. hover
brighten, transparent background, font h*0.6 -> h*1.2 (2x), hard against
the screen edge with 2px buffer (num_buffer).
KNOWN DEBT: peek_fraction hardcoded — plumb live deck_split in the PEEK
UNIT pass (see LAW DRAFT above).
LOGO SHADING (tray.zig drawLogoWidget): replaced the flat 0.9-alpha tint
with three mask passes, design untouched —
  L1 umbra: glyph +1.2% downshift, border color @35% luminance, 0.45a
     (soft drop-shadow; pulls the wave into shadow);
  L2 body: flat tint at 0.80a (was 0.9 — subtler per Barticus);
  L3 crown light: glyph @135% luminance, 0.22a, clipped to top 40% so
     K-stem top + S/D catch a sheen; the wave never sees it.
Also fit * 0.92 (slightly smaller, still centered + bottom-anchored).
Tuning levers if the eye objects: umbra 0.45, crown 0.22, clip 0.40,
fit 0.92.
BARTICUS VERDICT (2026-09-15): "beautiful work!" — EXIT signs + logo
shading both LOCKED.

## 2026-09-15 VERDICT 24: KSD logo widget — bottom of left peek, committed
8d49b45, deployed kidulwm 3b11cb67 (active on next session reload).
Asset: src/ui/assets/ksd_logo_mask.png — preprocessed from
'~/Pictures/Kidul SlideDeck Balanced SD Logo.png' (2048²): white ->
transparent, black ink -> alpha mask, cropped to ink bbox (350,380
-1772,1844), downscaled 498x512 master. Runtime tint via
cairo_mask_surface with style.color_border — visible ink IS the border
color, tracks theme generation like every other peek widget.
Wiring: PerOutputLogo + logo_widgets in tray.zig (same lifecycle as
weather/gauges/drives: created per output at addOutput, destroyed at
removeOutput/deinit). ensureLogoSurface loads the embedFile'd PNG once
via memfd + cairo_image_surface_create_from_png — first frame only.
Placement: bottom-anchored, horizontally centered, fitted to peek width,
8px*scale margin. Click -> tray.toggle() (same door as SW key + IPC
tray_toggle) — the future CFC'd tray opens through the same path.
LOW-POWER LAW honored: no polling, no timers, no animation; redraws
only on layout/scale/theme-generation change.
AWAITING BARTICUS VERDICT after compositor reload: logo visible
bottom-left peek in border color; click opens tray. If the logo draws
too big/small in the narrow peek, the lever is the fit/margin math in
drawLogoWidget (tray.zig ~2770).

## 2026-09-15 VERDICT 23: 'Log in' click fires 'Sign in' — ONE-SPACE LAW
deployed (kidul-browser 74e56c8b + renderer e65ad10a, ReleaseSafe, host).
User report: twitchyness gone (verdict-22 work held), but clicks hit the
wrong button — pressing Login activated the Sign-in control above it.
DIAGNOSIS (static, three spaces proven misaligned in-tree):
1. RESIZE RACE (renderer): three resize owners — startup default
   1280x720, xdg configure (w.width at ack time), ready-event resize
   (shell.window_width) — each did gtk_window_resize + size_request +
   invalidate_snapshot. Racing snapshots at intermediate sizes meant the
   USER could be looking at a snapshot of one size/layout while clicks
   were mapped against the LIVE view at another. Fix: resize cmd only
   records configured_width/height pre-load; exactly ONE settle resize +
   snapshot at WEBKIT_LOAD_FINISHED ('settle resize WxH -> WxH' log
   line). Post-load resizes realign immediately (no race once loaded).
2. NO WINDOW->FRAME MAPPING (shell): drawPageFrame cover-scales the
   frame (scale=max(w/fw,h/fh), src_x centered, src_y=0), but pointer
   coords crossed IPC as raw window-local — WebKit hit-tests in FRAME
   space. Any aspect/size mismatch = clicks land off by the crop/scale
   delta, vertically in exactly the login-vs-sign-in direction. Fix:
   mapWindowToFrame() in Shell.zig (inverse of the draw transform,
   identity when frame==window) applied in sendRendererMotion,
   sendRendererButton, and handleClick's focus_page press path.
3. DELIVER probe armed (renderer stderr): every fabricated event logs
   'DELIVER type=N x= y= win=0x.. handled=0|1' — one repro answers
   whether the click arrives, at what coords, and whether WebKit honors
   it. STRIP after verdict.
AWAITING BARTICUS REPRO: relaunch kbrowser, load login page, click Log
in once, hover a little. Expect: settle-resize line, 'viewport snapshot
ready 1673x1064', DELIVER x/y matching the click point, correct button.
If STILL wrong with DELIVER coords correct: the remaining suspect is the
+25,25 geometry inset (buffer=1723x1114 vs geom=1673x1064@25,25 on every
commit, verdict-20/21 logs) — that one lives in KidulWM
applyContainment/xdg geometry, NOT the browser. Also still open from
verdict 21/22: PTR-ENTER never logged in session.log even after dd9709e
(clicks reach the page only because handleClick forces focus) — the
repro's session.log read will say if that needs its own fix.

## 2026-09-15 VERDICT 22: post-reboot browser triage — backspace dead,
cursor stuck as ibeam, fans. Three findings, two fixed+deployed:
1. BACKSPACE DEAD IN PAGE (kidul-browser, FIXED): Shell sends
   sendPageKey("Backspace", "\x08", 0); renderer keysym_for() took the
   text fallback FIRST (strlen==1 → gdk_unicode_to_keyval(0x08)=Ctrl-H),
   shadowing the GDK_KEY_BackSpace branch. WebKit got keyval 0x08 —
   handled=1, deletes nothing. Fix: text fallback only for printable
   bytes (>=0x20). Deployed /usr/local/bin/kidul-browser-webkitgtk-renderer.
2. CURSOR STUCK AS IBEAM (KidulWM, FIXED, active on next session reload):
   input.zig handleRequestSetCursor honored set-cursor from ANY client,
   no focus check → a text field's ibeam surface stuck forever. Added
   the standard wlroots guard (event.seat_client ==
   seat.pointer_state.focused_client) AND re-assert left_ptr in
   pointerEnterAtCursor's clear-focus branch (nothing was resetting the
   image when the pointer left all surfaces). /usr/local/bin/kidulwm
   swapped; live process still the old binary until reload.
3. FANS = known verdict-21 open item: Ghostty (id=1) commit-flooding,
   1268 handleCommit lines, ~100-144 fps on both outputs with nothing
   animating, kidulwm ~70% CPU. CHROME cache-miss culprit field still
   unfound — separate hunt, not browser-related.
Note: kidul-browser worktree has a large uncommitted trusted-input v2
changeset (904 insertions across 8 files) — left untouched.
Also seen: 'Failed to pick cursor plane format' DRM errors (hw cursor
plane rejected → software fallback, cosmetic).

## 2026-09-15 VERDICT 21: dead click/scroll AGAIN after verdict-20 — the
CHROME BUFFER was eating the pointer (dd9709e, deployed 79e1900b).
Verdict-20 fixed the cursor coords (passes now sane, clamped, over the
window), but the SAME log still showed zero PTR-ENTER, zero PTR-MISS,
all BTN-NOTIFY serial=0 focused=false. The two probes being absent
together was the fingerprint: pointerEnterAtCursor was returning on the
ONE branch with no log line — the tryFromBuffer orelse.
ROOT CAUSE: the chrome overlay is a raw DataBuffer scene buffer
(window.zig updateChrome: createSceneBuffer + setDestSize(w,h)), placed
at the SAME coords as the client surface and raised to the top of
overlay_tree, which applyLayout raises ABOVE all windows. Global
scene.tree.node.at() walks top-down → first buffer under the cursor
anywhere over a window is ALWAYS the chrome buffer. Chrome is not an
xdg surface → wlr.SceneSurface.tryFromBuffer() = null → silent return,
no pointer enter ever, wlroots drops all buttons/axis. Keyboard and
click-FOCUS sailed through because focusAtCursor walks the PER-WINDOW
trees, which never contain chrome — that asymmetry named the culprit.
FIX: pointerEnterAtCursor no longer hit-tests the global scene at all;
it walks per-window trees exactly like focusAtCursor, resolving the hit
buffer to its xdg surface. PTR-MISS probe deleted (its diagnostic
branch is gone; PTR-ENTER log kept, now with window id).
LAW (ksd-input-claim-law): compositor-drawn scene buffers that share
geometry with client surfaces poison every global hit-test that expects
a client surface. Pointer-enter must walk per-window trees; the global
tree is for RENDER order, not input resolution.
Also noted same session: compositor hot-loop on Ghostty id=5 (6.5k
handleCommit/CHROME cache-miss floods, 75% CPU, fans) — updateChrome
cache-miss diag shows identical old/new keys, cache-miss culprit field
still unfound; orphaned dev-tree ksound pid 7014 likely behind the
stale media "playing" dot (media slide closed, no player alive).
REPRO after reload: hover page → PTR-ENTER id=N; click → BTN-NOTIFY
serial!=0 focused=true; wheel scrolls; browser clicks/links work.

## 2026-09-15 VERDICT 20: dead click/scroll/hover SYSTEM-WIDE — split-brain
cursor bookkeeping, FIXED (6d84450, deployed ecf973bb). The 'browser can
type but not click/scroll/backspace' hunt ended one layer down, in KidulWM,
and it explains the same dead-pointer class in terminals + media player:
- server.cursor_x/y accumulated relative deltas UNCLAMPED while wlr.Cursor
  clamps to the output layout. After any warp (boot park at 960,1620,
  focus jumps, Mod4+O) the two diverged permanently — log showed cursor
  coords down to x=-1181, y=-254, off every output.
- Scene node.at(negative) missed every window → zero PTR-ENTER in the
  entire log → wlroots dropped ALL button/axis events (BTN-NOTIFY
  serial=0 focused=false flood). Keyboard sailed through via
  keyboardNotifyEnter — that asymmetry IS the symptom split.
- FIX (6d84450): wlr.Cursor is the single writer of record. Motion and
  absolute handlers resync the mirror from cursor.x/y after every move;
  all cursor-consuming entry points (claim chain, pointerEnterAtCursor,
  focusFollowsCursor, focusAtCursor, axis) call syncCursorMirror() first.
  Claim-chain params now ignored in favour of the clamped truth.
- Tray two-screens checked and CLEARED: one Tray, per-output panels with
  correct layout coords — by design, not an input doubler.
- Law recorded in ksd-input-claim-law skill: never accumulate deltas into
  a parallel cursor position.
REPRO after reload: first motion logs PTR-ENTER surface=...; clicks show
serial!=0 focused=true; browser hover lights, links click, wheel scrolls,
Backspace/arrows work in fields (renderer-side gtk_widget_grab_focus +
GDK_SCROLL_SMOOTH fixes deployed to /usr/local/bin/kidul-browser* same
session, md5-matched). Terminals + media player pointer input restored.

## 2026-09-15 VERDICT 18: faint-tray ghost + dead left-peek inputs — BARRY
REMOVED (bbd9628, deployed 3e71454c). Symptom: faint tray visible in left
peek, browser/page inputs dead over that strip. Root cause: the Barry pet's
input machinery — pointInsidePet = always-live hit box over the left peek
(tray open or closed); hover-to-open could latch `hovered`, pinning
tray_anim > 0.001 draw floor → ghost panel + clicks eaten before
focusAtCursor. Log: BTN-NOTIFY focused=false flood, zero PTR-ENTER.
Barticus verdict: pet deleted from code entirely (toy pets hold no input
handles; art archived ~/brain/shelf/barry/). Tray opener now = RAM cauldron
gauge-pill click (re-enabled) + keyboard paths. Hover-open gone.
REPRO after reload: no ghost in left peek; clicks pass through; cauldron
toggles tray; browser pointer (verdict-18) still live.

## 2026-09-15 VERDICT 19: media player EVICTED from tray; cauldron severed
(bd2f089 + cf2697f, deployed ccc5bb39). The weeks-long fight's prime
structural suspect is gone: the player was a FIELD of the tray UI struct
(tray.media, ~104 uses); kill-switches (ensureStopped on slide change)
routed through it. Now Server.media_player owns the player; tray reads
via TrayHost.media pointer for card/peek display only. Cauldron→tray
click DELETED — gauges are pure telemetry now. Tray opens by keybind/IPC
only (peek has no mouse door until the CFC launcher build gives
kidulButton its own zone). REPRO: music IPC/keys unchanged; slide-change
ensureStopped still fires (rewired — watch); cauldron click = no-op.

## 2026-09-09 VERDICT: invisible-video root cause FOUND + FIXED (kmedia)
The census logs told the whole story once read per-stream instead of
aggregated:
- "Invisible video" is NOT file #2 — it's the FILE. Raya (audio starts
  ~4.6 min in → container clock ≈ 0) played fine; Bob.Marley (audio starts
  at 790.88s absolute) never showed a frame.
- Evidence: OPEN#1 (Bob.Marley) produced exactly 2 PRES in ~60s, both
  lagging ~800-960ms vs the absolute audio clock; 6312 AUGAPs; compositor
  logged committed=0 dropped=80 and "refresh NULL: no va_frame". OPEN#2
  (the same file re-opened) even fired AUPTS jump=-1696000 — the audio
  pipeline saw the discontinuity.
- Root cause (Player.zig): video frame PTS was compared against an audio
  master clock that starts near 0, but both were ABSOLUTE container
  timestamps. For a file whose audio starts at t=790s, every early video
  frame reads as "not due yet" — black screen with audio until the clock
  catches up. "A few stills got through after a minute" = the audio clock
  finally overtaking the first video PTS values.
- mpv law applied: --start=0 means playback time 0 = first frame. mpv
  normalises away the container start offset; we did not.
- FIX (kmedia/src/Player.zig, commit ffc8877): learn vid_base_pts_us /
  aud_base_pts_us from the first timestamp each stream produces, rebase
  both to a 0-based timeline in the decoder (video) and audioLoop
  (clock + DAC anchor). Resume-seek target converts normalised → absolute
  via container start_time; post-seek (resume AND mid-play) the bases are
  reset and video display is gated (seek_armed) until the audio ring
  re-primes — mpv's wait-for-audio-after-seek.
- Census-law note: the prime suspect (playTimerMs ceil) is NOT the
  invisible-video cause. See below — the REAL cadence bug was elsewhere.

## 2026-09-09 VERDICT 2: stutter root cause FOUND + FIXED (kmedia 6af6ea5)
The ceil suspect was looking at the wrong clock. The compositor-side
playTimerMs ceil is harmless (it only wakes the playloop; the present
decision lives in Player.tick). The damage was INSIDE the playloop:
- Raya evidence (VA-API active, ~2% CPU, decode clean): PRES p50=166ms,
  62% of deltas >70ms when the ideal is a steady 41.7ms (24fps). The
  decoder was never the bottleneck — the display clock was.
- FAULT 1: the vsync grid in advanceVideoFrame() FLOOR'd the due-clock
  to the previous grid edge (@divFloor). At 143Hz (6.945ms slots) a
  24fps frame stayed "not due yet" for 1-2 extra ticks past its slot →
  presents landed a half-to-full frame-period late, every frame.
  FIX: snap the grid clock UP (ceil) to the first edge at-or-after the
  raw clock — mpv display-sync presents at the next vsync >= pts,
  never below it.
- FAULT 2: after any stall, the ring held several ALL-due frames but
  the loop displayed ONE then broke — N stale frames smeared recovery
  over N wrong-phase ticks. FIX: drain the stale prefix (frames whose
  successor is already due) in the same tick, count as drops, display
  the newest due frame. One PRES, back on grid.
- Both in kmedia/src/Player.zig, commit 6af6ea5. playertest 28 PASS.

## LINKAGE ANSWER (the "half our problem" question) + FIX
KidulWM statically includes kmedia as SOURCE MODULES (build.zig reads
../kmedia/src/{c,av,libkmedia}.zig directly — no .so, no .a, no
package pin). ldd shows no kmedia. Consequence: a kmedia commit is
INVISIBLE at runtime until KidulWM is rebuilt + redeployed + reloaded.
That's what lost the morning (deployed probes that weren't).
FIX (KidulWM build.zig + main.zig): compile-time provenance stamps —
build runs git rev-parse on BOTH repos, bakes them in via addOptions,
and main logs at boot:
  "KidulWM boot (kidulwm=XXXXXXX kmedia=YYYYYYY)"
session.log now proves which player code is actually running. Verified
live: the fresh binary strings show kidulwm=2e37c87 kmedia=6af6ea5.
Architecture (in-process, zero-copy VA-API dmabuf into the scene
graph) is CORRECT and stays — mpv libmpv embedders do the same. The
only real cost is player-crash = compositor-crash; accepted.

## WHAT CHANGED TODAY (running list, newest last)
- kmedia ffc8877  Player.zig  start-PTS normalisation (invisible-video)
- kmedia 6af6ea5  Player.zig  vsync-ceil + stale-backlog drain (stutter)
- KidulWM build.zig + main.zig (UNCOMMITTED) provenance stamps
- KidulWM 286a76b  src/core/kmedia.zig  silence watchdog (stale dot)
- CENSUS-NOTES.md (this file) updated per change + law amendment
DEPLOY: /usr/local/bin/kidulwm = sha256 ad1de802… = 286a76b/6af6ea5,
deployed 11:47 via mv-aside. Takes effect on compositor reload. Old binary
kept as /usr/local/bin/kidulwm.bak-pre-silencewd.
Reload + repro closes: stale dot (watchdog), and re-tests symptoms 1+2.


## THE THREE SYMPTOMS (Barticus, 2026-09-09)
1. STUTTER on playback. — root-caused (vsync-floor + backlog-smear),
   fixed in 6af6ea5. REPRO NEEDED on new binary to close.
2. SECOND VIDEO INVISIBLE — root-caused to start-PTS offset, fixed in
   ffc8877. REPRO NEEDED on the new binary to close.
3. MAYBE-LOCKUP — watchdog showed 129-151fps steady, i915 irqs counting,
   compositor never wedged during the hunt. Downgraded: no evidence.

## THE LAW THIS HUNT RUNS ON
- External-bug law: if the player measures clean and the symptom persists,
  the bug is NOT in the player. Check the seams (cache, lifecycle, timers).
- Census first, fix second. NO PATCHES on theory. The scorecard names the
  boundary, THEN we fix.
- Yesterday's failure mode was: symptom→theory→patch→new symptom. BANNED.
- AMENDMENT (Barticus, 2026-09-09): FIX-AND-RECORD. When the verdict is
  already proven (root cause named, mechanism shown in code/logs — NOT a
  theory) and the fix is small (a few lines, same function, no interface
  change), fix it immediately instead of waiting for approval. Waiting
  produces stale notes and stale running state. Rules:
    1. Evidence first — the exception only fires on a recorded verdict.
    2. Small only — crosses a file/subsystem boundary → back to census.
    3. Annotate in code (what/why; comment out old code when clearer) and
       log it under WHAT CHANGED with the commit.
    4. Repro still closes the symptom — early fix ≠ skip verification.
  That should be the way this works.

## 2026-09-09 VERDICT 3 (FIX-AND-RECORD #1): stale butterfly dot
Symptom (Barticus): live dot in the media widget with no player open and
nothing playing. Holder: kmedia FFT monitor (src/core/kmedia.zig) taps the
mixed sink output; onProcess just STOPS when the sink goes quiet, so
rms_slot/band_slots kept their last loud values forever and tray.zig
drawMediaWidget (audio_live = level() > 0.03) kept the widget live.
FIX (KidulWM 286a76b, src/core/kmedia.zig): capture thread timestamps every
buffer; a sibling watchdog publishes zeros through the SAME slots after
250ms of silence and on stream exit. smooth[] left to decay naturally
(capture-thread owned; resetting from watchdog would race). Deployed
/usr/local/bin/kidulwm sha256 ad1de802… (stamps 286a76b/6af6ea5).
REPRO after reload: dot must die within ~1s of audio stopping.

## 2026-09-09 VERDICT 4 (OPEN, census resumes): fixes live, symptoms persist
11:26 repro on the FIXED binary (boot stamp kidulwm=54ab4bc kmedia=6af6ea5,
proves BOTH ffc8877 start-PTS + 6af6ea5 vsync-ceil/drain were running):
- Raya open: PRES p50=199ms (ideal 41.7), DROP=648, STARVE=1618 vq=0 while
  aq=31 (audio ring FULL, video queue EMPTY) → video decode starves, not a
  display-grid problem. Stutter NOT fixed by 6af6ea5 — verdict 2 was wrong
  or incomplete; the vsync grid was never the bottleneck.
- Bob Marley open: PRES=0, 3223 AUGAPs growing ~4ms/32ms (133% clock rate),
  [present] committed=0 gen=3 → start-PTS fix did NOT cure invisible-video.
  AUWR shows pts=790880000 (ABSOLUTE) with AUPTS jump=+443951000 — the
  rebasing from ffc8877 is not what the audio writer is emitting, or the
  clock-vs-frame comparison still mixes absolute/normalised domains.
Next census question: why does vq starve with the decoder clean (VA-API ~2%
CPU) — READ cadence? demux thread? And where does AUGAP's 133% rate come
from (DAC anchor domain)? Both point at the demux/clock seam, not display.

## 2026-09-09 VERDICT 5 (FIX-AND-RECORD #2): invisible-B clock + stutter rings
Barticus law change: fix & record is the way of the land. No more
"what to fix next" round-trips — search & destroy, reload to verify.

Root cause invisible-B (CONFIRMED, kmedia 58e6514):
ffc8877 rebased each stream against its OWN first timestamp
(vid_base_pts_us / aud_base_pts_us) — two different 0-based timelines
compared in one expression. Evidence (OPEN5+6): the ~196 frames that
DID present all showed lag ≈ +703ms constant (clock 703ms ahead of
frame pts), then every later frame drain-dropped as stale
(DROP=363, then vq=0 for the rest of the open; compositor committed=0
gen=3). 703ms is the video-first-frame offset past audio-first —
video rebased ~703ms later than audio, permanently behind a clock it
could never catch. FIX: single stream_origin_us = EARLIEST
first-timestamp across both streams; both rebase against it; audio
clock = chunk.pts - origin. One timeline, no mixed domains. Same-file
fix, all 28 playertests PASS.

Root cause stutter refinement (verdict 2 incomplete, now mechanical):
the vsync-ceil fix (6af6ea5) WAS correct but never the bottleneck.
READ census: video packets arrive in bursts ~1ms wide then a
213-300ms gap, EVERY cycle, both files. Audio ring = 32 chunks ≈
680ms; pkt_ring back-pressure blocks the reader until audio drains;
video ring was 8 frames ≈ 330ms → empty inside every gap →
STARVE=3728, PRES p50~150ms. FIX: VIDEO_RING_SIZE 8→16 (~660ms).
No interface change.

WHAT CHANGED (running list, newest last):
- kmedia 58e6514  Player.zig  unified stream_origin_us clock + ring 8→16
DEPLOY: /usr/local/bin/kidulwm = sha256 f4775fc7… = 286a76b/58e6514,
deployed 12:1x via mv-aside (.bak-pre-origin kept). Reload + repro:
Raya must present p50≈41.7ms with STARVE≈0; Bob Marley must show
frames from t=0 (committed>0 gen>3).

## 2026-09-09 VERDICT 6 (FIX-AND-RECORD #3): pre-seek-target frames poison the clock
Barticus question this session: "have we exhausted ALL the how-does-mpv-do-it
avenues? maybe just a line of code, BUT IT IS KILLING THE MEDIA PLAYER."
Yes — it was one missing mpv law, and the 12:17 repro proves it.

Repro on the VERIFIED-FRESH binary (boot stamp kidulwm=286a76b kmedia=58e6514,
sha256 f4775fc7 — verdict 5's fixes were RUNNING):
- OPEN8 (Raya, resume ~23s): PRES p50=84ms, lag pinned at +707ms CONSTANT for
  the entire 36s open, 1736 audio underrun refills, 555 DROPs, 3191 STARVEs.
- OPEN9 (next file, audio-only symptom): AUGAP grows to 6.5s and keeps
  growing after the ring drains; video never presents; AUPTS jump=-58.78s
  (carrying OPEN8's clock).

The 707ms constant lag is the fingerprint. Numbers from the log:
  resume target        = 23.000s  (watch-state; STARVE clock=23000000 fallback)
  first video keyframe = 22.233s  (BACKWARD seek lands on the keyframe)
  first audio chunk    = 22.940s  (AUWR pts=22940000 absolute)
  22940 - 22233        = 707ms    = EXACTLY the pinned lag.

Mechanism (the missing mpv line): mpv's hr-seek decodes from the keyframe
but DISCARDS every decoded frame/sample whose pts < seek target. kmedia
PRESENTED them. Those pre-target frames learned stream_origin_us from the
keyframe (22.233s); audio's first chunk (22.94s) rebased against it lands at
+707ms; the DAC anchor starts the clock at 707ms the instant video frame 0
displays — a permanent, constant A/V offset baked in from frame zero. Every
frame reads "late by 707ms" → drop-storm → ring drains → STARVE → bursty
refill → 707ms again. The clock rate itself was perfect (AUWR pts rate
1.004 vs wall). The vsync grid, the ring sizes, the drain fix — all correct
and all fighting a clock that was born 707ms in the future.
On files where the keyframe-to-target gap exceeds the ring budget the video
ring drains as "stale" faster than decode can refill → committed=0 → the
TRANSPARENT next-movie. Same line of code, both symptoms.

FIX (kmedia/src/Player.zig): hr-seek law — after a resume/mid-play seek,
remember seek_floor_us (the normalised seek target); decodeVideoPacket and
decodeAudioPacket DISCARD decoded output with rebased pts < seek_floor_us;
floor clears on the first frame/chunk at-or-after it. Bases then learn from
post-target timestamps, origin converges on the real shared start, clock is
born at ~0. ~20 lines, same file, no interface change.

WHAT CHANGED (running list, newest last):
- kmedia 698fa75  Player.zig  hr-seek: drop decoded output pts < seek target
DEPLOY: /usr/local/bin/kidulwm = sha256 f027d90c… = 286a76b/698fa75,
deployed ~12:3x via rename-swap (.bak-pre-hrseek kept). Live at next
compositor reload — boot stamp must read kmedia=698fa75. Reload + repro:
lag must be ~0 (not +707ms), PRES p50 ≈ 41.7ms, DROP/STARVE ≈ 0, next
file must show frames immediately (committed>0).

## 2026-09-09 VERDICT 7 (FIX-AND-RECORD #4): the floor died one stream too early
13:0x repro on VERIFIED-FRESH 698fa75 (boot stamp proven): lag pinned at
+707ms CONSTANT again — identical fingerprint to verdict 6. The floor WAS
running; it just didn't live long enough.

Mechanism: 698fa75 tied seek_floor_us lifetime to seek_armed, and
seek_armed disarmed on `aud_ring.count > 0 OR stream_origin_us >= 0`.
Video sets stream_origin_us on its first post-target frame — ALWAYS
before audio decodes its first post-target chunk (keyframe packet leads,
audio packets follow). Next tick: disarm, floor=-1, and the audio
decoder's queued pre-target chunks (keyframe→target = exactly 707ms)
walked through the dead floor into the ring. First AUWR pts=35000000 =
the resume target (floor worked for the LEADING chunk) but the ring
behind it was pre-target backlog; the DAC anchored from it and the clock
was born 707ms in the future. Again.

What mpv actually does (the missing half of the law): the pre-target
discard stays armed across ALL streams until AUDIO has re-primed — video
display gated on the audio clock existing, not on video having produced
a frame. FIX (kmedia d2b7113): seek_armed disarms ONLY on
aud_ring.count > 0 (or no audio stream — aud_codec_ctx == null);
stream_origin_us no longer factors in. Floor lives exactly as long as
the gate. ~8 lines, same function. playertest CLEAN EXIT.

Compositor cross-examined and INNOCENT (again): per-frame [present]
late=682-685ms mirrors the poisoned clock faithfully; gen=3 (Ratatouille,
the "transparent next movie") shows committed=0 dropped=~100/s where
dropped = "vsync, no new serial" = empty player ring = STARVE upstream.
Cache/gen guards held all day.

WHAT CHANGED (running list, newest last):
- kmedia d2b7113  Player.zig  hr-seek floor gated on audio re-prime
DEPLOY: /usr/local/bin/kidulwm = sha256 4b9fb9fc… = 286a76b/d2b7113,
deployed 13:37 via mv-aside (.bak-pre-hrseek2 kept). Reload + repro:
lag ≈ 0 (NOT +707ms), PRES p50 ≈ 41.7ms, next file committed>0 from t=0.
Boot stamp must read kmedia=d2b7113.

## 2026-09-09 VERDICT 8 (OPEN, probe deployed): d2b7113 ran, +707ms survives
13:3x repro on VERIFIED-FRESH d2b7113 (boot stamp + sha 4b9fb9fc proven):
- OPEN (Raya, resume 25.0s): first AUWR pts=25005000 at +4ms, aq=31 —
  audio primed EXACTLY at target; the verdict-7 gate held on the audio
  side. Yet first PRES (+644ms) lag=+718ms, p50 lag=+708ms constant
  across all 279 presents, DROP=505 (drop-lag p50=808ms), STARVE=2960,
  PRES delta p50=66ms. Same fingerprint, third binary.
- OPEN (next movie): PRES=0, AUPTS jump=-57.3s (cross-generation clock
  leak in the discontinuity detector), video never presented.
- Demux cross-examined INNOCENT: 823/830 video packets delivered over
  the 34.6s open (24fps honoured, one 1.4s gap at +33s), audio 40154
  pkts. Reader/decoder are not starving — frames die between decode and
  present, drained as "stale" by a clock born keyframe→target ahead.

Where that leaves the hunt: the gate now provably holds for AUDIO, so
the surviving pre-target teacher is on the VIDEO side — some frame with
pts below the floor still reaches `stream_origin_us = pts_us` (video
packets lead audio after a seek; the only value 707ms below 25.005s is
the keyframe). Inference has hit its limit; the next repro must NAME
the packet. Probe deployed for exactly that.

WHAT CHANGED (running list, newest last):
- kmedia 0b8b773  Player.zig + Timing.zig:
  1. FIX (proven in code): mid-play seek in readerLoop passed the
     NORMALISED target raw to av_seek_frame while open-resume adds
     cont_start — a seek in a start_time!=0 container (Bob Marley 790s)
     landed ~790s early on the absolute axis. Both doors same law now.
  2. PROBE: Timing.vfpts logs abs/cont_start/floor/PASS|DROP per decoded
     video frame while seek_armed — names the packet teaching the origin.
  3. FIX (evidence): openInternal resets last_auwr_pts_us/end so AUPTS
     stops carrying the previous player's clock into a fresh open.
DEPLOY: /usr/local/bin/kidulwm = sha256 212d89f7… = 286a76b/0b8b773,
deployed ~14:0x via mv-aside (.bak-pre-vfpts kept). Reload + repro:
watch for VFPTS lines after the Raya resume — the DROP/PASS sequence
pinpoints the origin teacher; lag must be ≈0 once that door closes.
Boot stamp must read kmedia=0b8b773.

## 2026-09-09 VERDICT 9 (FIX-AND-RECORD #5): ONE-CLOCK law — origin is derived, never learned
Credits ran out mid-run yesterday; the edit was found complete in the
kmedia worktree (verified: build clean, playertest CLEAN EXIT) and
committed this session.

Root cause (final form of the +707ms fingerprint, four binaries):
stream_origin_us was LEARNED from first decoded output. After a
BACKWARD seek the pre-target keyframe always decodes first and taught
the origin keyframe→target µs too early; the audio clock was born that
far in the future and every frame read exactly that much late, forever.
Fix: the origin is DERIVED at seek/open from the one value both doors
already agree on:
  origin = cont_start + seek_floor  (post-seek)
  origin = cont_start               (fresh open from t=0)
Live streams keep the learn path (no container timeline). The video-path
learning code is deleted; the old learn lines elsewhere are now dead
code (origin always set first) — left for the close-out sweep per
Barticus.

WHAT CHANGED (running list, newest last):
- kmedia 7d2b169  Player.zig  ONE-CLOCK law (committed 2026-09-11)
DEPLOY: /usr/local/bin/kidulwm = sha256 be466344… = 286a76b/7d2b169
ReleaseSafe, deployed 23:4x (.bak-pre-oneclock kept). Reload + repro:
resume Raya — lag must be ≈ 0 from frame zero (NOT +707ms), PRES p50
≈ 41.7ms, DROP/STARVE ≈ 0; next file committed>0 from t=0. VFPTS probe
from 0b8b773 still in the build if a packet needs naming.
Boot stamp must read kmedia=7d2b169.

## PRIME SUSPECT (stutter) — playTimerMs() ceil bug, KidulWM src/server.zig
  143.998Hz panel → 6.945ms vsync → @divTrunc(+999) ceil → 7ms timer.
  Timer at 142.9Hz vs panel 143.998Hz → present phase drifts ~1Hz →
  periodic judder beat. Code's own comment warns firing early drifts
  phase, yet it CEILS. Fix direction: fire at or just under vsync
  (floor, or fractional timer), verify against scorecard late_avg/drops.

## DEPLOYED STATE (verify hashes, never assume)
- /usr/local/bin/kidulwm = 1f934d708ee72c50afad95552fe07a17a1fbfbdbb6db70a314d3786908d4577b
  = commit 2e37c87 (signed) — [present] instrumentation. DEPLOYED 09:58 via
  mv-aside (old binary kept open by running compositor → .old-running).
  Takes effect ONLY AFTER Barticus reloads the compositor session.
- kidulwm-session: KMEDIA_TIMING=1 exported (line 26, .bak kept) so the
  in-process player's Timing.zig writes /tmp/kmedia-timing.log every boot
  during the hunt.
- KidulWM commits: 8ff8b0a (vsync-cadence timer, has the ceil suspect),
  2e37c87 ([present] probes). kmedia: f5c082c (displayed_pts_us stamp).
- Old running binary: /usr/local/bin/kidulwm.old-running (pre-2e37c87).
- .bak-5b0d95e also exists. session wrapper bak: kidulwm-session.bak.
- Watchdog: kmedia-watchdog.service active, /var/log/kmedia-watchdog.log.
- Persistent compositor log: ~/.local/state/kidulwm/session.log.

## WHAT THE SENSORS SHOW (the scorecard: kmedia/tools/census-scorecard.py)
  python3 /home/dad/dev/kmedia/tools/census-scorecard.py [start_iso] [end_iso]
- PLAYER side (/tmp/kmedia-timing.log): PRES delta histogram = cadence,
  lag = a/v drift, DROP/STARVE/AUGAP = decode/ring health.
- COMPOSITOR side ([present] in session.log/journal):
  per-frame: surface, gen, cache hit/miss, late=Xms (audioclock-pts proxy)
  per-sec:   committed=N dropped=N hit=N miss=N memcpy=N late_avg late_max
- WATCHDOG: frames/s, media_open/ready/active flags, i915 irqs.

## VERDICT KEYS — what answer looks like what
- STUTTER: PRES delta p95 tight + [present] dropped rising + late drift
  pattern → cadence/timer (ceil suspect). PRES delta p95 huge + STARVE →
  decode starve → file-side. AUGAP spikes → audio ring.
- INVISIBLE B: [media] "gen now" bumps on stop; play B shows
  committed=0 with cache=miss+surface reused → cache/lifecycle STILL alive.
  committed=N but black → scene-node/present path, not cache.
- LOCKUP: watchdog heartbeat stops → compositor dead; heartbeat lives,
  frames/s 0 → GPU wedge (i915 irqs frozen) → journal for i915 errors.

## REPRO SCRIPT (Barticus runs, Bob watches live)
  play video A ~30s → close slide → reopen → play video B.
  Bob tails: ~/.local/state/kidulwm/session.log + watchdog + timing log.

## 2026-09-11 VERDICT 10 (OPEN, recorded for HANDOFF): fixes ran, ALL symptoms persist
Repro (Barticus, fresh session on the deployed 7d2b169 binary — sha256
be466344 = KidulWM 286a76b / kmedia 7d2b169, ONE-CLOCK law live):
- Raya STILL stutters.
- Second video STILL invisible.
- Butterfly widget STILL out of whack: movement stops & starts, shows
  media when media is no longer playing (verdict-3 silence watchdog did
  NOT kill it), song names render in the BOTTOM half of the butterfly
  instead of ON TOP of it.
- MEDIA SLIDE IS NOT A SLIDE (law violated): moving through the deck,
  the media slide STAYS in the focused area above or below the focused
  slide. It does not ride with the others. 8cd0a02 ("retire the
  sentinel, normal deck slide") did not deliver the actual behavior.

BARTICUS DIAGNOSIS (accepted): "our problem is a complexity that we
made, that needs to be gone." Nine verdicts on the clock seam; every
fix was individually verified yet the session symptoms never died.
The slide-not-a-slide integration is the structural smell — the media
slide still has special-case positioning/lifecycle instead of being
one more slide in the deck.

DECISION: media player investigation PAUSED per Barticus. Fresh eyes
after the browser works. No more patches on this seam until then.

TODO when the hunt resumes (fresh-eyes checklist):
  1. Slide geometry: why does the media slide pin above/below focus
     instead of riding the deck? Diff 8cd0a02's intent against the
     actual slide-layout code path (slide deck focus/scroll vs the
     media slide's position source).
  2. Butterfly widget: (a) liveness still not dying on stop — the
     verdict-3 watchdog path did not hold in real use; (b) song name
     placement = on TOP of the butterfly, not bottom half.
  3. Clock seam: verdict 9 (ONE-CLOCK) unverified-in-session — the
     stutter/invisible pair survived it. Next repro reads VFPTS lines.

## 2026-09-12 VERDICT 11 (IN PROGRESS): ONE-TRUTH architecture — the stale dot's real name
Session triggered by Barticus: butterfly shows dot + lines with NOTHING
playing, all sink-inputs empty. Live census proved it:
- pactl: zero sink-inputs; monitor tap records rms=0.000000 peak=0.000000
  (3s direct capture) — PipeWire is feeding the FFT pure silence.
- The only "holder" is our own tap: source-output "kidulwm-kmedia" on the
  analog sink monitor (core/kmedia.zig capture thread, permanent by design).
- Watchdog heartbeats: media_open=false active=false; player fully closed.
So the lit widget is compositor-internal state, not audio.

THE ROACH (Barticus): "how can a movie that relies on ms timed sound have
2 or more sound timelines?" We had THREE "is it live" answers:
  1. ksound's floor table (the real one — dead service, never consulted)
  2. FFT rms_slot residue in core/kmedia.zig (the lying one — sampled
     loudness re-purposed as liveness; verdict-3 watchdog didn't hold)
  3. player_active/player cached state in the media slide
The butterfly (a REACTOR, never a participant) was drawing whichever was
stalest. Same family as the +707ms clock fight: state re-derived in
consumer code instead of read from its owner.

THE ONE-TRUTH ARCHITECTURE (locked in-session, Barticus):
  - TALKING (is audio live): ksound's stream table ONLY. pw_watch already
    tracks every stream with class/role/corked. ksound gains an
    audio_live socket verb answering 1/0 over that table (non-corked
    output streams with live owners; LISTENING taps excluded by class).
  - LISTENING (FFT monitor tap): loudness food ONLY — rung energies while
    ksound says live. level()/bands() stop being a liveness oracle.
  - CLOCK: kmedia Player.zig DAC anchor, ONE timeline (verdict 9 stands).
    ksound carries NO clock — it arbitrates, never timestamps.
  - TRAY: zero media-liveness derivation. Both tray.zig:3680 and
    media.zig:1498 delete their local `level() > 0.03` duplications and
    read one bool: kmedia.audioLive() (ksound socket, ~100ms cache,
    non-blocking; daemon absent = not live).
  - BUTTERFLY: pure reaction — breathes with what plays, owns nothing.
    "The butterfly should never stop" while ksound says someone talks.
  - TITLE/SONG DETAILS: own dedicated space ABOVE the butterfly, never
    drawn inside the helix lane (kills verdict-10's "song names in the
    BOTTOM half"); that space may be interactive, but it is its own
    region, not the butterfly's.

Law audit (sound.md, full re-read 2026-09-12): clean of everything we've
been fighting — no tray invitation (face owns ONE control + chime
button), LAW 7 already writes honest-clock as law, LISTENING vocab
already defines the FFT tap as floor-less. ONE GAP: the law never says
who answers "is audio live?" for the face — the hole this bug grew in.
Lock amendment to add when this lands: "The face asks the floor table
for liveness; the meter answers loudness, never liveness."

WORK ORDER (search & destroy per census law):
  1. ksound: audioLive() over the table + `audio_live` socket verb.
  2. ksound.service: enable + start; verify socket answers 0/1 live.
  3. KidulWM core/kmedia.zig: pub fn audioLive() (ksound, cached).
  4. tray.zig + media.zig: delete both level()>0.03 derivations → bool.
  5. media.zig renderPeek: title lane moves ABOVE the helix, own space.
  6. ReleaseSafe build, deploy, Barticus reloads, repro closes:
     dot dead with nothing playing; butterfly breathes while playing;
     title sits in its own space above.

## 2026-09-12 VERDICT 11 LANDED (reload pending):
- ksound c2d0500  pw_watch.audioLive() + audio_live socket verb.
  VERIFIED LIVE: '0' with empty floor; '1' with a real pacat stream;
  an orphaned pacat (killed wrapper, ppid=1) honestly reported '1' —
  the truth includes ghosts, exactly as the law wants. FFT monitor tap
  (Stream/Input) correctly ignored. NOTE: hit the HANDOFF cold-cache
  trap — warm zig-cache shipped a binary WITHOUT the new verb; rm -rf
  zig-out .zig-cache is the build protocol. Pre-existing ksoundtest
  floor5 failures (2) confirmed on clean HEAD, not from this change.
- KidulWM 24eff5a  core/kmedia.zig audioLive() (unix socket, 100ms
  cache, 50ms io deadline, daemon-absent = not live) + tray.zig &
  media.zig FFT-liveness derivations DELETED + movie/TV title moved
  to the reserved title lane above the helix (own space).
- ksound.service: enabled + active (ExecStart dev path zig-out/bin).
  Daemon must be running for the widget to light — intended: no
  daemon, no truth, butterfly rests (never hallucinates).
DEPLOY: /usr/local/bin/kidulwm = sha256 830e6604… via mv-aside
(.bak-pre-onetruth kept). REPRO after reload:
  1. Nothing playing → no dot, no rung lines, within ~1s (100ms cache).
  2. Play music → butterfly breathes, title ABOVE the butterfly.
  3. Play movie → title in the same top lane, not the bottom half.
  4. Boot stamp proves kmedia=7d2b169 + new kidulwm commit.
PENDING: sound.md law-lock amendment — "The face asks the floor table
for liveness; the meter answers loudness, never liveness." (Barticus)

## 2026-09-12 VERDICT 12 (FIX-AND-RECORD #6): the clock is born in the future — host PROVEN innocent
Barticus: "maybe a single test to see if it is our player or the host."
New harness: kmedia test_clockprobe.zig (`zig build clockprobe`) —
headless Player.open(resume Raya 23s) + real host sink + tick() at
vsync cadence, NO compositor, NO PipeWire mixer in the decision path.
lag = masterClockUs - displayed_pts_us per present.

HEAD (7d2b169, ONE-CLOCK live): lag p50 = +923ms, CONSTANT, aq=0.
0c5308c ("ZERO-COPY" known-good): same shape, worse (no rebase at all).
The bug reproduces with zero host involvement → Player.zig, always was.

Mechanism (probe data, not theory):
- AUWR wall-delta p50 = 7µs per 833µs chunk — pa_simple_write returns
  INSTANTLY into PipeWire's 100ms tlength; the aud_ring drains to 0
  while the DAC has played almost nothing.
- The anchor then stamps pts + dur as if the DAC had played it → the
  clock is born ~(all queued audio) in the future and every video
  frame reads that much late, forever. Drop-storm → STARVE → burst →
  stutter; on next-file open, born ~1s ahead → frames dropped →
  committed=0 → the transparent movie. ONE mechanism, both symptoms.
- Why 4K/60Hz shows it and 144Hz hides it: same constant offset, but
  the 4K present path has no refresh headroom to mask the judder.
- Sink latency probe: PipeWire honestly reports 45-99ms unplayed
  (tlength) while letting us sprint ~1s ahead. We just never asked.

FIX (kmedia 03e4e6f): anchor subtracts pa_simple_get_latency() — "what
the DAC is playing NOW", mpv's audio-law line we never implemented.
Recovers ~80-90ms (the sink's own queue). PARTIAL: the remaining
constant is the ring-drain history at clock birth — the throttle +
anchor + latency submission arithmetic is three patches over one
missing truth: THE GRAPH MUST PACE THE CLOCK, not the other way round
(Barticus: "we have been anchoring off the sound when we should be
doing the reverse"). That rewrite is next, with clockprobe as harness.

WHAT CHANGED (running list, newest last):
- kmedia 03e4e6f  Player.zig DAC-latency anchor + test_clockprobe.zig
DEPLOY: /usr/local/bin/kidulwm = sha256 0729cfb0… = 27eeddd/03e4e6f,
deployed 12:0x via mv-aside (.bak-pre-latency kept). Reload + repro:
lag must DROP by the sink's latency; stutter/invisible persist =
verdict 13's graph-paced clock. Boot stamp must read kmedia=03e4e6f.

## 2026-09-12 VERDICT 14 (FIX-AND-RECORD #7): THE FREEZE — pkt ring storage
Two boots, same death: smoothest playback yet (~30s), then whole-machine
wedge, power-button recovery, ZERO journal (journal tail: kmedia stream
appears 13:31:26, then silence; watchdog: RSS 350MB→1.1GB in 7s at open,
stable 1.1GB, then heartbeat ends mid-line). A userspace crash leaves a
journal; this was kernel-side (zram + VA-API dmabuf pressure + i915).
Root cause (PROVEN in code): verdict 13 raised PKT_RING_FILE 64→2048 but
pktRingType's array, head/tail modulo AND clear loop all stayed 256.
count climbed toward 2048 against 256 slots — head lapped tail,
counted-queued packets overwritten/leaked, back-pressure fired ~8x late,
reader sprinted the demux/decode buffers into memory death. Both freezes
occurred only on the graph-paced build — the only one carrying 2048.
FIX (kmedia 67f77a0, dac-paced-clock): PKT_RING_STORAGE = PKT_RING_FILE;
array, both modulos and clear loop use STORAGE; caps stay 256 live /
2048 file below it. playertest CLEAN EXIT.
DEPLOY: /usr/local/bin/kidulwm = sha256 073c423d… = kidulwm 27eeddd +
kmedia 67f77a0 (stamp 67f77a0 verified in-binary), via mv-aside
(.bak-pre-ringfix kept). REPRO: same playback that froze twice must now
run past 60s+ with RSS stable and no wedge. Boot stamp kmedia=67f77a0.

## STANDING OPEN (from HANDOFFs, not this hunt)
- pause-pill chrome placement (letterbox gutter anchor) — cosmetic, parked.
- backups owed: 67+ commits ahead (sda1/Codeberg/Apocalypse).
- 2 uncommitted debug log lines in KidulWM src/ui/media.zig (gen logging)
  + HANDOFF.md addendum — leave them, commit when hunt closes.

## 2026-09-12 VERDICT 13 (IN PROGRESS): graph-paced clock + screens census
Branch dac-paced-clock (kmedia). Clock-patch pile (ffc8877→03e4e6f, eight
commits) DELETED and replaced with: absolute pts end-to-end + ONE anchor
line (pts_anchor = chunk_end_pts - pa_simple_get_latency) + seek_armed
gate. playertest CLEAN EXIT; clockprobe STILL shows +800ms constant —
but the LAT probe acquitted the sink (honest 80-100ms) and AUWR showed
audio pts advancing at rate 0.609 vs wall (bursty underrun feeding, NOT
a racing clock). The constant is NOT DAC sprint — census continues.
SCREENS CENSUS (Barticus questions, this session): NO master/slave
exists today — every output owns a full media_slide + tray widget +
player, and playTimerMs() SEARCHES outputs for an owner. Two seams
named: (A) playTimerMs ceil ms-timer vs exact µs grid = ~1.14Hz beat
(PRIME SUSPECT since 09-08, still live); (B) timer follows first-found
owner. Barticus law (locked in speech): ONE Master screen holds ALL
widgets + controls + truth; slaves present slides only; slides ride
focus; grid borrows the presenting screen's crystal. "One computer, one
compositor, one player, one clock — screens are windows." Latency of
Master ownership = ZERO (intra-process; HDMI carries pixels only).
LAW DOC: KidulWM docs/law/screens.md (DRAFT, awaits Barticus lock).
The crawl (Star-Wars app launcher, bottom-center, big white letters,
border-colour idle / white focus) = Barticus design, tray-as-we-know-it
retired to a later date — parked as future taskcard.
Seek & destroy mandate granted 2026-09-12; keep notes along the way.

## 2026-09-12 LAW EVOLUTION: Master/slave-screens REPLACED by Boss/slaves/pack
Barticus: "Master & slave screen is the wrong metaphor — the Master is
the COMPUTER; all screens are slaves, numbered (1,2,3...); slave 1 gets
the PACK (widgets+controls+crawl) by default; users can move the pack;
headless = 0 slaves." "1 boss 1 truth — we have been saying this all
along; giving it to anything else is actually silly. The Boss sends the
visuals to the screen & sound to the speakers — on time every time."
docs/law/screens.md rewritten in the new vocabulary (6 laws: Boss /
slaves are addresses / the pack / slides ride focus / one clock
borrowed crystals / latency honesty). DRAFT — awaits Barticus lock.

## 2026-09-12 VERDICT 13 (CONT'D): rings fixed, lag cut to ~20ms, drift named
dac-paced-clock branch state: AUDIO_RING 32→1024 (was a 27ms buffer
pace-locking the decode thread — chunks on Raya are ~1ms NOT 21ms),
PKT_RING_FILE 64→2048 (was ~1.5 video frames — every demux audio-run
starved video: 54v vs 2671a packets in 2s), anchor = chunk_end −
pa_simple_get_latency (LAT probe: honest 80-100ms), absolute pts
end-to-end, hr-seek floor as pure presentation filter, clock clamps
deleted. clockprobe: first-present lag fell +800ms → ~20-60ms at wall
1.5s (was 775ms). presents 133→213/10s. REMAINING: audio pts_rate
decays 1.01→0.89 after ~4s (PipeWire pulling at ~0.89× while honestly
reporting 80-90ms occupancy; WR probe: writes succeed in ~8µs, stream
live+uncorked on the real analog sink). Video stays glued to audio
(skew constant) so a/v sync itself is FINE — the drift is clock-rate
vs wall, only visible as lag growth vs pts. Suspects: PipeWire rate-
match/resample bookkeeping vs pa_simple_get_latency, or tlength=100ms
starving the mixer quantum. Live session repro will tell whether the
deployed path (HDMI sink) shows it at all — probe uses analog.

## 2026-09-12 VERDICT 13 DEPLOYED (reload pending)
- kmedia cf68efd (dac-paced-clock branch, SIGNED): graph-paced clock,
  ring pile deleted. Committed with full census mechanism in the message.
- KidulWM rebuilt ReleaseSafe (27eeddd + kmedia cf68efd statically
  included; stamps verified in-binary: cf68efd + 27eeddd present).
DEPLOY: /usr/local/bin/kidulwm = sha256 293ca6e1… via mv-aside
(.bak-pre-graphpaced kept). Barticus reloads + repro:
  1. Raya resume 23s: lag ≈ 0 from early presents (NOT +700ms pinned),
     PRES p50 ≈ 41.7ms, DROP/STARVE ≈ 0.
  2. Next video: committed>0 frames from t=0 (no transparent movie).
  3. Boot stamp must read kmedia=cf68efd.
  4. WATCH: drift — probe showed audio rate 0.89× vs wall on the
     ANALOG sink after ~4s (a/v sync holds; video glued to audio).
     If live HDMI path shows position-counter drift, next census is
     tlength/PipeWire quantum interaction. KMEDIA_TIMING=1 is live in
     the session wrapper — /tmp/kmedia-timing.log has LAT/ANCH/WR.

## 2026-09-12 VERDICT 15 (FIX-AND-RECORD #8): THE 20s CRASH — dmabuf cache vs ring size
Barticus: "media player is still crashing after 20sec." Search & destroy
granted. The watchdog log told it in one window, same shape EVERY boot:
- 17:22:14 media slide open, rss=357MB. RSS sprints ~15-35MB/s
  (+216MB in ONE second at 17:22:34), 774MB at 17:22:37 — last
  heartbeat. 17:24:00: [ERROR] [render/dmabuf.c:23]
  fcntl(F_DUPFD_CLOEXEC) failed: Too many open files ×4 → compositor
  dead, session restarts. Boot -2: identical at 16:19:49-52.
- Not OOM — the compositor runs out of FILE DESCRIPTORS (soft
  RLIMIT_NOFILE=2048). ~5 fds/frame at 24fps ≈ EMFILE in 17-20s =
  "crashes after 20 seconds", exactly.
Root cause (PROVEN in code): kmedia VIDEO_RING_SIZE went 8→16 (verdict
5/13) but the slide's dmabuf_cache stayed [8] (media_slide.zig). The
live VA surface set = ring 16 + displayed frame + decoder DPB refs
(~4-8) — it outgrew the cache the moment the ring doubled. EVERY frame
became a cache MISS: vaExportSurfaceHandle + DmabufBuffer.create +
evict-drop + setBuffer with a different buffer → wlroots texture
destroy/create churn → render/dmabuf.c F_DUPFD_CLOEXEC leak — the
EXACT 2026-09-08 fd-leak mechanism, re-armed by the ring resize. The
09-08 RENDER-ONCE fix only guarded the hit path; with a thrashing
cache the hit path never ran. Leaked fds pin GEM buffers = the RSS
sprint. One seam, both numbers (fd count AND RSS).
FIX (KidulWM 0dfbc46): dmabuf_cache 8→32 (ring 16 + headroom; SIZE LAW
comment in media_slide.zig), plus a CACHE-THRASH probe in
media_video.zig: misses >48 and climbing logs "[media] CACHE-THRASH"
loud — the census sees the next size mismatch before EMFILE does.
Also rode along in the commit (previously uncommitted in tree):
6309562's pointer-enter fix state + docs/law/kvis.md + theme/style
edits — noted so the record is honest.
DEPLOY: /usr/local/bin/kidulwm = sha256 df5ace07… = kidulwm 0dfbc46 +
kmedia c704ce5 (kvis seal; in-binary stamp verified), via mv-aside
(.bak-pre-cache32 kept). REPRO after reload: play 60s+ — RSS must sit
FLAT after pool warmup (~<400MB), [present] cache=hit after the first
~16 frames, zero CACHE-THRASH lines, no F_DUPFD errors, no wedge.
Live fd check during playback: ls /proc/$(pgrep -x kidulwm)/fd | wc -l
must stay bounded (~150-250), not climb to 2048.

## 2026-09-12 VERDICT 17 (FIX-AND-RECORD #9): THE PREWARM OOM — card repaint guard
Barticus: crash "a little different, survives a few seconds longer" after
verdicts 15+16. coderBob (session 20260912_214946_a87f5c, cut off by HTTP
402 at 166 msgs — report lost, commit landed and signed before the cut).
Watchdog window (17:22 session): RSS 356→523MB over 17s while
media_open=true ready=true active=FALSE (the prewarm window between
media_play IPC and player active=true), then +216MB on active=true
(dmabuf pool warmup, expected), dead at 773MB. Same shape every crash
window: RSS climbs BEFORE active=true — verdict 16's guard only covered
the playing phase.
Root cause: mediaSlideRefresh is called from applyLayout on EVERY layout
event while the slide is open. renderToBuffer allocates a 33MB ARGB32
cairo surface per call; prewarm layout re-fires pile up simultaneous
GPU-held bufs → 20-35MB/s RSS growth → OOM.
FIX (KidulWM 417aecc, B&B signed): card repaint guard in
mediaSlideRefresh (!playing branch) — skip renderToBuffer when target
geometry AND widget.state_generation are unchanged and card_dirty=false;
guard-skipped calls still reposition the existing card node.
state_generation bumped on every real mutation (key/play/stop/art);
card_dirty belt-and-suspenders on open/play/stop paths.
Result: one fixed 33MB card buffer held instead of a new one per layout
event; prewarm RSS growth eliminated. Fullscreen-fill geometry, VSYNC
SELF-PERPETUATION, no-stills reconcile, isDone teardown, slideless music
pump all preserved (guard touches only the !playing renderToBuffer path).
BUILD: zig build Debug exit 0; ReleaseSafe exit 0 (verified independently
by orchestrator, sha256 d230e07c13c7322c…).
DEPLOY: /usr/local/bin/kidulwm = sha256 d230e07c… (kidulwm 417aecc),
sudo install, 2026-09-12 ~22:10 AEST. REPRO after reload: open slide,
idle on card 60s+ — RSS must sit FLAT while active=false (no 20-35MB/s
climb), then one bounded jump on play (pool warmup only), then flat.
STILL OPEN: (a) mpv-style timings — the current timer cadence is
vsync-derived (playTimerMs(), TIMER CADENCE LAW 2026-09-08 comment);
true sleep-until-due off the audio clock + playback-rate combos (0.5x/2x)
were on coderBob's card but NOT landed when credits died — next dispatch.
(b) kidul-browser input on engine & pages — separate card, not started.

## 2026-09-15 VERDICT 18: BROWSER POINTER — compositor never called pointerNotifyEnter
Symptom (Barticus): browser pages take NO mouse at all (no hover/click/
scroll), keyboard reaches chrome but page typing dead; 'google' page
autofocuses its searchbar yet nothing types.
Chain: wlroots drops pointer events when no focused pointer surface.
pointerNotifyMotion was being called but pointerNotifyEnter never was —
keyboard worked only because keyboardNotifyEnter was wired. Zero
wl_pointer events ever reached the browser surface.
FIX: commit 6309562 (found uncommitted after the 2026-09-12 credit-death,
committed as-is per rescue law). server.zig pointerEnterAtCursor()
resolves the scene node under the cursor to its wlr.Surface and enters
it (guarded on surface identity); pointer.zig enter-before-notify on
motion/abs/button. PTR-PASS/BTN-NOTIFY probe logging still live.
Deploy was the missing piece: the fix sat committed-but-unbuilt for 3
days; pre-fix binary d230e07c kept running. Built ReleaseSafe and
deployed by orchestrator 2026-09-15 ~08:07 AEST:
/usr/local/bin/kidulwm = sha256 09a12fa9e0a26dc0… (main cde8b2d incl.
6309562). Takes effect on session reload.
BROWSER SIDE (kidul-browser repo, deployed 2026-09-12, sha256 shell
026e08d6 / renderer 93aaa64d): ALL JS input injection deleted
(synthetic KeyboardEvent / elementFromPoint().click() / window.scrollBy
— engines ignore untrusted events, hence autofocus-but-no-typing).
Renderer now fabricates genuine GdkEvents (window, time, keymap-resolved
keycodes, button/modifier tracking) delivered via gtk_widget_event()
straight to the WebKitWebView + gtk_widget_grab_focus on realize.
gtk_main_do_event was tried first and died silently (GDK dispatches via
focus/grab bookkeeping the renderer holds none of) — renderer input law
in the kidul-browser skill now records this. IPC gained pointer_motion,
pointer_button press/release, key_release; real wheel events.
REPRO (Barticus, after reload): load page → move/click/scroll, click a
field and type, Tab between fields. If pointer still dies:
grep -a 'PTR-\|BTN-' ~/.local/state/kidulwm/session.log — the probes
name the claimer. On success: strip probes and close the verdict.
STILL OPEN: (a) mpv-style timings (verdict 17 tail, unchanged).
(b) tray.zig removeOutput listener-lifetime crash on deinit (2026-09-12
autopsy item 1). (c) probe strip pending repro.

## 2026-09-17 VERDICT 28 (bobdotrix): media slide's future is kvisd — the embedded player is EOL

Evidence session (kmedia HANDOFF session 22): the identical Player
engine that wedges/silences EMBEDDED in the compositor process plays
clean as kvisd (own process, kvis.sock protocol): VAAPI zero-copy,
EAC3+FLAC both loud, DAC-pure clock, 6.8% CPU, and ksound watched the
stream lifecycle without a leak. The day's "no sound" was ksound's
fade-restore ratchet (fixed, ksound b9ece85, deployed), never the
engine, never the compositor.

LOCKED CONSEQUENCE for this repo: ui/media.zig + media_video.zig
embedded-libkmedia path is scheduled for DELETION in kvis CARD 2b/2c.
Do NOT invest in its letterbox-offset / fullscreen-border bugs (kmedia
docs/design/kvis-process.md §9) — both die structurally when the slide
becomes a kvisd parent surface (one coordinate space, kvis letterboxes
inside its own surface; fullscreen = the subsurface edge-to-edge).

NEXT CARD HERE (attack order, kmedia HANDOFF has the full plan):
  1. server.zig: create wlr_xdg_foreign_v2 registry (wlroots-0.20
     headers on host: /usr/include/wlroots-0.20/wlr/types/
     wlr_xdg_foreign_v2.h; XML in /usr/share/wayland-protocols/
     unstable/xdg-foreign/).
  2. Media slide surface: zxdg_exporter_v2 export → handle string.
  3. Slide → kvis.sock client: open/parent <handle> <x> <y>/seek/pause;
     geometry moves ride the socket; unparent on slide close.
  4. Delete embedded module + present path; slide keeps ONLY chrome,
     geometry, focus. Music-peek (beefcaa) moves in CARD 3.
Acceptance: kvisd wedge cannot freeze the WM (LAW 5, crash containment
structural); slide paints letterbox matte and NAMES the corpse.

Session-21 wedge (verdict 19 tail, tray-path caveat): SUPERSEDED as a
hunt — if the wedge returns at all, it returns inside kvisd where it
can be named and killed. Do not re-probe the embedded path.
