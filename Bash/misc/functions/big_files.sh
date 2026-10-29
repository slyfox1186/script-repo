#!/usr/bin/env bash

set -euo pipefail

# Display the N largest folders and files in the current directory
# Usage: big_files [count]   (default: 5)

big_files() (
    local num_results="${1-5}" record

    if [[ $# -gt 1 || ! "$num_results" =~ ^[1-9][0-9]*$ ]]; then
        echo "Usage: big_files [positive_number_of_results]" >&2
        return 1
    fi

    cd -P -- .
    echo "Largest Folders:"
    # Keep filenames intact and consume all sorted records to avoid SIGPIPE.
    du -h -d 1 --null -- "$PWD" | LC_ALL=C sort -zhr | sed -z -n "1,${num_results}p" |
    while IFS= read -r -d '' record; do
        printf "%-80s %10s\n" "${record#*$'\t'}" "${record%%$'\t'*}"
    done

    echo
    echo "Largest Files:"
    find "$PWD" -type f -print0 | du -h --null --files0-from=- |
    LC_ALL=C sort -zhr | sed -z -n "1,${num_results}p" |
    while IFS= read -r -d '' record; do
        printf "%-80s %10s\n" "${record#*$'\t'}" "${record%%$'\t'*}"
    done
)

big_files "$@"
