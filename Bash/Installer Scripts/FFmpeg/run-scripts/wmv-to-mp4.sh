#!/usr/bin/env bash
# Recursively search and re-encode all found wmv files to mp4

printf "%s\n\n" "Searching for .wmv files to convert to .mp4 with NVIDIA CUDA acceleration..."

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

    # CUDA accelerated conversion
    if ffpb -y -hide_banner -hwaccel cuda -hwaccel_output_format cuda -fflags '+genpts' -i "$file_in" -c:v h264_nvenc -preset slow -c:a libfdk_aac "$file_out"; then
        printf "\n%s\n\n" "Conversion complete: $file_out"
        read -p "Do you want to delete the input WMV file (y/n)?: " choice
        case "$choice" in
            [yY]*) rm -f "$file_in" ;;
            [nN]*) ;;
        esac
    else
        echo "Conversion failed: $file_out"
    fi
}

export -f convert_to_mp4

# Find and convert all .wmv files
find "${BASH_SOURCE%/*}" -type f -iname "*.wmv" -exec bash -c 'convert_to_mp4 "$1"' _ {} \;
