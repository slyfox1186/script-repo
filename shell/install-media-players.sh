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
read -p 'Your choices are (1 to 5): ' ANSWER
clear

if [[ "${ANSWER}" -eq '1' ]]; then
    echo 'Installing VLC Media Player'
    echo
    if ! which snap &> /dev/null; then
        echo 'Snap package installer is required to install VLC.'
        echo
        echo 'Do you want to do that now?'
        echo
        echo '[1] Yes'
        echo '[2] Exit'
        echo
        read -p 'Your choices are (1 or 2): ' VLC_ANSWER
        clear
        if [[ "${VLC_ANSWER}" -eq '1' ]]; then
            sudo apt update
            sudo apt -y install snapd
        else
            echo
            exit 0
        fi
        sudo snap install vlc
        if ! which vlc &> /dev/null; then
            fail_fn 'VLC Media Player'
        fi
elif [[ "${ANSWER}" -eq '2' ]]; then
    echo 'Installing Kodi Media Player'
    echo
    sudo apt install software-properties-common
    sudo add-apt-repository -y ppa:team-xbmc/ppa
    sudo apt -y install kodi
    if [ ! -d '/usr/share/kodi' ]; then
        fail_fn 'Kodi Media Player'
    fi
elif [[ "${ANSWER}" -eq '3' ]]; then
    echo 'Installing SMPlayer'
    echo
    sudo apt -y install smplayer
    if ! which smplayer &> /dev/null; then
        fail_fn 'SMPlayer'
    fi
elif [[ "${ANSWER}" -eq '4' ]]; then
    echo 'Installing SMPlayer'
    echo
    sudo apt -y install totem
    if ! which totem &> /dev/null; then
        fail_fn 'GNOME Videos (Totem)'
    fi
elif [[ "${ANSWER}" -eq '5' ]]; then
    echo 'Installing Bomi'
    echo
    sudo add-apt-repository ppa:nemonein/bomi
    sudo apt update
    sudo apt -y install bomi
    if ! which bomi &> /dev/null; then
        fail_fn 'Bomi'
    fi
elif [[ "${ANSWER}" -eq '6' ]]; then
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
sudo rm "${0}"
exit 0
