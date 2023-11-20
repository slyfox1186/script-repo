#!/usr/bin/env bash

clear

list='/etc/apt/sources.list'

# make a backup of the file
if [ ! -f "$list.bak" ]; then
    sudo cp -f "$list" "$list.bak"
fi

sudo cat > "$list" <<EOF
deb http://security.ubuntu.com/ubuntu/ lunar-security main restricted universe multiverse
deb https://mirror.enzu.com/ubuntu/ lunar-security main restricted universe multiverse
deb https://mirror.enzu.com/ubuntu/ lunar main restricted universe multiverse
deb https://mirror.enzu.com/ubuntu/ lunar-updates main restricted universe multiverse
deb https://mirror.enzu.com/ubuntu/ lunar-backports main restricted universe multiverse
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
    printf "\n%s\n\n" \
        "Could not find an EDITOR to open: $list"
    exit 1
fi

sudo rm "$0"
