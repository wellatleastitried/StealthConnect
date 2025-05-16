#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "[!] Please run as root"
    exit 1
fi

if [ ! -f /tmp/network_stealth_state ]; then
    echo "[!] Could not find saved state file. Some settings may not be restored properly."
    IFACE="wlan0"
    ORIGINAL_HOSTNAME="my-machine"
else
    source /tmp/network_stealth_state
fi

echo "[*] Starting cleanup process..."

function restore_hostname() {
    echo "[*] Restoring original hostname: $ORIGINAL_HOSTNAME"
    hostnamectl set-hostname "$ORIGINAL_HOSTNAME"
    sed -i "s/127.0.1.1.*/127.0.1.1\t$ORIGINAL_HOSTNAME/" /etc/hosts
}

function restore_mac() {
    echo "[*] Restoring original MAC address"
    ip link set $IFACE down

    if [[ -n "$ORIGINAL_MAC" ]]; then
        ip link set dev $IFACE address $ORIGINAL_MAC
        CURRENT_MAC=$(cat /sys/class/net/$IFACE/address)

        if [[ "$CURRENT_MAC" != "$ORIGINAL_MAC" ]]; then
            echo "[!] Failed to restore MAC via ip command, trying macchanger"

            if command -v macchanger &> /dev/null; then
                macchanger --mac $ORIGINAL_MAC $IFACE
            else
                echo "[!] WARNING: Could not restore original MAC address"
            fi
        fi
    else
        echo "[!] Original MAC address not found in state file"
    fi

    ip link set $IFACE up
}

function restore_network_settings() {
    echo "[*] Removing traffic shaping rules"
    tc qdisc del dev $IFACE root 2>/dev/null || true
    echo "[*] Flushing IP configuration"
    ip addr flush dev $IFACE
    echo "[*] Restoring network configuration"
    ip link set dev $IFACE mtu 1500
}

function restore_dns() {
    echo "[*] Restoring DNS settings"
    chattr -i /etc/resolv.conf 2>/dev/null || true

    if [ -f /etc/resolv.conf.backup ]; then
        mv /etc/resolv.conf.backup /etc/resolv.conf
    else
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    fi

    echo "[*] Re-enabling IPv6..."
    sysctl -w net.ipv6.conf.all.disable_ipv6=0
    sysctl -w net.ipv6.conf.default.disable_ipv6=0
    sysctl -w net.ipv6.conf.$IFACE.disable_ipv6=0
}

function restore_tcp_parameters() {
    echo "[*] Restoring TCP/IP stack parameters"

    if [[ -n "$ORIGINAL_TCP_FIN_TIMEOUT" ]]; then
        sysctl -w net.ipv4.tcp_fin_timeout=$ORIGINAL_TCP_FIN_TIMEOUT
    else
        sysctl -w net.ipv4.tcp_fin_timeout=60
    fi

    if [[ -n "$ORIGINAL_TCP_KEEPALIVE_TIME" ]]; then
        sysctl -w net.ipv4.tcp_keepalive_time=$ORIGINAL_TCP_KEEPALIVE_TIME
    else
        sysctl -w net.ipv4.tcp_keepalive_time=7200
    fi

    if [[ -n "$ORIGINAL_TCP_WINDOW_SCALING" ]]; then
        sysctl -w net.ipv4.tcp_window_scaling=$ORIGINAL_TCP_WINDOW_SCALING
    else
        sysctl -w net.ipv4.tcp_window_scaling=1
    fi
}

function restart_network_services() {
    echo "[*] Restarting network services"
    systemctl start systemd-resolved.service 2>/dev/null || true
    systemctl start NetworkManager.service 2>/dev/null || true
    systemctl start avahi-daemon.service 2>/dev/null || true
    systemctl start cups.service 2>/dev/null || true
}

function cleanup_state_file() {
    echo "[*] Removing temporary state file"
    rm -f /tmp/network_stealth_state
}

restore_hostname
restore_mac
restore_network_settings
restore_dns
restore_tcp_parameters
restart_network_services
cleanup_state_file

echo "[+] Cleanup complete. Your original network configuration has been restored."
echo "[+] You may need to reconnect to your network normally now."

