#!/usr/bin/env bash

set -euo pipefail

# Display the N largest folders and files in the current directory
# Usage: big_files [count]   (default: 5)

big_files() {
    local num_results="${1:-5}"

    if ! [[ "$num_results" =~ ^[0-9]+$ ]]; then
        echo "Usage: big_files [number_of_results]" >&2
        return 1
    fi

    echo "Largest Folders:"
    du -h -d 1 2>/dev/null | sort -hr | head -n "$num_results" | while IFS=$'\t' read -r size folder; do
        printf "%-80s %10s\n" "$(realpath "$folder")" "$size"
    done

    echo
    echo "Largest Files:"
    find . -type f -exec du -h {} + 2>/dev/null | sort -hr | head -n "$num_results" | while IFS=$'\t' read -r size file; do
        printf "%-80s %10s\n" "$(realpath "$file")" "$size"
    done
}

big_files "${1:-5}"
