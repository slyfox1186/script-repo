#!/Usr/bin/env bash

clear

set -e


pacman -Sy gnome lightdm lightdm-gtk-greeter nano gnome-terminal gnome-text-editor gedit gedit-plugins git nvidia pulseaudio pulseaudio-alsa sudo xorg xorg-xinit xorg-server

EDITOR=nano visudo

systemctl enable gdm.service

printf "\n%s\n\n" 'The script has finished. Please reboot.'
