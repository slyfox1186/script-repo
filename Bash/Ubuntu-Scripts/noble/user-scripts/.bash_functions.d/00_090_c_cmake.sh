#!/usr/bin/env bash

## CMAKE commands
c_cmake() {
    local dir
    if ! sudo dpkg -l | grep -q cmake-curses-gui; then
        sudo apt -y install cmake-curses-gui
    fi
    echo

    if [[ -z "$1" ]]; then
        read -r -p "Enter the relative source directory: " dir
    else
        dir=$1
    fi

    cmake "$dir" -B build -G Ninja -Wno-dev
    ccmake "$dir"
}
