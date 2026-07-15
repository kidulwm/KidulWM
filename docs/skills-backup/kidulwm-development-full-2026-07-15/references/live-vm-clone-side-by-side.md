# Disposable VM clones for KidulWM side-by-side comparison

Use this recipe when you want to test an experimental KidulWM build without touching the currently running “good” VM.

## Why

KidulWM visual state is hard to recover from a bad binary deploy. Running two VMs side by side lets the user keep the known-good build on one screen while judging an experimental build on another.

## What you need

- A running libvirt/KVM VM on `qemu:///system` (the source of truth).
- New QCOW2 path for the clone.
- New NVRAM path (copy the source's NVRAM).
- Libre Studio / `virsh` available.

## Live-clone a running disk

```bash
SRC=cachyos-kidulwm
DEST=cachyos-kidulwm-experiment

# 1. Convert the live disk to a new independent qcow2.
# --force-share lets qemu-img read the image while QEMU holds a write lock.
sudo qemu-img convert --force-share -O qcow2 \
  /var/lib/libvirt/images/${SRC}.qcow2 \
  /var/lib/libvirt/images/${DEST}.qcow2

sudo chown libvirt-qemu:libvirt-qemu /var/lib/libvirt/images/${DEST}.qcow2
sudo chmod 660 /var/lib/libvirt/images/${DEST}.qcow2

# 2. Copy NVRAM.
sudo cp /var/lib/libvirt/qemu/nvram/${SRC}_VARS.fd \
        /var/lib/libvirt/qemu/nvram/${DEST}_VARS.fd
sudo chown libvirt-qemu:libvirt-qemu /var/lib/libvirt/qemu/nvram/${DEST}_VARS.fd
sudo chmod 660 /var/lib/libvirt/qemu/nvram/${DEST}_VARS.fd
```

## Prepare the clone XML

Dump the source XML, then change at minimum:

- `<name>` to the new name.
- `<uuid>` to a fresh UUID.
- `<disk><source file='...'>` to the new QCOW2.
- `<nvram>` path to the new NVRAM file.
- `<interface><mac address='...'>` to a random MAC.
- `<graphics type='spice' port='...' autoport='...'>`: set `port='5901'` (or next free port) and `autoport='no'`.
- Remove `<seclabel type='dynamic' model='dac'>` if libvirt rejects it on define (CachyOS hosts may fail with "Security driver model 'dac' is not available").

Runtime-specific elements (serial/console source path, channel source path, alias attributes) should be stripped so libvirt regenerates them.

A quick Python snippet:

```python
import xml.etree.ElementTree as ET
import uuid
import os

src = "/tmp/cachyos-kidulwm.xml"
dst = "/tmp/cachyos-kidulwm-experiment.xml"

tree = ET.parse(src)
root = tree.getroot()
name = "cachyos-kidulwm-experiment"
root.find("name").text = name
if "id" in root.attrib:
    del root.attrib["id"]
root.find("uuid").text = str(uuid.uuid4())

root.find('.//disk/source').set('file', f'/var/lib/libvirt/images/{name}.qcow2')
nvram = root.find('.//nvram')
if nvram is not None:
    nvram.text = f'/var/lib/libvirt/qemu/nvram/{name}_VARS.fd'

mac = root.find('.//interface/mac')
mac.set('address', f"52:54:00:{ord(os.urandom(1)):02x}:{ord(os.urandom(1)):02x}:{ord(os.urandom(1)):02x}")

graphics = root.find('.//graphics')
graphics.set('port', '5901')
graphics.set('autoport', 'no')

# Strip runtime alias/source path/state attrs
def strip_aliases(elem):
    for child in list(elem):
        if child.tag == 'alias':
            elem.remove(child)
        elif child.tag == 'source' and child.get('path'):
            elem.remove(child)
        elif child.tag == 'target' and 'state' in child.attrib:
            del child.attrib['state']
        else:
            strip_aliases(child)

strip_aliases(root.find('devices'))

for seclabel in root.findall('seclabel'):
    root.remove(seclabel)

tree.write(dst, encoding='utf-8', xml_declaration=True)
```

Then define and start:

```bash
export LIBVIRT_DEFAULT_URI=qemu:///system
virsh define /tmp/cachyos-kidulwm-experiment.xml
virsh start cachyos-kidulwm-experiment
```

## Port forwards

User-mode networking forwards must be re-added after each start/reboot. Use a different host port for the clone, e.g. `2223`:

```bash
virsh -c qemu:///system qemu-monitor-command cachyos-kidulwm-experiment \
  --hmp 'hostfwd_add tcp::2223-:22'
```

SPICE then lives on `127.0.0.1:5901` and SSH on `127.0.0.1:2223`.

## Deploy to the clone

```bash
cd /home/dad/dev/KidulWM   # or the relevant worktree
zig build
scp -P 2223 -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm.new
ssh -p 2223 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm.new /usr/bin/kidulwm && sudo chmod 755 /usr/bin/kidulwm && sudo systemctl start kidulwm && systemctl is-active kidulwm'
```

## Open viewers

```bash
export WAYLAND_DISPLAY=wayland-1
export XDG_RUNTIME_DIR=/run/user/$(id - u)
virt-viewer --connect "$(virsh -c qemu:///system domdisplay cachyos-kidulwm)" &
virt-viewer --connect "$(virsh -c qemu:///system domdisplay cachyos-kidulwm-experiment)" &
```

## Cleanup

When done with the experiment:

```bash
export LIBVIRT_DEFAULT_URI=qemu:///system
virsh destroy cachyos-kidulwm-experiment
virsh undefine cachyos-kidulwm-experiment --remove-all-storage
rm -f /var/lib/libvirt/qemu/nvram/cachyos-kidulwm-experiment_VARS.fd
```
