#!/bin/bash

# GitHub: https://github.com/slyfox1186/script-repo/new/main/shell

# SIMPLE SCRIPT TO FIX GEDIT BUGS THAT DONT ALLOW YOU
# TO MAKE CHANGES TO PREFERENCES WHEN RUNNING GEDIT WITH THE SUDO COMMAND

sudo apt update

sudo apt -y install \
    dbus-x11 \
    gir1.2-gtksource-3.0

echo

echo 'All you have to do is close and restart gedit with sudo and the changes should take effect.'
echo
read -p 'Press enter to exit.'
