#!/usr/bin/env bash

set -euo pipefail

# Recursively search and re-encode all found wmv files to mp4

printf "%s\n\n" "Searching for .wmv files to convert to .mp4 with NVIDIA CUDA acceleration..."

for cmd in ffpb; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is not installed."
        exit 1
    fi
done

convert_to_mp4() {
    local file_in="$1"
    local file_out="${file_in%.wmv}.mp4"

    local filename_in="${file_in##*/}"
    local filename_out="${file_out##*/}"
    local folder_path="${file_in%/*}"

    echo "Name in:  $filename_in"
    echo "Name out: $filename_out"
    echo
    echo "CWD:      ${folder_path}"
    echo

    if ffpb -y -hide_banner -hwaccel cuda -hwaccel_output_format cuda -fflags '+genpts' -i "$file_in" -c:v h264_nvenc -preset slow -c:a libfdk_aac "$file_out"; then
        printf "\n%s\n\n" "Conversion complete: $file_out"
        read -rp "Do you want to delete the input WMV file? (y/n): " choice
        case "$choice" in
            [yY]*) rm -f "$file_in" ;;
            [nN]*) ;;
        esac
    else
        echo "Conversion failed: $file_in" >&2
    fi
}

# Find and convert all .wmv files
while IFS= read -r -d '' wmv_file; do
    convert_to_mp4 "$wmv_file"
done < <(find . -type f -iname "*.wmv" -print0)
