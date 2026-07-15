# Visual verification fallbacks for KidulWM

KidulWM currently does not implement `wlr-screencopy-v1`, so `grim` fails with:

```
compositor doesn't support the screen capture protocol
```

Use these workarounds until the protocol is implemented.

## QEMU monitor screendump

The QEMU monitor `screendump` command writes the *host* framebuffer file from the QEMU process, not from the guest filesystem. Use a host path such as `/tmp/kidulwm-screenshot.ppm`.

From the host:

```bash
virsh -c qemu:///system qemu-monitor-command cachyos-kidulwm --hmp 'screendump /tmp/kidulwm-screenshot.ppm'
magick /tmp/kidulwm-screenshot.ppm /tmp/kidulwm-screenshot.png
```

Then load `/tmp/kidulwm-screenshot.png` with the vision tool.

If `convert` or `magick` is unavailable, use ImageMagick's `convert` or `ffmpeg`:

```bash
ffmpeg -y -i /tmp/kidulwm-screenshot.ppm /tmp/kidulwm-screenshot.png
```

## End-to-end VM verification recipe

A fast way to verify a UI change without a SPICE viewer:

1. Ensure the VM is running and SSH hostfwd is up:
   ```bash
   virsh -c qemu:///system list
   ssh -o ConnectTimeout=5 -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 'systemctl is-active kidulwm'
   ```

2. Spawn test windows if none are visible:
   ```bash
   ssh -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
     'for i in 1 2 3; do WAYLAND_DISPLAY=wayland-1 /usr/bin/ghostty & done'
   ```

3. Cycle focus and confirm deck state:
   ```bash
   ssh -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
     'XDG_RUNTIME_DIR=/run/user/1000 /usr/bin/kidulwm-control get_layout'
   ```

4. Capture and convert:
   ```bash
   virsh -c qemu:///system qemu-monitor-command cachyos-kidulwm --hmp 'screendump /tmp/kidulwm-screenshot.ppm'
   magick /tmp/kidulwm-screenshot.ppm /tmp/kidulwm-screenshot.png
   ```

5. Inspect with `vision_analyze` on `/tmp/kidulwm-screenshot.png`.

## VNC / SPICE

If the VM has a VNC or SPICE display configured, connect with a viewer and capture from the host.

## Implementing wlr-screencopy-v1

To make `grim` work natively:

1. Create the manager in `Server.init()`:
   ```zig
   const screencopy_manager = try wlr.ScreencopyManagerV1.create(wl_server);
   _ = screencopy_manager;
   ```

2. wlroots scene compositors get most of the protocol handling automatically once the global is present; tie it to the scene output state in `Server.applyLayout()` or output commit loop.

This is a `good-first-issue` level protocol addition worth doing when screenshots become a frequent debug tool.
