#!/usr/bin/env bash

# Fix missing gpnu keys used to update packages
fix_key() {
    local file url

    if [[ -z "$1" ]] && [[ -z "$2" ]]; then
        read -r -p "Enter the filename to store in /etc/apt/trusted.gpg.d: " file
        read -r -p "Enter the gpg key url: " url
        clear
    else
        file="$1"
        url="$2"
    fi

    if curl -fsS# "$url" | gpg --dearmor | sudo tee "/etc/apt/trusted.gpg.d/$file"; then
        echo "The key was successfully added!"
    else
        echo "The key failed to add!"
    fi
}
