#!/usr/bin/env bash

list() {
    local param
    if [[ -z "$1" ]]; then
        read -r -p "Enter the string to search: " param
    else
        param="$1"
    fi
    clear
    sudo apt list -- "*$param*" 2>/dev/null | awk -F'/' '{print $1}' | grep -Eiv '\-dev|Listing' | sort -fuV
}
