#!/usr/bin/env bash

###########################
## CHANGE HOSTNAME OF PC ##
###########################

chostname() {
    local name
    clear

    if [[ -z "$1" ]]; then
        read -r -p "Please enter the new hostname: " name
    else
        name="$1"
    fi

    sudo nmcli g hostname "$name"
    clear
    printf "%s\n\n" "The new hostname is listed below."
    hostname
}
