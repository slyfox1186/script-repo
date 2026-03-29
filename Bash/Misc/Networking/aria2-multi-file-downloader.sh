#!/usr/bin/env bash

# Extension for all files
ext="mp4"

# Define arrays for paths, filenames, and URLs
paths=(
    ""
    ""
)

# Define the arrays
filenames=(
    ""
    ""
)

urls=(
    ""
    ""
)

# Loop through the arrays
download_failed=false
for i in "${!paths[@]}"; do
    cd "${paths[i]}" || exit 1
    if ! aria2c --conf-path="$HOME/.aria2/aria2.conf" --out="${filenames[i]}.$ext" "${urls[i]}"; then
        download_failed=true
    fi
done

if [[ "$download_failed" == false ]]; then
    google_speech "Batch video download completed." &>/dev/null
else
    google_speech "Batch video download failed." &>/dev/null
fi
