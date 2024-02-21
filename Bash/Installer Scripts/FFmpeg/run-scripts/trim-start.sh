#!/usr/bin/env bash

trim_video() {
    local input_file="$1"
    local temp_file="$(mktemp).mp4"
    local trim_time=18 # Set the trim amount in seconds

    echo "Processing file: $input_file"

    # Correctly trim the first $trim_time seconds without entering interactive mode
    if ffmpeg -y -loglevel 16 -hide_banner -ss "$trim_time" -i "$input_file" -c copy "$temp_file" 2>&1; then
        echo "Successfully trimmed: $input_file"
        mv "$temp_file" "$input_file"
        rm /tmp/tmp.*
    else
        echo "Error trimming: $input_file."
        rm /tmp/tmp.*
    fi
    echo
}

export -f trim_video

# Find all mp4 files and trim them
find ./ -type f -name "*.mp4" -exec bash -c 'trim_video "$0"' {} \;

echo "Completed processing files."
