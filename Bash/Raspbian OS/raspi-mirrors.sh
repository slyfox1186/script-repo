
#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

<<<<<<< Updated upstream
fname="/etc/apt/sources.list"

if [[ ! -f "$fname.bak" ]]; then
    cp -f "$fname" "$fname.bak"
=======
script_path=$(readlink -f "$BASH_SOURCE[0]")
script_name=$(basename "$script_path")

fname="/etc/apt/sources.list"

if [ ! -f "$fname.bak" ]; then
    cp -f "$fname" "$fname.bak"
>>>>>>> Stashed changes
fi

cat > "$fname" <<EOF
deb http://atl.mirrors.clouvider.net/debian/ bookworm main contrib non-free non-free-firmware
deb http://atl.mirrors.clouvider.net/debian/ bookworm-updates main contrib non-free non-free-firmware
deb http://atl.mirrors.clouvider.net/debian/ bookworm-backports main contrib non-free non-free-firmware

deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware
EOF

if command -v nano &>/dev/null; then
    nano "$fname"
else
    echo -e "\\nThe script failed to locate nano to open the file...\\n"
fi

script_path=$(readlink -f "${BASH_SOURCE[0]}")
script_name=$(basename "$script_path")

[[ -f "$script_name" ]] && rm "$script_name"
