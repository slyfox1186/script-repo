#!/usr/bin/env bash

# Check and install the google_speech Python module if not already installed
if ! python3 -c "import google_speech" &>/dev/null; then
    echo "google_speech module not found. Installing..."
    pip3 install google_speech || { echo "Failed to install google_speech. Please install it manually."; exit 1; }
else
    echo "google_speech module is already installed."
fi

# Check if a specific parameter (e.g., --backup) is passed
backup_mode=0
for arg in "$@"; do
    if [[ "$arg" == "--backup" ]]; then
        backup_mode=1
        echo "Backup mode enabled. Original images will be backed up."
    fi
done

# Change directory to "pics-convert" if it exists, otherwise scan the script's directory
if [[ -d pics-convert ]]; then
    cd pics-convert
    echo "Changed directory to pics-convert."
else
    echo "Directory pics-convert does not exist. Using the script's current directory."
fi

process_image() {
    local infile="$1"
    local infile_name="${infile##*/}"
    local base_name="${infile_name%%.jpg}"

    # Check if the output file already exists
    local outfile="${infile%.*}-IM.jpg"
    if [[ -f "$outfile" ]]; then
        echo "Output file $outfile already exists. Skipping..."
        return 0
    fi

    local temp_dir="/tmp/$base_name_$(date +%s%N)_mpc"
    mkdir -p "$temp_dir"
    echo "Created temporary directory: $temp_dir"

    local mpc_file="$temp_dir/$base_name.mpc"
    local cache_file="$temp_dir/$base_name.cache"

    echo "Processing: $infile"

    if convert "$infile" \
            -filter Triangle -define filter:support=2 \
            -thumbnail $(identify -ping -format '%wx%h' "$infile") \
            -strip -unsharp "0.25x0.08+8.3+0.045" -dither None -posterize 136 -quality 82 \
            -define jpeg:fancy-upsampling=off -auto-level -enhance -interlace none \
            -colorspace sRGB "$mpc_file"; then
        if [[ $backup_mode -eq 1 ]]; then
            # Backup original file
            mv "$infile" "${infile}.backup"
            echo "Original image backed up as ${infile}.backup"
        else
            # Remove original file
            rm "$infile"
        fi
        convert "$mpc_file" "$outfile"
        echo "Finished processing: $infile, output: $outfile"
    else
        echo "Error: Failed to process the file: $infile"
        return 1
    fi

    rm -r "$temp_dir"
    printf "%s\n\n" "Cleaned up temporary directory: $temp_dir"
}

export -f process_image

# Determine the number of parallel jobs
num_jobs=$(nproc --all)
echo "Starting image processing with $num_jobs parallel jobs..."

if find . -maxdepth 1 -name "*.jpg" -type f | parallel -j $num_jobs process_image; then
    google_speech "Images successfully optimized."
else
    google_speech "Failed to optimize images."
fi
