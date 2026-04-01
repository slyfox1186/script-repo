#!/usr/bin/env bash
# File Analysis Functions

## UNIFIED FILE SIZE FINDER ##
# A unified function to find large files or directories with flexible options.
# Replaces big_files, big_file, big_vids, big_img, jpgsize, large_files.
find_large() {
    local count=10
    local min_size=""
    local type_filter=""
    local search_mode="file" # 'file' or 'dir'

    # Simple and portable argument parsing
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -c|--count) count="$2"; shift ;;
            -s|--min-size) min_size="$2"; shift ;;
            -t|--type) type_filter="$2"; shift ;;
            --dir) search_mode="dir" ;;
            -h|--help)
                echo "Usage: find_large [options]"
                echo "Options:"
                echo "  -c, --count N        Show top N results (default: 10)."
                echo "  -s, --min-size SIZE  Filter by minimum size (e.g., 10M, 1G)."
                echo "  -t, --type EXT       Filter by file extension (e.g., jpg, mp4)."
                echo "  --dir                Search for directories instead of files."
                echo "  -h, --help           Show this help message."
                return 0
                ;;
            *) echo "Unknown parameter: $1" >&2; return 1 ;;
        esac
        shift
    done

    if [[ "$search_mode" == "dir" ]]; then
        echo "Searching for top ${count} largest directories..."
        # du is best for finding directory sizes. -d 1 limits to current level.
        du -h -d 1 . 2>/dev/null | sort -hr | head -n "${count}"
    else
        echo "Searching for files..."
        local find_cmd="find . -type f"
        [[ -n "$type_filter" ]] && find_cmd+=" -name '*.${type_filter}'"
        [[ -n "$min_size" ]] && find_cmd+=" -size +${min_size}"

        # -printf is efficient. We sort by size (%s) and then format output.
        eval "$find_cmd" -printf '%s %p\n' 2>/dev/null |
        sort -rn |
        head -n "${count}" |
        awk '{
            size=$1;
            path="";
            for(i=2; i<=NF; i++) { path=(path=="" ? "" : path " ") $i };
            # Human-readable size conversion
            split("B KB MB GB TB", units, " ");
            i=1;
            while (size > 1024 && i < 5) { size/=1024; i++; }
            printf "%.2f %s\t%s\n", size, units[i], path;
        }' | column -t
    fi
}

## DEPRECATED FILE SIZE FUNCTIONS ##
# The functions below are deprecated - use find_large instead
big_files() {
  local num_results full_path size folder file suffix
  # Check if an argument is provided
  if [ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    num_results=$1
  else
    # Prompt the user to enter the number of results
    read -p "Enter the number of results to display: " num_results
    while ! [[ "$num_results" =~ ^[0-9]+$ ]]; do
      read -p "Invalid input. Enter a valid number: " num_results
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
    find . -type f -print0 | du -ha --files0-from=- | LC_ALL='C' sort -rh | head -n $1
}

big_vids() {
    local count
    if [[ -n "$1" ]]; then
        count=$1
    else
        read -p "Enter the max number of results: " count
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
    read -p "Enter the image size (units in MB): " size
    find . -size +"$size"M -type f -iname "*.jpg" > "$random_dir/img-sizes.txt"
    sed -i "s/^..//g" "$random_dir/img-sizes.txt"
    sed -i "s|^|$PWD\/|g" "$random_dir/img-sizes.txt"
    echo
    nohup gnome-text-editor "$random_dir/img-sizes.txt" &>/dev/null &
}

##########################
## SORT IMAGES BY WIDTH ##
##########################

jpgs() {
    sudo find . -type f -iname "*.jpg" -exec identify -format " $PWD/%f: %wx%h " {} > /tmp/img-sizes.txt \;
    cat /tmp/img-sizes.txt | sed 's/\s\//\n\//g' | sort -h
    sudo rm /tmp/img-sizes.txt
}

###################################
## FFPROBE LIST IMAGE DIMENSIONS ##
###################################

ffp() {
    [[ -f 00-pic-sizes.txt ]] && sudo rm 00-pic-sizes.txt
    sudo find "$PWD" -type f -iname "*.jpg" -exec bash -c "identify -format '%wx%h' {}; echo {}" > 00-pic-sizes.txt \;
}

## List large files by type
large_files() {
    local choice
    clear

    if [[ -z "$1" ]]; then
        echo "Input the FILE extension to search for without a dot: "
        read -p "Enter your choice: " choice
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

## MediaInfo
mi() {
    local file

    if [[ -z "$1" ]]; then
        ls -1AhFv --color --group-directories-first
        echo
        read -p "Please enter the relative FILE path: " file
        echo
        mediainfo "$file"
    else
        mediainfo "$1"
    fi
}
