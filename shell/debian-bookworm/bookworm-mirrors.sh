#!/bin/bash

clear

list='/etc/apt/sources.list'

# make a backup of the file
if [ ! -f "$list.bak" ]; then
    sudo cp -f "$list" "$list.bak"
fi

cat > "$list" <<'EOF'
#######################################################
##
##  DEBIAN BOOKWORM
##
##  /etc/apt/sources.list
##
##  ALL MIRRORS IN EACH CATAGORY ARE LISTED AS BEING
##  IN THE USA. IF YOU USE ALL THE LISTS YOU CAN RUN
##  INTO APT COMMAND ISSUES THAT STATE THERE ARE TOO
##  MANY FILES.
##
#######################################################
##
## DEBIAN DEFAULT (DISABLED DUE TO HOW SLOW THESE ARE COMPRED TO THE 3RD PARTY MIRRORS)
##
# deb http://deb.debian.org/debian/ bookworm main contrib non-free-firmware non-free
# deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free-firmware non-free
# deb http://ftp.debian.org/debian/ bookworm-backports main contrib non-free-firmware non-free
##
## DEBIAN SECURITY
##
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware non-free
##
## DEBIAN MAIN
##
deb http://atl.mirrors.clouvider.net/debian/ bookworm main contrib non-free-firmware non-free
deb https://nyc.mirrors.clouvider.net/debian/ bookworm main contrib non-free-firmware non-free
deb https://mirrors.wikimedia.org/debian/ bookworm main contrib non-free-firmware non-free
deb https://debian.osuosl.org/debian/ bookworm main contrib non-free-firmware non-free
deb http://mirror.us.leaseweb.net/debian/ bookworm main contrib non-free-firmware non-free
##
## DEBIAN UPDATES
##
deb http://atl.mirrors.clouvider.net/debian/ bookworm-updates main contrib non-free-firmware non-free
deb https://nyc.mirrors.clouvider.net/debian/ bookworm-updates main contrib non-free-firmware non-free
deb https://mirrors.wikimedia.org/debian/ bookworm-updates main contrib non-free-firmware non-free
deb https://debian.osuosl.org/debian/ bookworm-updates main contrib non-free-firmware non-free
deb http://mirror.us.leaseweb.net/debian/ bookworm-updates main contrib non-free-firmware non-free
##
## DEBIAN BACKPORTS
##
deb http://atl.mirrors.clouvider.net/debian/ bookworm-backports main contrib non-free-firmware non-free
deb https://nyc.mirrors.clouvider.net/debian/ bookworm-backports main contrib non-free-firmware non-free
deb https://mirrors.wikimedia.org/debian/ bookworm-backports main contrib non-free-firmware non-free
deb https://debian.osuosl.org/debian/ bookworm-backports main contrib non-free-firmware non-free
deb http://mirror.us.leaseweb.net/debian/ bookworm-backports main contrib non-free-firmware non-free
EOF

# Open the sources.list file for review
if which gnome-text-editor &>/dev/null; then
    sudo gnome-text-editor "$list"
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
