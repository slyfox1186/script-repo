#!/usr/bin/env bash

script_path=$(readlink -f "${BASH_SOURCE[0]}")
script_name=$(basename "$script_path")

fname="/etc/apt/sources.list"

# Make a backup of the file
if [[ ! -f "${list}.bak" ]]; then
    cp -f "$list" "${list}.bak"
fi

cat > "$fname" <<EOF
deb https://atl.mirrors.clouvider.net/ubuntu/ jammy main restricted universe multiverse
deb https://atl.mirrors.clouvider.net/ubuntu/ jammy-updates main restricted universe multiverse
deb https://atl.mirrors.clouvider.net/ubuntu/ jammy-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
EOF

# Open an editor to view the changes
if command -v nano &>/dev/null; then
    sudo nano "$fname"
else
    echo -e "\\nThe script failed to locate nano to open the file...\\n"
fi

sudo rm "$script_name"
