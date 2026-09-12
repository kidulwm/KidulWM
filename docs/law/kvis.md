# LAW: KVIS — one owner per truth (DRAFT for Barticus lock, 2026-09-12)

## The sentence
ksound owns EVERYONE'S sound truth. kvis owns OUR playback. The
compositor owns FOREIGN pixels. Nothing anywhere holds two owners, and
every bug lands in one file family by its first symptom.

## Why this law exists (census record)
2026-09-09→12 media hunt: fourteen verdicts, every one an ownership
leak — +707ms (two timelines), stale dot (liveness derived from
loudness), frozen second video (cache keyed without generation),
whole-machine wedge (ring cap vs storage array). Each fix was the same
move: delete the second owner. The cost of the hunt was not the bugs;
it was that every symptom required a census because ownership was
smeared across Player.zig, Timing.zig, core/kmedia.zig, tray.zig,
media.zig, server.zig. This law makes symptom → owner a lookup table.

## LAW 1 — ksound: all sound, one table
Every audio stream on the machine — our movies, browser videos, any
app — is a row on ksound's floor table. The floor answers liveness,
arbitration, and routing. The meter (FFT tap) answers loudness ONLY,
never liveness (screens.md precedent; verdict 11). ksound carries NO
clock and touches NO pixels.

## LAW 2 — kvis: our playback, whole and sealed
kvis is a PROCESS (the standalone kmedia grown up) owning the entire
product playback path: demux, decode, rings, the DAC-anchored graph-
paced clock, presentation. A/V sync never crosses a process boundary —
the clock lives whole inside kvis. kvis is the parent of its own video
surface and nothing else.

## LAW 3 — Zero-copy is non-negotiable, and survives the boundary
dmabufs are file descriptors; they cross processes by design
(SCM_RIGHTS / linux-dmabuf-v1, which the compositor already serves to
every client). kvis submits dmabuf buffers like any Wayland client:
GPU-to-GPU, zero copies — proven on this host by standalone kmedia
0c5308c (~2% CPU, VAAPI surface straight to screen). A process
boundary never means a memcpy.

## LAW 4 — The slide parents kvis; nothing parents anything else
The media slide owns geometry, focus, and letterboxing; kvis's surface
is a subsurface parented into it. Slide moves, video rides — the
"mediaPlayer acts like a slide" fix falls out of the structure.
Foreign AV (browser, games, anything) is a plain Wayland client of the
compositor: its pixels are the compositor's everyday job, its sound is
ksound's everyday table. No foreign pixel ever enters kvis; no kvis
pixel ever enters the compositor's logic.

## LAW 5 — Crash containment is structural
If kvis wedges, the compositor keeps breathing and can NAME the corpse
— no more power-button recoveries, no more volatile-journal mysteries.
A new kvis process is a new decoder pool: stale VA surfaces die with
the old process. The generation law (dmabuf key = surface id +
generation) gains a process wall in front of it.

## LAW 6 — One clock, borrowed crystals (from screens.md, restated)
kvis paces to the PRESENTING slave's vsync via Wayland frame
callbacks, per-output, read live. Screens report their credentials;
nobody stores per-screen timing tables. The DAC is the only clock.

## THE BUG-TO-OWNER LOOKUP TABLE
| First symptom                              | Owner                        |
|--------------------------------------------|------------------------------|
| No sound / wrong device / who's playing    | ksound floor table (1 query) |
| Liveness lies (dot, widget, butterfly)     | impossible — only the floor  |
| Our movie: stutter / sync / crash          | kvis (Player clock + rings)  |
| Our movie: slide won't sit / focus wrong   | media.zig (thin geometry)    |
| Browser/foreign vid broken                 | compositor scene graph; else |
|                                            | THEIR bug, not ours          |
| Butterfly / widget reaction wrong          | consumer of ksound, period   |
| Whole-machine wedge from media             | structurally impossible (L5) |

## What this is NOT
- NOT a media server. Files on a drive, played straight up
  (no-server.md stands).
- NOT a browser video pipeline. Foreign playback stays foreign.
- NOT a new clock, cache, or truth anywhere. N owners = N truths =
  ghosts.
