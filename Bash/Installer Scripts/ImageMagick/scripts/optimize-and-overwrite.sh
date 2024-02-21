#!/usr/bin/env bash

# Change directory to "pics-convert" if it exists otherwise scan the script's directory
[[ -d pics-convert ]] && cd pics-convert

# Define the function to process images
process_image() {
    local infile="$1"
    # Use parameter expansion to extract the file name from the path
    local infile_name="${infile##*/}"
    local base_name="${infile_name%%.jpg}"

    # Create a unique directory in /tmp for the MPC file of this image
    local temp_dir="/tmp/$base_name_$(date +%s%N)_mpc"
    mkdir -p "$temp_dir"

    local mpc_file="$temp_dir/$base_name.mpc"
    local cache_file="$temp_dir/$base_name.cache"

    echo "Processing: $infile"

    # Convert the image to MPC to optimize processing
    if convert "$infile" \
            -filter Triangle -define filter:support=2 \
            -thumbnail "$(identify -ping -format '%wx%h' "$infile")" \
            -strip -unsharp "0.25x0.08+8.3+0.045" -dither None -posterize 136 -quality 82 \
            -define jpeg:fancy-upsampling=off -auto-level -enhance -interlace none \
            -colorspace sRGB "$mpc_file"; then
        # Append '-IM' to the filename before the .jpg extension and save it
        local outfile="${infile%.*}-IM.jpg"
        convert "$mpc_file" "$outfile"
        rm "$infile"
        echo "Finished processing: $infile, output: $outfile"
    else
        echo "Error: Failed to process the file: $infile"
    fi

    # Cleanup: remove the temporary directory
    rm -r "$temp_dir"
    echo "Cleaned up temporary directory: $temp_dir"
    echo
}

# Export the function to make it accessible to parallel
export -f process_image

# Find .jpg files and process them in parallel
if find . -maxdepth 1 -name "*.jpg" -type f | parallel -j $(nproc --all) process_image; then
    google_speech "Images successfully optimized."
else
    google_speech "Failed to optimize images."
fi
