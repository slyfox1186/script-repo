#!/usr/bin/env bash

# Capture the directory where the script is located
script_dir=$(dirname "$(realpath "$0")")

# Change the directory to "pics-convert"
cd pics-convert || { echo "Failed to change directory to pics-convert. Exiting..."; exit 1; }

# Define the output directory using the script's location
output_dir="$script_dir/output"
# Check and create the output directory if it doesn't exist
[[ ! -d "$output_dir" ]] && mkdir "$output_dir"

# Export the output_dir to be accessible within the process_image function in parallel execution
export output_dir

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
        echo "Finished processing: $infile, output: $outfile"
    else
        echo "Error: Failed to process the file: \"$infile\""
    fi

    # Cleanup: remove the temporary directory
    rm -r "$temp_dir"
    echo "Cleaned up temporary directory: $temp_dir."
}

# Export the function to make it accessible to parallel
export -f process_image

# Find .jpg files and process them in parallel
find . -maxdepth 1 -name "*.jpg" -type f | parallel process_image
