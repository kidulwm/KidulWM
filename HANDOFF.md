# KidulWM HANDOFF — the session bridge

ROLE: handoff. RECYCLED each relog, never appended. The old diary lives in
docs/archive/HANDOFF-diary-2026-09.md (git history = the record; find past
sessions with session_search). Live state lives in the ledger, not here.

## Read order on relog

  1. /home/dad/dev/SYSTEM.md      the constitution — I1-I7 + phase order (arbiter)
  2. /home/dad/dev/KSD-INDEX.md   the map — every doc's role + the STALE list
  3. CENSUS-NOTES.md              the ledger — verdict 64 = current position + next test

## Current position (2026-09-28, end of night — bobdotrix)

  - SYSTEM FIXES THIS SESSION (2026-09-27, system admin — NOT KSD code; detail
    in the sda1 change journal /mnt/sda_backup/change-log/CHANGELOG.md):
      - kernel split-brain FIXED: linux-cachyos 7.2.8 rebuilt to /boot +
        limine.conf (was stale 7.2.6 vmlinuz, no modules — SDDM dead on the
        cachyos kernel; LTS 6.18.52 was the workaround boot).
      - fstab FIXED: duplicate /mnt/lacie-apocalypse line removed.
      - nvidia -> COMPUTE-ONLY (supersedes verdict 53's full 4-module blacklist):
        ollama needs nvidia + nvidia_uvm for CUDA. Toggle
        /usr/local/bin/nvidia-profile: `off` (default) | `gaming`
        (PRIME render offload, `prime-run <game>`). Intel iGPU drives all
        screens. verdict 53's "nvidia-smi gone / D3cold" verify is VOID.
      - bobdotrix approvals.mode -> smart.

  - KSD (verdict 64, current — see CENSUS for full text). Two compositor fixes
    DEPLOYED this session to /usr/local/bin/kidulwm (ReleaseSafe, hash
    39193e2d, matches zig-out/bin/kidulwm). RUNNING pid was NOT restarted —
    relog picks it up:
      1. Fullscreen chrome removal: applyLayout now clearChrome() when
         slide.fullscreen (was always updateChrome(.all), ignored the flag).
         Fullscreen slide = edge-to-edge, no border, no chrome. All apps get
         it free (shared focused-slide branch).
      2. Media player spawn direction: was inserting at index 0 (far LEFT,
         pushing everything right — backwards). Now spawns at focused_index+1,
         same as addWindow: becomes focused, former focus slides LEFT. Home
         slide stays at index 0 (the far-left "empty-slide" exception).

  - LEAK = THE COMPOSITOR (CORRECTS verdict 63's "compositor did NOT
    reproduce"). Live on the host this session: kidulwm anon 325MB -> 3.45GB
    over Barticus's open/close testing, STILL climbing, RSS 3.6GB, no drop on
    close. smaps = verdict-57 fingerprint (~27.8MB anon chunks, coalesced into
    83/111/166/250/278MB slabs = "one 4K P010 frame each"). kplayd is CLEAN
    (respawns 27MB / 0 renderD / 0 GEM — put-to-bed holds). Reproduces ONLY
    through the real fullscreen flow (Mod4+m), NOT raw kplay.sock — that's why
    verdict 63's raw-socket test missed it.

## Next action (tomorrow — "2 suspect review")

  PIN the exact allocator in the fullscreen present path, then fix. Two
  suspects, both fire on fullscreen enter/exit layout events:
    A. media-slide 33MB ARGB32 re-render (mediaSlideRefresh -> renderToBuffer,
       src/server.zig ~2072; guarded by card_dirty but re-fired on fullscreen
       layout).
    B. chrome border regen (updateChrome create/destroy churn, src/window.zig
       ~472 — TEMP DIAG "CHROME cache-miss" log lines still in place).
  Also on the table (video-playback-architecture skill): per-frame dmabuf
  import churn — cache per VASurfaceID (~8 slots), create scene node ONCE,
  setBuffer the cached entry instead of re-export+import each frame.
  The sampler /home/dad/.hermes/profiles/bobdotrix/cache/scratch/ramsample-*.log
  has the full 1s trace (columns: ts kplayd_pid kplayd_rss fds gem kidulwm_pid
  kidulwm_rss fds gem anon memavail).

  METHOD: relog first so the two DEPLOYED fixes are live, re-test, then re-run
  the sampler while Barticus cycles fullscreen open/close, and read the anon
  delta against the CHROME cache-miss + mediaSlideRefresh log lines to name
  A vs B. Don't guess — the log already distinguishes them.

## Trip wires / commands / secrets

  KNOWN_CMDS.md   build, deploy, VM (ksd-reset 192.168.122.87 / fresh-one FROZEN), SSH
  AGENTS.md       secrets map + agent strategy + build gotchas
  Deploy trap: build ReleaseSafe (-Doptimize=ReleaseSafe), mv-over swap
    (sudo cp .new + chmod + mv), .bak kept, NEVER restart the running
    compositor for Barticus — relog is his call.
