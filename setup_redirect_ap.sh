#!/bin/bash

set -e

echo "[+] Updating system"
apt update && apt upgrade -y

echo "[+] Installing packages"
apt install -y hostapd dnsmasq nginx iptables-persistent

echo "[+] Stopping services for config"
systemctl stop hostapd
systemctl stop dnsmasq

echo "[+] Configuring static IP for wlan0"
cat <<EOF > /etc/dhcpcd.conf
interface wlan0
static ip_address=192.168.4.1/24
nohook wpa_supplicant
EOF

systemctl restart dhcpcd

echo "[+] Configuring hostapd"
cat <<EOF > /etc/hostapd/hostapd.conf
interface=wlan0
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

sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

systemctl unmask hostapd
systemctl enable hostapd

echo "[+] Configuring dnsmasq"
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig

cat <<EOF > /etc/dnsmasq.conf
interface=wlan0
dhcp-range=192.168.4.50,192.168.4.150,12h

address=/facebook.com/192.168.4.1
address=/youtube.com/192.168.4.1
EOF

echo "[+] Enabling IP forwarding"
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

echo "[+] Setting up NAT"
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT

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
