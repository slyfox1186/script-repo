#!/usr/bin/env bash

big_vids() {
    local count
    if [[ -n "$1" ]]; then
        count=$1
    else
        read -r -p "Enter the max number of results: " count
        echo
    fi
    echo "Listing the $count largest videos"
    echo
    sudo find "$PWD" -type f \( -iname "*.mkv" -o -iname "*.mp4" \) -exec du -Sh {} + | grep -Ev "\(x265\)" | sort -hr | head -n"$count"
}
