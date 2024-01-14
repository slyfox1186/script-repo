#!/usr/bin/env bash

clear

fname='/etc/pacman.conf'

# make a backup of the file
if [ ! -f "$fname".bak ]; then
    cp -f "$fname" "$fname".bak
fi

cat > "$fname" <<EOF
[core]
SigLevel = Required
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://arch.mirror.constant.com/$repo/os/$arch
Include = /etc/pacman.d/mirrorlist

[other]
SigLevel = Required
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://arch.mirror.constant.com/$repo/os/$arch
Include = /etc/pacman.d/mirrorlist

[extra]
SigLevel = Required
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://arch.mirror.constant.com/$repo/os/$arch
Include = /etc/pacman.d/mirrorlist

[multilib]
SigLevel = Required
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://arch.mirror.constant.com/$repo/os/$arch
Include = /etc/pacman.d/mirrorlist
EOF

# OPEN AN EDITOR TO VIEW THE CHANGES
if type -P gnome-text-editor &>/dev/null; then
    sudo gnome-text-editor "$fname"
elif type -P gedit &>/dev/null; then
    sudo gedit "$fname"
elif type -P nano &>/dev/null; then
    sudo nano "$fname"
elif type -P vim &>/dev/null; then
    sudo vim "$fname"
elif type -P vi &>/dev/null; then
    sudo vi "$fname"
else
    printf "\n%s\n\n" "Could not find an EDITOR to open \"$fname\""
    exit 1
fi

if [[ "${0}" == 'archlinux-mirrors' ]]; then
    sudo rm 'archlinux-mirrors'
fi
