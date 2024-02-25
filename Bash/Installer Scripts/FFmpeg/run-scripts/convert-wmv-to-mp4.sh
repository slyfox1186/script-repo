#!/usr/bin/env bash
# Recursively search and re-encode all found WMV files to MP4

echo "Searching for .wmv files to convert to .mp4 with NVIDIA CUDA acceleration..."
echo

# Define the conversion process as a function for clarity
convert_to_mp4() {
    local file_in="$1"
    local file_out="${file_in%.wmv}.mp4"

    local filename_in="${file_in##*/}"
    local filename_out="${file_out##*/}"
    local folder_path="${file_in%/*}"

    echo "Name in:  $filename_in"
    echo "Name out: $filename_out"
    echo
    echo "CWD:      $PWD/${folder_path//.\//}"
    echo

    if ffpb -y -hide_banner -hwaccel cuda -hwaccel_output_format cuda -fflags '+genpts' -i "$file_in" -c:v h264_nvenc -preset slow -c:a libfdk_aac "$file_out"; then
        echo "Conversion complete: $file_out"
        rm "$file_in"
    else
        echo "Conversion failed: $file_out"
    fi
    clear
}

export -f convert_to_mp4

# Find and convert all .wmv files
find "$(dirname "$0")" -type f -iname "*.wmv" -exec bash -c 'convert_to_mp4 "$0"' "{}" \;
