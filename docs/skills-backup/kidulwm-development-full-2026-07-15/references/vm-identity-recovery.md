# Recovering a running KidulVM's identity

Use these commands when the user names a VM but you don't have its SPICE/SSH port or even its libvirt name.

## 1. List all libvirt domains

```bash
virsh -c qemu:///system list --all
```

`virsh` without `-c` defaults to `qemu:///session`, which usually shows nothing for system VMs.

## 2. Find the QEMU command line for a running VM

```bash
ps aux | grep '[q]emu' | grep <vm-name>
```

This prints the full `qemu-system-x86_64` invocation. Look for:

- `-name guest=<vm-name>` — confirms the VM.
- `-spice port=<n>,addr=127.0.0.1,...` — SPICE display port.
- `-netdev {"type":"user",...}` with `id=hostnet0` — QEMU user-mode networking (SLIRP), so the guest has no host-bridged IP by default.

## 3. Open an SSH port forward

If no SSH forward exists, add one to the running QEMU process without restarting the VM:

```bash
virsh -c qemu:///system qemu-monitor-command <vm-name> --hmp "hostfwd_add hostnet0 tcp:127.0.0.1:<host-port>-:22"
```

Pick a host port that does not collide with untouchables (2222, 2223) or other clones.

## 4. Test access

```bash
ssh -p <host-port> -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1
```

If the key was previously injected via guest agent, it should work immediately. If not, use `virt-manager` console or ask the user for credentials.

## 5. When the user says "lock that in"

Stop, record the new active VM in memory, and confirm its connection details before any build or deploy. Do not revert to old defaults (2222/2225) for the rest of the session unless explicitly told to.
