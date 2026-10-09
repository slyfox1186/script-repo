#!/usr/bin/env bash

## 1. VLC
## 2. Kodi
## 3. SMPlayer
## 4. GNOME Videos (Totem)
## 5. Bomi
## 6. Exit

clear

# Functions

exit_fn()
{
    printf "\n%s\n\n%s\n\n" \
        'Please star this repository to show your support!' \
        'https://github.com/slyfox1186/script-repo'
    return 0
}

fail_fn()
{
    printf "\n%s\n\n%s\n\n%s\n\n" \
        "$1" \
        'If you think this is a bug please fill out a report.' \
        'https://github.com/slyfox1186/script-repo/issues'
    return 1
}

success_fn()
{
    clear
    echo "$1 was succesfully installed."
    exit_fn
}

printf "%s\n\n%s\n%s\n%s\n%s\n%s\n%s\n\n" \
    'Please choose a media player to install' \
    '[1] VLC' \
    '[2] Kodi' \
    '[3] SMPlayer' \
    '[4] GNOME Videos (Totem)' \
    '[5] Bomi' \
    '[6] Return'

read -p 'Your choices are (1 to 6): ' media_selection
clear

case "$media_selection" in 
    1)
        echo -e "Installing VLC Media Player\\n"
        if sudo snap install vlc; then
            success_fn 'VLC Media Player'
        else
            fail_fn 'VLC Media Player failed to install.'
        fi
        ;;
    2)
        echo -e "Installing Kodi Media Player\\n"
        sudo apt install software-properties-common 2>/dev/null
        sudo add-apt-repository -y ppa:team-xbmc/ppa 2>/dev/null
        if sudo apt install kodi; then
             success_fn 'Kodi Media Player'
        else
            fail_fn 'Kodi Media Player failed to install.'
        fi
        ;;
    3)
        echo -e "Installing SMPlayer\\n"
        if sudo apt install smplayer; then
             success_fn 'SMPlayer'
        else
            fail_fn 'SMPlayer failed to install.'
        fi
        ;;
    4)
        echo -e "GNOME Videos (Totem)\\n"
        if sudo apt install totem; then
             success_fn 'GNOME Videos (Totem)'
        else
            fail_fn 'GNOME Videos (Totem) failed to install.'
        fi
        ;;
    5)
        echo -e "Installing Bomi\\n"
        sudo add-apt-repository ppa:nemonein/bomi 2>/dev/null
        sudo apt update 2>/dev/null
        if sudo apt install bomi; then
             success_fn 'Bomi'
        else
            fail_fn 'Bomi failed to install.'
        fi
        ;;
    6)
        exit_fn
        ;;

    *)
        fail_fn 'Bad user input: Run the script again.'
        ;;
esac
