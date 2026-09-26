#!/usr/bin/env bash

rmd() {
    local path resolved_path
    local -a dirs

    if (($# == 0)); then
        clear
        ls -1AvhF --color --group-directories-first
        echo
        read -r -a dirs -p "Enter the directory path(s) to delete: "
    else
        dirs=("$@")
    fi

    ((${#dirs[@]} > 0)) || return 1
    for path in "${dirs[@]}"; do
        [[ -n "$path" ]] || {
            printf 'Refusing an empty directory target.\n' >&2
            return 1
        }
        resolved_path=$(realpath -m -- "$path") || return 1
        case "$resolved_path" in
            /|"$HOME")
                printf 'Refusing unsafe directory target: %q\n' "$path" >&2
                return 1
                ;;
        esac
    done

    sudo rm -rf -- "${dirs[@]}"
    echo
    ls -1AvhF --color --group-directories-first
}
