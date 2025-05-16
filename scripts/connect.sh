#!/bin/bash
# -----------------------------------------------------------------------------
# Author: wellatleastitried
# -----------------------------------------------------------------------------
# DISCLAIMER
# -----------------------------------------------------------------------------
# This script is provided for educational and authorized security testing only.
# You are solely responsible for ensuring that your use of this script complies
# with all applicable laws, regulations, and terms of service.
#
# The author assumes NO LIABILITY and NO RESPONSIBILITY for any misuse, damage,
# unauthorized access, disruption of service, or illegal activity resulting from
# the use of this script.
#
# By using this script, you acknowledge that:
# - You understand the potential impact of the actions it performs;
# - You have explicit permission to use it in the target environment;
# - You accept full responsibility for any consequences arising from its use.
#
# If you do not agree to these terms, you are prohibited from using this script.
# -----------------------------------------------------------------------------

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[!] Please run as root"
    exit 1
fi

IFACE="wlan0"
HOSTNAME="Galaxy-S21"               # Set to mimic android phone, can be changed to anything you want
SAMSUNG_MAC_OUI="58:CB:52"          # Preset is to mimic a Samsung phone, can be changed to any OUI

# Traffic shaping settings to mimic mobile requests
RATE="100kbps"
BURST="32kbit"
LATENCY="100ms"

ORIGINAL_MAC=$(cat /sys/class/net/$IFACE/address)
ORIGINAL_HOSTNAME=$(hostname)

echo "ORIGINAL_MAC=$ORIGINAL_MAC" > /tmp/stealthConnectionState
echo "ORIGINAL_HOSTNAME=$ORIGINAL_HOSTNAME" >> /tmp/stealthConnectionState
echo "IFACE=$IFACE" >> /tmp/stealthConnectionState

function kill_dhcp() {
    echo "[*] Killing DHCP clients..."
    pkill dhclient 2>/dev/null || true
    pkill wpa_supplicant 2>/dev/null || true
    systemctl stop NetworkManager.service 2>/dev/null || true
    systemctl stop avahi-daemon.service 2>/dev/null || true
    systemctl stop cups.service 2>/dev/null || true
}

function randomize_mac() {
    echo "[*] Randomizing MAC address to appear as a Samsung..."
    ip link set $IFACE down
    NEW_MAC="${SAMSUNG_MAC_OUI}:$(hexdump -n3 -e '/1 ":%02X"' /dev/urandom)"
    ip link set dev $IFACE address $NEW_MAC
    CURRENT_MAC=$(cat /sys/class/net/$IFACE/address)

    if [[ "$CURRENT_MAC" != "$NEW_MAC" ]]; then
        echo "[!] Failed to set MAC address. Trying a different method..."

        if command -v macchanger &> /dev/null; then
            macchanger --mac $NEW_MAC $IFACE
        else
            echo "[!] macchanger not installed. MAC change has failed."
        fi
    fi
    ip link set $IFACE up
    echo "NEW_MAC=$NEW_MAC" >> /tmp/stealthConnectionState
}

function set_hostname() {
    echo "[*] Setting spoofed hostname..."
    hostnamectl set-hostname "$HOSTNAME"
    sed -i "s/127.0.1.1.*/127.0.1.1\t$HOSTNAME/" /etc/hosts
}

function discover_subnet() {
    echo "[*] Listening for DHCP offer to learn subnet..."

    if command -v tcpdump &> /dev/null; then
        echo "[*] Using tcpdump to passively detect the subnet..."
        OFFER=$(timeout 10 tcpdump -i "$IFACE" -n -v udp port 67 and port 68 2>/dev/null | awk '/Your-IP/ {print $NF}' | head -n1)
    fi

    if [[ -z "$OFFER" ]] && command -v iwlist &> /dev/null; then
        echo "[*] Attempting to detect network via wireless scan..."
        ESSID=$(iwlist $IFACE scanning | grep -i essid | head -n1 | cut -d'"' -f2)
        echo "[*] Detected ESSID: $ESSID"
    fi

    if [[ -z "$OFFER" ]]; then
        echo "[!] Failed to detect subnet via DHCP. Attempting common subnets..."
        COMMON_SUBNETS=("192.168.1" "192.168.0" "10.0.0" "10.0.1" "172.16.0")

        for BASE in "${COMMON_SUBNETS[@]}"; do
            GATEWAY="$BASE.1"

            if ping -c 1 -W 1 $GATEWAY &>/dev/null; then
                echo "[+] Found active gateway at $GATEWAY"
                break
            fi
        done

        if [[ -z "$GATEWAY" ]]; then
            BASE="192.168.1"
            GATEWAY="$BASE.1"
        fi
    else
        BASE=$(echo "$OFFER" | cut -d. -f1-3)
        GATEWAY="$BASE.1"
    fi
    IP="$BASE.$((RANDOM % 100 + 150))"
    STATIC_IP="$IP/24"

    if ping -c 1 -W 1 $IP &>/dev/null; then
        echo "[!] IP $IP is already in use. Trying a different one..."
        IP="$BASE.$((RANDOM % 50 + 150))"
        STATIC_IP="$IP/24"
    fi
    echo "[+] Subnet detected: $BASE.0/24"
    echo "[+] Gateway: $GATEWAY"
    echo "[+] Assigning IP: $IP"
    echo "GATEWAY=$GATEWAY" >> /tmp/stealthConnectionState
    echo "STATIC_IP=$STATIC_IP" >> /tmp/stealthConnectionState
}

function assign_ip() {
    echo "[*] Assigning static IP $STATIC_IP..."
    ip addr flush dev $IFACE
    ip addr add $STATIC_IP dev $IFACE
    ip route add default via $GATEWAY
}

function set_dns() {
    echo "[*] Setting dummy DNS resolver..."
    cp /etc/resolv.conf /etc/resolv.conf.bak
    echo "nameserver 1.1.1.1" > /etc/resolv.conf
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    chattr +i /etc/resolv.conf
    systemctl stop systemd-resolved.service 2>/dev/null || true
    echo "[*] Disabling IPv6..."
    sysctl -w net.ipv6.conf.all.disable_ipv6=1
    sysctl -w net.ipv6.conf.default.disable_ipv6=1
    sysctl -w net.ipv6.conf.$IFACE.disable_ipv6=1
}

function shape_traffic() {
    echo "[*] Applying traffic shaping on $IFACE..."
    tc qdisc del dev $IFACE root 2>/dev/null
    tc qdisc add dev $IFACE root tbf rate $RATE burst $BURST latency $LATENCY
    tc qdisc add dev $IFACE parent 1:1 handle 10: netem delay 20ms 10ms
}

function modify_tcp_fingerprint() {
    echo "[*] Modifying TCP/IP stack params to mimic Android..."
    echo "ORIGINAL_TCP_FIN_TIMEOUT=$(cat /proc/sys/net/ipv4/tcp_fin_timeout)" >> /tmp/network_stealth_state
    echo "ORIGINAL_TCP_KEEPALIVE_TIME=$(cat /proc/sys/net/ipv4/tcp_keepalive_time)" >> /tmp/network_stealth_state
    echo "ORIGINAL_TCP_WINDOW_SCALING=$(cat /proc/sys/net/ipv4/tcp_window_scaling)" >> /tmp/network_stealth_state
    sysctl -w net.ipv4.tcp_fin_timeout=40
    sysctl -w net.ipv4.tcp_keepalive_time=1200
    sysctl -w net.ipv4.tcp_window_scaling=1
    ip link set dev $IFACE mtu 1472
}

function launch_payload() {
    echo "[*] Launching request..."
    SAMSUNG_USER_AGENT="Mozilla/5.0 (Linux; Android 10; SM-G991B Build/RP1A.200720.012) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.105 Mobile Safari/537.36"
    curl --user-agent "$SAMSUNG_USER_AGENT" -s https://cdn.cloudflare.com/favicon.ico > /dev/null
    echo "[+] Connection test successful."
}

echo "[*] Starting stealth connection..."

kill_dhcp
randomize_mac
set_hostname
discover_subnet
assign_ip
set_dns
shape_traffic
modify_tcp_fingerprint
launch_payload

echo "[+] Stealth connection established."
echo "[+] Your device appears as: $HOSTNAME (Samsung Galaxy)"
echo "[+] Connected with IP: $IP"
echo "[+] Settings saved to /tmp/network_stealth_state for disconnect script"
echo "[+] Run disconnect.sh when finished to restore original settings"

