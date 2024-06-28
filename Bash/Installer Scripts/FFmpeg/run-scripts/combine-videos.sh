#!/usr/bin/env bash

set -e

# Set the output file name
output_file="combined.mp4"
temp_file=$(mktemp)
repaired_dir="repaired_videos"

# Create a directory for repaired videos
mkdir -p "$repaired_dir"

# Find all video files, sort them, and save the list to a temporary file
find ./ -maxdepth 1 -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.mkv" \) | sort -V > "$temp_file"

# Check if any video files were found
if [ ! -s "$temp_file" ]; then
    echo "No video files found in the current directory."
    rm "$temp_file"
    exit 1
fi

# Display found files for debugging
echo "Found video files:"
cat "$temp_file"

# Repair each video file
while IFS= read -r file; do
    base_name=$(basename "$file")
    echo "Repairing $base_name..."
    ffmpeg -hide_banner -y -i "$file" -c copy -bsf:v h264_mp4toannexb -f mp4 "$repaired_dir/repaired_$base_name" </dev/null
done < "$temp_file"

# Prepare the input file for FFmpeg, using repaired files
find "$repaired_dir" -type f -name "repaired_*.mp4" | sort -V | while IFS= read -r file; do
    printf "file '%s'\n" "$file"
done > ffmpeg_input.txt

# Display content of ffmpeg_input.txt for debugging
echo "Contents of ffmpeg_input.txt:"
cat ffmpeg_input.txt

# Combine videos using FFmpeg with codec copy
if ffmpeg -f concat -safe 0 -i ffmpeg_input.txt -c copy "$output_file" </dev/null; then
    echo "Videos combined successfully. Output file: $output_file"
else
    echo "Error occurred while combining videos."
    echo "FFmpeg input file contents:"
    cat ffmpeg_input.txt
fi

# Clean up temporary files and repaired videos
rm -fr "$temp_file" ffmpeg_input.txt "$repaired_dir"
