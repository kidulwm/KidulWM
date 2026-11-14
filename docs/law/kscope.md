# kscope — the telescope (one ship sees another, pushes a slide across) — LOCKED 2026-10-05

## The name

kscope = the telescope. "I can see another kidulShip ahead — let's send them a
message." Two verbs, one instrument: SPOT the other ship (rendezvous) and REACH
it (transport). "Scope" carries both — the range you see and the reach you make.

Two names, two things, never blurred:
- kscope = the whole capability (see another ship, rendezvous, push a slide).
- the gangway = the pixel-transport seam inside it.
  kscope spots the ship; the gangway boards it.

Naming note: the K-prefix by the letter of theatre.md is for RESIDENT DAEMONS.
kscope is a SCHEME, not a daemon — it follows the krypto / kpax / KID precedent
(scheme names; the KID = the kID — kid.md), not the ksound / knetd / kushd
daemon pattern. If a resident daemon ever forms to run the wire, that daemon
earns its own K-name later.

## What it is

The original dream: Wayland thin clients on the LAN. Server kushd runs the game
(in a brig); TV kushd presents it. The server BUILDS, the TV PRESENTS — it
paints pixels on cue and does as little work as it needs to. The same seam
doubles as our Wayland remote-desktop.

## The hard wall (named once, so it never bites)

"Zero-copy piping" is impossible in the absolute sense: a dma-buf is GPU memory
on THAT machine; bytes must cross the wire — that copy can never be zero. What
IS achievable:
- zero-CPU-copy (RDMA: NIC-to-NIC DMA, no CPU bounce either end),
- zero-waste (stream damaged/moving regions, not whole frames),
- zero-decode on the TV (blit a received buffer straight to the scanout plane).

## Lossless-first (LOCKED — "100% go for the lossless")

The pipe is LOSSLESS. Perfect pixels, zero decode on the TV, "just paint on
cue" in its purest form. Cost: 1080p60 ~ 3 Gbit/s, 4K60 ~ 12 Gbit/s — viable on
the wired LAN / krouter / QoS we own, not wifi. The codec (H.264/HEVC/AV1) is a
LATER per-link compression tier dialled in where bandwidth demands — never the
foundation. Fidelity is the thing you can't buy back once a codec eats it;
bandwidth is ours.

## The signature (LOCKED): strip the BS — the clock that owns the medium leads

This is the same discipline the media player is already nailing, one
abstraction higher. Strip the middleware. The clock that owns the medium LEADS:
- media player: sink-clock pacing (sound.md), being re-derived as "let the
  video do the timing" for the lossless path;
- kscope: the TV paints on vblank cue, the server produces on cue. No
  re-clocking, no buffer guess, no open-loop wall-clock.

One principle, both places: CLOSED-LOOP TIMING — pace against the clock that
owns the stream, never an open-loop timer (sound.md). That is our signature:
lossless pixels, video-as-clock, nothing in the middle.

## Why only we can do it (the four-fold ownership)

Nobody else holds all four:
- own BOTH compositors -> the seam lives inside kidulwm's render loop at the
  plane/scanout layer, not a screen-grab bolted on after;
- own BOTH supervisors -> rendezvous is kushd-to-kushd, not a user app someone
  launches;
- own identity -> the kidulKey attests both ends (trusted-by-proof, not
  password) — krypto applied to machines;
- own confinement -> the game runs in a brig, caged while its pixels stream.

## How the pieces already in place carry it

- The kcell AV bridge IS this seam, locally proven: guest renders -> host
  presents, input back down. kscope moves the cell to another machine and makes
  the bridge's transport a wire instead of a local socket. Same seam, different
  transport.
- silk.md §7: submit early into the DRM atomic queue, vblank fires the present.
  That is the TV's "paint on cue."
- krypto / kpax: attestation for machines — "no doorman, the skipper's KID signs
  the list." The server is trusted-by-proof.
- kushd hierarchy: subordinate REPORTS a surface, superior DECIDES to seat it —
  now across two machines.
- knetd / krouter: the owned, QoS-shaped direct link the pixels travel.

## The transport split (who owns what — freeze in code, not guessed)

- kscope rendezvous (SPOT the ship): knetd / krouter discovers + attests the
  peer; krypto proves who it is. The "is there another ship, and who?" moment.
- kscope transport (the gangway, REACH the ship): the lossless damage-rect
  stream, server -> TV. kushd-to-kushd hands up the surface descriptor; the
  TV's kidulwm seats it as a plane and paints on vblank.
- input rides back down the same attested channel (TV -> server), the mirror of
  the local AV bridge.
- audio: server-side render, streamed as the session's audio class. ksound is
  STILL the sole loudness governor — the TV's ksound, never the server's.

## Not built yet — honest status

Architecture frozen. Mechanism not built. The local kcell AV bridge is the
proven predecessor; the wire transport, the rendezvous protocol, and the
lossless damage-rect codec-free stream are all to be built. This is the ONE
place we deliberately go beyond what is available — we may need something
beyond Wayland remote desktop, and we own every piece required to build it.
