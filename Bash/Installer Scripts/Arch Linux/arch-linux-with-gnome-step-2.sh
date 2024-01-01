#!/usr/bin/env bash

clear

set -e

####################################
## AFTER YOU LOAD INTO ARCH LINUX ##
####################################

# INSTALL REQUIRED SOFTWARE USING PACMAN
pacman -Sy gnome lightdm lightdm-gtk-greeter nano gnome-terminal gnome-text-editor gedit gedit-plugins nvidia pulseaudio pulseaudio-alsa sudo xorg xorg-xinit xorg-server

# SET VISUDO ENV VAR
EDITOR=nano visudo

# LOGIN TO GNOME DESKTOP
systemctl enable gdm.service

printf "\n%s\n\n" 'The script has finished. Please reboot.'
