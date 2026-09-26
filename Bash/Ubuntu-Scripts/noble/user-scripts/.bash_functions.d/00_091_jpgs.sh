#!/usr/bin/env bash

##########################
## SORT IMAGES BY WIDTH ##
##########################

jpgs() {
    local output_file
    output_file=$(mktemp) || return 1
    find . -type f -iname '*.jpg' -exec identify -format " $PWD/%f: %wx%h " {} \; > "$output_file"
    sed 's/\s\//\n\//g' "$output_file" | sort -h
    rm -f -- "$output_file"
}
