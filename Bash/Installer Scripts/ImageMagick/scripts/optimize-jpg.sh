#!/usr/bin/env bash

# Define usage function
usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "    -b, --backup                         Enable backup mode. Original images will be backed up before processing."
    echo "    -d, --dir <path>                     Specify the working directory where images are located."
    echo "    -h, --help                           Display this help message and exit."
    echo
    echo "Example:"
    echo "    $0 --backup -d pictures   Process images in 'pictures' directory with backups of the originals."
}

# Parse command-line options
backup_mode=0
working_dir="."

while [ "$1" != "" ]; do
    case "$1" in
        -b | --backup )     backup_mode=1 ;;
        -d | --dir )        shift
                            working_dir="$1" ;;
        -h | --help )       usage
                            exit ;;
        * )                 usage
                            exit 1 ;;
    esac
    shift
done

echo "Backup mode: $backup_mode"
echo "Working directory: $working_dir"

# Check and install the google_speech Python module if not already installed
if ! python3 -c "import google_speech" &>/dev/null; then
    echo "google_speech module not found. Installing..."
    pip install --user google_speech || { echo "Failed to install google_speech. Please install it manually."; exit 1; }
else
    echo "google_speech module is already installed."
fi

# Check if GNU parallel is installed
if ! dpkg -s parallel &>/dev/null && ! which parallel &>/dev/null; then
    echo "GNU parallel is not installed. Installing..."
    sudo apt -y install parallel || { echo "Failed to install GNU parallel. Please install it manually."; exit 1; }
else
    echo "GNU parallel is already installed."
fi

# Change to the specified working directory
cd "$working_dir" || { echo "Specified directory $working_dir does not exist. Exiting."; exit 1; }

process_image() {
    local infile="$1"
    local infile_name="${infile##*/}"
    local base_name="${infile_name%%.jpg}"
    local backup_name="${infile%.*}_1.jpg"

    # Check if the output file already exists
    local outfile="${infile%.*}-IM.jpg"
    if [[ -f "$outfile" ]]; then
        echo "Output file $outfile already exists. Skipping..."
        return 0
    fi

    local temp_dir="/tmp/$base_name_$(date +%s%N)_mpc"
    mkdir -p "$temp_dir"
    echo
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
            # Backup original file with new naming scheme
            mv "$infile" "$backup_name"
            echo "Backup created: $backup_name"
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
    echo "Cleaned up temporary directory: $temp_dir"
}

export -f process_image

# Explicitly export backup_mode to make it available to subprocesses
export backup_mode

# Determine the number of parallel jobs
num_jobs=$(nproc --all)
echo "Starting image processing with $num_jobs parallel jobs..."

if find . -maxdepth 1 -name "*.jpg" -type f | parallel --env backup_mode -j $num_jobs process_image; then
    google_speech "Images successfully optimized."
else
    google_speech "Failed to optimize images."
fi
