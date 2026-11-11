# DESIGN — the input path: path-based libinput, no udev (LOCKED 2026-11-10)

## The decision

Input devices are discovered and admitted by a PATH-BASED libinput backend
patched into our own build of wlroots — not by udev, not by a resident udevd,
and not by hand-rolled evdev parsing.

  USE   libinput (the evdev engine + its quirks data). Open, battle-tested,
        already a system dep. Its PATH context (libinput_path_create_context +
        libinput_path_add_device) enumerates from the devnode. Device
        classification and the ID_INPUT* tags libinput needs are PATCHED IN
        from evdev capability bits (see "the libinput fork" below) — no
        resident udev.

  OWN   enumeration (scan /dev/input/event*), hotplug (the kobject-uevent
        netlink listener kushd already runs), and ADMISSION (the four-tier gate
        in input-trust.md, enforced at enumeration).

  DROP  the udev database, udev rules, the resident udevd — all lawed out
        already ("NETLINK_KOBJECT_UEVENT listener replaces udevd — no resident
        udev"). This closes the seam that still reached for them. BOUNDARY
        (refined 2026-11-10): libudev.so.1 the CLIENT lib STAYS — it is
        libinput's device model (meson dep_udev is non-optional) and reads
        sysfs directly, no daemon. Dropping it = rewriting libinput's device
        model = a full fork, not a patch.

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
  The quirks tree MUST match the libinput version (1.31.3) — see below.

  XKB keymap data (xkeyboard-config) is the FOURTH instance of the same gap,
  found on the nvme1 boot (2026-11-10): /usr/share/X11/xkb is absent, so
  xkbcommon logs "Failed to add any default include path" and "failed to create
  default keymap", and even an admitted keyboard produces no keysyms. Ship
  xkeyboard-config (or an equivalent XKB data tree) into the rootfs — inert
  data + the xkbcommon parser, no udev, no daemon. Required for layouts and for
  KidulFlow/braille (multi-layout, blind-usable).

  BAKED 2026-11-11 (gap CLOSED). The host's tree is a symlink
  /usr/share/X11/xkb -> /usr/share/xkeyboard-config-2 (real data there). The
  assembly step is a plain data-tree copy — follow the symlink target, do NOT
  carry the symlink into the rootfs:

    sudo mkdir -p /mnt/ksd/usr/share/X11
    sudo cp -a /usr/share/xkeyboard-config-2 /mnt/ksd/usr/share/X11/xkb

  VERIFIED: 293 files / 4.0M under /mnt/ksd/usr/share/X11/xkb (compat geometry
  keycodes rules symbols types); the KSD's own libxkbcommon.so.0 lists
  /usr/share/X11/xkb in its default include path; `XKB_CONFIG_ROOT=…
  xkbcli compile-keymap --layout us --rules evdev --model pc105` compiles a
  valid keymap (EXIT 0). This closes GAP 1 (keymap); the ADMITTED internal AT
  keyboard will now emit keysyms. The Planck still needs Phase-2 hotplug below.

## The libinput fork (1.31.3 — a SECOND patch, discovered on boot)

The wlroots patch alone was NOT sufficient. Booting it showed the crash one
level deeper: libinput 1.31.3's own path backend still requires udev.

  path-seat.c  udev_device_from_devnode() loops up to 200x10ms waiting for
               udev_device_get_is_initialized(), which is NEVER true without a
               resident udevd (set only when udevd writes /run/udev/data).
               -> "udev device never initialized" -> "Invalid path" -> every
               device rejected. (Also why the earlier host-side smoke test was
               a FALSE green — the host runs udevd.)

  evdev.c      evdev_device_get_udev_tags() reads ID_INPUT* udev properties
               (written by udev's input_id builtin + hwdb). Absent without udev
               -> every device hits the "not tagged as supported input device"
               gate. This falsifies the "classification itself from evdev"
               premise above — libinput 1.31.3 does NOT classify from evdev; we
               had to make it.

Patch: patches/libinput-1.31.3-ksd-path-no-udev.patch (2 files, sha256 267e60d7…).

  path-seat.c  drop the get_is_initialized() wait; accept the sysfs device
               (udev_device_new_from_devnum already returns devnode/syspath).
  evdev.c      ksd_evdev_tags_from_evdev(): faithful port of systemd's
               udev-builtin-input_id.c (test_pointers + test_key +
               scrollwheel-only + switch) reading capability bits via libevdev,
               as a fallback in evdev_device_get_udev_tags() when the udev
               scan yields NONE.

Built 1.31.3 with -Dlibwacom=false (drops libgudev from libinput's DT_NEEDED),
prefix=/usr. Quirks data MUST match the libinput version: the rootfs carried a
1.32 quirks tree -> "Unknown key ModelCircularTouchpad"; shipped 1.31.3's.

CHROOT-PROVEN (no udevd, /run/udev absent): 18 devices admitted — AT keyboard,
Planck 03a8:a4f9, ELAN touchpad, lid/power/sleep buttons, MX Master 3. 10 audio
devices (HDA jacks, PC speaker) correctly rejected, identical to stock (switch
support is SW_LID / SW_TABLET_MODE / SW_KEYPAD_SLIDE only).

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

BUILT 2026-11-12 (Phase-2): backend/libinput/hotplug.c — a
NETLINK_KOBJECT_UEVENT listener (SOCK_DGRAM, nl_groups=1, non-root) bound
BEFORE the cold-plug scan, registered on the event loop after dispatch, so a
device that enumerates during the scan is neither missed nor double-added
(handler dedupes by libinput_device_get_sysname). On input add/remove it calls
libinput_path_add_device / libinput_path_remove_device; the four-tier ladder
re-runs because both paths funnel through DEVICE_ADDED -> handle_device_added.
Deployed /mnt/ksd (libwlroots-0.20.so, DT_NEEDED identical to stock); netlink
smoke PASS (18 input uevents received + parsed, non-root). Reboot-test = the
proof that the Planck admits.

## Vendoring (RESOLVED: patch + rebuild)

wlroots is a pacman binary (wlroots0.20 0.20.2-1.1). "Patch backend.c" means we
produce our own libwlroots-0.20.so. LOCKED approach: carry a .patch against
pinned 0.20.2 + the distro's build recipe (PKGBUILD), rebuild, ship OUR .so.
We own the delta; the C source stays upstream (no full-vendor fork). The
shipped KSD root gets OUR libwlroots-0.20.so, linked by KidulWM's existing
linkSystemLibrary("wlroots-0.20").

## Two-phase plan

  PHASE 1 (unblock the boot): patch + rebuild wlroots AND patch + rebuild
  libinput (the fork above), copy the MATCHING 1.31.3 quirks into the rootfs,
  deploy all three, boot nvme1.
  Success = kushd.log "seated kidulwm" with no "died kidulwm" loop AND the
  AT keyboard + Planck produce input (Tier 0 + Tier 1).

  PHASE 2 (harden): netlink hotplug in the backend + Tier 2 crypto proof wired
  to the kidulKey gate.

  PHASE 2.5 (netlink hotplug) BUILT 2026-11-12 (backend/libinput/hotplug.c) —
  see §Hotplug. Tier 2 crypto proof is the remaining Phase-2 half.

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
