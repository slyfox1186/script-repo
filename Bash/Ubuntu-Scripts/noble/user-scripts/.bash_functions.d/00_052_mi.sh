#!/usr/bin/env bash

## MediaInfo
mi() {
    local file

    if [[ -z "$1" ]]; then
        ls -1AhFv --color --group-directories-first
        echo
        read -r -p "Please enter the relative FILE path: " file
        echo
        mediainfo "$file"
    else
        mediainfo "$1"
    fi
}
