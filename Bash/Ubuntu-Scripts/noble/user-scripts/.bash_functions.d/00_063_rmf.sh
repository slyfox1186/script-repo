#!/usr/bin/env bash


rmf() {
    local -a files

    if (($# == 0)); then
        clear
        ls -1AvhF --color --group-directories-first
        echo
        read -r -a files -p "Enter the file path(s) to delete: "
    else
        files=("$@")
    fi

    ((${#files[@]} > 0)) || return 1
    sudo rm -- "${files[@]}"
    echo
    ls -1AvhF --color --group-directories-first
}
