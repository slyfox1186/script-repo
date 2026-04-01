#!/usr/bin/env bash

list() {
    local param
    if [[ -z "$1" ]]; then
        read -p "Enter the string to search: " param
    else
        param="$1"
    fi
    clear
    pacman -Ss "$param" 2>/dev/null | grep -v '^\s' | awk '{print $1}' | sort -fuV
}

listd() {
    local param
    if [[ -z "$1" ]]; then
        read -p "Enter the string to search: " param
    else
        param="$1"
    fi
    clear
    pacman -Ss "${param}-dev\|${param}-devel" 2>/dev/null | grep -v '^\s' | awk '{print $1}' | sort -fuV
}
