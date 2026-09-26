#!/usr/bin/env bash

dL() {
    local input="$1"

    if [[ -z "$input" ]]; then
        read -r -p "Enter the string to search: " input
    fi

    echo "Searching installed packages for: $input"
    dpkg -L "$input"
}
