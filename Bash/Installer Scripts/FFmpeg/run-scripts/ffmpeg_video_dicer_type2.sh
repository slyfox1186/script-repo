#!/usr/bin/env bash

concat_video_segments() {
    local video_path=$1
    local starts=("$2")
    local stops=("$3")

    local ext="${video_path##*.}"
    local output_name="$(basename "$video_path" ."$ext")-OUT.$ext"
    local tmp_dir=$(mktemp -d)

    echo "Temporary directory: $tmp_dir"
    local concat_file="$tmp_dir/filelist.txt"
    > "$concat_file"

    for i in "${!starts[@]}"
    do
        local segment="$tmp_dir/segment$i.$ext"
        echo "Processing segment: $segment"
        ffmpeg -hide_banner -y -ss "${starts[i]}" -to "${stops[i]}" -i "$video_path" -c copy "$segment"
        echo "file '$segment'" >> "$concat_file"
    done

    echo "Concatenation file list:"
    cat "$concat_file"

    echo "Concatenating to $output_name"
    ffmpeg -hide_banner -y -f concat -safe 0 -i "$concat_file" -c copy "$output_name"

    # Clean up temporary files
    rm -r "$tmp_dir"
}

START_TIMES=(
00:12:12
00:16:00
00:16:32
)
STOP_TIMES=(
00:14:51
00:16:28
00:17:12
)

# Video path and start/stop times
video_path='/path/to/video.mp4' # Replace with your actual video file path

concat_video_segments "$video_path" "${START_TIMES[@]}" "${STOP_TIMES[@]}"
