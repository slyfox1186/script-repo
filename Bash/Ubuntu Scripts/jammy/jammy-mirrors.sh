#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

fname=/etc/apt/sources.list

# Make a backup of the sources list
if [[ ! -f "$fname.bak" ]]; then
    cp -f "$fname" "${fname}.bak"
fi

cat > "$fname" <<'EOF'
# clouvider.net - Atlanta, GA
deb https://atl.mirrors.clouvider.net/ubuntu/ jammy main restricted universe multiverse
deb https://atl.mirrors.clouvider.net/ubuntu/ jammy-updates main restricted universe multiverse
deb https://atl.mirrors.clouvider.net/ubuntu/ jammy-backports main restricted universe multiverse

# Ubuntu Security
deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse

# pilotfiber.com
# deb https://mirror.pilotfiber.com/ubuntu/ jammy main restricted universe multiverse
# deb https://mirror.pilotfiber.com/ubuntu/ jammy-updates main restricted universe multiverse
# deb https://mirror.pilotfiber.com/ubuntu/ jammy-backports main restricted universe multiverse

# teraswitch.com
# deb http://mirror.pit.teraswitch.com/ubuntu/ jammy main restricted universe multiverse
# deb http://mirror.pit.teraswitch.com/ubuntu/ jammy-updates main restricted universe multiverse
# deb http://mirror.pit.teraswitch.com/ubuntu/ jammy-backports main restricted universe multiverse
EOF

# Open an editor to view the changes
if command -v gedit &>/dev/null; then
    sudo gedit "$fname"
elif command -v nano &>/dev/null; then
    sudo nano "$fname"
elif command -v vim &>/dev/null; then
    sudo vim "$fname"
elif command -v vi &>/dev/null; then
    sudo vi "$fname"
else
    printf "\n%s\n" "Unable to open the sources.list file because no text editor was found."
fi
