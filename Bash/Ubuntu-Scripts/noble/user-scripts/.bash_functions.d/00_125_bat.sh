#!/usr/bin/env bash

# BATCAT COMMANDS

bat() {
    local executable

    if executable=$(type -P batcat); then
        "$executable" "$@"
    elif executable=$(type -P bat); then
        "$executable" "$@"
    else
        echo "Installing batcat now."
        sudo apt update && sudo apt -y install bat
    fi
}
