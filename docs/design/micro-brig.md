# MICRO-BRIG — the KVM arm, mechanism (design)

Status: SPEC (draft for verdict — the HOW). cells.md is the locked WHAT
(foreign CODE -> brig, own kernel, the exception not the default). The pen
(kcell, namespaces/LXC) is BUILT (rootfs mode proven). This doc specifies the
second arm's mechanism and the slice plan to prove it in a VM.

## 1. What we are building

micro-brig = a stock kernel + a minimal initramfs + the trusted FOUNDATION —
the SAME ladder as the host, not a bespoke guest init. cells.md calls it
"one trusted binary" (that phrase means the trusted codebase vs the foreign
code, not literally one file). The trusted set is: kboot (PID-1), knetd
(foundation/network), kushd (the subordinate usher). The subordinate usher
seats the foreign code. Everything beyond that trusted set is foreign, and
the guest's own kernel survives a kernel-bug-grade threat, which is the whole
reason this arm exists.

Host side, the micro-brig is a CUED act of the superior kushd: ABSENT until
cued, seated on cue, killed (the plank) on discard. It is not a resident.

## 2. The boot shape (kboot.md — kboot owns PID-1, always)

  guest:  stock kernel -> initramfs /init = kboot (PID-1) -> kboot forks
          knetd (foundation: the guest HAS network) + kushd (the subordinate
          usher) -> kushd seats the foreign code it was told to seat.
  host:   superior kushd seats the micro-brig as a cued act. Cue = launch the
          guest; plank (discard) = kill the guest (process-death-is-the-kill,
          one level up — the whole cell is the process).

kboot owns PID-1 — LOCKED (kboot.md): the immortal thing is the smallest
thing, and the usher is kboot's KILLABLE child, never init, on the host OR in
a guest. There is no bespoke guest init. knetd in the guest's base is the
point: it gives the subordinate usher a network, so the TWO USHERS TALK — the
subordinate (guest) kushd reports its descriptor to the superior (host) kushd
over the wire (cells.md §superior usher; the kscope rendezvous seam, now local
guest<->host instead of machine<->machine). The guest reports a DESCRIPTOR up
("24fps film, stereo 48k, role=media, class=brig"); the host DECIDES what
seats. A subordinate can only hand up a descriptor; it can never claim to be
an authority.

## 3. The AV bridge (the seam, one level up from the pen)

The pen passes Wayland/PipeWire by BIND-MOUNTING the host sockets (shared
kernel, the cell app is a normal host client in a namespace). The brig has its
OWN kernel, so there is no host socket to bind-mount. The transport becomes a
virtio channel instead of a bind-mount — this is the same seam kscope names
("the local kcell AV bridge IS the seam, proven; kscope moves the cell to
another machine and makes the transport a wire instead of a local socket").
Here the "wire" is local: a vsock.

  - Wayland/PipeWire control crosses on virtio-vsock (AF_VSOCK, in-kernel,
    non-experimental) through a host-side proxy that forwards to kidulwm's
    socket. The guest app is still a HOST Wayland + PipeWire client in the
    blindness sense (cells.md §AV bridge): it sees only its own surface, its
    own input, its own stream.
  - The PIXELS cross as the scanout: the guest renders into its own virtio-gpu
    (no host /dev/dri in the cell — GPU driver bugs stay in the guest kernel),
    and only the scanout/framebuffer crosses to the host present path. This is
    the lossless seam (kscope.md), the same "paint on vblank cue" present path
    as kplayd's software-present fallback (docket #12) — one seam, three
    consumers (brig, kscope, no-GPU media).
  - wp_security_context_manager_v1 tags the guest client sandboxed, so the host
    compositor refuses to let it be screenshotted or read the clipboard.

## 4. Coordination (reuses the pen's two rules, cells.md)

  AV is focus-coupled: the focused slide owns the pipe; blur = park (mute, stop
  presenting). Reuses ksound's floor table + kidulwm's pixel map — no new
  authority.
  Network is focus-decoupled: kushd/knetd mints the guest's netns once and
  holds it for the guest's whole life, independent of what is on screen. The
  guest network is just a cell (cells.md) — same wall, `guest` role.

## 5. virtio device set (the micro-brig's walls)

  virtio-gpu   rendering; scanout crosses, driver bugs stay in-guest
  virtio-vsock control (descriptor up, cue down) + the AV proxy seam
  virtio-rng   entropy (no /dev/random stall)
  virtio-net   the guest's network = knetd's lane; focus-decoupled, netns
               minted by kushd/knetd — the two-ushers-talk channel
  virtio-blk   read-only if the foreign code needs an image; else initramfs-only
  (no virtio-input: input rides the AV pipe focus-coupling, per input-trust.md —
   the guest never owns an input device)

## 6. The launcher (KVM)

Two rungs, in order:
  1. qemu-system-x86_64 as SCAFFOLDING to prove slices 1-2 (same status as
     the nmcli/wpa_supplicant bridges: a bridge that keeps the slice iterating
     while the real core lands — do not polish it).
  2. a thin Zig KVM launcher (the KVM ioctls, no libvirt/qemu) that the
     superior kushd calls to seat/plank the guest — the real mechanism,
     matching kboot/kushd's "own the primitive, don't wrap it" law.

## 7. Slice plan (prove in a VM, host has /dev/kvm + nested=Y)

  Slice 1 — micro-brig exists: boot a stock kernel + minimal initramfs (busybox)
            under KVM, reach a prompt, tens of MB. PROVEN (verdict 98).
  Slice 1b — the trusted ladder: swap busybox for kboot (PID-1) -> knetd +
            kushd (subordinate usher) in the initramfs; prove the SAME boot
            ladder that runs on the host runs in the guest.
  Slice 2 — AV bridge crosses: a guest client renders as a host kidulwm slide
            over the vsock seam (control) + virtio-gpu scanout (pixels).
  Slice 3 — superior usher: host kushd seats/planks the micro-brig as a cued
            act; descriptor up, host decides, plank = guest death.
  Slice 4 — input + network: input rides the focus-coupled AV pipe; netns is
            focus-decoupled (minted by kushd/knetd).
  Slice 5 — foreign code runs: the trusted ladder supervises the foreign payload
            (the local brain's model, a downloaded binary) — the plank applies
            to the whole guest.

## 8. Open decisions for verdict

  1. Guest init: RESOLVED — kboot owns PID-1 (kboot.md), forks knetd + kushd.
     No bespoke guest init. (Was wrongly floated as kushd-as-init; kboot.md
     had already answered it.)
  2. Launcher now: confirm qemu-as-scaffolding is acceptable for slices 1-2
     before writing the Zig KVM launcher.
  3. Transport: confirm virtio-vsock (recommended, in-kernel) over the
     experimental virtio-Wayland device.
  4. Guest kernel/initramfs image: built per-brig at first (mkinitcpio with a
     kboot+knetd+kushd hook), vs. a frozen golden micro-brig image. RECOMMEND:
     build per slice during proof, freeze a golden image only when the
     mechanism is locked.

## 9. Slice 1 PROVEN (2026-10-06) — the boot recipe + the pitfalls it flushed

The arm is real. A stock kernel + a mkinitcpio `base`-only initramfs boots
under KVM to a live shell. Exact recipe (host has /dev/kvm + nested=Y):

  # minimal initramfs — the base hook bundles the DYNAMICALLY-LINKED busybox
  # (interpreter /lib64/ld-linux...); do NOT hand-craft a cpio, use base.
  printf 'MODULES=()\nBINARIES=()\nFILES=()\nHOOKS=(base)\n' > microbrig.conf
  sudo mkinitcpio -k 7.2.8-1-cachyos -c microbrig.conf -g microbrig-initramfs.img
  sudo chown $(id -u) microbrig-initramfs.img      # mkinitcpio writes root 600

  # boot — CachyOS keeps the kernel at /usr/lib/modules/<kver>/vmlinuz
  qemu-system-x86_64 -enable-kvm -cpu host -m 256 \
    -kernel /usr/lib/modules/7.2.8-1-cachyos/vmlinuz \
    -initrd microbrig-initramfs.img \
    -append "console=ttyS0,115200 panic=-1" -nographic -no-reboot

  -> "Failed to mount '' on real root" -> emergency shell -> "[rootfs ~]#"

Sizes: kernel 17.2MB + initramfs 7.5MB = ~25MB — inside "tens of MB".

Pitfalls (all hit, all fixed):
  1. -cpu host is REQUIRED: qemu's default qemu64 CPU lacks AVX; CachyOS
     glibc/busybox is -march=x86-64-v3, so init faults vpxor -> SIGILL ->
     "Attempted to kill init! exitcode=0x00000004" panic. For a REAL brig,
     decide -cpu host vs a defined model (host exposes the full CPU).
  2. -nodefaults STRIPS the serial port: console=ttyS0 then has no ttyS0 and
     the boot is silent. Drop -nodefaults; -nographic wires serial to stdio.
  3. Drive the shell over a PTY (pty.fork), NOT a pipe: the emergency shell
     needs a controlling tty ("sh: can't access tty; job control turned off"
     is normal, not a fault); piped stdin is never delivered.
  4. The busybox applet set in the base hook is minimal (id/head absent);
     uname -a proves execution. The emergency shell is only the SLICE-1
     scaffold — the REAL init is the SAME ladder as the host: kboot (PID-1)
     -> knetd + kushd (subordinate usher). Slice 1b swaps busybox for that
     ladder; then slice 2 (AV bridge).

## 10. Slice 1b PROVEN (2026-10-06) — the trusted ladder boots in the guest

kboot owns PID-1 in the guest, exactly as on the host. Recipe:

  # deploy kboot + kushd (knetd already at /usr/local/bin; bash at /bin/bash)
  sudo cp kboot/zig-out/bin/kboot /usr/local/bin/kboot
  sudo cp kushd/zig-out/bin/kushd /usr/local/bin/kushd
  printf 'MODULES=()\nBINARIES=(/usr/local/bin/kboot /usr/local/bin/kushd /usr/local/bin/knetd /bin/bash)\nFILES=()\nHOOKS=(base)\n' > microbrig-kboot.conf
  sudo mkinitcpio -k 7.2.8-1-cachyos -c microbrig-kboot.conf -g microbrig-kboot.img
  sudo chown $(id -u) microbrig-kboot.img

  qemu-system-x86_64 -enable-kvm -cpu host -m 256 \
    -kernel /usr/lib/modules/7.2.8-1-cachyos/vmlinuz \
    -initrd microbrig-kboot.img \
    -append "console=ttyS0,115200 rdinit=/usr/local/bin/kboot panic=-1" \
    -nographic -no-reboot

  PROOF: /proc/1/comm = "kboot"; ps -> knetd + kushd + -bash (getty) under PID 1;
  knetd "v0.4 up (event-driven)"; getty shell "-bash-5.3#".
  Sizes: kernel 17.2MB + initramfs 14MB (kboot+knetd+kushd+bash+libs) = ~31MB.

Pitfall (slice 1b):
  1. kboot fopen's /tmp/kboot.log BEFORE mountEarly mounts tmpfs over /tmp, so
     in a bare initramfs (no /tmp dir yet) fopen fails and kboot is SILENT —
     the "forked knetd pid=X" log lines never land. On the host (real root)
     /tmp exists so it works. Prove the ladder via /proc/1/comm + ps instead.
     FOLLOW-UP: kboot should mkdir /tmp or fopen after mountEarly so the log
     survives an initramfs boot (needed for slice 3+ debugging).

## 11. Slice 2 recon (2026-10-06) — the wire's gate: vsock/virtio-gpu are modules

The AV bridge needs two virtio devices in the guest, both =m (NOT built-in) on
this kernel:
  CONFIG_VIRTIO_VSOCKETS=m   (guest vsock transport)
  CONFIG_DRM_VIRTIO_GPU=m    (guest render/scanout)
  CONFIG_VHOST_VSOCK=m       (host side; /dev/vhost-vsock IS present)

Host side is READY NOW: python3 has AF_VSOCK(40), bind+listen on CID 2 works.
Guest side is GATED: kboot loads NO modules (no udev; kmodd is still a stub),
so the guest cannot reach vsock/virtio-gpu without a load step. Two ways through:
  1. brig-specific kernel with vsock + virtio-gpu built-in (=y) — cleanest for
     the brig's own kernel, but it is a kernel build.
  2. build kmodd (the machine-class module loader, kboot slice-2 stub) — loads
     the right modules per machine class before kushd forks.
qemu wire: -device vhost-vsock-pci,guest-cid=<N> (host CID=2, first guest CID=3).
This gate is the same "own kernel, own modules" seam cells.md §AV bridge #2
names (no host /dev/dri; its own virtio GPU) — expected, not a surprise.

## 12. Slice 2 UNBLOCKED (2026-10-06) — kmodd loads the brig's modules (vsock live)

kmodd is BUILT and PROVEN: the machine-class module loader, kboot step 2.
kboot now forkKmodd()s (fork + waitpid) between mountEarly and startFoundation;
kmodd reads the class (kclass=brig via /proc/cmdline, or /etc/kboot/class,
default tv), decompresses + loads that class's modules, then EXITS (one-shot —
NOT a body act; kboot does not respawn it).

Mechanism (own-the-primitive; no kmod, no kernel-config dependency):
  1. read the whole .ko.zst (mkinitcpio stores modules COMPRESSED, .ko.zst).
  2. zstd-decompress in userspace (kmodd links libzstd) and init_module(2) the
     ELF bytes — finit_module does NOT decompress here despite
     CONFIG_MODULE_DECOMPRESS=y: it returns ENOEXEC on .ko.zst, so kmodd
     decompresses itself rather than lean on the kernel.
  3. init_module does NOT auto-load deps — load in TOPOLOGICAL order.

brig class loads (fixed hardware, dependency-ordered):
  vsock <- vmw_vsock_virtio_transport_common <- vmw_vsock_virtio_transport
  failover <- net_failover <- virtio_net

PROOF (qemu -device vhost-vsock-pci,guest-cid=3 -device virtio-net-pci,
append "kclass=brig"): /proc/modules shows all six Live —
  vsock 77824 2 vmw_vsock_virtio_transport,vmw_vsock_virtio_transport_common
  ... vmw_vsock_virtio_transport 20480, failover 16384 -> net_failover 24576
  -> virtio_net 122880

Slice 2 is unblocked: the guest now has AF_VSOCK (control plane) + virtio_net
(network plane). Next rung = the AV bridge itself (host CID 2 <-> guest CID 3
handshake, then virtio-gpu scanout — virtio-gpu still needs its drm dep chain
drm_kms_helper/ttm, a LATER kmodd slice).

kboot changes: forkKmodd() at step 2; kmodd built as a sibling exe in kboot/
(build.zig), links libzstd. Zig 0.16: linkSystemLibrary is on Module
(kmodd_mod.linkSystemLibrary("zstd", .{})), NOT on Compile.

## 13. Slice 2: the vsock wire is LIVE (2026-10-06) — control plane proven

With kmodd loading vsock in the guest, the AV bridge control plane is proven
end-to-end. A static vsock-test client in the guest connected to CID 2 (the
host), sent "ping-from-brig"; the host's AF_VSOCK server received it and
echoed "pong-from-host" back. Both directions carry bytes:

  guest (CID 3)  --connect-->  host (CID 2)
  "HOST ACCEPT from (3, ...)"  = guest CID 3 reached host CID 2
  "HOST GOT: ping-from-brig"   = guest -> host
  "BRIG GOT: pong-from-host"   = host -> guest

Wire-up (host): qemu -device vhost-vsock-pci,guest-cid=3 bridges the guest's
vsock to /dev/vhost-vsock; the host binds AF_VSOCK CID 2 (VMADDR_CID_ANY) and
accepts. Guest side is a static C client (AF_VSOCK, connect to CID 2) dropped
into the initramfs via BINARIES=.

PITFALL (will recur in the real AV bridge): vsock close-reset RACE — a server
that send()s then immediately close()s races the FIN against the data; the
client reads EOF/partial. FIX: flush (sleep) before close on the sender side,
or shutdown(SHUT_WR) and let the peer drive the close.

Next rung: virtio-gpu scanout (pixels over the wire) — still needs its drm dep
chain (drm_kms_helper/ttm, a later kmodd slice); then the guest client renders
as a host kidulwm slide.

## 14. Slice 2 scanout: virtio-gpu live (2026-10-06) — the guest has its own GPU

virtio-gpu loads clean in the brig. The drm core + kms/shmem helpers are
BUILT-IN on this kernel, so the whole loadable chain is just two modules:
virtio_dma_buf -> virtio-gpu (modprobe --show-depends order). kmodd's brig
class now carries them; booting with -device virtio-gpu-pci yields a real DRM
device in the guest: /dev/dri/card0 + /dev/dri/renderD128.

virtio_dma_buf is the seam worth naming: it is the dma-buf export path from
the guest's virtio-gpu — exactly the "no host /dev/dri, own virtio GPU" pixel
bridge cells.md §AV bridge names. The guest is now a complete foreign-code
cell: own GPU (virtio-gpu) + network (virtio-net) + control (vsock).

Next rung: the scanout share — the guest renders a surface and the host
kidulwm shows it as a slide (the actual AV bridge payload).

## 15. Slice 2 scanout share: guest pixels cross the wire (2026-10-06)

A raw-DRM guest program (drm-fill, no libdrm) modesets virtio-gpu's virtual
connector and scans out a solid red framebuffer. qemu boots with
`-vga none -device virtio-gpu-pci -display vnc` + a unix monitor; screendump
captures the host side. Result: 1280x800 all-red, center (255,0,0), 400/400
samples red — the guest's framebuffer is visible on the host.

The AV bridge's pixel plane is proven end-to-end: the guest renders via its
own virtio GPU, the pixels cross, the host sees them. virtio-gpu's connector
is type 15 (VIRTUAL), connection=1, default mode 1280x800.

Pitfalls (raw DRM modeset, modern `_ptr` UAPI):
  - the connection-status enum (`drm_connector_status`) is NOT in the
    installed UAPI header — use numeric 1 (connected).
  - GETCONNECTOR is two-phase; pass 2 must allocate `props_ptr` +
    `prop_values_ptr` too, or the ioctl fails (the connector has properties).
  - the UAPI uses `_ptr` pointer members (`connector_id_ptr`, `modes_ptr`, ...)
    not inline arrays.

Next: route the virtio-gpu scanout to a dma-buf kidulwm imports as a slide
(the virtio_dma_buf seam), instead of qemu's VNC window — the real "foreign
code paints the face" integration.

## 16. Show time: foreign code paints the face (2026-10-06)

Rung A, proven. The brig boots with `-display gtk` — qemu's GTK window is a
native kidulwm client, so the guest's render lands on the face as its own space
inside a slide. drm-fill modeset + filled virtio-gpu's framebuffer red;
Barticus saw RED, in its own space, in the slide.

This is the stepping stone: pixels go guest virtio-gpu -> qemu's GTK surface ->
kidulwm. Rung B (production) is the dma-buf seam — import the guest's
virtio-gpu framebuffer directly as a slide texture (virtio_dma_buf / udmabuf),
no qemu surface in between.

Note: screendump of the full GTK window sampled (0,0,255) at the centre — the
red 1280x800 framebuffer is a sub-region; the eyes are the authoritative red.

## 17. Rung B seam: the dma-buf handoff is the dbus path (2026-10-06)

Leg 1 (blob + udmabuf, true zero-copy) is blocked by the qemu build: qemu 11
ships the `blob=` flag but not the udmabuf backend ("need rutabaga or udmabuf
for blob resources"; no udmabuf device option). The package, not the design.

Leg 2 (qemu `-display dbus`) is the seam, unblocked and mapped:
  - qemu exports `org.qemu.Display1` with `/org/qemu/Display1/Console_0`
    (interface `org.qemu.Display1.Console`):
      RegisterListener(h)  — take a unix-fd handle; qemu pushes the scanout
                             (a dma-buf fd via SCM_RIGHTS) over it.
      Width=1280 / Height=800 — the guest's virtio-gpu mode, reported live.

This is the RIGHT architecture: own software virtio-gpu (2D), no host /dev/dri
in the cell, pixels cross as a dma-buf fd. virgl / rutabaga would put the host
GPU INSIDE the cell — against cells.md.

Next: the brig shim — a GDBus / sd-bus client that RegisterListener()s a socket
and reads the scanout dma-buf fd, then maps it as a kidulwm slide texture.

## 18. The brig shim: guest framebuffer delivered via dbus p2p (2026-10-06)

The shim (brig-shim.c, GDBus) receives the guest's virtio-gpu framebuffer from
qemu's -display dbus over a peer-to-peer D-Bus connection:

  1. shim calls Console_0.RegisterListener(h) on the session bus, handing qemu
     one end of a socketpair.
  2. qemu is the D-Bus SERVER (AUTHENTICATION_SERVER); the shim is the CLIENT
     (AUTHENTICATION_CLIENT, guid=NULL — the client receives the guid).
  3. the shim exports org.qemu.Display1.Listener at /org/qemu/Display1/Listener.
  4. qemu CALLS the Listener methods; Scanout carries the framebuffer.

Result: "Scanout 1280x800 stride=5120 pixman_fmt=0x20028888 (X8R8G8B8)
bytes=4096000" — the full framebuffer as raw bytes.

The delivery is the RAW-BYTES Scanout fallback, not ScanoutDMABUF: virtio-gpu
2D mode keeps the framebuffer guest-local (shmem), so qemu's dbus display
copies it to a pixman surface. ScanoutDMABUF needs blob+udmabuf (blocked:
qemu lacks udmabuf) or virgl (host GPU inside the cell — against cells.md).

Listener method set (all 9): Scanout(u,u,u,u,ay), Update(i,i,i,i,u,u,ay),
ScanoutDMABUF(h,u,u,u,u,t,b), UpdateDMABUF(i,i,i,i), Disable(), MouseSet(i,i,i),
CursorDefine(i,i,i,i,ay), ScanoutMap(h,u,u,u,u,u), UpdateMap(i,i,i,i).

Next: import the framebuffer into kidulwm as a slide (wl_shm for raw bytes).
The 4MB-per-frame copy is the pacing risk — "timing is everything" applies here.

## 19. The face import: guest pixels on a kidulwm slide (2026-10-06)

Full chain proven:

  guest drm-fill (red) → qemu -display dbus Scanout (raw X8R8G8B8)
    → brig-shim (p2p Listener) → /tmp/brig-frame.rgba (100% red, 1280x800x4)
    → brig-present (wl_shm client) → kidulwm slide = RED.

Facts worth keeping:
  - pixman X8R8G8B8 == wl_shm XRGB8888 byte-for-byte: the shim's Scanout bytes
    memcpy straight into a shm buffer, zero conversion.
  - Little-endian XRGB8888: red=0x00FF0000, blue=0x000000FF. 0xFF000000 is
    BLACK (X is the HIGH byte, not blue).
  - kidulwm slide = 1673x1064 logical (HiDPI output 3840x4320 physical).
  - xdg-shell ordering: empty commit → roundtrip (ack configure) → attach
    buffer. Committing a buffer pre-configure = protocol error 3
    ("xdg_surface has never been configured").

Remaining polish: guest framebuffer 1280x800 vs slide 1673x1064 (misaligned
top-left); fix = letterbox or set the guest mode to the slide size. Then
continuous frames + frame-callback pacing — the flicker law applied to the seam.

## 20. The slide producer (design freeze, locked — Barticus 2026-10-06)

The brig is NOT a desktop in a window. It is a SLIDE PRODUCER: a foreign-code
cell that renders ONE surface at the slide's exact size, and the host presents
it 1:1. No WM, no cursor, no display of its own, no resolution negotiation.
This refines cells.md (foreign code -> brig, the exception not the default): the
exception is a cell that emits a slide, not an OS that demands a screen.

Kills "resolution inside our resolution" at the root — there is only ONE
resolution (the slide's), one handshake at slide creation, then never again.

Consequences (locked):
- 1:1 = the guest renders at the slide's LOGICAL size, matching the rest of the
  KSD UI render scale. NOT the physical output (the guest would draw double the
  pixels for no gain and need its own HiDPI handling).
- Golden images are the mechanism: we force every VM onto our base image
  (kernel + package manager + KSD slide renderer), so we guarantee it renders at
  the slide size. GNOME/KDE break because they insist on owning the display,
  cursor, and resolution — exactly the three things we confiscate. Not a
  limitation; it is the enabler.
- Framebuffer cost is bigger (slide-size vs a small mode), but it is per-CHANGE,
  not per-frame (qemu Update, not a 60fps Scanout; continuous video is kmedia's
  job, not the brig's).
- No letterbox, no black bars. The slide IS the VM. Host-drawn controls are an
  overlay or a peek-widget, never dead space in a letterbox.

### The cursor: the last perceptible lag (locked)

Cursor lag in a VM is one thing: the guest draws its cursor INSIDE its
framebuffer, so it round-trips host-pointer -> guest -> guest-render ->
framebuffer-copy -> host. That round-trip is the lag.

Fix: the cursor is NEVER in the framebuffer. It is a HOST hardware cursor:
- the guest sends its cursor as a SPRITE, not pixels — qemu dbus CursorDefine
  (w, h, hot_x, hot_y, data), already mapped on the p2p Listener.
- the shim forwards it to kidulwm as a cursor surface.
- kidulwm renders it at the host refresh rate -> zero perceptible lag; the guest
  only sees pointer position for input semantics.

The enter/exit "resolution change" is NOT a resolution change — it is a cursor
SHAPE swap at the slide boundary. Instant, no fade, no resize.

NOT mouse acceleration — acceleration is non-linear = unpredictable = feels
laggy. The goal is 1:1 linear + instant. At 1:1 there is no cursor scaling and
no coordinate transform: the sprite is used as-is, position is direct.

## 21. The under/over — deck = fullscreen = 16:9, chrome is a z-layer (Barticus 2026-10-06)

Correction to §20's "the guest renders at the slide's logical size": there is
ONE shape — 16:9 (1920x1080 logical, which is the logical size of BOTH outputs:
Kogan at scale 2, Predator at scale 1) — shared by deck AND fullscreen. The
deck slide is NOT reduced to 1673x1064 to make room for the peeks. The peeks
are HOST chrome (notifications/widgets), not guest content, so they float as
glass OVERLAYS on top of the full slide instead of squeezing it.

Z-stack (bottom -> top):
  - VM slide: full-screen 16:9. The guest renders this ONE size forever — no
    resolution change, no expand handshake, no bars, no aspect mismatch.
  - host chrome (peeks, widgets, notifications, backgrounds): translucent glass
    overlaid on the slide's edges.

Fullscreen = show/hide the chrome layer. The guest is ALWAYS fullscreen; it has
no idea the deck ever collapsed it. This is the INVERSE of Wayland remote
desktop: not host->remote, but guest scanout -> host slide, 1:1, lag-free.
"the wayland remote desktop we only dreamed of at the start."

Build note (what changes): guest drm-fill mode 1673x1064 -> 1920x1080 (custom
mode, same SETCRTC path proven); kidulwm deck slide 1673x1064 -> 1920x1080 with
the peek/chrome moved from "beside the slide" to a glass z-layer ABOVE it.
