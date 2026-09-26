#!/usr/bin/env bash

# COPY THE CONTENT OF A FILE
# USAGE: cf <file name here>

cfc() {
    local file
    clear

    if [[ -z "$1" ]]; then
        clear
        echo "The command syntax is shown below"
        echo "cfc INPUT"
        echo "Example: cfc $PWD"
        echo
        return 1
    else
        xclip -i -rmlastnl -select clipboard < "$1"
    fi
}
