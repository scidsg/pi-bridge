#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit
fi

# 1. Update and Upgrade the system
apt update && apt -y dist-upgrade && apt -y autoremove

# 2. Install required packages
apt -y install hostapd dnsmasq dhcpcd iptables git

# Stop services while configuring
systemctl stop hostapd
systemctl stop dnsmasq

# 3. Configure hostapd
cat > /etc/hostapd/hostapd.conf << EOL
interface=wlan0
driver=nl80211
ssid=Pi_AP
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=raspberry
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOL

# Point the DAEMON_CONF to the file we just created
if ! grep -q "DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"" /etc/default/hostapd; then
    echo "DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"" >> /etc/default/hostapd
fi

# 4. Configure dnsmasq
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
cat > /etc/dnsmasq.conf << EOL
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
EOL

# 5. Configure network interfaces
cp /home/pi/pi-bridge/dhcpcd.conf /etc/dhcpcd.conf

# Restart dhcpcd service
service dhcpcd restart

# 6. Enable IP forwarding
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"

# Set up IP tables to forward traffic
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sh -c "iptables-save > /etc/iptables.ipv4.nat"

# Make these IP tables rules persistent across reboots
if ! grep -q "iptables-restore < /etc/iptables.ipv4.nat" /etc/rc.local; then
    sed -i -e '$i \iptables-restore < /etc/iptables.ipv4.nat\n' /etc/rc.local
fi

# Ensure rc.local is executable
chmod +x /etc/rc.local

# 7. Start services

# Unmask hostapd service
sudo systemctl unmask hostapd

# Unblock wlan interface
sudo rfkill unblock wlan

# Enable and start the services
sudo systemctl enable hostapd
sudo systemctl start hostapd
systemctl start dnsmasq

sudo ip addr add 192.168.0.2/24 dev eth0
sudo ip link set eth0 down
sudo ip link set eth0 up
sudo route add default gw 192.168.0.1 eth0
sudo systemctl restart networking
sudo systemctl restart dhcpcd

echo "Setup complete! Your Raspberry Pi should now be functioning as a wireless access point."
echo "It might be a good idea to reboot the Raspberry Pi to ensure all changes are applied properly."
