# KSD RESET LEDGER — live state (bobdotrix, migrated from media census 2026-09-20)

Read THIS FILE first in any reset session. It is the live state of the Great
Reset (SYSTEM.md is the arbiter; this file is the running ledger). Update it
after every verdict. The old MEDIA CENSUS (embedded-player hunt, verdicts 1-28)
is retired — those verdicts live in git history and their laws survive in the
kmedia + ksd-input-claim-law skills.

# RELOG-IN-PROGRESS HANDOFF (bobdotrix 2026-09-21) — CHECK HUB, THEN GO NO-NVIDIA
#
# Barticus is reloading RIGHT NOW with the TV moved to the USB-C hub
# (verdict-51 re-cable). bobdotrix dies on this relog; this note is the bridge.
#
# BASELINE (pre-reload, captured): HDMI-A-1 = connected (TV on NVIDIA),
# card1 DP-1/DP-2 = disconnected, USB-C port0 had NO partner.
#
# FIRST POST-RELOG CHECK — did the hub work?
#   /sys/class/drm/card1/card1-DP-1/status  (or DP-2) == connected
#   AND /sys/class/drm/card0/card0-HDMI-A-1/status == disconnected
#   => TV now on Intel iGPU. That kills the cross-GPU staging wedge at the root.
#
# IF HUB WORKED — GO NO-NVIDIA STRAIGHT AWAY:
#   1. Confirm dGPU idle: nvidia-smi (P8/power state, no processes).
#   2. runtime_status at /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
#      == "suspended" (or at least not "active" while idle).
#   3. If still active, park it: runtime PM (auto) or blacklist nvidia modules
#      so decode+present are BOTH Intel. Record what you did in this ledger.
#   4. Re-run the wedge repro (media_play Raya): kidulwm RSS must stay FLAT.
#
# IF HUB DID NOT WORK (TV dark / still on HDMI-A-1):
#   DO NOT disable NVIDIA. The TV is the product display; a dark TV is worse
#   than the wedge. Report back, keep NVIDIA, wedge stays open (deferred).

# VERDICT 52 (bobdotrix 2026-09-21) — SCANOUT RECON DONE: present path has ONE seam, direct scanout is wlroots-native but unwired
#
# THE PRESENT PATH (confirmed in tree, wlroots 0.20.1):
#   Output.handleFrame (server.zig:310) -> scene_output.commit(null) (341) ->
#   sendFrameDone. Every frame walks the WHOLE scene graph and re-composites
#   through the GPU renderer. No direct-scanout attempt, no frame gating.
#   That one seam is the root of BOTH live symptoms: fullscreen video jitter
#   (no zero-copy passthrough) + idle 36% CPU (ghostty GTK4 commit ~14/s
#   wakes the loop, every wake = full re-composite of both outputs).
#
# WLROOTS 0.20.1 ALREADY EXPOSES EVERYTHING (bindings present, zero use):
#   wlr_output_is_direct_scanout_allowed, SceneBuffer.OutputSample.
#   direct_scanout, SceneOutput.buildState/commitState, StateOptions. We link
#   these and call none. The fix is wiring, not invention.
#
# THE STRUCTURAL BLOCKER TO SCANOUT TODAY (why fullscreen video can't scan):
#   kplayd's video surface is a SceneXdgSurface inside a per-window
#   scene_tree, raised to top but left BELOW overlay_tree. overlay_tree
#   (peek + chrome rings) is always enabled and raiseToTop()'d — peek hides
#   its child trees on fullscreen but the overlay_tree node itself stays up.
#   wlroots direct scanout requires a SINGLE buffer covering the output with
#   NOTHING above it, no scale transform. So today: fullscreen video =
#   wallpaper + layer strata + slide card + kplayd surface + overlay_tree all
#   composited. Scanout needs the fullscreen path to collapse to: kplayd
#   buffer alone, overlay_tree (and slide card + wallpaper) disabled/hidden,
#   opaque, exact-cover.
#
# NEXT CARD (render-path law, LOCKED docs/law/render-path.md): scanout first,
#   then gating. Card A = fullscreen-video scanout reachability: on focused
#   fullscreen video slide, disable overlay_tree + hide wallpaper/card so
#   kplayd's buffer is the sole cover, then verify wlroots engages direct
#   scanout (log evidence + CPU ~2-5%). Card B = frame gating: handleFrame
#   skips commit when no scene damage + no active animation + no pending
#   layout (kills the idle 36%). Slow path (thin tentacles) unchanged.
#   GHOSTTY FORK + slide-protocol/"GodCodeMode" = separate spec, wargamed
#   after this law lands. Cross-GPU re-cable (verdict 51) still deferred.

# WEDGE ROOT-CAUSED + FOCUS DEADLOCK (bobdotrix 2026-09-20 ~22:30) — VERDICT 51 (LOCKED 2026-09-21)
#
# WEDGE = cross-GPU staging retention (I4). Live repro (Raya, ACTIVE playback,
# kplay committing ~4754 frames, kplayd healthy 400MB): kidulwm 288MB -> 1003MB.
# smaps classifies the +722MB as PRIVATE ANONYMOUS mmap: ~22 chunks of ~27-30MB,
# rw- MAP_PRIVATE, RETAINED (kidulwm stays ~989MB after `close` verb to kplayd).
# Root = hybrid GPU: kplayd decodes on INTEL iGPU (renderD128, VAAPI); the 4K TV
# (HDMI-A-1) is on the NVIDIA dGPU (sysfs card0=0x10de RTX3060 owns HDMI-A-1;
# card1=0x8086 Intel owns eDP-1). Cross-vendor dmabuf import (Intel decode ->
# NVIDIA present) CANNOT zero-copy -> each frame = ~27MB CPU staging buffer,
# wlroots/GL retains them. Phase-2 "zero-copy ~2% CPU" bar is STRUCTURALLY
# unattainable while decode+present sit on different GPUs.
# DECISION (Barticus 2026-09-21, LOCKED): forget the NVIDIA side — drive the TV
# from the INTERNAL Intel GPU (fork b). Decode is already Intel VAAPI; presenting
# on Intel removes the vendor boundary that forced the ~27MB CPU staging buffers.
# No NVDEC, no PRIME offload. wlroots releasing the staging buffers on the
# copy path stays as defense-in-depth (land it regardless of the GPU fix).
# MECHANICS RESOLVED (bobdotrix 2026-09-21): HDMI-A-1 is hardwired to the NVIDIA
# dGPU (card0) — muxless laptop, no mux, no software routing. The Intel iGPU's
# only external outputs are DP-1/DP-2 = the Thunderbolt 4 / USB-C port. So the
# fix is a RE-CABLE: TV -> USB-C hub -> TB4 port, then park NVIDIA.
# DEFERRED ("later thing" — Barticus has a USB-C hub ready for it):
#   BARTICUS does: plug the TV into the USB-C hub / TB4 port (USB-C->HDMI).
#   BOBDOTRIX does, when re-cabled: (1) verify TV lights on Intel DP-1/DP-2;
#   (2) park/disable NVIDIA (runtime PM or BIOS); (3) re-run the wedge repro —
#   kidulwm RSS flat, no staging growth; (4) confirm audio still Intel HDA
#   analog (default sink already is); (5) close verdict 51, retire the
#   cross-GPU staging root-cause.
#
# FOCUS DEADLOCK (separate bug, found live): a .video slide that loses focus
# (focus-follows-cursor / walk) becomes PARKED; focusNext/focusPrev SKIP parked
# slides -> unreachable (no re-focus, no Ctrl+q quit). videoSlideSpawnRightOfPlayer
# guards `findKind(.video) != null` -> no re-spawn either. Net = stuck slide,
# recover only via overview/relog. Fix: focus walk must land on a parked .video
# slide, or the slide must unpark on quit.

# WORKBENCH (READJUSTED 2026-09-19): Phase 2 (RSS wedge) is GPU-only, so the
# workbench moves BACK TO THE HOST for this phase — kidulwm runs on the host's
# real i915/VAAPI/dmabuf (GL, NOT pixman). ksd-reset stays the software/pixman
# workbench for everything else. fresh-one FROZEN, never touch. Host deploy =
# ReleaseSafe build on host -> /usr/local/bin/kidulwm (mv-over swap + .bak).
# bobdotrix does NOT survive an sddm login — document handoff here first.
#
# CURRENT POSITION (2026-09-20 ~20:50): verdict 50 + tracer DEPLOYED 869c68a9
# (commits 57dab29 + f5b4beb signed B&B) AND RELOG DONE — running pid 830305 ==
# /usr/local/bin/kidulwm == 869c68a9 byte-identical, live since 20:39. Git HEAD =
# 3f381ff (2 doc-only CENSUS commits past the deployed code; nothing undelivered).
# 15 commits UNPUSHED to Codeberg (ledger earlier said 3 — stale; list below).
# FRAMETRACE live 10s idle sample: rendered 14.2/s, commit 9.4/s = ghostty 9.4/s
# (100% of commits), all 6 scheduleFrame sites flat, kplay=0 other=0. Idle
# committer NAMED = ghostty. NEW GAP: rendered 14.2 vs 9.4 commit = ~4.8 wakes/s
# with NO named source (not commit, not any scheduleFrame site) — next question.
# Phase 2 step 1 DONE (wedge owner = kidulwm), step 2 IN PROGRESS. Raya = video.
#
# SURGERY DEPLOYED (2026-09-20 ~22:00): per-output render counter. The global
# ft_rendered folded a 144Hz+60Hz two-output rig into one number, so the
# "rendered 14.2 vs commit 9.4" gap was un-attributable. handleFrame now bumps
# per-Output ft_rendered AND emits FRAMETRACE-OUT {s} rendered={d} per output.
#   Deployed c360c8cc (.bak-869c68a9), build+test clean, signed. RELOG OWED.
#   POST-RELOG (bobdotrix dies on relog): grep FRAMETRACE-OUT, compute per-output
#   rate deltas. Expect ghostty's 9.4/s pinned to one output and ~4.8/s of
#   self-wake on the other (eDP 144Hz prime suspect) — names the idle waster.
#
# POST-RELOG READ DONE (bobdotrix, ~22:07) — idle waster NAMED, eDP hypothesis FALSIFIED:
#   Relog done: running kidulwm pid 1691 (started 22:04) == /usr/local/bin/kidulwm
#   == c360c8cc (no "(deleted)" on exe -> per-output tracer LIVE). FRAMETRACE-OUT:
#   eDP-1 rendered FLAT at 425 (never climbs); HDMI-A-1 rendered climbs ~14/s.
#   => idle render is 100% on the 4K HDMI output; eDP 144Hz is NOT the waster.
#   Global: commit ~14/s, ghostty=100% (kplay=0 other=0); rendered~=commit~=14/s
#   now — verdict-50 chrome fix closed the old "rendered 14.2 vs commit 9.4" gap
#   (the mystery ~4.8/s self-wake WAS the chrome regen loop). Idle cost: kidulwm
#   31% CPU, RSS 273MB FLAT (no idle wedge), i915_irqs ~86-100/s; kplayd 27MB/0.1%
#   healthy. ghostty (stock GTK4, pid 2502) is the SOLE committer, mapped on
#   HDMI-A-1 (CHROME create output=HDMI-A-1). 17 KidulWM commits UNPUSHED; kmedia
#   still NO git remote.
#   NEXT (step 2 close, ONE probe): is each ghostty commit a tiny-damage 4K redraw
#   (-> compositor commit-path cost, fix THERE) or a full-surface repaint (-> GTK4
#   frame-clock/client misconfig, fix the CLIENT)? Check ghostty GTK env/config for
#   the ~14/s driver FIRST (no relog); else add damage-rect to commit path + relog.
#
# KEY FINDING THIS SESSION (Barticus caught it): the "thick tentacle" committing
# ~8/s at idle is a STOCK ghostty — CachyOS package ghostty 1.3.1-2.2, a full
# GTK4 + libadwaita + gtk4-layer-shell app (ldd confirms libgtk-4/libadwaita-1/
# gtk4-layer-shell). The stripped-back ghostty fork is the END GAME and is NOT
# built yet. So the idle commit rate is GTK4 frame-clock + libadwaita + GSK
# machinery, NOT a light terminal. kidulwm itself links NO GTK (pure Zig/wlroots/
# cairo; only transitive libglib). The Zig-GTK4 plan has NOT leaked into the
# compositor — it is a separate tentacle (rkt-dashboard/gauge shells).
# VERDICT 50 also killed a stale premise: "damage-clipped commit" is a NON-FIX
# on wlroots 0.20.1 (commit() takes StateOptions, damage is internal).
#
# NEXT SESSION (post-relog): read FRAMETRACE's ghostty=/kplay=/other= split to
# NAME the idle committer by rate. Then answer: is each ghostty commit a cheap
# damage-clipped redraw or an expensive one? Dig the GTK4 frame-clock driver.
#
# LOG-GATE DEPLOYED (verdict 46, commit 8f85879): dev-trace (handleCommit /
# setSurfaceOffsetForFocus / BTN-NOTIFY / PTR-ENTER / pointer-diag) demoted
# info->debug. /usr/local/bin/kidulwm = 4544249f (stamp 8f85879, kmedia 1db5571),
# .bak-37fcf59. TAKES EFFECT ON RELOG. Watchdog now logs kplayd RSS too.
# Commit NOT yet pushed to Codeberg (owes post-relog verify + push).
#
# FINDING (verdict 46): idle CPU ~30-55% is NOT the watchdog (0.2%) and NOT the
# logging (16 lines/s is cheap). i915_irqs climbs ~28/s while idle = continuous
# frame scheduling -> the RENDER LOOP is the suspect, not the commit path (the
# no-op guards already kill the commit->damage->redraw loop). This IS the
# Phase 2 compositor-side suspect (verdict 45), not scope creep.
#
# NEXT SESSION STARTS HERE (2026-09-20):
#   POST-RELOG STATE VERIFIED (bobdotrix 2026-09-20 ~15:52): relog ALREADY DONE
#   (kidulwm pid 465925, started 15:39:58). Running binary == deployed == HEAD:
#   kidulwm 4544249f (8f85879), kplayd 6b6b040b. Log gate LIVE + verified SILENT
#   (dev-trace grep = 0). RESULT: idle CPU STILL ~40% (kidulwm), i915_irqs still
#   ~100/s. Log gate is CONFIRMED not-the-fix — verdict 46 was right that logging
#   was never the cause. The render loop / damage source IS the target.
#   NEW DATA: eDP-1 = 1920x1080 @144Hz + HDMI-A-1 = 3840x2160 @60Hz (2 outputs
#   live). A 144Hz panel amplifies any residual idle damage into 144 commits/s.
#   Live windows: ghostty mapped (the 8 commits/s thick tentacle); video-slide-
#   host unmapped; kplayd toplevel NOT mapped (no video playing). kidulwm RSS
#   flat 528MB / kplayd 429MB — no wedge at idle, as expected.
#   BAR/BUTTONS HYPOTHESIS (Barticus) CHECKED: transport bar + 2 buttons are GONE
#   from the compositor (verdict 33 deleted media_video.zig; media.zig has zero
#   transport/seek/scrub/button code). mediaSlideRefresh is verdict-17 guarded
#   (not a hot loop). kplayd 0.2% CPU = not looping. So no compositor code is
#   "searching for" the absent bar/buttons. Idle wake = damage-driven render-loop
#   churn, NOT an orphaned bar/button poll.
#
#   NEXT (Phase 2 step 2, compositor side): instrument WHO schedules frames /
#   damages at idle — render loop is event-driven (no free-running loop;
#   scheduleFrame sites all bounded: peek minute-timer 1029, requestLayout 1164,
#   scale change 3623, one-shot wallpaper reveal 3872/3911/3942). Prime suspects:
#   ghostty commit damage (thick tentacle) and/or a requestLayout storm. THEN
#   Phase 2 step 1 HOST repro (media_play Raya, watch BOTH RSS in
#   /var/log/kmedia-watchdog.log) to name the wedge owner.
#   Raya: /mnt/sda_backup/Jelly/Kids Movies/Raya.and.the.Last.Dragon.mkv.
#   3 KidulWM commits UNPUSHED (8f85879, 34c129f, 38bc43a) — push owed. kmedia
#   checkout has NO git remote configured (flag).
#
# PARKED (at Phase-2 base):
#   - CONSOLIDATE kidulwm-development skill (100KB god-file at size cap).
#   - Prune 20+ /usr/local/bin/kidulwm.bak-* binaries.
#   - Weather widget redo (new design, not clamps — see verdict 27 below).
#   - Peek-unit law (%-of-peek sizing) — deferred polish pass.
#   - Screens law (Boss/slaves/pack) — docs/law/screens.md, locked.
#
# NEW CARD (2026-09-20, Barticus) — HOUSE TEXT-SIZE TOKEN + remote scroll wheel:
#   TBD date. NOT discussed before tonight. The idea: a smooth scroll wheel on
#   the remote adjusts text size on the focused slide, so Granny sets the right
#   size from the lounge chair, and ALL our apps come ready with the same sized
#   CFC text. The CFC payoff: one token, every app follows.
#   SHAPE (agreed in conversation): do NOT build per-slide "remote -> focused
#   slide -> that slide's font size" as a hack. Build ONE house text-size token
#   (per-output, integer-scaled, like the existing CFC scale law) that every
#   THIN-tentacle app reads through the one shared painter (kpaint — see the
#   thin/thick + kpaint discussion, also new this session). Remote scroll wheel
#   just nudges that single token; all CFC text follows. This is the typography
#   half of the renderer-unification decision, and it supersedes the parked
#   "kfiles font ramp (typography law)" crumb in HANDOFF.
#   PRE-EXISTING HOOKS: theme.toml [typography] font_size_s/m/l=13/16/22, loaded
#   once in core/theme.zig (fixed, not runtime). output_layout_config.zig:24
#   already tags "text size" as the future per-output setting shape. Integer
#   scale from pixel density (CFC scale law, server.zig ~3470) is the model.
#   Frontier: token must live per-OUTPUT (two outputs, different scales) and be
#   integer-scaled, never fractional, to stay crisp (CFC law).

# ─────────────────────────────────────────────────────────────────────
# PROCESS LAWS (load-bearing for all reset work)
# ─────────────────────────────────────────────────────────────────────
# FIX-AND-RECORD (Barticus 2026-09-09): when a verdict is PROVEN (root cause
#   named, mechanism shown in code/logs, not theory) and the fix is small
#   (same file, no interface change), fix immediately — don't wait for approval.
#   Still: repro closes the symptom; early fix != skip verification.
# CENSUS-FIRST, NO PATCHES ON THEORY. Name the boundary, THEN fix.
# ONE CHANGE PER DEPLOY. Commit immediately when something works.
# SESSION HANDOFF (Barticus 2026-09-19): bobdotrix dies on an sddm login —
#   do all host-prep that needs no login cycle, record exact next commands,
#   hand off. This ledger IS the bridge.
# Dmabuf cache-key law: never key a dmabuf cache on surface id alone (pools
#   reuse ids across decoders -> stale hit renders freed GPU surfaces).


## 2026-09-20 VERDICT 50: chrome cache-key false-miss FIXED; "damage-clipped commit" is a NON-FIX

FRAMETRACE read post-relog (live, 3f42fd60): rendered climbs ~13.6/s while ALL
ft_* counters stay flat (layout=26, peek=86, scale=2, reveal=310, notify=0);
commit climbs ~8.2/s. Confirms wlroots auto-schedules frames off the client
commit/damage path — the ghostty tentacle (~8 commits/s) keeps the render loop
awake. NOT any of the 6 scheduleFrame sites. Verdict 48's fork is resolved.

FIX (57dab29, signed): the label term in updateChrome's cache key
(window.zig:501) compared self.chrome_label.asSlice() against the computed
label. With edges==.all the computed label is null, so the term read "Ghostty"
vs "" and never matched -> full chrome regen on every updateChrome(.all). When
edges != .all it was a self-comparison that always matched. Zero discrimination
either way — and label changes already force regen via refreshPeekLabel zeroing
chrome_width/chrome_height. Dropped the term. Deployed 00245f4b (.bak-3f42fd60).

STALE-PREMISE CORRECTION (load-bearing): the ledger's next move — "damage-
clipped commit, scene_output.commit(damage) not null" — is a NON-FIX. On the
pinned wlroots 0.20.1 (build.zig.zon), SceneOutput.commit takes StateOptions
(timer/color_transform/swapchain), NOT a damage region. Damage is tracked
INTERNALLY (SceneOutput.damage_ring + private.pending_commit_damage). There is
no "full-scene redraw every frame, no damage clipping" to fix — commit(null)
already clips to the damage ring. The verdict-48 recon note was written against
the OLD wlroots mental model.

NEXT RECON (Phase 2 step 2, re-pointed): WHY does ghostty commit ~8/s at idle
(the thick tentacle), and is each commit a cheap damage-clipped redraw or an
expensive one? The idle CPU (~74% instant, i915_irqs ~106/s) is NOT full-redraw
cost and NOT the chrome regen (~0.3/s) — it is the render loop staying hot per
client commit. Dig the ghostty commit driver next.

## 2026-09-20 VERDICT 49: fullscreen side-effects gate on focused, not sticky flag — FIXED

Barticus hit it live during the Raya repro: the video slide "took over" — a
fullscreen slide walked off-focus stayed chrome-less and suppressed the peek,
so he couldn't reach it to close it.

ROOT: the .video slide's fullscreen flag is STICKY (set at spawn, stays until
Mod4+f toggles it). targetForSlide (slidedeck.zig 601) already gates fullscreen
GEOMETRY on delta==0 (focused) — so the rect correctly falls back to a standard
peek/windowed slide off-focus. But two side-effects read the raw flag:

  1. videoSlidePaint (server.zig 2241) — chrome decision: rendered zero chrome
     whenever fullscreen was set, even off-focus. Off-focus video got no border.
  2. peek visibility (server.zig 3235) — hid the peek while ANY slide was
     fullscreen, so walking off the fullscreen video left the peek suppressed
     and the slide visually unreachable (the "can't get back to it" symptom).

FIX (b3329c0): both now gate on 'fullscreen AND focused' (empty_slot==.none and
idx==focused_index), matching the geometry gate. Focused video = insta
fullscreen zero-chrome (unchanged); off-focus video = standard slide with
border + visible, reachable peek. Deployed 3f42fd60 (.bak-387008ec). RELOG OWED.

DESIGN NOTE (Barticus, locked): fullscreen is a property of the FOCUSED slide.
Side-effects (chrome, peek visibility) must derive from focus, never the sticky
flag. This is the FULLSCREEN-FOCUS LAW, noted in both code sites.

## 2026-09-20 PHASE 2 STEP 1 HOST REPRO — wedge owner NAMED (kidulwm, not kplayd)

Played Raya on the host (kidulwm live, i915 GL). Sampler (2s cadence, kidulwm +
kplayd RSS/CPU + FRAMETRACE + watchdog line) captured the full ramp.

MEASUREMENT (RSS):
  - kplayd HEALTHY: 429MB idle -> 577MB during decode -> 482MB after stop.
    CPU 0.4% throughout. Hardware decode + zero-copy import working as designed.
  - kidulwm THE WEDGE: 282MB idle -> 912MB during playback (+630MB in ~10s),
    then stepped up through the Bluey ramp to ~1160MB and PLATEAUED FLAT
    (1159.89MB for 60s+ post-stop, CPU ~33%). It does not release the ~880MB
    it gained — retention, not runaway growth: a one-time allocation that's
    never freed, consistent with the Phase 2 resource-pool wedge.

  => The RSS wedge owner is the COMPOSITOR (kidulwm placement/card churn),
     not kplayd. Verdict 45's "owner UNKNOWN" is now answered.

IDLE FRAMETRACE (verdict 48 tracer, live): rendered climbs ~13/s continuously
while ALL ft_* counters stay flat (layout=14, peek~8, scale=2, reveal=332,
notify=0). commit climbs ~8.7/s in lockstep (ghostty client commits). This is
the verdict-48 fork resolved: wlroots AUTO-SCHEDULES frames off the
commit/damage path — NOT off any of the 6 scheduleFrame sites. The ~8.7/s
ghostty client commit (the verdict-46 "thick tentacle") is what keeps the
render loop awake at idle. Next: damage-clipped commit (scene_output.commit
with damage, not null) to cut the full-redraw cost.

CHROME cache-miss bug (verdict 48) CONFIRMED live: 44 misses this session, all
'label X->""' gen 0->0 — the cache key never matches because chrome_label is
never cleared on regen. Candidate fix for next verdict.



## 2026-09-20 VERDICT 48: Phase 2 step 2 — frame-source tracer DEPLOYED; render-loop recon + chrome_label bug

RECON (bobdotrix, host kidulwm live, no theory):
  - Render loop is EVENT-DRIVEN, sole entry = Output.handleFrame (server.zig
    305): tick animations -> tick wallpaper reveal -> scene_output.commit(null)
    -> sendFrameDone. It does NOT re-arm frames.
  - scene_output.commit(NULL) = FULL-scene redraw every frame (no damage
    clipping) across BOTH outputs (eDP 1080p@144 + HDMI 4K@60). This is why
    each frame is expensive, independent of who arms it.
  - scheduleFrame has exactly 6 sites, all bounded/event-driven: peek
    minute-timer (1029), requestLayout (1164), scale-change (3625),
    wallpaper-reveal start (3874) + tick (3913), notification (3944). NONE
    explains ~100/s i915_irqs delta or ~38% idle CPU.
  - requestLayout is NOT storming: applyLayout logged 22x in a 2-min session.
  - CONFIRMED BUG (candidate fix, next verdict): chrome cache-miss loop.
    updateChrome (window.zig 493) computes label=null when edges==.all but the
    cache key still compares self.chrome_label (never cleared on regen), so
    every updateChrome(.all) regenerates the full 1673x1064@2x cairo chrome.
    40 CHROME create / 31 destroy in the 2-min log. Expensive but ~0.3/s —
    not the 100fps source alone.
  - libinput "system too slow" (30-134ms) = the event loop starved by whatever
    the render loop is doing. This is the user-facing symptom.

ACTION (deployed, awaiting relog): commit e4cd405 adds per-source scheduleFrame
  counters + handleFrame render count + client-commit count, logged 1/s as
  "FRAMETRACE rendered=.. layout=.. peek=.. scale=.. reveal=.. notify=..
  commit=..". Binary 387008ec at /usr/local/bin/kidulwm (.bak-eafc798e).
  Running process still eafc798e — safe, no relog yet.

OWED (relog kills bobdotrix): relog, then
  grep FRAMETRACE /home/dad/.local/state/kidulwm/session.log | tail -40
  READ: rendered delta/s = real frame rate. Whichever ft_* counter climbs in
  step with it IS the idle frame source. If rendered climbs but ALL ft_* stay
  ~flat, wlroots is auto-scheduling (commit/damage path) -> dig there.
  THEN: fix the chrome_label cache key; consider scene_output.commit(damage)
  instead of null for the full-redraw cost.
  5 KidulWM commits now UNPUSHED (8f85879 34c129f 38bc43a 8c5ce3b e4cd405).
  kmedia still has NO git remote (flag).

## 2026-09-20 VERDICT 47: focusOutputNext empty-stage desync FIXED; "WHERE AM I" systemic finding

TWO KEYS CONFIRMED LIVE (Barticus + session log):
  - Mod4+Ctrl+O (moveFocusedToOutputNext) WORKS — full move HDMI<->eDP observed
    (pos 123,1088 <-> 123,8, chrome scale 2<->1). ONE GAP: it never calls
    notifyScale, so the client is not told its scale changed on a cross-scale
    (1.0<->2.0) move — renders at the old output's scale. Visual fine; wasted
    GPU + latent wrong-size. Polish, not the bug.
  - Mod4+O (focusOutputNext) = the "everything weird" key. Root cause: it set
    focused_output = target UNCONDITIONALLY, then only focused a window IF the
    target deck had a slide. Empty eDP -> focused_output=eDP while the focused
    window stays on HDMI -> the two "where am I focused" answers desync ->
    cursor warp, spawn-target, and focus-follows all act weird.
  FIX (this commit): return early when the target deck is empty or in a
    virtual end-slot. focusOutputNext now only lands on a stage with a real
    slide. Build clean; deployed eafc798e (.bak 4544249f). RELOG OWED.

SYSTEMIC FINDING (Barticus, GSI): "every app suffers WHERE AM I with no
  answer." The compositor is the sole authority for client placement identity
  = output (enter/leave) + scale (notifyScale) + size (configure), and it
  answers inconsistently: notifyScale at map + scale-change ONLY (not on
  cross-output move); configure-size for the focused slide only (external
  clients grid-snap past it -> centered windowed 1673x1064, not fullscreen).
  mediaPlayer/kplayd, terminals, browser webkit all carry this wound. This is
  I1 restated for the placement domain. Candidate Phase-2/I1 card: ONE
  placement-identity path (output+scale+size) applied on every transition.

ALSO SEEN: libinput "event processing lagging / system too slow" (mouse +
  Planck dropping events) = the ~40% idle render loop starving the event loop.
  This is the user-facing symptom of the Phase 2 step 2 render-loop fire.

## 2026-09-20 VERDICT 45: PHASE 2 RESCOPED — pool owner moved to kplayd; DmabufBuffer is dead

ARCHITECTURE SHIFT (Barticus big-picture read, same day as verdict 44):
CARD 2b slice 4 (verdict 33) DELETED the embedded player, but SYSTEM.md's
Phase 2 target was never re-pointed. It still said the pool is "VAAPI surface
-> dmabuf -> EGL -> scene buffer, one owner" — a chain that no longer exists
in the compositor.

WHAT THE CODE SHOWS (bobdotrix recon):
  - kplayd is a separate process: decode + VAAPI + dmabuf + EGL import all live
    in kmedia (Gl.zig, ~2% CPU zero-copy path, landed 5273cab/0c5308c).
  - The compositor only tracks kplayd's toplevel (app_id com.kidul.kplay,
    classifyKplay) and pins it over the video slide rect (placeKplayWindow).
    That is pure scene-tree work — setSize/setLayoutTarget/setEnabled/raiseToTop.
    No dmabuf import anywhere in the compositor.
  - src/render/dmabuf_buffer.zig (DmabufBuffer) is DEAD CODE: zero importers,
    not in build.zig, last touched by 364a4cc (the deleted embedded player).
  - The compositor's remaining buffer work is CPU-side (DataBuffer cards, the
    media card's 33MB cairo renderToBuffer — guarded by card_dirty since
    verdict 17).

CONSEQUENCE: the old wedge suspects (SETBUFFER-IMPORT-CHURN,
UNTHROTTLED-IMPORT in placeKplayWindow/videoSlidePaint) describe the DELETED
import path. The wedge's current owner is UNKNOWN: kplayd RSS climbing = kmedia
pool work; kidulwm RSS climbing = placement/card churn. The host repro (step 1)
is now the FIRST deliverable of Phase 2, not a prelude — it names the owner.

SYSTEM.md updated: §4 + §6 Phase 2 rescoped, §3 item 2 + I4 re-pointed to
kplayd. QUALITY BAR added (LOCKED): media picture must match or beat the big
TV makers — zero-copy end-to-end, display-mode matching (24p -> 24/48/120Hz,
never juddered 3:2), VFR by construction. The pool is the foundation FOR that;
the presentation-timing lane (verdict 44) stays closed until the render loop
stops wedging.

ACTION: none to deploy. This is a spec correction + a dead-code finding.


## 2026-09-20 VERDICT 46: idle-resource audit — log gate deployed; render loop is the CPU suspect

Barticus asked whether our idle cost is the accumulated watchdogs/extras or
the compositor. Measured, not guessed (host, kidulwm live on i915 GL, no video).

MEASUREMENT:
  - kmedia-watchdog.sh = 0.2% CPU / 4MB RSS. NOT the cost.
  - kidulwm = ~30-55% CPU idle, 543MB RSS, 8 commits/sec from ghostty (id=4).
  - kplayd = 0.4% CPU, 451MB RSS retained AFTER closing Raya — a Phase 2
    leak-or-retention item to chase.
  - RAM split: KSD stack ~1.4GB (kidulwm 543 + kplayd 451 + ghostty 169 +
    hermes 236); the rest is host dev infra (mullvad 140 / ollama 44 /
    libvirtd 38 / Xorg-sddm-greeter 140) absent from a Granny TV. kidulwm
    grown 117MB->543MB with no per-feature attribution = the record-keeping gap.

FINDING: i915_irqs climbs ~28/s while idle = kidulwm continuously schedules
frames. The commit path already has no-op guards (setSurfaceOffset /
applyContainment early-return on unchanged geometry) so this is NOT the old
commit->damage->redraw feedback loop. The ~30-55% idle CPU is the RENDER LOOP
staying awake — the real compositor-side Phase 2 suspect (verdict 45), to be
perf'd after the log is silent.

ACTION (deployed, staged): commit 8f85879 (signed B&B) demotes per-commit /
pointer dev-trace (handleCommit, setSurfaceOffsetForFocus, BTN-NOTIFY,
PTR-ENTER, pointer-diag) info->debug — compiled OUT of ReleaseSafe, still live
in Debug builds. /usr/local/bin/kidulwm = 4544249f, .bak-37fcf59. Watchdog also
extended to log kplayd RSS (kplayd_rss/kplayd_cpu) — it was kidulwm-only, a
false-negative hole in the wedge repro. Commit not yet pushed to Codeberg.

OWED (relog kills bobdotrix): relog -> confirm log silent + re-measure CPU +
i915_irqs post-gate; then Phase 2 step 1 HOST repro (media_play Raya, watch
BOTH processes' RSS). If CPU is still hot, perf the render loop (scheduleFrame
re-arm) — that is on-path Phase 2 work, not a detour.


## 2026-09-20 VERDICT 44: timing-tweak detour CLOSED — grid + ring-depth reverted (scope creep)

The vsync presentation grid (90bfcb9) and per-stream ring depth (fbc27e2) are
NOT reset work — neither clears SYSTEM.md §5's bar. 24p-on-60Hz judder is a
DISPLAY-MODE issue, not a player-clock bug. The grid REGRESSED playback: tick()
anchored vsync_origin_us to the AUDIO clock (masterClockUs) but stepped it by
vsync_interval_us measured from wall-clock (MONOTONIC) frameDone deltas —
cross-timebase anchor, grid phase drifted off the real vsync -> added jitter.

ACTION (kmedia): e4ad0b9 revert grid, 7d6af90 revert ring-depth (parked in
history for Phase 2). Source byte-identical to b4149bd. Deployed kplayd sha
6b6b040b. EYE-TEST CONFIRMED (Barticus): playback back to prior state — grid
was the regression.


## 2026-09-19 VERDICT 43: blank-screen password LEAK — gracePeriod swallow (input-blind)

Coming back from smartLock idle blank, the tail of a typed password landed in
the FOCUSED TERMINAL. Root: blank is blanking-only (no lock), blind-first-press
swallowed exactly ONE key; everything after flowed to the focused app. TV =
shared appliance -> NO global lock; blank stays anti-burn; profiles/keyToOpen
are the primitive. FIX (24dd60d): while screens_off swallow every key; on wake
a 2s gracePeriod swallows all keys+pointer. Deployed de63c8d7.
OWED: relog + repro (type at blanked screen, nothing lands in terminal).


## 2026-09-19 VERDICT 42: BLACK-SCREEN root = z-order (kplayd buried under placeholder)

Sound plays, no picture: videoSlidePaint renders a black placeholder card, then
applyLayout re-raises it ABOVE kplayd's surface. Net z-order: overlay > black
placeholder > kplayd. FIX (ad11d7b): re-raise kplay_window after the slide-tree
raiseToTop. Deployed bf3c565f (superseded by de63c8d7 in verdict 43).
GHOST still OPEN (verdict 41 #2).


## 2026-09-19 VERDICT 40: WORKBENCH -> HOST + kidulwm GL deployed (0fc87a0d)

Phase 2 wedge is GPU-only -> workbench moves to the HOST (real i915, GL not
pixman). Deployed kidulwm 0fc87a0d + kidulwm-control 46b89df5. kplayd current
(579686c). Raya already in host library (hardcoded scan root
/mnt/sda_backup/Jelly/Kids Movies). NEXT: host repro (step 1).


## 2026-09-19 VERDICT 39: PHASE 2 STEP 1 — wedge does NOT repro in the VM; host path locked

Reproduced the media path in ksd-reset: kidulwm RSS flat (~90MB), kplayd
~390MB software decode, zero churn. Root: the wedge is dmabuf/EGL zero-copy
import churn (GPU-only); ksd-reset is pixman+shm. Repro rig made permanent
(kmedia-watchdog.service, linger fix). DECISION: repro moves to HOST (i915 +
VAAPI + dmabuf). Canonical test video = Raya; BBB deleted (corrupt).


## 2026-09-19 VERDICT 38: CARD 2 LANDED — kvisd -> kplayd rename (naming law §7)

Mechanical sweep, once, as its own card. kmedia f2ff36f + KidulWM efb98c6:
binary/socket/files/verbs all kvis->kplay (kplay.sock, KplayClient,
placeKplayWindow, classifyKplay). 0 "kvis" left in src/. Both repos clean.
Fossil /usr/local/bin/kvisd binary still on host (root-owned, no refs) —
remove whenever convenient.


## 2026-09-19 VERDICT 37: CARD 1.5 LANDED — terminal body-organ/tentacle split (I1, I2)

1) ESCAPE HATCH: getty@tty2 enabled (kidulwm owns tty1) — death no longer =
black screen. 2) TENTACLE LOGIC OUT OF THE FACE: spawnCommand no longer
fabricates envp; identity seeded ONCE in start() and inherited. Two terminals
collapsed to one (ghostty wrapper; alacritty deleted, Mod4+w parked).
Deployed bea11929.


## 2026-09-19 VERDICT 36: PHASE 0 COMPLETE — IPC control socket is a main-loop fd source (I5)

ipcThreadLoop/ipc_thread/ipc_running DELETED. Control socket (listener + every
client fd) is now a wl_event_loop fd source; handleLine/handleRequest run on
the MAIN loop. Three bugs fixed in the seam: (1) readClient parsed from `base`
(pre-read offset) -> dropped split-request lines (3s stalls); fix parse from 0.
(2) pending_video_spawn deferral is LOAD-BEARING for re-entrancy (keeps the
event-loop pump OUT of the read path), not merely thread safety; plus a
`reading` re-entrancy guard. (3) kvis.sock verbs were BLOCKING on the main loop
-> SOCK_NONBLOCK connect + non-blocking reply. ACCEPTANCE: 100x get_layout +
50x media_play, 0 fails, compositor alive. Commit a04c78c.


## 2026-09-18 VERDICT 35: IPC-thread event-loop re-entrancy — video-slide spawn deferred

SIGSEGV: IPC thread called handleRequest -> videoSlideHostSpawn ->
InternalClient.create -> pumpRoundtrip -> event_loop.dispatch(1), re-entering
the main loop while the main thread dispatched it = two threads, one wl_display.
FIX (737c2ed): media_play (video) sets pending_video_spawn + requestLayout();
the layout-pipe deferral runs the spawn on the main loop. ALSO separated the
FREEZE (still open): kidulwm RSS 167MB -> ~1.94GB over ~90s (~80MB/s) — the
wedge, now owned by Phase 2. (Rescoped by verdict 45.)


## 2026-09-18 VERDICT 34: kvisd classification + media focus gate

Four host-test symptoms, two roots. 1) kvisd set app_id AFTER toplevel creation
-> never marked is_kvis -> became a deck slide (black placeholder, chrome,
focus grab). FIX (4ea2bc7): classifyKplay on set_app_id, unlink from deck.
2) mediaSlideKey routed keys when a media slide EXISTED, not when FOCUSED. FIX:
bail unless focused centre slide is .media_player.


## 2026-09-17 VERDICT 33: CARD 2b slice 4 LANDED — embedded player DELETED  [the pivot]

The embedded libkmedia Player path is GONE. Playback = kvis.sock verbs only;
the compositor never decodes a frame. Deleted ui/media_video.zig (457 ln,
dmabuf present path), MediaWidget Player path, play_timer + handlePlayTimer,
all video presentation state. REDIRECTED: media_play -> KvisClient.open;
toggle/seek -> pause/resume/seek_rel; close -> scene-node destroy only (the
crash class is structurally dead). Commit d995800 + 38b3699 (two pre-existing
teardown bugs). Deployed c1afad6f. This deletion is WHY verdict 45 rescopes
Phase 2 — the zero-copy chain moved to kplayd with it.


## 2026-09-17 VERDICT 32: CARD 2b slice 3 LANDED — kvisd placement

kvisd video toplevel (app_id com.kidul.kvis) tracked server-side OUTSIDE the
deck — no slide/chrome/focus; placeKvisWindow pins its scene tree over the
video slide rect. Fullscreen = edge-to-edge zero chrome. Commit 6402578.
Deployed f2f642ac.


## 2026-09-17 VERDICT 31: CHROME LAW locked + boot-open gated

198d057: A5 boot ladder behind KIDULWM_BOOT_MEDIA (host default OFF). 228abf6:
CHROME LAW (LOCKED) — fullscreen video = ZERO chrome (the ring cost ~6% CPU
and painted over the picture). Deployed d2ae35f0.


## 2026-09-17 VERDICT 30: CARD 2b slices 1+2 LANDED — internal client + slide lifecycle

5b0aff3: src/ipc/internal_client.zig (socketpair -> wl_client_create ->
pumpRoundtrip -> compositor + xdg_wm_base + zxdg_exporter_v2). DEADLOCK LAW:
a same-thread internal client never uses blocking wl_display_roundtrip.
a065188: kvis_client.zig (SEQPACKET) + video-slide lifecycle (spawn -> host
toplevel -> export -> parent verb). Deployed 7e7f29cf.


## 2026-09-17 VERDICT 29: CARD 2b part 1 + CARD 2c (kvisd half) LANDED

KidulWM 6b73fc7: XdgForeignRegistry + XdgForeignV2 globals. kmedia 17f45c8:
kvisd binds importer, parentTo/unparent real, 'parent <handle>'/'unparent' live
on the socket. ARCHITECTURE: xdg-foreign parents TOPLEVELS; kvisd letterboxes
inside its own surface (the matte-overlap class dies structurally).


## LIVE PARKED ITEMS (deferred polish / follow-up, not reset-blocking)

### Weather widget redo (verdict 27, still parked)
Removed 46757df (NOT deleted from history). The mirror-the-clock layout never
converged (five layout commits, each fixed one overlap + created another).
REDO RULES: harness-before-painter (offscreen render at scale 1 AND 2 before
any deploy); no mirroring anchors from different-size glyphs; no clamp hacks;
one build -> one verdict. Salvage: moon.zig shaded-sphere renderer, home.json
cache format, fetcher script were all correct — ONLY the pill layout was wrong.

### Peek-unit law (deferred polish pass)
Every peek widget still sizes in hardcoded px while the peek band is a fraction
of the output. LAW (draft, lock at polish time): one peek_unit = peek_band_px/16;
all widget dims are integer multiples of it; band px comes from live deck_split;
scale multiplies AFTER unit math. Same proportion on every screen.

### Screens law (Boss/slaves/pack — docs/law/screens.md, locked)
One Boss (the computer) owns all widgets + truth + one clock; screens are
slaves (numbered); slave 1 gets the PACK by default. Headless = 0 slaves.
Screens are windows, not masters.

### Skill consolidation (parked)
kidulwm-development skill is a 100KB god-file. Dedupe the ~15 restated lessons,
archive dated incidents to references/, leave a thin router. Plus prune the
20+ /usr/local/bin/kidulwm.bak-* binaries.
