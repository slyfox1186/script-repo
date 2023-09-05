#!/usr/bin/env bash

clear

if [ "$EUID" -ne '0' ]; then
    printf "%s\n\n" 'You must run this script with root/sudo.'
    exit 1
fi

printf "%s\n\n" "Installing fonts in /usr/local/share/fonts/adobe-fonts"

cd /usr/local/share/fonts || exit 1

if [ -d adobe-fonts ]; then
    sudo rm -fr adobe-fonts
fi
sudo mkdir adobe-fonts

git clone --depth 1 https://github.com/adobe-fonts/source-code-pro.git adobe-fonts

fc-cache -f -v adobe-fonts

printf "\n%s\n\n" 'Font installation completed.'
