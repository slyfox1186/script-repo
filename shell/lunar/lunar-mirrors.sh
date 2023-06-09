#!/bin/bash

clear

list='/etc/apt/sources.list'

# make a backup of the file
if [ ! -f "$list.bak" ]; then
    sudo cp -f "$list" "$list.bak"
fi

sudo cat > "$list" <<EOF
###################################################
##
##  UBUNTU LUNAR
##
##  v23.04
##
##  /etc/apt/sources.list
##
##  ALL MIRRORS IN EACH CATAGORY ARE LISTED AS BEING
##  IN THE USA. IF YOU USE ALL THE LISTS YOU CAN RUN
##  INTO APT COMMAND ISSUES THAT STATE THERE ARE TOO
##  MANY FILES. JUST AN FYI FOR YOU.
##
###################################################
##                Default Mirrors                ##
##     Disabled due to slow download speeds      ##
##  The security updates have been left enabled  ##
###################################################
##
# deb http://archive.ubuntu.com/ubuntu/ lunar main restricted universe multiverse
# deb http://archive.ubuntu.com/ubuntu/ lunar-updates main restricted universe multiverse
# deb http://archive.ubuntu.com/ubuntu/ lunar-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ lunar-security main restricted universe multiverse
##
####################################################
##                                                ##
##                  20Gb Mirrors                  ##
##                                                ##
####################################################
##
## MAIN
##
deb https://mirror.enzu.com/ubuntu/ lunar main restricted universe multiverse
deb http://mirror.genesisadaptive.com/ubuntu/ lunar main restricted universe multiverse
deb http://mirror.math.princeton.edu/pub/ubuntu/ lunar main restricted universe multiverse
deb http://mirror.pit.teraswitch.com/ubuntu/ lunar main restricted universe multiverse
##
## UPDATES
##
deb https://mirror.enzu.com/ubuntu/ lunar-updates main restricted universe multiverse
deb http://mirror.genesisadaptive.com/ubuntu/ lunar-updates main restricted universe multiverse
deb http://mirror.math.princeton.edu/pub/ubuntu/ lunar-updates main restricted universe multiverse
deb http://mirror.pit.teraswitch.com/ubuntu/ lunar-updates main restricted universe multiverse
##
## BACKPORTS
##
deb https://mirror.enzu.com/ubuntu/ lunar-backports main restricted universe multiverse
deb http://mirror.genesisadaptive.com/ubuntu/ lunar-backports main restricted universe multiverse
deb http://mirror.math.princeton.edu/pub/ubuntu/ lunar-backports main restricted universe multiverse
deb http://mirror.pit.teraswitch.com/ubuntu/ lunar-backports main restricted universe multiverse
EOF

# OPEN AN EDITOR TO VIEW THE CHANGES
if which 'gnome-text-editor' &>/dev/null; then
    sudo gnome-text-editor "$list"
elif which 'gedit' &>/dev/null; then
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
