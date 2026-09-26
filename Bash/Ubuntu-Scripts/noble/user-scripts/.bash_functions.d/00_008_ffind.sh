#!/usr/bin/env bash

## FIND COMMANDS ##
ffind() {
    local fname="${1-}" ftype="${2-}" fpath="${3-}"
    local -a find_args

    # Check if any argument is passed
    if [[ "$#" -eq 0 ]]; then
        read -r -p "Enter the name to search for: " fname
        read -r -p "Enter a type of FILE (d|f|blank for any): " ftype
        read -r -p "Enter the starting path (blank for current directory): " fpath
    fi

    # Default to the current directory if fpath is empty
    fpath=${fpath:-.}

    find_args=("$fpath" -iname "$fname")
    if [[ -n "$ftype" ]]; then
        case "$ftype" in
            d|f) find_args+=(-type "$ftype") ;;
            *)
            echo "Invalid FILE type. Please use \"d\" for directories or \"f\" for files."
            return 1
            ;;
        esac
    fi

    command find "${find_args[@]}"
}
