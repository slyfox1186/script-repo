#!/usr/bin/env bash

set -euo pipefail

# Video path and start/stop times
video_path="/path/to/video.mp4"

concat_video_segments() {
    local video_path="$1"
    shift

    if [[ $# -lt 2 || $(( $# % 2 )) -ne 0 ]]; then
        echo "Error: Must provide an equal number of start and stop times." >&2
        return 1
    fi

    local num_segments=$(( $# / 2 ))
    local starts=("${@:1:$num_segments}")
    local stops=("${@:$num_segments+1}")

    if [[ ! -f "$video_path" ]]; then
        echo "Error: Video file not found: $video_path" >&2
        return 1
    fi

    local ext="${video_path##*.}"
    local output_name="$(basename "$video_path" ."$ext")-OUT.$ext"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' RETURN

    local concat_file="$tmp_dir/filelist.txt"

    for i in "${!starts[@]}"; do
        local segment="$tmp_dir/segment${i}.$ext"
        echo "Processing segment $((i+1)): ${starts[i]} -> ${stops[i]}"
        ffmpeg -hide_banner -ss "${starts[i]}" -to "${stops[i]}" -i "$video_path" -c copy "$segment"
        echo "file '$segment'" >> "$concat_file"
    done

    echo "Concatenating ${#starts[@]} segments to $output_name"
    ffmpeg -hide_banner -f concat -safe 0 -i "$concat_file" -c copy "$output_name"
    echo "Done: $output_name"
}

# Each start time corresponds with the stop time at the same index.
start=("00:00:00" "00:04:07")
stops=("00:02:48" "00:22:37")

concat_video_segments "$video_path" "${start[@]}" "${stops[@]}"
