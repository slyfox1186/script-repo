#!/Usr/bin/env bash

clear

script_ver=1.1
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'

echo "Discord Update Script - version $script_ver"
echo "======================================================"
sleep 2

if [ "$EUID" -eq 0 ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

required_pkgs=("curl" "wget")
for pkg in "${required_pkgs[@]}"; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        sudo apt-get install -y "$pkg"
    fi
done

get_installed_version() {
    dpkg-query --showformat='$Version' --show discord 2>/dev/null | grep -oP '0.0.\K\d+'
}

download_and_install_discord() {
    local current_ver="$1"
    local file_name="discord-0.0.$current_ver.deb"
    local url="https://dl.discordapp.net/apps/linux/0.0.$current_ver/$file_name"

    local installed_ver=$(get_installed_version)

    if [ "$installed_ver" != "$current_ver" ] && [ ! -f "$file_name" ]; then
        echo "Downloading $file_name"
        wget --show-progress -U "$user_agent" -O "$file_name" "$url"
        sudo apt-get install -y "./$file_name"
        rm -f "$file_name"
    elif [ "$installed_ver" == "$current_ver" ]; then
        echo "Discord version $current_ver is already installed."
    else
        echo "$file_name already exists."
    fi
}

uninstall_discord() {
    echo "Uninstalling Discord..."
    sudo apt-get remove -y discord
}

latest_ver=$(curl -s -A "$user_agent" "https://discord.com/api/download?platform=linux&format=deb" | grep -oP 'discord-0.0.\K\d+' | head -n1)

main() {
    echo "Choose an option:"
    echo "1. Install latest Discord release"
    echo "2. Uninstall Discord"
    read -p "Enter your choice (1/2): " choice

    case $choice in
        1)
            if [ -n "$latest_ver" ]; then
                download_and_install_discord "$latest_ver"
            else
                echo "Failed to find the latest Discord version."
            fi
            ;;
        2) uninstall_discord ;;
        *) echo "Invalid choice. Exiting." ;;
    esac
}

main
