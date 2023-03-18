#!/bin/bash

############################
##
## Install Media Players
##
## 1. VLC
## 2. Kodi
## 3. SMPlayer
## 4. GNOME Videos (Totem)
## 5. Bomi
##
############################

clear

##
## Functions
##

fail_fn()
{
    clear
    echo "${1} was not installed."
    echo
    echo 'Please put in a support ticket.'
    echo
    sudo rm "${0}"
    exit 1
}

echo 'Please choose a media player to install'
echo
echo '[1] VLC'
echo '[2] Kodi'
echo '[3] SMPlayer'
echo '[4] GNOME Videos (Totem)'
echo '[5] Bomi'
echo '[6] Exit'
echo
read -p 'Your choices are (1 to 5): ' answer
clear

if [[ "${answer}" -eq '1' ]]; then
    echo 'Installing VLC Media Player'
    echo
    sudo snap install vlc
elif [[ "${answer}" -eq '2' ]]; then
    echo 'Installing Kodi Media Player'
    echo
    sudo apt -y install software-properties-common
    sudo add-apt-repository -y ppa:team-xbmc/ppa
    sudo apt -y install kodi
elif [[ "${answer}" -eq '3' ]]; then
    echo 'Installing SMPlayer'
    echo
    sudo apt -y install smplayer
elif [[ "${answer}" -eq '4' ]]; then
    echo 'Installing SMPlayer'
    echo
    sudo apt -y install totem
elif [[ "${answer}" -eq '5' ]]; then
    echo 'Installing Bomi'
    echo
    sudo add-apt-repository ppa:nemonein/bomi
    sudo apt update
    sudo apt -y install bomi
elif [[ "${answer}" -eq '6' ]]; then
    echo
    exit 0
else
    echo 'Bad user input: Run the script again.'
    echo
    exit 1
fi

echo
echo 'Installation completed.'
echo
exit 0
