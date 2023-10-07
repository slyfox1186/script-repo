#!/usr/bin/env bash

clear

list=/etc/apt/sources.list

# make a backup of the file
if [ ! -f "$list".bak ]; then
    sudo cp -f "$list" "$list".bak
fi

cat > "$list" <<EOF
##################################################################
##
##  DEBIAN BULLSEYE MIRRORS
##
##  /etc/apt/sources.list
##
##  ALL MIRRORS IN EACH CATEGORY ARE LISTED AS BEING IN THE USA.
##
##################################################################
##
## DEFAULT
##
# deb http://deb.debian.org/debian bullseye main contrib non-free
# deb http://deb.debian.org/debian bullseye-updates main contrib non-free
# deb http://deb.debian.org/debian bullseye-backports main contrib non-free
deb http://security.debian.org/debian-security bullseye-security main contrib non-free
##
## MAIN
##
deb http://mirror.cogentco.com/debian/ bullseye main contrib non-free
deb http://atl.mirrors.clouvider.net/debian/ bullseye main contrib non-free
deb http://mirrors.wikimedia.org/debian/ bullseye main contrib non-free
##
## UPDATES
##
deb http://mirror.cogentco.com/debian/ bullseye-updates main contrib non-free
deb http://atl.mirrors.clouvider.net/debian/ bullseye-updates main contrib non-free
deb http://mirrors.wikimedia.org/debian/ bullseye-updates main contrib non-free
##
## BACKPORTS
##
deb http://mirror.cogentco.com/debian/ bullseye-backports main contrib non-free
deb http://atl.mirrors.clouvider.net/debian/ bullseye-backports main contrib non-free
deb http://mirrors.wikimedia.org/debian/ bullseye-backports main contrib non-free
EOF

# OPEN AN EDITOR TO VIEW THE CHANGES
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
    printf "\n%s\n\n" "Could not find an EDITOR to open: $list"
    exit 1
fi

sudo rm "$0"
