#!/usr/bin/env bash

# Enhanced image processing script with adjusted overwrite feature and two-step conversion

# Define usage function
usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "    -d, --dir <path>                      Specify the working directory where images are located."
    echo "    -o, --overwrite                       Enable overwrite mode. Processed images will have '-IM' appended to their names."
    echo "    -m, --optimize                        Enable image optimization for web."
    echo "    -v, --verbose                         Enable verbose output."
    echo "    -h, --help                            Display this help message and exit."
    echo
    echo "Example:"
    echo "    $0 --overwrite --optimize -d pictures    Overwrite and optimize images in 'pictures' directory."
}

# Initialize variables
overwrite_mode=0
optimize_mode=0
verbose_mode=0
working_dir="."

# Parse command-line options
while [ "$1" != "" ]; do
    case "$1" in
        -d | --dir )        shift
                            working_dir="$1" ;;
        -o | --overwrite )  overwrite_mode=1 ;;
        -m | --optimize )   optimize_mode=1 ;;
        -v | --verbose )    verbose_mode=1 ;;
        -h | --help )       usage
                            exit ;;
        * )                 usage
                            exit 1 ;;
    esac
    shift
done

log() {
    if [[ $verbose_mode -eq 1 ]]; then
        echo "$@"
    fi
}

echo "Overwrite mode: $overwrite_mode"
echo "Optimize mode: $optimize_mode"
echo "Verbose mode: $verbose_mode"
echo "Working directory: $working_dir"

# Change to the specified working directory
cd "$working_dir" || { echo "Specified directory $working_dir does not exist. Exiting."; exit 1; }

process_image() {
    local infile="$1"
    local outfile="${infile%.*}-IM.jpg"

    local convert_base_opts=(
        -filter Triangle -define filter:support=2
        -thumbnail "$(identify -ping -format '%wx%h' "$infile")"
        -strip -unsharp 0.25x0.08+8.3+0.045 -dither None -posterize 136 -quality 82
        -define jpeg:fancy-upsampling=off -auto-level -enhance -interlace none
        -colorspace sRGB
    )

    if [[ $optimize_mode -eq 1 ]]; then
        convert_base_opts+=(-sampling-factor 4:2:0)
        convert_base_opts+=(-resize 800x800)
    fi

    # First attempt to process with full options
    if ! convert "$infile" "${convert_base_opts[@]}" -sampling-factor 2x2 -limit area 0 "$outfile"; then
        log "First attempt failed, retrying without '-sampling-factor 2x2 -limit area 0'..."
        # Retry without the specific options if the first attempt fails
        if ! convert "$infile" "${convert_base_opts[@]}" "$outfile"; then
            log "Error: Second attempt failed as well."
            return 1
        fi
    fi

    # Overwrite the original file if overwrite mode is enabled
    if [[ $overwrite_mode -eq 1 ]]; then
        mv "$outfile" "$infile"
    fi

    log "Finished processing: $infile, output: $outfile"
}

export -f process_image log

# Determine the number of parallel jobs and sort files numerically
num_jobs=$(nproc --all)
echo "Starting image processing with $num_jobs parallel jobs..."

find ./ -maxdepth 1 -type f -name "*.jpg" | sort -V | parallel -j "$num_jobs" process_image
