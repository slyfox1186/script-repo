#!/usr/bin/env bash

# ffmpeg_video_dicer.sh

concat_video_segments() {
    local video_path=$1
    local start=("${@:2:$(($#/2))}") # First half of arguments are 'starts'
    local stops=("${@:$(($#/2 + 2))}") # Second half of arguments are 'stops'

    local ext="${video_path##*.}"
    local output_name="$(basename "$video_path" ."$ext")-OUT.$ext"
    local tmp_dir=$(mktemp -d)

    echo "Temporary directory: $tmp_dir"
    local concat_file="$tmp_dir/filelist.txt"
    > "$concat_file"

    for i in "${!start[@]}"
    do
        local segment="$tmp_dir/segment$i.$ext"
        echo "Processing segment: $segment"
        ffmpeg -hide_banner -y -ss "${start[i]}" -to "${stops[i]}" -i "$video_path" -c copy "$segment"
        echo "file '$segment'" >> "$concat_file"
    done

    echo "Concatenation file list:"
    cat "$concat_file"

    echo "Concatenating to $output_name"
    ffmpeg -hide_banner -y -f concat -safe 0 -i "$concat_file" -c copy "$output_name"

    # Clean up temporary files
    rm -r "$tmp_dir"
}

# Video path and start/stop times
video_path='/path/to/video.mp4' # Replace with your actual video file path

# Each start variable on top corresponds with the stop variable directly below it.
# Add additional matching start and stop times as needed.
start=("00:02:00" "00:06:18")
stops=("00:04:10" "00:07:12")

concat_video_segments "$video_path" "${start[@]}" "${stops[@]}"
