#!/usr/bin/env bash

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this without root or sudo."
    exit
fi

# Update arch
sudo pacman -Syu

# Install required packages
sudo pacman -S --needed --noconfirm base-devel git

# Make temporary diretory to place the build files
dir=$(mktemp -d)

# Git clone the yay AUR repository
git clone "https://aur.archlinux.org/yay.git" "$dir/yay"
cd "$dir/yay" || exit 1

# edit the mirrorlist file permissions or the makepkg command will fail
sudo chmod 644 /etc/pacman.d/mirrorlist
sudo chown jman:root /etc/pacman.d/mirrorlist

# Install yay
makepkg -Csif

# Cleanup build files
sudo rm -fr "$dir"
