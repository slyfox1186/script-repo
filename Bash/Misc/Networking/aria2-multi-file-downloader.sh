#!/usr/bin/env bash

set -euo pipefail

ext="mp4"

# Define arrays for paths, filenames, and URLs
# Fill these in before running
paths=(
    ""
    ""
)

filenames=(
    ""
    ""
)

urls=(
    ""
    ""
)

if [[ ${#paths[@]} -ne ${#filenames[@]} || ${#paths[@]} -ne ${#urls[@]} ]]; then
    echo "Error: paths, filenames, and urls arrays must have the same length." >&2
    exit 1
fi

if ! command -v aria2c &>/dev/null; then
    echo "Error: aria2c is not installed." >&2
    exit 1
fi

download_failed=false
for i in "${!paths[@]}"; do
    if [[ -z "${paths[i]}" || -z "${filenames[i]}" || -z "${urls[i]}" ]]; then
        echo "Warning: Skipping entry $i (empty path, filename, or URL)" >&2
        continue
    fi

    if [[ ! -d "${paths[i]}" ]]; then
        echo "Warning: Directory '${paths[i]}' does not exist, skipping." >&2
        download_failed=true
        continue
    fi

    echo "Downloading ${filenames[i]}.$ext to ${paths[i]}..."
    if ! aria2c --conf-path="$HOME/.aria2/aria2.conf" \
                --dir="${paths[i]}" \
                --out="${filenames[i]}.$ext" \
                "${urls[i]}"; then
        echo "Warning: Failed to download ${filenames[i]}.$ext" >&2
        download_failed=true
    fi
done

if [[ "$download_failed" == false ]]; then
    echo "Batch download completed successfully."
else
    echo "Batch download completed with errors." >&2
    exit 1
fi
