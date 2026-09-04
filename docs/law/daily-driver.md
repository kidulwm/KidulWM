# LAW — Daily Driver Path (LOCKED 2026-09-04, Barticus: "sound solid, GSI")

Status: LOCKED 2026-09-04 by Barticus. Drafted by bobdotrix.
Supersedes: nothing. Sits beside kmedia/docs/law/* and ksound/docs/law/sound.md.

## 1. Two-environment law

There are TWO environments with TWO different standards. Never confuse them.

  The B&B workbench (the dev laptop)
    - Standard: PRODUCTIVE, not pure. Messy is correct.
    - Niri stays installed as escape hatch. Any app needing a "real"
      environment runs there.
    - Hermes / the Bobs live here and ONLY here. "You are not for sale."
      The workbench is never shown, so it never needs to be clean.
    - Gate: does it boot, does knet hold, can B&B work. Nothing else.

  The product (ksd-golden → TV copy)
    - Standard: PERFECTION. It is the face: "safest OS for Granny & the kids."
    - No Niri, no escape hatches, no AI talk, no dev cruft.
    - Ships from ksd-golden + install-ksd.sh + the signed repo.
    - The product NEVER ships from the workbench. Workbench mess can never
      reach it, by construction.

Public-face law unchanged: only message = 'safest OS for Granny & the kids.'
(kmedia/docs/law/public-face.md)

## 2. v1 settings surface

ksignals IS the settings surface for v1. Pills, detail views, and proven
apply paths (powerprofilesctl) already exist there. A dedicated settings
APP is real work and is DEFERRED — do not move the kbottle mid-pour.

Settings-shaped things go into ksignals until the product settings surface
is designed for the TV copy.

## 3. Browser position

kidul-browser is FLAGSHIP and product-critical (kids-web curated allowlist
is core to the public face). It is NOT on the Phase A critical path.

Interim: any browser (helium or whatever is installed) runs as an ordinary
window in KSD, and Niri remains available on the workbench regardless.
kidul-browser returns to the foreground after the workbench flip, during
product polish.

## 4. Phase A — the flip gate (in stranding order)

Phase A contains ONLY items that can strand the workbench — things that
cannot be fixed from inside if broken. Four items:

  1. knet settings (ksignals network slide)
     knetd is PROVEN: live on the host since Aug 31, replacing
     NetworkManager/wpa_supplicant/dhcpcd, this very session rides it.
     So the item is NOT a build — it is (a) verifying the KSD session
     uses knet end-to-end (scan → join → PSK → save → reconnect), and
     (b) the slide as the RECOVERY surface for when something goes wrong
     (drop-loop/backoff-stuck, ref Aug 19 knet-watch trigger). Settings
     exist for the bad day, not the good one.
  2. Session launch from existing DM (GRUB + DM stay)
     kidul-init/kiduldm remain the north star but are NOT BUILT YET —
     they are product-side, not flip-gating. Workbench keeps GRUB and
     the current display manager. The item is only: KSD session appears
     in the DM session list, launches clean, seat + input devices work,
     no manual steps. VM-verified is NOT bare-metal-verified.
  3. Output config + displays row
     Persistent per-output config (mode, position, scale, on/off) read at
     handleNewOutput — today every boot re-rolls addAuto. Resolution and
     brightness controls: panel via /sys/class/backlight (pattern exists
     in network.zig), external via DDC/CI (ddcutil setvcp 10, shell-out
     fine for v1). Includes "laptop panel off when docked".
  4. Lid-behaviour pill
     Battery slide gains LID CLOSED: do nothing · suspend · power off,
     backed by logind (HandleLidSwitch). Rides the existing battery.detail
     + pill pattern. Workbench setting: do nothing (always-on, lid as
     UPS-backed screen-sleep).

The flip happens the day Phase A closes — not when a feature list is done.

## 5. Phase B — in-situ dogfood

After the flip, everything else is fixed from inside KSD, by B&B, as daily
use exposes it: gauges, shop card, live TV, chrome polish, clipboard,
notifications, brightness keys, per-screen backgrounds (explicitly
"much later"), the settings app, kidul-browser.

In-situ is the dogfood loop. The ponder pays off there.

## 6. Explicitly NOT gated

  - kidul-browser (see §3)
  - Settings app (see §2)
  - Per-screen backgrounds (much later; scene graph already supports it)
  - MIC LIGHT (parked, ksound 7ee81b2+2b9a08d)
  - ksound law lock (docs/law/sound.md — separate pending lock)
  - kidul-init / kiduldm — north stars, NOT BUILT YET, product-side.
    Workbench keeps GRUB + existing DM indefinitely.
