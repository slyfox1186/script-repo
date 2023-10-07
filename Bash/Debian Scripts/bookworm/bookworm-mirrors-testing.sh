#!/usr/bin/env bash

clear

list='/etc/apt/sources.list'

# Create a backup of the sources.list file
if [ ! -f "${list}.bak" ]; then
    sudo cp -f "${list}" "${list}.bak"
fi

cat > "${list}" <<'EOF'
#######################################################################################
##
##  DEBIAN TESTING MIRRORS
##
##  /etc/apt/sources.list
##
##  ALL MIRRORS IN EACH CATEGORY ARE LISTED AS BEING LOCATED IN THE UNITED STATES
##
#######################################################################################
##
## DEFAULT
##
deb https://deb.debian.org/debian testing main contrib non-free non-free-firmware
deb https://deb.debian.org/debian testing-updates main contrib non-free non-free-firmware
deb https://deb.debian.org/debian testing-backports main contrib non-free non-free-firmware
deb https://security.debian.org/debian-security testing-security main contrib non-free non-free-firmware
##
## MAIN
##
deb http://atl.mirrors.clouvider.net/debian/ testing main contrib non-free non-free-firmware
deb http://mirror.us.leaseweb.net/debian/ testing main contrib non-free non-free-firmware
##
## UPDATES
##
deb http://atl.mirrors.clouvider.net/debian/ testing-updates main contrib non-free non-free-firmware
deb http://mirror.us.leaseweb.net/debian/ testing-updates main contrib non-free non-free-firmware
##
## BACKPORTS
##
deb http://atl.mirrors.clouvider.net/debian/ testing-backports main contrib non-free non-free-firmware
deb http://mirror.us.leaseweb.net/debian/ testing-backports main contrib non-free non-free-firmware
EOF

# Open the sources.list file for review
if which gnome-text-editor &>/dev/null; then
    sudo gnome-text-editor "${list}"
elif which gedit &>/dev/null; then
    sudo gedit "${list}"
elif which nano &>/dev/null; then
    sudo nano "${list}"
elif which vim &>/dev/null; then
    sudo vim "${list}"
elif which vi &>/dev/null; then
    sudo vi "${list}"
else
    fail_fn 'Could not find an EDITOR to open the updated sources.list'
fi
