#!/usr/bin/env bash

set -e

####################################
## After YOU LOAD INTO ARCH LINUX ##
####################################

#IMPORTANT - Login as the root user before running this script

# Install required software using pacman
pacman -Sy gnome lightdm lightdm-gtk-greeter nano gnome-terminal gnome-text-editor gedit gedit-plugins git nvidia pulseaudio pulseaudio-alsa sudo xorg xorg-xinit xorg-server

# Set visudo env var
EDITOR=nano visudo

# Enable the gnome desktop
systemctl enable gdm.service
# Enable and start the networkmanager
systemctl enable NetworkManager
systemctl start NetworkManager

echo
echo "The script has finished. Please reboot."
echo
