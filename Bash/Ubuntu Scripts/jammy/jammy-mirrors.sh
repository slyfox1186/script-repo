#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

script_path=$(readlink -f "${BASH_SOURCE[0]}")
script_name="${script_path##*/}"

fname=/etc/apt/sources.list
backup_fname="${fname}.bak"

# Make a backup of the sources list
if [[ ! -f "$backup_fname" ]]; then
    cp -f "$fname" "$backup_fname"
fi

cat > "$fname" <<'EOF'
deb https://atl.mirrors.clouvider.net/ubuntu/ jammy main restricted universe multiverse
deb https://atl.mirrors.clouvider.net/ubuntu/ jammy-updates main restricted universe multiverse
deb https://atl.mirrors.clouvider.net/ubuntu/ jammy-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
EOF

# Open an editor to view the changes
if command -v nano &>/dev/null; then
    nano "$fname"
else
    printf "\n%s\n" "The script failed to locate nano to open the file."
fi
