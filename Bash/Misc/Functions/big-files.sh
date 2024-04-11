#!/usr/bin/env bash

# Pass the number of folder/files you want to populate results for
# Example: To get the 5 largest folders and files in the directory execute: big_files 5

big_files() {
    local count

    if [[ -n "$1" ]]; then
        count=$1
    else
        read -p "Enter how many files to list in the results: " count
        echo
    fi

    echo "$count largest files"
    echo

    sudo find "$PWD" -type f -exec du -bh {} + | sort -hr | awk '
        function display_size(size, unit, path) {
            if (unit ~ /G$/) {
                printf("%s %s\n", size, path)
            } else if (unit ~ /M$/) {
                printf("%s MB %s\n", size, path)
            } else if (unit ~ /K$/) {
                printf("%s KB %s\n", size, path)
            } else {
                printf("%s %s %s\n", size, unit, path)
            }
        }

        {
            file_path = ""
            for (i = 3; i <= NF; i++) {
                file_path = file_path " " $i
            }
            display_size($1, $2, file_path)
        }
    ' | head -n"$count"

    echo
    echo "$count largest folders"
    echo

    sudo du -bh "$PWD" 2>/dev/null | sort -hr | awk '
        function display_size(size, unit, path) {
            if (unit ~ /G$/) {
                printf("%s %s\n", size, path)
            } else if (unit ~ /M$/) {
                printf("%s MB %s\n", size, path)
            } else if (unit ~ /K$/) {
                printf("%s KB %s\n", size, path)
            } else {
                printf("%s %s %s\n", size, unit, path)
            }
        }

        {
            display_size($1, $2, $3)
        }
    ' | head -n"$count"
}

big_files 5
