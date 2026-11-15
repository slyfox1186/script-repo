#!/usr/bin/env bash

clear

echo "Discord Update Script - version 1.2"
echo "======================================================"
echo

# Check for root/sudo and exit if detected
if [[ $EUID -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    echo
    exit 1
fi

# Install required apt packages if missing
required_pkgs=(curl wget)
for pkg in "${required_pkgs[@]}"; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        sudo apt -y install "$pkg"
    fi
done

# Function to check the installed version of discord
get_installed_version() {
    dpkg-query --showformat='${Version}' --show discord 2>/dev/null | grep -oP '0.0.\K\d+'
}

# Function to download and install discord
download_and_install_discord() {
    local current_ver file_name installed_ver url
    current_ver="$1"
    file_name="discord-0.0.$current_ver.deb"
    url="https://dl.discordapp.net/apps/linux/0.0.$current_ver/$file_name"

    installed_ver=$(get_installed_version)

    if [[ "$installed_ver" != "$current_ver" ]] && [[ ! -f "$file_name" ]]; then
        echo "Downloading $file_name"
        wget --show-progress -U "Mozilla/5.0 (X11; Linux x86_64; rv:160.0) Gecko/20100101 Firefox/160.0" -O "$file_name" "$url"
        sudo apt update
        sudo apt install -y "./$file_name"
        rm -f "$file_name"
    elif [ "$installed_ver" == "$current_ver" ]; then
        echo "Discord version $current_ver is already installed."
    else
        echo "$file_name already exists."
    fi
}

# Function to uninstall discord
uninstall_discord() {
    echo "Uninstalling Discord..."
    sudo apt -y remove discord
}

# Discover the latest version
latest_ver=$(curl -fsS -A "$user_agent" "https://discord.com/api/download?platform=linux&format=deb" | grep -oP 'discord-0.0.\K\d+' | head -n1)

# Main function
main() {
    echo "Choose an option:"
    echo "1. Install latest Discord release"
    echo "2. Uninstall Discord"
    echo "3. Exit"
    echo
    read -p "Enter your choice (1 to 3): " choice

    case $choice in
        1)
            if [[ -n "$latest_ver" ]]; then
                download_and_install_discord "$latest_ver"
            else
                echo "Failed to find the latest Discord version."
            fi
            ;;
        2) uninstall_discord ;;
        3) exit 0 ;;
        *) echo "Invalid choice. Exiting." ;;
    esac
}

# Execute the main function
main
