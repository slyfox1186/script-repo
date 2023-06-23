#!/bin/bash

clear

list='/etc/apt/sources.list'

# make a backup of the file
if [ ! -f "$list.bak" ]; then
    sudo cp -f "$list" "$list.bak"
fi

sudo cat > "$list" <<EOF
#######################################################
##
##  DEBIAN BULLSEYE
##
##  /etc/apt/sources.list
##
##  ALL MIRRORS IN EACH CATAGORY ARE LISTED AS BEING
##  IN THE USA. IF YOU USE ALL THE LISTS YOU CAN RUN
##  INTO APT COMMAND ISSUES THAT STATE THERE ARE TOO
##  MANY FILES. JUST AN FYI FOR YOU.
##
#######################################################
##
## DEFAULT
##
deb http://deb.debian.org/debian bullseye main contrib non-free
deb http://deb.debian.org/debian bullseye-updates main contrib non-free
deb http://deb.debian.org/debian bullseye-backports main contrib non-free
deb http://security.debian.org/debian-security bullseye-security main contrib non-free
##
## MAIN
##
deb http://atl.mirrors.clouvider.net/debian bullseye main contrib non-free
deb http://debian.mirror.constant.com/debian bullseye main contrib non-free
deb http://debian.osuosl.org/debian bullseye main contrib non-free
deb http://ftp.us.debian.org/debian bullseye main contrib non-free
deb http://mirror.cogentco.com/debian bullseye main contrib non-free
deb http://mirror.steadfast.net/debian bullseye main contrib non-free
deb http://mirror.us.leaseweb.net/debian bullseye main contrib non-free
deb http://mirrors.wikimedia.org/debian bullseye main contrib non-free
deb http://nyc.mirrors.clouvider.net/debian bullseye main contrib non-free
##
## UPDATES
##
deb http://atl.mirrors.clouvider.net/debian bullseye-updates main contrib non-free
deb http://debian.mirror.constant.com/debian bullseye-updates main contrib non-free
deb http://debian.osuosl.org/debian bullseye-updates main contrib non-free
deb http://ftp.us.debian.org/debian bullseye-updates main contrib non-free
deb http://mirror.cogentco.com/debian bullseye-updates main contrib non-free
deb http://mirror.steadfast.net/debian bullseye-updates main contrib non-free
deb http://mirror.us.leaseweb.net/debian bullseye-updates main contrib non-free
deb http://mirrors.wikimedia.org/debian bullseye-updates main contrib non-free
deb http://nyc.mirrors.clouvider.net/debian bullseye-updates main contrib non-free
##
## BACKPORTS
##
deb http://atl.mirrors.clouvider.net/debian bullseye-backports main contrib non-free
deb http://debian.mirror.constant.com/debian bullseye-backports main contrib non-free
deb http://debian.osuosl.org/debian bullseye-backports main contrib non-free
deb http://ftp.us.debian.org/debian bullseye-backports main contrib non-free
deb http://mirror.cogentco.com/debian bullseye-backports main contrib non-free
deb http://mirror.steadfast.net/debian bullseye-backports main contrib non-free
deb http://mirror.us.leaseweb.net/debian bullseye-backports main contrib non-free
deb http://mirrors.wikimedia.org/debian bullseye-backports main contrib non-free
deb http://nyc.mirrors.clouvider.net/debian bullseye-backports main contrib non-free
EOF

# OPEN AN EDITOR TO VIEW THE CHANGES
if which 'gedit' &>/dev/null; then
    sudo gedit "$list"
elif which 'nano' &>/dev/null; then
    sudo nano "$list"
elif which 'vi' &>/dev/null; then
    sudo vi "$list"
else
    printf "\n%s\n\n" \
        "Could not find an EDITOR to open: $list"
    exit 1
fi

sudo rm "$0"
