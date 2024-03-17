#!/Usr/bin/env bash

clear

set -e

####################################
## After you load into arch linux ##
####################################

# Install required software using pacman
pacman -Sy gnome lightdm lightdm-gtk-greeter nano gnome-terminal gnome-text-editor gedit gedit-plugins git nvidia pulseaudio pulseaudio-alsa sudo xorg xorg-xinit xorg-server

# Set visudo env var
EDITOR=nano visudo

# Login to gnome desktop
systemctl enable gdm.service

printf "\n%s\n\n" 'The script has finished. Please reboot.'
