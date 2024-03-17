#!/Usr/bin/env bash


concat_video_segments() {
    local video_path=$1

    local output_name="$(basename "$video_path" ."$ext")-OUT.$ext"
    local tmp_dir=$(mktemp -d)

    echo "Temporary directory: $tmp_dir"
    local concat_file="$tmp_dir/filelist.txt"
    > "$concat_file"

    for i in "${!start[@]}"
    do
        local segment="$tmp_dir/segment$i.$ext"
        echo "Processing segment: $segment"
        ffmpeg -hide_banner -ss "$start[i]" -to "$stops[i]" -i "$video_path" -c copy "$segment"
        echo "file '$segment'" >> "$concat_file"
    done

    echo "Concatenation file list:"
    cat "$concat_file"

    echo "Concatenating to $output_name"
    ffmpeg -hide_banner -f concat -safe 0 -i "$concat_file" -c copy "$output_name"

    rm -r "$tmp_dir"
}


start=("00:02:00" "00:06:18")
stops=("00:04:10" "00:07:12")

concat_video_segments "$video_path" "${start[@]}" "${stops[@]}"
