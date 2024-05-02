#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this as root or with sudo."
    exit
fi

# Update arch
pacman -Syu

# Install required packages
pacman -S --needed --noconfirm base-devel git

# Git clone the yay AUR repository
git clone https://aur.archlinux.org/yay.git
cd yay || exit 1

# edit the mirrorlist file permissions or the makepkg command will fail
chmod 644 /etc/pacman.d/mirrorlist
chown jman:root /etc/pacman.d/mirrorlist

# Install yay
makepkg -sif
