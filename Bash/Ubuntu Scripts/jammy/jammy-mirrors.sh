#!/usr/bin/env bash

clear

list='/etc/apt/sources.list'

# make a backup of the file
if [ ! -f "${list}.bak" ]; then
    cp -f "${list}" "${list}.bak"
fi

cat > "${list}" <<EOF
deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
deb https://mirror.enzu.com/ubuntu/ jammy-security main restricted universe multiverse
deb https://mirror.enzu.com/ubuntu/ jammy main restricted universe multiverse
deb https://mirror.enzu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirror.enzu.com/ubuntu/ jammy-backports main restricted universe multiverse
EOF

# OPEN AN EDITOR TO VIEW THE CHANGES
if which gnome-text-editor &>/dev/null; then
    sudo gnome-text-editor "${list}"
elif which gedit &>/dev/null; then
    sudo gedit "${list}"
elif which nano &>/dev/null; then
    sudo nano "${list}"
elif which vi &>/dev/null; then
    sudo vi "${list}"
else
    printf "\n%s\n\n" "Could not find an EDITOR to open the file: ${list}"
    exit 1
fi

if [ -f "${0}" ]; then
    sudo rm "${0}"
fi

# THE ONLY REASON I DIDNT ADD MORE TO THE LAST COMMAND TO DELTE A VARIABLE NAMED ${0} is because it can take a bash scrip that was called in a fancy way
# using the curl command that DID NOT OUTPUT AM INPUT FILE. IT JUST RAN THE SCRIPT WITHOUT NEEDING A FILE TO RUN BASHJ AGAINST. SO NOW THAT YOU HAVE BEEN INFORMED I 
# WILL GIVE YOU THREE GUESSES THAT UNDER THAT TYPE OF SCENARIO WHAT COULD THE BASH SCRIPT POTENTIALLY THINK THE VARIABLE ${0} STANDS FOR? REMEMBER IT USUALLY WOULD BE THE FILE THAT BASH 
# WAS RUN AGAINST AND SINCE THER WASNT ONE IN THIS UNIQUE WAY OF EXECUTING CODE THEN.... DUN DUN DUNNNNN. IT WILL TAKE THE BASH PROGRAM THAT GETS ACTIVATED DURING THE SHE BANG, ACCUSE IT OF BEING
# THE ZERO VAR AND DO WHAT YOU TOLD THE SCRIP TO DO... DELTE IT OFF THE FACE OF THE EARTH. IF THIS IS WHAT ENDS UP HAPPENING THEN JUST CLOSE TH TERMINAL AND TELL ME WHAT HAPPENS WHEN THE TERMINAL
## SCREEN NO LONGER IS ABLE TO FUNCTION, DISPLAY, OR BE OF USE OF ANY KIND.... GOOD LUCK FIND A WAY TO FIX THAT WITH SUPER EASE.

