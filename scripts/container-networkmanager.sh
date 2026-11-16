#!/bin/bash
# Inside the Omarchy container (root): let NetworkManager own the container's one link (eth0, NAT
# through the phone) instead of systemd-networkd, so Omarchy's bar and network panel show the real
# connection. Android still owns Wi-Fi and mobile data; DNS stays Droidspaces' resolv.conf.
# Rolls back to systemd-networkd by itself if eth0 has no IPv4 address after 30 seconds.
set -u
cat > /etc/NetworkManager/conf.d/s22-container.conf <<'X'
# S22 container: NetworkManager mirrors only eth0 (the phone's NAT link); DNS is Droidspaces'.
[main]
dns=none
rc-manager=unmanaged
no-auto-default=*

[device-s22-only-eth0]
match-device=interface-name:!eth0
managed=0
X
cat > /etc/NetworkManager/system-connections/phone.nmconnection <<'X'
[connection]
id=Phone
type=ethernet
interface-name=eth0
autoconnect=true

[ethernet]

[ipv4]
method=auto

[ipv6]
method=ignore
X
chmod 600 /etc/NetworkManager/system-connections/phone.nmconnection
mkdir -p /etc/systemd/network/off
mv /etc/systemd/network/*.network /etc/systemd/network/off/ 2>/dev/null
systemctl disable --now systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service >/dev/null 2>&1
systemctl unmask NetworkManager.service >/dev/null 2>&1
systemctl enable --now NetworkManager.service >/dev/null 2>&1
for i in $(seq 30); do
    ip -4 -o addr show dev eth0 | grep -q 'inet ' && nmcli -t -f STATE general | grep -q connected && break
    sleep 1
done
if ! ip -4 -o addr show dev eth0 | grep -q 'inet '; then
    echo "no address from NetworkManager: rolling back to systemd-networkd"
    systemctl disable --now NetworkManager.service >/dev/null 2>&1
    systemctl mask NetworkManager.service >/dev/null 2>&1
    mv /etc/systemd/network/off/*.network /etc/systemd/network/ 2>/dev/null
    systemctl enable --now systemd-networkd.service >/dev/null 2>&1
    exit 1
fi
nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device | grep eth0
nmcli -t -f CONNECTIVITY general
ip -4 -o addr show dev eth0 | awk '{print $4}'
