#!/usr/bin/env bash

## UNINSTALL DEBIAN FILES ##
rm_deb() {
    local fname

    if [[ -n "$1" ]]; then
        sudo dpkg -r "$(dpkg -f "$1" Package)"
    else
        read -r -p "Please enter the Debian FILE name: " fname
        clear
        sudo dpkg -r "$(dpkg -f "$fname" Package)"
    fi
}
