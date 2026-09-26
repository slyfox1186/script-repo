#!/usr/bin/env bash

# COPY A FILE"S FULL PATH
# USAGE: cp <file name here>

cfp() {
    local pipe
    if [[ -z "$*" ]]; then
        clear
        echo "The command syntax is shown below"
        echo "cfp INPUT"
        echo "Example: cfp $PWD"
        echo
        return 1
    else
        pipe="$*"
    fi

    readlink -fn "$pipe" | xclip -i -selection clipboard
    clear
}
