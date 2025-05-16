#!/bin/bash

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[!] Please run as root"
    exit 1
fi

IFACE="wlan0"
HOSTNAME="Galaxy-S21"           # Set to mimic android phone - can be anything you want
NEW_MAC_OUI="00:11:22"          # Preferably pulled from macchanger -l, but can be any OUI

# Traffic shaping settings
RATE="100kbps"
BURST="32kbit"
LATENCY="100ms"

function kill_dhcp() {
    echo "[*] Killing DHCP clients..."
    pkill dhclient || true
    pkill wpa_supplicant || true
    pkill NetworkManager || true
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

function discover_subnet() {
    echo "[*] Listening for DHCP offer to learn subnet..."
    OFFER=$(timeout 6 tcpdump -i "$IFACE" -n -v udp port 67 and port 68 2>/dev/null | awk '/Your-IP/ {print $NF}' | head -n1)

    if [[ -z "$OFFER" ]]; then
        echo "[!] Failed to detect subnet via DHCP. Falling back to 192.168.x.x/24"
        BASE="192.168.1"
        GATEWAY="$BASE.1"
        IP="BASE.$((RANDOM % 100 + 100))"
        return
    fi

    BASE=$(echo "OFFER" | cut -d. -f1-3)
    GATEWAY="$BASE.1"
    IP="$BASE.$((RANDOM % 100 + 100))"

    echo "[+] Subnet detected: $BASE.0/24"
    echo "[+] Assigning IP: $IP"
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
discover_subnet
assign_ip
set_dns
shape_traffic
launch_payload

echo "[*] Done. You can now connect using IP $IP."

