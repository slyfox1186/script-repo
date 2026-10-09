#!/usr/bin/env bash
# File Analysis Functions

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

## GET FILE SIZES ##

big_files() {
    local count="${1-}"
    if [[ -z "$count" ]]; then
        read -r -p 'Number of results: ' count || return 1
    fi
    [[ "$count" =~ ^[1-9][0-9]*$ ]] || {
        printf 'Usage: big_files [POSITIVE_COUNT]\n' >&2
        return 1
    }
    printf 'Largest Folders:\n'
    (
        set -o pipefail
        du -h --max-depth=1 --null . | LC_ALL=C sort -zrh | sed -z -n "1,${count}p" | tr '\0' '\n'
    ) || return
    printf '\nLargest Files:\n'
    big_file "$count"
}

big_file() (
    local count="${1:-20}"

    [[ "$count" =~ ^[1-9][0-9]*$ ]] || {
        printf 'Usage: big_file [POSITIVE_COUNT]\n' >&2
        return 1
    }
    set -o pipefail
    find . -type f -print0 | du -h --null --files0-from=- | LC_ALL=C sort -zrh | sed -z -n "1,${count}p" | tr '\0' '\n'
)

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

_jpg_files_over_size() {
    local size="$1"
    [[ "$size" =~ ^[0-9]+$ ]] || {
        printf 'Image size must be a nonnegative whole number of MiB.\n' >&2
        return 1
    }
    find "$PWD" -type f -iname '*.jpg' -size "+${size}M"
}

big_img() {
    _jpg_files_over_size "${1:-10}"
}

jpgsize() {
    local size="${1-}"
    if [[ -z "$size" ]]; then
        read -r -p 'Minimum image size (MiB): ' size || return 1
    fi
    _jpg_files_over_size "$size"
}
