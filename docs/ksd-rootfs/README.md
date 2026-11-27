# KSD rootfs config (the parts the deploy copies onto the m.2)

These files MIRROR what lives on the KSD drive. The drive is the running truth;
this directory is the tracked record so a rebuilt rootfs can reproduce it.

Deploy one file:

    sudo -S -p '' mount -o remount,rw /mnt/ksd
    sudo -S -p '' install -o root -g root -m 644 <file> /mnt/ksd/etc/.../<name>
    sudo -S -p '' sync && sudo -S -p '' mount -o remount,ro /mnt/ksd

## 10-ksd-alsa.conf  ->  /etc/pipewire/pipewire.conf.d/

KSD has no udev, and libspa-alsa.so's only device enumerator is
`api.alsa.enum.udev`. So WirePlumber's ALSA monitor has never found a device:
no sink, no sound, and every player stream parks in PAUSED. This drop-in
declares the sinks explicitly through the adapter factory instead
(`api.alsa.pcm.sink`), which needs no device database:

  analog hw:0,0  default (priority.session 1000, host parity)
  HDMI   hw:0,3  the TV (900)

Proof recipe without a reboot: run the IMAGE's pipewire in a chroot against
real /dev and read the graph with the host's pw-cli (both 1.6.9):

    sudo -S -p '' mount --bind /dev /mnt/ksd/dev
    sudo -S -p '' mount -t tmpfs -o size=32M tmpfs /mnt/ksd/run
    sudo -S -p '' mkdir -p /mnt/ksd/run/pwtest && sudo -S -p '' chown 1000:1000 /mnt/ksd/run/pwtest
    sudo -S -p '' mount --bind /proc /mnt/ksd/proc; sudo -S -p '' mount --bind /sys /mnt/ksd/sys
    sudo -S -p '' XDG_RUNTIME_DIR=/run/pwtest HOME=/tmp \
      chroot --userspec=1000:1000 --groups=995,983 /mnt/ksd /usr/bin/pipewire &
    XDG_RUNTIME_DIR=/mnt/ksd/run/pwtest pw-cli ls Node | grep -A2 alsa_output
    # cleanup: kill pipewire, umount sys proc run dev, remount /mnt/ksd ro

The rootfs has NO /usr/bin/env and NO pw-cli: chroot must inherit env, and
setpriv cannot chroot (CAP_SYS_CHROOT is gone after --reuid).
