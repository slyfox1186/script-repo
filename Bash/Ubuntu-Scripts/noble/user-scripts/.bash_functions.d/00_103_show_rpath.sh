#!/usr/bin/env bash

######################################
## SHOW BINARY RUNPATH IF IT EXISTS ##
######################################

show_rpath() {
    local binary find_rpath
    clear

    if [[ -z "$1" ]]; then
        read -r -p "Enter the full path to the binary/program: " find_rpath
    else
        find_rpath="$1"
    fi

    clear
    if ! binary=$(command -v -- "$find_rpath"); then
        printf 'Command not found: %s\n' "$find_rpath" >&2
        return 1
    fi
    sudo chrpath -l "$binary"
}
