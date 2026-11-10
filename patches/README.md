# wlroots 0.20.2 rebuild — the KSD path-based libinput backend + tier gate

Decision (LOCKED 2026-11-10): the KSD input path is a PATH-BASED libinput
backend, no udev. wlroots' libinput backend is udev-only, so we rebuild
wlroots 0.20.2 from source with a surgical patch (patch + rebuild — we own the
delta, not the C tree). The four-tier admission gate (input-trust.md ladder)
is built INTO that enumeration path from the start (Ruling Q3), never a
retrofit.

Design + rationale: ../docs/design/input-path.draft.md
Law (admission ladder): ../docs/law/input-trust.md

## The patch — four files

`wlroots-0.20.2-libinput-path.patch` (git diff against tag 0.20.2):

  backend/libinput/backend.c
    backend_start(): libinput_udev_create_context + assign_seat
    -> libinput_path_create_context + glob("/dev/input/event*") +
    libinput_path_add_device() per path. open_restricted still routes fds
    through wlr_session_open_file (seatd) — no change to kboot devRules /
    seatd minting / groups.

  backend/libinput/events.c
    handle_device_added(): classify each device into the four-tier ladder
    BEFORE init_device_keyboard/pointer (see below), store it on the device,
    log "[input-trust] <name> [vid:pid] tier=N <tier>".

  include/backend/libinput.h
    struct wlr_libinput_input_device gains `enum wlr_libinput_trust trust`.

  include/wlr/backend/libinput.h  (public unstable API)
    enum wlr_libinput_trust + wlr_libinput_get_device_trust() — the read-point
    the compositor uses at keybind dispatch (the old global
    /run/kushd/input-trust verdict is superseded by per-device tier).

sha256: aac16e3d5b026331edbc58ed854c10d307bee69da9734006ad55cae4e3849520

## The four-tier classification (events.c, in this build)

  TIER 0  internal — bustype in {I8042, HOST, PCI, INTEL_ISHTP, I2C, SPI, ISA,
          ISAPNP, RMI, CEC, AMD_SFH, SDW}. TRUSTED (harmful binds allowed).
  TIER 1  known external — vid:pid in /etc/kushd/input-allowlist. USABLE
          (type/navigate, no harmful binds). Planck 03a8:a4f9.
  TIER 2  proven — crypto-proven remote. NOT wired yet (see remaining below);
          deliberately NOT read from the global verdict: that proves the SEAT,
          not the device — promoting every device would re-open "first
          keyboard wins".
  TIER 3  unknown — everything else. UNTRUSTED (type/navigate, no harmful
          binds). Dangerous class (mass-storage/smartcard/net) is REJECTED by
          the USB guard BELOW us; such a device never reaches libinput.

## Rebuild recipe (proven 2026-11-10)

  1. Obtain wlroots 0.20.2 source: `git clone --depth 1 --branch 0.20.2
     https://gitlab.freedesktop.org/wlroots/wlroots.git wlroots-src`
  2. Apply the patch: `cd wlroots-src && patch -p1 < ../wlroots-0.20.2-libinput-path.patch`
  3. Install the ONE missing build dep: `sudo pacman -S --needed vulkan-headers`
     (vulkan.pc is present via vulkan-icd-loader, but the vulkan/vulkan.h
     HEADER is not — without it meson silently sets vulkan-renderer=NO and the
     .so loses libvulkan.so.1, so it is NOT a strict superset of stock).
  4. Build: `meson setup build --buildtype=release && ninja -C build`
  5. Deploy our .so + quirks + allowlist into the rootfs (see below).

## Deploy (into the KSD rootfs, /mnt/ksd)

  strip -o /tmp/lw.so build/libwlroots-0.20.so
  sudo install -m 755 /tmp/lw.so /mnt/ksd/usr/lib/libwlroots-0.20.so
  sudo cp -a /usr/share/libinput /mnt/ksd/usr/share/libinput   # the quirks data tree
  # /etc/kushd/input-allowlist — one `vid:pid` per line (hex, no 0x), `#` comments:
  #   03a8:a4f9  drop-planck

## Verify (no reboot)

  # ABI: our .so must be a strict superset of stock (identical DT_NEEDED).
  diff <(readelf -d build/libwlroots-0.20.so | grep NEEDED | sort) \
       <(readelf -d /usr/lib/libwlroots-0.20.so | grep NEEDED | sort)
  # new symbol + path backend present:
  nm -D /mnt/ksd/usr/lib/libwlroots-0.20.so | grep -E 'libinput_get_device_trust|libinput_path_create'
  # rootfs resolves:
  sudo chroot /mnt/ksd /lib64/ld-linux-x86-64.so.2 --list /usr/local/bin/kidulwm

  # Smoke-test the mechanism WITHOUT a compositor/boot (run as root so it can
  # open /dev/input/event*): a tiny program that does path-context + glob +
  # add_device + dispatch + classify, prints each device's tier. See the
  # scratch/ksd-path-smoke.c prototype. Proven 2026-11-10 on the host: 20
  # devices enumerated with ZERO udev — AT keyboard/touchpad/buttons TIER0,
  # Drop Planck TIER1, Bluetooth MX Keys/Master TIER3.

## REMAINING (the "harden" phase, follow-on slices)

  - Tier 2 crypto proof: per-device kidulKey Ed25519 challenge wired into
    events.c (the remote). The kidulkey-gate one-shot is the prover; today no
    device lands in TIER 2 because no per-device proof identity exists.
  - Netlink kobject-uevent hotplug INSIDE the backend: libinput_path_add_device
    / libinput_path_remove_device on input add/remove (the cold-plug
    enumeration already handles the boot-time devices).
  - kidulwm enforcement: switch seatTrusted() from the global verdict to
    per-device tier via wlr_libinput_get_device_trust() (the getter exists;
    the compositor-side consume is the follow-on).

## libinput 1.31.3 rebuild — the path backend's own udev dependency (2026-11-10)

The wlroots patch above is necessary but NOT sufficient. Deploying it and
booting showed the SAME crash one level deeper: libinput 1.31.3's PATH backend
still requires udev internally.

  path-seat.c  udev_device_from_devnode() loops up to 200x10ms waiting for
               udev_device_get_is_initialized(), which is NEVER true without a
               resident udevd (set only when udevd writes /run/udev/data). ->
               "udev device never initialized" -> "Invalid path" -> every
               device rejected. This is also why the README's "host smoke
               test" was a FALSE green: the host runs udevd, which masked the
               gap.

  evdev.c      evdev_device_get_udev_tags() reads ID_INPUT* udev properties
               (written by udev's input_id builtin + hwdb). Absent without
               udev -> every device hits the "not tagged as supported input
               device" gate.

The patch (libinput-1.31.3-ksd-path-no-udev.patch, 2 files):

  src/path-seat.c  udev_device_from_devnode(): drop the get_is_initialized()
                   wait. udev_device_new_from_devnum() already returns a
                   sysfs-fallback device (devnode/syspath/sysname populated);
                   accept it as-is.

  src/evdev.c      ksd_evdev_tags_from_evdev(): faithful port of systemd's
                   udev-builtin-input_id.c (test_pointers + test_key +
                   scrollwheel-only + switch) reading capability bits via
                   libevdev. Called as a fallback in evdev_device_get_udev_tags()
                   when the udev scan yields NONE.

  sha256: 267e60d71462cf896f1bb503d368d57711977c075308fb13cb89a4e15ba0725d

Build (proven):
  1. git clone --depth 1 --branch 1.31.3 https://gitlab.freedesktop.org/libinput/libinput.git libinput-src
  2. patch -p1 < libinput-1.31.3-ksd-path-no-udev.patch
  3. meson setup build --prefix=/usr --buildtype=release \
        -Dlibwacom=false -Ddocumentation=false -Dtests=false \
        -Ddebug-gui=false -Dautoload-plugins=false -Dlua-plugins=disabled \
        -Dinternal-event-debugging=false
  4. ninja -C build

Deploy:
  sudo install -m 755 build/libinput.so.10.13.0 /mnt/ksd/usr/lib/libinput.so.10.13.0
  sudo ln -sf libinput.so.10.13.0 /mnt/ksd/usr/lib/libinput.so.10
  # quirks MUST match the libinput version (1.31.3). The rootfs carried a 1.32
  # quirks tree -> "Unknown key ModelCircularTouchpad". Install 1.31.3's:
  DESTDIR=/tmp/li ninja -C build install
  sudo cp -a /tmp/li/usr/share/libinput /mnt/ksd/usr/share/libinput

Verify (no-udev chroot — the host has udev, so a host-side test is a FALSE green):
  bind-mount live dev/sys/proc into /mnt/ksd, run a path-context smoke harness
  INSIDE the chroot. Proven 2026-11-10: 18 devices admitted with zero udev —
  AT keyboard, Planck (03a8:a4f9), ELAN touchpad, lid/power/sleep buttons,
  MX Master 3. 10 audio devices (HDA jacks, PC speaker) correctly rejected —
  identical to stock libinput (switch support is SW_LID / SW_TABLET_MODE /
  SW_KEYPAD_SLIDE only).

Purity boundary (LOCKED): libinput hard-depends on libudev.so.1 as its DEVICE
MODEL (meson dep_udev is non-optional). "Drop udev" = no resident udevd + no
udev database + no rules/hwdb; the libudev CLIENT library stays (it reads
sysfs directly, no daemon). Dropping libudev entirely = rewriting libinput's
device model = a full fork, not a patch. libwacom is disabled so libgudev
drops out of libinput's DT_NEEDED (the rootfs's libgudev.so.0 becomes orphan
and can be removed).
