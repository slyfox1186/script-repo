#!/usr/bin/env bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

fname=/etc/apt/sources.list

# Make a backup of the sources list
if [[ ! -f "${fname}.bak" ]]; then
    cp -f "${fname}" "${fname}.bak"
fi

cat > "${fname}" <<'EOF'
# clouvider.net - Atlanta, Georgia
deb https://atl.mirrors.clouvider.net/debian/ bullseye main contrib non-free non-free-firmware
deb https://atl.mirrors.clouvider.net/debian/ bullseye-updates main contrib non-free non-free-firmware
deb https://atl.mirrors.clouvider.net/debian/ bullseye-backports main contrib non-free non-free-firmware
deb https://security.debian.org/debian-security/ bullseye-security main contrib non-free non-free-firmware

# Official Debian Mirrors
# deb http://ftp.us.debian.org/debian/ bullseye main contrib non-free non-free-firmware
# deb http://ftp.us.debian.org/debian/ bullseye-updates main contrib non-free non-free-firmware
# deb http://ftp.us.debian.org/debian/ bullseye-backports main contrib non-free non-free-firmware

# osuosl.org
# deb https://debian.osuosl.org/debian/ bullseye main contrib non-free non-free-firmware
# deb https://debian.osuosl.org/debian/ bullseye-updates main contrib non-free non-free-firmware
# deb https://debian.osuosl.org/debian/ bullseye-backports main contrib non-free non-free-firmware

# steadfast.net
# deb https://mirror.steadfast.net/debian/ bullseye main contrib non-free non-free-firmware
# deb https://mirror.steadfast.net/debian/ bullseye-updates main contrib non-free non-free-firmware
# deb https://mirror.steadfast.net/debian/ bullseye-backports main contrib non-free non-free-firmware
EOF

# Open an editor to view the changes
if command -v gedit &>/dev/null; then
    sudo gedit "${fname}"
elif command -v nano &>/dev/null; then
    sudo nano "${fname}"
elif command -v vim &>/dev/null; then
    sudo vim "${fname}"
elif command -v vi &>/dev/null; then
    sudo vi "${fname}"
else
    printf "\n%s\n" "Unable to open the file sources.list because no text editor was found."
fi
