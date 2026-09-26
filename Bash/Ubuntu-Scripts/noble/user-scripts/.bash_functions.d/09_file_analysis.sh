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
  local num_results full_path size folder file suffix
  # Check if an argument is provided
  if [ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    num_results=$1
  else
    # Prompt the user to enter the number of results
    read -r -p "Enter the number of results to display: " num_results
    while ! [[ "$num_results" =~ ^[0-9]+$ ]]; do
      read -r -p "Invalid input. Enter a valid number: " num_results
    done
  fi
  echo "Largest Folders:"
  du -h -d 1 2>/dev/null | sort -hr | head -n "$num_results" | while read -r size folder; do
    full_path=$(realpath "$folder")
    suffix="${size: -1}"
    size=$(echo "${size%?}" | awk '{printf "%d.%02d", $1, int(($1-int($1))*100)}')
    printf "%-80s %14s%s\n" "$full_path" "$size" "$suffix"
  done | column -t
  echo
  echo "Largest Files:"
  find . -type f -exec du -h {} + 2>/dev/null | sort -hr | head -n "$num_results" | while read -r size file; do
    full_path=$(realpath "$file")
    suffix="${size: -1}"
    size=$(echo "${size%?}" | awk '{printf "%d.%02d", $1, int(($1-int($1))*100)}')
    printf "%-80s %14s%s\n" "$full_path" "$size" "$suffix"
  done | column -t
}

big_file() {
    local count="${1:-20}"

    [[ "$count" =~ ^[1-9][0-9]*$ ]] || {
        printf 'Usage: big_file [POSITIVE_COUNT]\n' >&2
        return 1
    }
    find . -type f -print0 | du -ha --files0-from=- | LC_ALL=C sort -rh | head -n "$count"
}

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

big_img() {
    clear
    sudo find . -size +10M -type f -name "*.jpg" 2>/dev/null
}

jpgsize() {
    local random_dir size

    random_dir=$(mktemp -d)
    read -r -p "Enter the image size (units in MB): " size
    find . -size +"$size"M -type f -iname "*.jpg" > "$random_dir/img-sizes.txt"
    sed -i "s/^..//g" "$random_dir/img-sizes.txt"
    sed -i "s|^|$PWD\/|g" "$random_dir/img-sizes.txt"
    echo
    nohup gnome-text-editor "$random_dir/img-sizes.txt" &>/dev/null &
}
