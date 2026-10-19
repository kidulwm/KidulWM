# LAW — the system owns the boot TARGET; the app owns its STATE

Status: LOCKED 2026-10-19 by Barticus ("gsi — all 5 on point"). Drafted
2026-10-19 by bobdotrix. Sources: docket #8 CLARIFICATION (LOCKED 2026-10-19)
and Barticus's in-app-DB steering this session.

Companion: slide-process.md (the PROCESS boundary this law restates at boot
altitude), kboot.md (the ladder — no target machinery), power-states.md (clean
shutdown + power verbs), kplay.md (one owner per truth), media-is-a-slide.md.

## The sentence

On cold boot the system restores WHICH app was primary — never WHERE inside
it. The boot TARGET is a configurable autostart entry (TV / PC / remember-last
/ any app); the playback STATE (channel, position, placemark) is in-app data
the system does not know and does not want. One line: system owns the target,
the app owns the state. This is slide-process.md's law (an APP owns its
CONTENT) restated at boot altitude.

## The finding (why this law now)

Barticus, 2026-10-19, two halves of one steer:

1. Boot-to-TV must NOT be static. It is a STANDARD SETTING we turn ON for our
   own TVs — flexible, never a hardcoded boot behaviour. "Static boot-to-TV =
   a gremlin we'd burn a GREAT RESET killing; the setting, not the behaviour,
   is the law." (docket #8 CLARIFICATION, LOCKED.)

2. Playback state is in-app only. "The app knows [Granny's fav channel], the
   system shouldn't care at what stage in playback each item is. An auto-
   placemark WITHIN the media player ... purely IN-APP data, nothing system
   wide."

The current boot knob is a static env bool (KIDULWM_BOOT_MEDIA, server.zig
~3800) — exactly the hardcoded behaviour this law retires. The general setting
replaces it.

Shipped 2026-10-19 (bobdotrix): the setting is now LIVE — src/core/boot_config.zig
(boot.toml, target = pc | tv | remember-last | <app-id>) + a
`kidulwm-control set-boot-target` setter. `tv` maps to the existing in-process
media ladder; the env bool is retained only as a DEPRECATED transition shim
until the TV golden image ships its own boot.toml (then the shim is deleted).
remember-last / <app-id> resolution remains the post-#24 far side.

## The split (system vs app, at boot)

  SYSTEM (kushd + kidulwm) owns the TARGET:
    - the boot-target setting (remember-last | tv | pc | <any-app-id>)
    - the last-primary record (which app/slide was focused at clean shutdown)
    - the seating: kushd seats the target app focused, kidulwm composites it
    - the auto-play CUE ("you're primary, play") — a signal with NO content

  APP (kmedia, via libkmedia) owns the STATE:
    - the last channel / fav channel
    - the resume position in each item (the auto-placemark)
    - its own DB, never exposed to the system

The system's last-primary record is the ONLY state the system carries, and it
carries WHICH app — never WHERE in the content. "Granny's box boots into her
last channel" = the system seats media as primary + cues play; kmedia then
restores channel and position from its OWN DB.

## One mechanism, not two (Barticus's systemd framing)

Barticus: "just either a systemd-autostart-add app we need to replicate, OR a
linux 'preferred' setting we move apps in and out of." The answer is ONE
mechanism:

  autostart-add app  = add an app to the boot set
  preferred          = mark which is PRIMARY (focused at boot)
  remember-last      = the RESOLVER: read the last-primary record, restore it

XDG autostart + preferred-apps + session-save is the reference shape. Our apps
are slides; our session-saver is kushd. Not two subsystems — one list, a
primary marker, and a remember-last resolver.

## Where the target lives (not kboot)

The boot target is a SEATING decision, made by kushd when it seats the face
and the apps — never by kboot. kboot.md already says "no target machinery, no
eager boot"; this law does not reopen that. kboot boots and hands off; kushd
reads the boot-target setting and seats the primary. The setting is consumed
at seating time, not at boot-stage time.

## The boundary (what to check when boot is wrong)

  - "boots to the wrong app"          -> system (target/record/seat) — external.
  - "wrong channel / wrong position"  -> kmedia in-app DB (content) — internal.
  - "lands but won't play"            -> kplayd/kmedia handoff cue (#9) — playback.

A symptom with no clear owner = a boundary crossed (slide-process.md's rule).

## Clean shutdown is where the record is written

The last-primary record is written by the system (kidulwm's focus knowledge +
kushd's seating) on clean power-down (power-states.md), not on crash — a crash
keeps the last-known-good record. No new daemon; it rides the existing
shutdown path.

## Sequencing (why the law precedes the build)

The mechanism builds on the far side of #24 (MEGA ROACH) C1-C3: kushd live +
kmedia as a client. The resume DB must live in the app before the target
handoff is clean, else C1 could leave resume state half system-wide. This law
is C1's DESTINATION — freeze it now, build after.
