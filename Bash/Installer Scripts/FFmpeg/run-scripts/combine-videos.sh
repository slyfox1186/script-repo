#!/usr/bin/env bash

set -euo pipefail

output_file="combined.mp4"
repaired_dir="repaired_videos"

cleanup() {
    rm -f "$temp_file" ffmpeg_input.txt
    rm -rf "$repaired_dir"
}
trap cleanup EXIT

temp_file=$(mktemp)
mkdir -p "$repaired_dir"

# Find all video files, sort them
find ./ -maxdepth 1 -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.mkv" \) \
    ! -name "$output_file" | sort -V > "$temp_file"

if [[ ! -s "$temp_file" ]]; then
    echo "No video files found in the current directory."
    exit 1
fi

echo "Found video files:"
cat "$temp_file"

# Repair each video file
while IFS= read -r file; do
    base_name=$(basename "$file")
    echo "Repairing $base_name..."
    ffmpeg -hide_banner -y -i "$file" -c copy -bsf:v h264_mp4toannexb -f mp4 "$repaired_dir/repaired_$base_name" </dev/null
done < "$temp_file"

# Prepare the concat input file using repaired files
find "$repaired_dir" -type f -name "repaired_*.mp4" | sort -V | while IFS= read -r file; do
    printf "file '%s'\n" "$(realpath "$file")"
done > ffmpeg_input.txt

echo "Contents of ffmpeg_input.txt:"
cat ffmpeg_input.txt

if ffmpeg -f concat -safe 0 -i ffmpeg_input.txt -c copy "$output_file" </dev/null; then
    echo "Videos combined successfully. Output file: $output_file"
else
    echo "Error occurred while combining videos." >&2
    exit 1
fi
