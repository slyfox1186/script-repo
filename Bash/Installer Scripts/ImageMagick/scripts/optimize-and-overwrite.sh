#!/usr/bin/env bash

clear

# Define the output directory
output_dir="output"
# Check and create the output directory if it doesn't exist
[ ! -d "$output_dir" ] && mkdir "$output_dir"

# Export the output_dir to be accessible within the process_image function in parallel execution
export output_dir

# Define the function to process images
process_image() {
    local infile="$1"
    local infile_name=$(basename "$infile")

    # Create a unique directory in /tmp for the MPC file of this image
    local temp_dir="/tmp/${infile_name%%.jpg}_$(date +%s%N)_mpc"
    mkdir -p "$temp_dir"

    # Specify the path for the output MPC file and the final JPG file
    local outfile_mpc="${temp_dir}/${infile_name%%.jpg}.mpc"
    local outfile_jpg="${output_dir}/${infile_name%%.jpg}.jpg"

    echo "Processing: $infile"

    # Execute the convert command with the correct parameters and paths
    convert "$infile" -monitor -filter Triangle -define filter:support=2 \
            -thumbnail "$(identify -ping -format '%wx%h' "$infile")" \
            -strip -unsharp '0.25x0.08+8.3+0.045' -dither None -posterize 136 -quality 82 \
            -define jpeg:fancy-upsampling=off -auto-level -enhance -interlace none \
            -colorspace sRGB "$outfile_mpc"

    # Convert the MPC file back to a JPG file
    convert "$outfile_mpc" "$outfile_jpg"

    echo "Finished processing: $infile, output MPC: $outfile_mpc, output JPG: $outfile_jpg"

    # Cleanup: remove the temporary directory
    rm -r "$temp_dir"
    echo "Cleaned up temporary directory: $temp_dir"
}

# Export the function to make it accessible to parallel
export -f process_image

# Find .jpg files and process them in parallel
find . -maxdepth 1 -name '*.jpg' -type f | parallel process_image
