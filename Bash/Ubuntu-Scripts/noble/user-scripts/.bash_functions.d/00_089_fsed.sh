#!/usr/bin/env bash

## SED COMMANDS ##
fsed() {
    local otext rtext
    echo "This command is for sed to act only on files"
    echo

    if [[ -z "$1" ]]; then
        read -r -p "Enter the original text: " otext
        read -r -p "Enter the replacement text: " rtext
        echo
    else
        otext=$1
        rtext=$2
    fi

     sudo sed -i "s/${otext}/${rtext}/g" "$(find . -maxdepth 1 -type f)"
}
