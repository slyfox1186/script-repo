#!/usr/bin/env bash

## KILLALL COMMANDS ##
tkapt() {
    local program
    local list=(apt apt-get aptitude dpkg)
    for program in "${list[@]}"; do
        sudo killall -9 "$program" 2>/dev/null
    done
}
