#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "[!] Please run as root"
    exit 1
fi

IFACE="wlan0"
NEW_MAC_OUI="00:11:22"          # Preferably pulled from macchanger -l, but can be any OUI
STATIC_IP="192.168.1.241/24"    # Change if the network uses a different ip-range/subnet
GATEWAY="192.168.1.1"           # Change if the network uses a different gateway
HOSTNAME="Galaxy-S21"           # Set to mimic android phone - can be anything you want

# Traffic shaping settings
RATE="100kbps"
BURST="32kbit"
LATENCY="100ms"

function kill_dhcp() {
    echo "[*] Killing DHCP clients..."
    pkill dhclient
    pkill wpa_supplicant
}

function randomize_mac() {
    echo "[*] Randomizing MAC address..."
    ip link set $IFACE down
    macchanger --mac ${NEW_MAC_OUI}:$(hexdump -n3 -e '/1 ":%02X"' /dev/urandom) $IFACE
    ip link set $IFACE up
}

function set_hostname() {
    echo "[*] Setting spoofed hostname..."
    hostnamectl set-hostname "$HOSTNAME"
}

function assign_ip() {
    echo "[*] Assigning static IP $STATIC_IP..."
    ip addr flush dev $IFACE
    ip addr add $STATIC_IP dev $IFACE
    ip route add default via $GATEWAY
}

function set_dns() {
    echo "[*] Setting dummy DNS resolver..."
    echo "nameserver 1.1.1.1" > /etc/resolv.conf

    # Prevent resolv.conf from being overwritten by DHCP or systemd
    chattr +i /etc/resolv.conf
}

function shape_traffic() {
    echo "[*] Applying traffic shaping on $IFACE..."
    tc qdisc del dev $IFACE root 2>/dev/null
    tc qdisc add dev $IFACE root tbf rate $RATE burst $BURST latency $LATENCY
}

function launch_payload() {
    echo "[*] Launching request..."
    curl --user-agent "Mozilla/5.0 (Linux; Android 10)" https://cdn.cloudflare.com/favicon.ico
}

echo "[*] Starting stealth connection..."

kill_dhcp
randomize_mac
set_hostname
assign_ip
set_dns
shape_traffic
launch_payload

echo "[*] Connection established. You can now use the network."

