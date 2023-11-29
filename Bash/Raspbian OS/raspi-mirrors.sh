#!/usr/bin/env bash

clear

fname='/etc/apt/sources.list'

# Create a backup of the sources.list file
if [ ! -f "${fname}.bak" ]; then
    sudo cp -f "${fname}" "${fname}.bak"
fi

cat > "${fname}" <<'EOF'
# Custom Atlanta GA Mirrors
deb http://atl.mirrors.clouvider.net/debian/ bookworm main contrib non-free non-free-firmware
deb http://atl.mirrors.clouvider.net/debian/ bookworm-updates main contrib non-free non-free-firmware
deb http://atl.mirrors.clouvider.net/debian/ bookworm-backports main contrib non-free non-free-firmware

# Official Raspbian Sources (Default)
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware
EOF

# Open the sources.list file for review
if type -P gnome-text-editor &>/dev/null; then
    sudo gnome-text-editor "${fname}"
elif type -P gedit &>/dev/null; then
    sudo gedit "${fname}"
elif type -P nano &>/dev/null; then
    sudo nano "${fname}"
else
    fail_fn 'Could not find an EDITOR to open the updated sources.list'
fi
