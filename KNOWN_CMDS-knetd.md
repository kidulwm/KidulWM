# KidulWM — knetd commands (slice)

Read only for knetd work. Host core is KNOWN_CMDS.md.

## knetd (network daemon — replaces NM/wpa_supplicant/dhcpcd)

Repo `/home/dad/dev/knetd`, binary `zig-out/bin/knetd`, installed
`/usr/local/bin/knetd`, unit `knetd.service`, log `/var/log/knetd.log`.

Control file is `/tmp/knet/cmd` — write a verb line, knetd picks it up
within 5s, truncates the file after processing. State is readable at
`/tmp/knet/state` and `/tmp/kidul-signals/network.detail`.

```bash
echo 'spoof wlan0 random'          > /tmp/knet/cmd   # or xx:xx:xx:xx:xx:xx
echo 'up wlan0'                    > /tmp/knet/cmd
echo 'down wlan0'                  > /tmp/knet/cmd
echo 'dhcp enp1s0'                 > /tmp/knet/cmd   # full DISCOVER flow
echo 'scan wlan0'                  > /tmp/knet/cmd   # results land in network.detail
echo 'connect wlan0 MySSID'        > /tmp/knet/cmd   # psk from store, else open
echo 'connect wlan0 MySSID secret' > /tmp/knet/cmd   # typed psk (dev loop)
echo 'save MySSID secret'          > /tmp/knet/cmd   # store, 0600 root:root
echo 'forget MySSID'               > /tmp/knet/cmd
echo 'reload'                      > /tmp/knet/cmd   # re-parse the store
```

Deploy to fresh-one (VM on qemu:///system, NAT 192.168.122.96):

```bash
export LIBVIRT_DEFAULT_URI=qemu:///system
cd /home/dad/dev/knetd && zig build
scp -i ~/.ssh/id_ed25519_kidulwm zig-out/bin/knetd kidul@192.168.122.96:/tmp/knetd
ssh -i ~/.ssh/id_ed25519_kidulwm kidul@192.168.122.96 \
  'echo kidul | sudo -S systemctl stop knetd; echo kidul | sudo -S cp /tmp/knetd /usr/local/bin/knetd; echo kidul | sudo -S systemctl start knetd'
```

Flap test without losing SSH (guest-agent, no network needed):

```bash
virsh -c qemu:///system qemu-agent-command fresh-one \
  '{"execute":"guest-exec","arguments":{"path":"/usr/bin/ip","arg":["link","set","enp1s0","down"],"capture-output":true}}'
# poll the returned pid with guest-exec-status, then bring it back up the same way
```
