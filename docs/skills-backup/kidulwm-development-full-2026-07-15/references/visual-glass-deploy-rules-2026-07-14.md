# Visual / glass / chrome deploy rules — 2026-07-14

This session's repeated mistake: deploying experimental visual changes to the wrong VM. The user had to correct the assistant multiple times. Capture the hard rule here so future sessions start with it.

## Hard rule

- The default work VM for any KidulWM **visual, chrome, border, glass, or peek** experiment is `kidulwm-glass` on SSH port **2225**.
- `cachyos-kidulwm` on port 2222 is an **untouchable** rounded-best known-good build. Never deploy visual experiments there.
- `cachyos-kidulwm-chamfer` on port 2223 is the archived chamfer-best build. Never deploy visual experiments there.

## Pre-deploy check

Before every deploy command, include an explicit echo and verify:

```bash
echo 'TARGET: kidulwm-glass PORT: 2225'
```

If the target is not `kidulwm-glass / 2225`, stop and ask the user. Do not rely on muscle memory or default to port 2222.

## If you already deployed to the wrong VM

1. Stop the affected VM's `kidulwm` service immediately so the experimental binary is not running.
2. Build a clean restore binary from the stable fallback commit (see `HANDOFF.md`).
3. Copy the stable binary to `/usr/bin/kidulwm` on the affected VM and restart.
4. Only after the untouchable is restored, return to `kidulwm-glass` for the experiment.

## Setting up port 2225 on `kidulwm-glass`

If it is missing after a VM start:

```bash
virsh -c qemu:///system qemu-monitor-command kidulwm-glass --hmp 'hostfwd_add tcp::2225-:22'
```

Verify with `ss -ltn | grep 2225` on the host.
