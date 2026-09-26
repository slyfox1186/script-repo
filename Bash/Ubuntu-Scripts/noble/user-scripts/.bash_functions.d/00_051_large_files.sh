#!/usr/bin/env bash

## List large files by type
large_files() {
    local choice
    clear

    if [[ -z "$1" ]]; then
        echo "Input the FILE extension to search for without a dot: "
        read -r -p "Enter your choice: " choice
        clear
    else
        choice=$1
    fi

    sudo find "$PWD" -type f -name "*.$choice" -printf "%s %h\n" | sort -ru -o "large-files.txt"

    if [[ -f "large-files.txt" ]]; then
        sudo gnome-text-editor "large-files.txt"
        sudo rm "large-files.txt"
    fi
}
