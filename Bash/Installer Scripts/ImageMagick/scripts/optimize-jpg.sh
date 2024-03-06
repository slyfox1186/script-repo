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

log() {
    if [[ $verbose_mode -eq 1 ]]; then
        echo "$@"
    fi
}

# Parse command-line options
while [ "$1" != "" ]; do
    case "$1" in
        -d | --dir )        shift
                            if [[ -z "$1" || "$1" == -* ]]; then
                                echo "Error: --dir requires a path argument."
                                usage
                                exit 1
                            fi
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

# Verify the working directory exists
if [[ ! -d "$working_dir" ]]; then
    echo "Error: Specified directory $working_dir does not exist. Exiting."
    exit 1
fi

# Change to the specified working directory
cd "$working_dir" || exit 1

process_image() {
    # Processing logic remains the same
}

export -f process_image
export overwrite_mode
export verbose_mode

# Determine the number of parallel jobs
num_jobs=$(nproc --all)
echo "Starting image processing with $num_jobs parallel jobs..."

find "$working_dir" -maxdepth 1 -type f -name "*.jpg" -print0 | sort -Vz | parallel -j "$num_jobs" -0 process_image
