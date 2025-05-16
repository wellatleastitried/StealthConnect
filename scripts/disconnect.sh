#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "[!] Please run as root"
    exit 1
fi

IFACE="wlan0"

function unset_traffic_shaping() {
    tc qdisc del dev $IFACE root 2>/dev/null
}

echo "[*] Cleaning up stealth settings..."

chattr -i /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf

unset_traffic_shaping

ip addr flush dev $IFACE

hostnamectl set-hostname "my-machine"

echo "[*] Cleanup complete."
