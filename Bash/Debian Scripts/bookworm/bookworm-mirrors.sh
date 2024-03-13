#!/usr/bin/env bash

script_path=$(readlink -f "${BASH_SOURCE[0]}")
script_name=$(basename "$script_path")

fname="/etc/apt/sources.list"

# Make a backup of the file
if [ ! -f "${fname}.bak" ]; then
    cp -f "$fname" "${fname}.bak"
fi

cat > "$fname" <<EOF
deb https://security.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware
deb https://atl.mirrors.clouvider.net/debian/ bookworm main contrib non-free non-free-firmware
deb https://atl.mirrors.clouvider.net/debian/ bookworm-updates main contrib non-free non-free-firmware
deb https://atl.mirrors.clouvider.net/debian/ bookworm-backports main contrib non-free non-free-firmware
EOF

# Open an editor to view the changes
if command -v nano &>/dev/null; then
    sudo nano "$fname"
else
    echo -e "\\nThe script failed to locate nano to open the file...\\n"
fi

sudo rm "$script_name"
