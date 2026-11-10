# DESIGN — the input path: path-based libinput, no udev (LOCKED 2026-11-10)

## The decision

Input devices are discovered and admitted by a PATH-BASED libinput backend
patched into our own build of wlroots — not by udev, not by a resident udevd,
and not by hand-rolled evdev parsing.

  USE   libinput (the evdev engine + its quirks data). Open, battle-tested,
        already a system dep. Its PATH context (libinput_path_create_context +
        libinput_path_add_device) does device classification itself from evdev
        capability bits — no udev involved.

  OWN   enumeration (scan /dev/input/event*), hotplug (the kobject-uevent
        netlink listener kushd already runs), and ADMISSION (the four-tier gate
        in input-trust.md, enforced at enumeration).

  DROP  libudev, the udev database, udev rules, the resident udevd. All three
        were lawed out already ("NETLINK_KOBJECT_UEVENT listener replaces udevd
        — no resident udev"). This closes the one seam that still reached for
        them.

## Why this is the truer path

The boot log said "libinput initialization failed, no input devices" while the
kernel had event0-14 enumerated and chowned. The reason is structural:

  wlroots' DRM backend ALREADY has a no-udev fallback — that is why the i915
  renderer came up (gles2=true) on the real boot with zero udev.

  wlroots' libinput backend has NO such fallback. backend_start() (wlroots
  0.20.2, backend/libinput/backend.c:90) hard-codes
  libinput_udev_create_context + libinput_udev_assign_seat, which read the udev
  database. Empty database -> zero devices -> "no input devices" -> backend
  fails -> multi backend tears down -> wlr_seat_destroy asserts -> SIGABRT ->
  kushd respawns on a backoff ladder forever.

So the crash is not a missing file, not a permission gap, not a hardware fault.
It is the one place in the compositor that still assumes udev exists. Adding the
path-based fallback to libinput is the SAME class of fix wlroots already made
for DRM — we are closing the asymmetry, not inventing a new input stack.

## The admission gate: the four-tier ladder (input-trust.md, LOCKED)

The policy lives in docs/law/input-trust.md §"admission ladder" — four tiers,
per-device, decided at enumeration time:

  TIER 0  INTERNAL (topology) — kernel-standard signals, no allowlist: bustype
          (I8042/HOST/PCI/INTEL_ISHTP/I2C/SPI) or USB with sysfs removable=fixed.
          Auto-admitted TRUSTED. The AT keyboard, touchpad, buttons, iGPU, HDA.
  TIER 1  KNOWN EXTERNAL (identity) — VID:PID(+serial) in the burned allowlist.
          Admitted USABLE (Planck 03A8:A4F9, kidulKey 2fe3, the remote).
  TIER 2  PROVEN (crypto) — kidulKey Ed25519 challenge/response. The only
          TRUSTED tier (harmful binds live). The remote earns it.
  TIER 3  UNKNOWN — benign class admitted UNTRUSTED (no harmful binds);
          dangerous class (mass-storage/smartcard/net) REJECTED.

This upgrades the gate from a POST-HOC filter (seatTrusted() at keybind-dispatch)
to the ADMISSION decision itself, in the enumeration path — precisely "a gate
BELOW seatd, a decision point, not a resident daemon."

## The patch (wlroots 0.20.2 — two files)

  backend/libinput/backend.c  backend_start(): replace
    libinput_udev_create_context + libinput_udev_assign_seat with
    libinput_path_create_context + enumerate /dev/input/event* (glob/readdir)
    + libinput_path_add_device() per path. The existing
    handle_libinput_readable() call then dispatches the queued ADD events and
    handle_device_added() creates the wlr devices unchanged. open_restricted
    (backend.c:18) still routes fds through wlr_session_open_file (seatd) — no
    change to kboot devRules / seatd minting / groups. The WLR_LIBINPUT_NO_DEVICES
    check and event-loop registration are unchanged.

  backend/libinput/events.c  handle_device_added() (events.c:64): insert the
    four-tier classification + admission decision before init_device_keyboard /
    init_device_pointer. The function already reads vendor/product/name from
    evdev (libinput_device_get_id_*) — no udev needed. Tier 0/1/3 decided from
    bustype + VID:PID; Tier 2 reads the verdict the kidulkey-gate one-shot
    produces.

  Quirks still apply: libinput matches /usr/share/libinput/*.quirks on the
  device's own bus/vendor/product (from evdev), not from udev. Copying that
  data dir into the rootfs is still required — it is the third instance of the
  rootfs-assembly data-tree gap (Mesa runtime drivers, firmware, now libinput).

## Hotplug (netlink = DEVICE events, not networking)

Clarification: "netlink" here is NETLINK_KOBJECT_UEVENT — the kernel's
device-hotplug channel ("a USB device was added/removed"), the same family
kushd's kidulKey gate already consumes. It is NOT the network stack (that is
NETLINK_ROUTE / nl80211, knetd's lane). Zero overlap with the KWEB.

libinput's path context has no monitor. Cold-plug enumeration above unblocks a
fixed set of devices. Hotplug (the Planck re-plug; the remote arriving later)
is the follow-on slice: a kobject-uevent listener INSIDE the patched backend
(it already owns the session + event loop), firing libinput_path_add_device /
libinput_path_remove_device, the tier ladder re-run per device. The
pre-existing-device gap (a listener sees only CHANGES, never the boot-time
adds) is already solved by the cold-plug enumeration — the two halves
complement.

## Vendoring (RESOLVED: patch + rebuild)

wlroots is a pacman binary (wlroots0.20 0.20.2-1.1). "Patch backend.c" means we
produce our own libwlroots-0.20.so. LOCKED approach: carry a .patch against
pinned 0.20.2 + the distro's build recipe (PKGBUILD), rebuild, ship OUR .so.
We own the delta; the C source stays upstream (no full-vendor fork). The
shipped KSD root gets OUR libwlroots-0.20.so, linked by KidulWM's existing
linkSystemLibrary("wlroots-0.20").

## Two-phase plan

  PHASE 1 (unblock the boot): patch + rebuild wlroots, copy
  /usr/share/libinput/*.quirks into the rootfs, deploy both, boot nvme1.
  Success = kushd.log "seated kidulwm" with no "died kidulwm" loop AND the
  AT keyboard + Planck produce input (Tier 0 + Tier 1).

  PHASE 2 (harden): netlink hotplug in the backend + Tier 2 crypto proof wired
  to the kidulKey gate.

  NOTE — there is no clean interim crutch for a reboot test. WLR_LIBINPUT_NO_DEVICES=1
  seats with ZERO input forever (no udev monitor to ever add a keyboard); the
  quirks copy alone won't stop the crash (the crash is the udev-enumeration gap,
  not the missing data dir).

## Rulings (all LOCKED 2026-11-10, Barticus present)

  Q1  vendoring: patch + rebuild (NOT full vendor).
  Q2  hotplug home: netlink kobject-uevent listener inside the backend.
  Q3  gate timing: build the four-tier admission gate into the enumeration
      helper from the start (never a retrofit). kidulKey v0.01 is the live
      Tier-2 prover on the first build.

## Relationship to existing law

  input-trust.md     §Status "mechanism is a docket" -> RESOLVED; ladder LOCKED.
  kidul-system-daemons.md  "no resident udev" -> now actually consistent with
                     wlroots end-to-end.
  wlroots            the "backend autocreate / libinput" notes gain the
                     path-backend fork as the canonical no-udev input path.
