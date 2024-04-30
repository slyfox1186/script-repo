#!/usr/bin/env bash

# Set the time in seconds to trim from the start of the video
secs=18

# Function to trim the first 18 seconds of an MP4 file using ffmpeg
trim_video() {
    input_file="$1"
    output_file="${input_file%.*}_trimmed.mp4"

    if ffmpeg -i "$input_file" -ss "$secs" -c copy "$output_file"; then
        mv "$output_file" "$input_file"
        echo "Successfully trimmed: $input_file"
    else
        echo "Error trimming: $input_file"
        exit 1
    fi
}

if [[ -n "$1" ]]; then
    in_file="$1"
else
    in_file=$(find . -maxdepth 1 -type f -name "*.mp4")
fi

# Get the absolute path of the provided argument
video_path=$(realpath "$in_file")

# Check if the provided path is a file or directory
if [[ -f "$video_path" ]]; then
    # If it's a file, process the single video file
    trim_video "$video_path"
elif [[ -d "$video_path" ]]; then
    # If it's a directory, recursively search for MP4 files in the directory and its subfolders
    find "$video_path" -type f -name "*.mp4" | while read -r file; do
        trim_video "$file"
    done
else
    echo "Invalid path: $video_path"
    exit 1
fi
