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

## The headphone jack is NOT a separate sink

The ALC295 exposes ONE analog playback PCM (`/proc/asound/pcm`: "00-00: ALC295
Analog"). The headphone jack is PIN node 0x21 `[Jack] HP Out at Ext Right`,
fed from the same DAC (node 0x02) as the internal speakers (pin 0x14). So the
analog sink above IS the headphone jack — adding a second adapter on `hw:0,0`
would fail, because a hw PCM opens exactly once and two nodes would fight over
it. Auto-Mute Mode reports `Disabled` on this codec, so the jack and the
speakers are driven at the same time; plugging in headphones does not silence
the speakers. Silencing them needs a mixer write, and KSD ships no alsa-utils
and no init to run one — that is a separate item, not a sink problem.

## Full-chain proof (the one that matters, no reboot)

Run the image's pipewire + wireplumber + pipewire-pulse in the chroot, then push
audio through the PULSE socket exactly as kplayd's pa_simple does, and watch the
HDA PCM open:

    sudo mount --bind /dev /mnt/ksd/dev
    sudo mount -t tmpfs -o size=64M,mode=1777 tmpfs /mnt/ksd/run
    sudo mkdir -p /mnt/ksd/run/pwtest && sudo chown 1000:1000 /mnt/ksd/run/pwtest
    sudo mount --bind /proc /mnt/ksd/proc; sudo mount --bind /sys /mnt/ksd/sys
    for b in pipewire wireplumber pipewire-pulse; do
      sudo XDG_RUNTIME_DIR=/run/pwtest HOME=/run/pwtest PIPEWIRE_RUNTIME_DIR=/run/pwtest \
        chroot --userspec=1000:1000 --groups=995,983 /mnt/ksd /usr/bin/$b &
      sleep 2; done
    PULSE_SERVER=unix:/mnt/ksd/run/pwtest/pulse/native paplay tone.wav &
    head -1 /proc/asound/card0/pcm0p/sub0/status   # state: RUNNING  = DAC is clocking
    head -1 /proc/asound/card0/pcm3p/sub0/status   # closed         = it went analog, not HDMI
    XDG_RUNTIME_DIR=/mnt/ksd/run/pwtest wpctl status  # '*' + [vol: 1.00] on the analog sink

Observed 2026-11-27: default.audio.sink =
alsa_output.pci-0000_00_1f.3.analog-stereo, sink state running, stream running,
pcm0p RUNNING (hw_ptr advancing, delay ~5k), pcm3p closed, volume 1.00. An
UNTARGETED pulse stream therefore lands on the jack — which is exactly kplayd's
shape. Note `wpctl status` will list the client as the IMAGE user (kidul), even
though it is invoked from the host.
