#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

fname="/etc/apt/sources.list"

# Make a backup of the file
if [[ ! -f "${list}.bak" ]]; then
    cp -f "$list" "${list}.bak"
fi

cat > "$fname" <<EOF
deb https://security.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware
deb https://atl.mirrors.clouvider.net/debian/ bookworm main contrib non-free non-free-firmware
deb https://atl.mirrors.clouvider.net/debian/ bookworm-updates main contrib non-free non-free-firmware
deb https://atl.mirrors.clouvider.net/debian/ bookworm-backports main contrib non-free non-free-firmware
EOF

# Open an editor to view the changes
if command -v nano &>/dev/null; then
    nano "$fname"
else
    echo -e "\\nThe script failed to locate nano to open the file...\\n"
fi

script_path=$(readlink -f "${BASH_SOURCE[0]}")
script_name=$(basename "$script_path")

rm "$script_name"
