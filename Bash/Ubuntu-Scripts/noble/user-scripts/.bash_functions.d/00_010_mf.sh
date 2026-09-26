#!/usr/bin/env bash

## CREATE FILES ##
mf() {
    local file

    if [[ -z "$1" ]]; then
        read -r -p "Enter filename: " file
        [[ ! -f "$file" ]] && touch "$file"
        chmod 744 "$file"
    else
        [[ ! -f "$1" ]] && touch "$1"
        chmod 744 "$1"
    fi

    clear; ls -1AhFv --color --group-directories-first
}
