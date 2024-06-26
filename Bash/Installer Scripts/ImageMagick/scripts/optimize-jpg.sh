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

# Change and set ImageMagick's hard-coded limits
MAGICK_AREA_LIMIT="2GP"
MAGICK_DISK_LIMIT="128GiB"
MAGICK_FILE_LIMIT="1536"
MAGICK_HEIGHT_LIMIT="640MP"
MAGICK_WIDTH_LIMIT="640MP"
MAGICK_MAP_LIMIT="32GiB"
MAGICK_MEMORY_LIMIT="32GiB"
MAGICK_THREAD_LIMIT="128"
export MAGICK_AREA_LIMIT MAGICK_DISK_LIMIT MAGICK_FILE_LIMIT MAGICK_HEIGHT_LIMIT MAGICK_MAP_LIMIT MAGICK_MEMORY_LIMIT MAGICK_THREAD_LIMIT MAGICK_WIDTH_LIMIT

# Initialize script options
overwrite_mode=0
verbose_mode=0
working_dir="."

log() {
    if [[ $verbose_mode -eq 1 ]]; then
        echo "$@"
    fi
}

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

# Check for running processes and terminate them
for process in magick convert parallel; do
    if pgrep -x "$process" >/dev/null; then
        echo "Terminating running process: $process"
        sudo killall -9 "$process"
    fi
done

process_image() {
    infile="$1"
    local base_name="${infile%.*}"
    local extension="${infile##*.}"
    local temp_dir=$(mktemp -d)
    local mpc_file="$temp_dir/${base_name##*/}.mpc"
    local outfile="${base_name}-IM.${extension}"

    local convert_base_opts=(
        -filter Triangle -define filter:support=2
        -thumbnail "$(identify -ping -format '%wx%h' "$infile")"
        -strip -unsharp '0.25x0.08+8.3+0.045' -dither None -posterize 136 -quality 82
        -define jpeg:fancy-upsampling=off -auto-level -enhance -interlace none
        -colorspace sRGB
    )

    # First attempt to process with full options
    if ! convert "$infile" "${convert_base_opts[@]}" -sampling-factor 2x2 -limit area 0 "$mpc_file"; then
        [[ "$verbose_mode" -eq 1 ]] && log "First attempt failed, retrying without '-sampling-factor 2x2 -limit area 0'..."
        # Retry without the specific options if the first attempt fails
        if ! convert "$infile" "${convert_base_opts[@]}" "$mpc_file"; then
            [[ "$verbose_mode" -eq 1 ]] && log "Error: Second attempt failed as well."
            return 1
        fi
    fi

    # Final convert from MPC to output image
    if convert "$mpc_file" "$outfile"; then
        echo "Processed: $outfile"
    else
        echo "Failed to process: $outfile"
    fi

    # Cleanup
    if [[ "$overwrite_mode" -eq 1 ]]; then
        rm -f "$infile"
    fi

    rm -rf "$temp_dir"
}

export -f process_image
export overwrite_mode verbose_mode

# Determine the number of parallel jobs (maximum of 8)
num_jobs=$(( $(nproc --all) > 16 ? 16 : $(nproc --all) ))
echo "Starting image processing with $num_jobs parallel jobs..."

find "$working_dir" -maxdepth 1 -type f -name "*.jpg" ! -name "*-IM.jpg" | sort -V | parallel -j "$num_jobs" process_image
