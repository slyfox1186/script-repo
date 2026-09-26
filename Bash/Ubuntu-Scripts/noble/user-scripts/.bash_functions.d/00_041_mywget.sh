#!/usr/bin/env bash

# WGET command
mywget() {
    local outfile url
    if [[ -z "$1" ]] || [[ -z "$2" ]]; then
        read -r -p "Please enter the output file name: " outfile
        read -r -p "Please enter the URL: " url
        echo
        wget --out-file="$outfile" "$url"
    else
        wget --out-file="$1" "$2"
    fi
}
