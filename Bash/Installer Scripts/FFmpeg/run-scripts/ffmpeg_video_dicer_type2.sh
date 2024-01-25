#!/usr/bin/env bash

concat_video_segments() {
    local video_path=$1
    local starts=("${@:2:$(($#/2))}") # First half of arguments are 'starts'
    local stops=("${@:$(($#/2 + 2))}") # Second half of arguments are 'stops'

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
    ffmpeg -hide_banner -y -f concat -safe 0 -i "$concat_file" -c copy "$PWD/$output_name"

    # Clean up temporary files
    rm -r "$tmp_dir"
}

START_TIMES=(
00:12:12 # PAIR 01
00:16:00 # PAIR 02
00:16:32 # ECT...
00:19:36
00:20:19
00:23:48
00:26:44
00:27:36
00:29:18
)
STOP_TIMES=(
00:14:51 # PAIR 01
00:16:28 # PAIR 02
00:17:12 # ECT...
00:20:14
00:20:42
00:26:37
00:27:31
00:29:10
00:30:27
)

# Video path and start/stop times
video_path='/path/to/video.mp4' # Replace with your actual video file path

concat_video_segments "$video_path" "${START_TIMES[@]}" "${STOP_TIMES[@]}"
