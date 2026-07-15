# VM source mismatch: bob-is-a-douche

Date: 2026-07-15

## Situation

`bob-is-a-douche` is a rounded-corner CachyOS KidulWM VM. Its running
binary was deployed from `/home/kidul/KidulWM`, not from the host repo
`/home/dad/dev/KidulWM`. The host repo branch `chrome-2x` at HEAD `e6da1ab`
is a `.cut`/chamfer branch and uses a Cairo-based `src/render/chrome.zig`
renderer. The VM source uses a wlroots scene/shader architecture with
`src/render/chamfer.zig`, `src/widgets`, and a tray.

## Consequences

- Patching `src/render/chrome.zig` on the host and deploying to the VM
  compiled and ran, but removed the action/title buttons because the host
  `chrome.zig` does not implement them.
- The host `renderChrome` path is not exercised by the VM binary; modifying it
  had no effect on the VM's actual chrome.
- Reverting the VM to the stock binary restored buttons and known-good state.

## Detection recipe

```bash
ssh -p <port> -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'find /home/kidul -maxdepth 2 -type d -name KidulWM | head -n 1'

ssh -p <port> -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'ls /home/kidul/KidulWM/src/render/ && ls /home/kidul/KidulWM/src/widgets/'
```

If the VM has `/home/kidul/KidulWM` with `render/chamfer.zig` and
`widgets/`, treat that source tree as the actual build target, not the host
repo.

## Recovery

- Host repo: `git checkout HEAD -- src/core/style.zig src/render/chrome.zig src/window.zig`
- VM: restore `/usr/bin/kidulwm` from `/tmp/kidulwm.stock` if saved, or
  rebuild cleanly from `/home/kidul/KidulWM`.

## Takeaway

Before changing KidulWM chrome on a VM, verify which source tree the running
binary came from. When a VM carries its own build tree, patch and build in the
VM, not in the host repo, or insist on rebuilding the VM from a fresh host
commit.
