#!/bin/bash
set -e

UPLINK_IFACE=eth0
WLAN_IFACE=wlan0
AP_IP=192.168.4.1

echo "[+] Updating system"
apt update && apt upgrade -y

echo "[+] Installing packages"
apt install -y hostapd dnsmasq nginx iptables-persistent dhcpcd5

echo "[+] Stopping services for config"
systemctl stop hostapd || true
systemctl stop dnsmasq || true

echo "[+] Configuring static IP for ${WLAN_IFACE}"
cat <<EOF > /etc/dhcpcd.conf
interface ${WLAN_IFACE}
static ip_address=${AP_IP}/24
nohook wpa_supplicant
EOF

systemctl restart dhcpcd

echo "[+] Configuring hostapd"
cat <<EOF > /etc/hostapd/hostapd.conf
interface=${WLAN_IFACE}
driver=nl80211
ssid=MyRedirectWiFi
hw_mode=g
channel=7
wmm_enabled=0
auth_algs=1
wpa=2
wpa_passphrase=supersecretpassword
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

# Ensure hostapd knows where its config is
sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd || true

sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl daemon-reload
sudo systemctl restart hostapd

echo "[+] Configuring dnsmasq"
if [ ! -f /etc/dnsmasq.conf.orig ]; then
  mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
fi

cat <<EOF > /etc/dnsmasq.conf
interface=${WLAN_IFACE}
dhcp-range=192.168.4.50,192.168.4.150,12h

address=/facebook.com/${AP_IP}
address=/youtube.com/${AP_IP}
EOF

echo "[+] Enabling IP forwarding"
# Enable immediately
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Make persistent (modern, safe)
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ipforward.conf
sysctl --system >/dev/null

echo "[+] Setting up NAT"
iptables -t nat -C POSTROUTING -o ${UPLINK_IFACE} -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o ${UPLINK_IFACE} -j MASQUERADE

iptables -C FORWARD -i ${UPLINK_IFACE} -o ${WLAN_IFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -i ${UPLINK_IFACE} -o ${WLAN_IFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT

iptables -C FORWARD -i ${WLAN_IFACE} -o ${UPLINK_IFACE} -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -i ${WLAN_IFACE} -o ${UPLINK_IFACE} -j ACCEPT

netfilter-persistent save

echo "[+] Setting up redirect web page"
cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
  <title>Redirected</title>
</head>
<body>
  <h1>This site is blocked</h1>
  <p>You were redirected by the Raspberry Pi network.</p>
</body>
</html>
EOF

echo "[+] Restarting services"
systemctl restart dnsmasq
systemctl restart hostapd
systemctl restart nginx

echo "[✓] Setup complete. Reboot recommended."
