#!/usr/bin/env bash
# Example config file = https://github.com/slyfox1186/script-repo/blob/main/Bash/Arch%20Linux%20Scripts/pacman-mirror-update.conf

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script as root or with sudo."
    exit 1
fi

default_fastest=5
default_latest=100

echo
read -p "Set how many mirrors to test (default 100): " latest
read -p "Set how many of the fastest mirrors to keep (default 5): " fastest
[[ -z "$latest" ]] && latest="$default_latest"
[[ -z "$fastest" ]] && fastest="$default_fastest"
clear
reflector --age 24 \
          --country "United States,Canada" \
          --fastest "$fastest" \
          --download-timeout 1 \
          --latest "$latest" \
          --protocol "http,https" \
          --save /etc/pacman.d/mirrorlist \
          --sort rate \
          --verbose
