#!/usr/bin/env bash

clear

list=/etc/apt/sources.list

# Create a backup of the sources.list file
if [ ! -f "$list.bak" ]; then
    sudo cp -f "$list" "$list.bak"
fi

cat > /etc/apt/sources.list <<'EOF'
##################################################################
##
##  DEBIAN BOOKWORM MIRRORS
##
##  /etc/apt/sources.list
##
##  ALL MIRRORS IN EACH CATEGORY ARE LISTED AS BEING LOCATED IN THE UNITED STATES
##
##################################################################
##
## DEFAULT
##
# deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
# deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
# deb http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
##
## MAIN
##
deb http://atl.mirrors.clouvider.net/debian/ bookworm main contrib non-free non-free-firmware
deb http://mirror.us.leaseweb.net/debian/ bookworm main contrib non-free non-free-firmware
##
## UPDATES
##
deb http://atl.mirrors.clouvider.net/debian/ bookworm-updates main contrib non-free non-free-firmware
deb http://mirror.us.leaseweb.net/debian/ bookworm-updates main contrib non-free non-free-firmware
##
## BACKPORTS
##
deb http://atl.mirrors.clouvider.net/debian/ bookworm-backports main contrib non-free non-free-firmware
deb http://mirror.us.leaseweb.net/debian/ bookworm-backports main contrib non-free non-free-firmware
EOF

# Open the sources.list file for review
if which gted &>/dev/null; then
    sudo gted "$list"
elif which gedit &>/dev/null; then
    sudo gedit "$list"
elif which nano &>/dev/null; then
    sudo nano "$list"
elif which vim &>/dev/null; then
    sudo vim "$list"
elif which vi &>/dev/null; then
    sudo vi "$list"
else
    fail_fn 'Could not find an EDITOR to open the updated sources.list'
fi
