# LAW — The Theatre (the whole system, named once)

Locked 2026-10-01, Barticus present. Do not relitigate. Supersedes the tier
names in usher.md (KSEAT is retired) and every earlier "body/tentacle" phrasing.

KSD is a theatre. The seating and the colouring are not the show until they
are together; the show is emergent, and it is legible only from above.

## The tier stack — who organises whom (top to bottom)

KEYE — the quantum view. Not one point of view; EVERY point of view, at every
instant, in the beer garden and on the stage at once. The chandelier. Two
powers, and both are the human's alone:

  SEE    — the aggregate of every telemetry stream: the overview, the klink
           graph, the census. Nothing in KSD is built by a stranger, so nothing
           is a black box, so the eye is genuinely everywhere at once.
  POWER  — turn the lights on and off at any time. The master switch. This is
           the escape hatch: the human is never INSIDE the system; the human is
           above it, holding the cord. sddm, niri, the kill button — one law.

The KEYE is not a seat. SEAT now means one thing only: a px's place. The eye
is the eye. KEYE keeps the K-prefix (ksound, knetd, kush, kplay, kidul, KEYE)
and retires the KSEAT collision where "seat" did two jobs.

USHER — kushd. The seating plan and the bouncer. Not a thing — the thing that
organises things. Seats every px in its correct seat, and carries the klink
graph (the cup-holder map: what every seat is, what it connects to, what it
breaks if it empties). Session lifecycle: seat everyone at boot (the mad-man
scramble), then lean and stir only on a miss — a lost seat is reseated, a
misbehaving seat is evicted to the beer garden — then at the end guide them all
out and usher the next show in. Owns the LIFECYCLE map.

CONDUCTOR — kidulwm. The face. Colours the px's (paints the pixels). The
performance. Owns the PIXEL map (geometry, focus, z-order).

KERNEL — the floor. Physics.

## The seats: px

A px is a seat. Every running thing sits in its place in the matrix, put there
by the usher. Two kinds, by lifecycle:

  BODY  — always-on, shared. ksound, knetd, the log drain, the getty. The
          organs everyone leans on. (knetd stands ALONE — its own locked stance;
          the network is the recovery path and the isolation substrate, never a
          kushd child. It is CAGED — a bubble, not a bare-kernel peer of the
          secrets; network does not live in the trust core. See dom0.md.)
  LIMBS — cued, single-purpose. kplayd, the slides. Seated on cue, dropped when
          the cue ends.

## The trust axis: theatre vs beer garden

THEATER — the trusted, the seated, the velour. Nothing rowdy reaches it. The
royals (the class-1 alarm, the show-stealing guest) may take the floor, but
they are still IN the theatre and still under the KEYE's light — nothing gets a
seat above the eye.

BEER GARDEN — the untrusted. The riff raff, the bubbles (was "the VM types"),
the trojan horses. They go crazy outside, and their drinks land on their own table, never the
velour. Three legs cut, by mechanism not vigil:

  BLIND   — separate pid/net/mount namespaces; it cannot see the theatre, the
            velour, or even its fellow riff raff.
  SPOOFED — knetd's `spoof` verb (MAC-randomised identity); its "internet" is a
            veth into the usher's bridge, not the wire.
  LEGLESS — one-way in both senses: pixels flow riff-raff -> screen and nothing
            flows screen -> riff-raff; telemetry flows everything -> KEYE and
            the blind thing never knows it is on camera.

The no-legs theorem: a trojan needs SEE (reconnaissance) and RUN (exfiltration).
The beer garden removes both. Containment, not confrontation — you do not police
the riff raff, you put the table out of arm's reach of the velour.

## The two maps, never blurred

The usher owns the LIFECYCLE map. The conductor owns the PIXEL map. Two owners,
two maps, never the same one. A symptom with no clear owner means a map got
blurred — find the second owner and delete it.

## The observability law

The truth of the system lives where the light is — the KEYE's aggregate — not in
any one seat. No single daemon log, no single px, no single slide shows the
system. Read the show from above.

## Why this exists

Fourteen verdicts once burned a week smearing ownership across six files. Every
fix was the same move: delete the second owner. This law makes symptom -> owner
a lookup table, and it names the whole structure once so the next session reads
the same words instead of re-deriving them.