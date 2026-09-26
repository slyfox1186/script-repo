#!/usr/bin/env bash

mdir() {
    local dir

    if [[ -z "$1" ]]; then
        read -r -p "Enter directory name: " dir
        mkdir -p "$PWD/$dir"
        cd "$PWD/$dir" || exit 1
    else
        mkdir -p "$1"
        cd "$PWD/$1" || exit 1
    fi

    clear; ls -1AhFv --color --group-directories-first
}
