#!/usr/bin/env bash

# Use dpkg to search for all apt packages by passing a name to the function
function dl() {
    local input="$1"

    if [[ -z "$input" ]]; then
        read -r -p "Enter the string to search: " input
    fi

    echo "Searching installed packages for: $input"
    dpkg -l | grep "$input"
}
