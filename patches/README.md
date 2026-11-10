# wlroots 0.20.2 rebuild — the libinput path patch

Decision (LOCKED 2026-11-10): the KSD input path is a PATH-BASED libinput
backend, no udev. wlroots' libinput backend is udev-only, so we rebuild
wlroots 0.20.2 from source with a surgical patch (patch + rebuild — we own the
delta, not the C tree).

Design + rationale: ../docs/design/input-path.draft.md
Law (admission ladder): ../docs/law/input-trust.md

## The patch

`wlroots-0.20.2-libinput-path.patch` — one file changed, backend/libinput/backend.c:

  backend_start(): libinput_udev_create_context + libinput_udev_assign_seat
  -> libinput_path_create_context + glob("/dev/input/event*") +
  libinput_path_add_device() per path.

Generated against wlroots tag 0.20.2 (git), applies clean to that tag.
sha256: 82be09a368fc85d50426df2367eda142b9255a29018dd1c45bfd7c7bcac91652

## Rebuild recipe

1. Obtain wlroots 0.20.2 source (git tag 0.20.2), or reuse the distro PKGBUILD
   (wlroots0.20-PKGBUILD.upstream here is the Arch recipe, pkgver 0.20.2).

2. Add a prepare() to the PKGBUILD that applies this patch:
     prepare() { cd "${pkgname}"; patch -p1 < "$srcdir/wlroots-0.20.2-libinput-path.patch" }
   and add the patch to source= + sha256sums.

3. Build: arch-meson + ninja (the PKGBUILD does this). Produces our own
   libwlroots-0.20.so.

4. Ship OUR .so into the KSD root (replacing the stock wlroots0.20 one), and
   copy /usr/share/libinput/*.quirks into the rootfs (the libinput data tree —
   the third rootfs-assembly data-copy gap, after Mesa drivers and firmware).

## PHASE 2 (not yet written)

backend/libinput/events.c handle_device_added(): the four-tier admission gate
(see input-trust.md §admission ladder). Tier 0/1/3 from bustype + VID:PID
against /etc/kushd/input-allowlist; Tier 2 from the kidulkey-gate verdict.
Netlink kobject-uevent hotplug (libinput_path_add_device/remove_device on
input add/remove).
