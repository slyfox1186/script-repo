#!/usr/bin/env bash

# Define usage function
usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "    -d, --dir <path>                      Specify the working directory where images are located."
    echo "    -o, --overwrite                       Enable overwrite mode. Original images will be overwritten."
    echo "    -v, --verbose                         Enable verbose output."
    echo "    -h, --help                            Display this help message and exit."
    echo
    echo "Example:"
    echo "    $0 --overwrite -d pictures            Directly overwrite and optimize images in 'pictures' directory."
}

# Initialize script options
overwrite_mode=0
verbose_mode=0
working_dir="."

# Parse command-line options
while [ "$1" != "" ]; do
    case "$1" in
        -d | --dir )        shift
                            working_dir="$1" ;;
        -o | --overwrite )  overwrite_mode=1 ;;
        -v | --verbose )    verbose_mode=1 ;;
        -h | --help )       usage
                            exit ;;
        * )                 usage
                            exit 1 ;;
    esac
    shift
done

echo "Overwrite mode: $overwrite_mode"
echo "Verbose mode: $verbose_mode"
echo "Working directory: $working_dir"

# Change to the specified working directory
cd "$working_dir" || { echo "Specified directory $working_dir does not exist. Exiting."; exit 1; }

process_image() {
    local infile="$1"
    local base_name="${infile%.*}"
    local extension="${infile##*.}"
    local temp_dir=$(mktemp -d)
    local mpc_file="$temp_dir/${base_name##*/}.mpc"
    local outfile

    # Set outfile based on overwrite mode
    if [[ $overwrite_mode -eq 1 ]]; then
        outfile="${base_name}-IM.${extension}"
    else
        outfile="${base_name}-IM.${extension}"
    fi

    # Execute convert command with attempt to include '-sampling-factor 2x2 -limit area 0'
    if ! convert "$infile" \
            -filter Triangle -define filter:support=2 \
            -thumbnail $(identify -ping -format '%wx%h' "$infile") \
            -strip -unsharp "0.25x0.08+8.3+0.045" -dither None -posterize 136 -quality 82 \
            -define jpeg:fancy-upsampling=off -auto-level -enhance -interlace none \
            -colorspace sRGB -sampling-factor 2x2 -limit area 0 "$mpc_file"; then
        # Fallback convert without '-sampling-factor 2x2 -limit area 0' upon failure
        convert "$infile" \
                -filter Triangle -define filter:support=2 \
                -thumbnail $(identify -ping -format '%wx%h' "$infile") \
                -strip -unsharp "0.25x0.08+8.3+0.045" -dither None -posterize 136 -quality 82 \
                -define jpeg:fancy-upsampling=off -auto-level -enhance -interlace none \
                -colorspace sRGB "$mpc_file"
    fi

    # Final convert from MPC to output image
    convert "$mpc_file" "$outfile"
    
    # Handle overwrite logic
    if [[ $overwrite_mode -eq 1 ]]; then
        mv -f "$outfile" "$infile"
        echo "Overwritten: $infile"
    else
        echo "Processed: $outfile"
    fi

    # Cleanup
    rm -rf "$temp_dir"
}

export -f process_image

# Determine the number of parallel jobs
num_jobs=$(nproc --all)
echo "Starting image processing with $num_jobs parallel jobs..."

find "$working_dir" -maxdepth 1 -type f -name "*.jpg" | sort -V | parallel -j "$num_jobs" process_image
