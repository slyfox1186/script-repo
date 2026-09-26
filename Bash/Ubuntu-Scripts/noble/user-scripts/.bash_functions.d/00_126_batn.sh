#!/usr/bin/env bash

batn() {
    local executable

    if executable=$(type -P batcat); then
        "$executable" -n "$@"
    elif executable=$(type -P bat); then
        "$executable" -n "$@"
    else
        echo "Installing batcat now."
        sudo apt update && sudo apt -y install bat
    fi
}
