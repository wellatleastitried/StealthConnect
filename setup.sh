#!/bin/bash

PROJECT_DIR=$(pwd)

function check_command() {
    command -v "$1" >/dev/null 2>&1 || { echo "[ERROR] Command '$1' is required but not installed. Please install it and try again."; exit 1; }
}

echo "[*] Checking for required commands..."
REQUIRED_COMMANDS=("aireplay-ng" "airodump-ng" "airmon-ng" "macchanger" "shred" "tcpdump")

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    check_command "$cmd"
done

echo "[*] All required commands are installed."
echo "[*] Setting name of interface to be used in scripts..."
read -p "Enter the name of your network interface (e.g., wlan0): " IFACE
sed -i "s/IFACE=\"wlan0\"/IFACE=\"$IFACE\"/" "$PROJECT_DIR"/scripts/connect.sh
sed -i "s/IFACE=\"wlan0\"/IFACE=\"$IFACE\"/" "$PROJECT_DIR"/scripts/disconnect.sh
sed -i "s/IFACE=\"wlan0\"/IFACE=\"$IFACE\"/" "$PROJECT_DIR"/scripts/deauth.sh
echo "[*] Setting up aliases for the connection scripts..."

if [ "$SHELL" == "/bin/bash" ]; then
    echo "alias connect='bash ~/scripts/connect.sh'" >> ~/.bashrc
    echo "alias disconnect='bash ~/scripts/disconnect.sh'" >> ~/.bashrc
    echo "alias status='bash ~/scripts/status.sh'" >> ~/.bashrc
    echo "alias list='bash ~/scripts/list.sh'" >> ~/.bashrc
    echo "alias help='bash ~/scripts/help.sh'" >> ~/.bashrc
    source ~/.bashrc
elif [ "$SHELL" == "/bin/zsh" ]; then
    echo "alias connect='zsh ~/scripts/connect.sh'" >> ~/.zshrc
    echo "alias disconnect='zsh ~/scripts/disconnect.sh'" >> ~/.zshrc
    echo "alias status='zsh ~/scripts/status.sh'" >> ~/.zshrc
    echo "alias list='zsh ~/scripts/list.sh'" >> ~/.zshrc
    echo "alias help='zsh ~/scripts/help.sh'" >> ~/.zshrc
    source ~/.zshrc
else
    echo "[!] Unsupported shell. You can add the aliases manually or run the scripts directly."
    echo "alias stealthConnect \"$(pwd)/connect.sh\" >> ~/.NAME_OF_SHELL_CONFIG"
    echo "alias stealthDisconnect \"$(pwd)/disconnect.sh\" >> ~/.NAME_OF_SHELL_CONFIG"
    echo "alias stealthDeauth \"$(pwd)/deauth.sh\" >> ~/.NAME_OF_SHELL_CONFIG"
fi

echo "[*] Marking scripts as executable..."
chmod +x "$PROJECT_DIR"/scripts/*.sh
echo "[*] Setup complete!"
