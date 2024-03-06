#!/usr/bin/env bash

# Define usage function
usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "    -d, --dir <path>                      Specify the working directory where images are located."
    echo "    -o, --overwrite                       Enable overwrite mode. Original images will be overwritten."
    echo "    -v, --verbose                         Enable verbose output."
    echo "    -n, --dry-run                         Perform a trial run with no changes made."
    echo "    -b, --backup <path>                   Enable backup mode and specify backup directory."
    echo "    -f, --format <format>                 Specify target image format for conversion (e.g., jpg, png)."
    echo "    -r, --recursive                       Enable recursive processing of directories."
    echo "    -h, --help                            Display this help message and exit."
    echo
    echo "Example:"
    echo "    $0 --overwrite --backup backups -d pictures --format png --recursive"
    echo "    Directly overwrite, backup, and convert images to PNG format in 'pictures' directory and its subdirectories."
}

# Initialize script options
overwrite_mode=0
verbose_mode=0
dry_run=0
backup_mode=0
backup_dir=""
target_format=""
recursive_mode=0
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
        -n | --dry-run )    dry_run=1 ;;
        -b | --backup )     backup_mode=1
                            shift
                            backup_dir="$1" ;;
        -f | --format )     shift
                            target_format="$1" ;;
        -r | --recursive )  recursive_mode=1 ;;
        -h | --help )       usage
                            exit ;;
        * )                 usage
                            exit 1 ;;
    esac
    shift
done

log "Overwrite mode: $overwrite_mode"
log "Verbose mode: $verbose_mode"
log "Dry run: $dry_run"
log "Backup mode: $backup_mode, Backup directory: $backup_dir"
log "Target format: $target_format"
log "Recursive mode: $recursive_mode"
log "Working directory: $working_dir"

# Backup function
backup_image() {
    if [[ $backup_mode -eq 1 && $backup_dir != "" ]]; then
        mkdir -p "$backup_dir"
        cp "$1" "$backup_dir"
        log "Backed up: $1 to $backup_dir"
    fi
}

process_image() {
    infile="$1"
    local base_name="${infile%.*}"
    local extension="${infile##*.}"
    local temp_dir=$(mktemp -d)
    local outfile_name
    if [[ $target_format != "" ]]; then
        outfile_name="${base_name##*/}.${target_format}"
    else
        outfile_name="${base_name##*/}.${extension}"
    fi
    local outfile="${base_name}-IM.${outfile_name##*.}"
    local mpc_file="$temp_dir/${outfile_name}.mpc"

    if [[ $dry_run -eq 1 ]]; then
        log "Dry run: Processing $infile would generate $outfile"
        return 0
    fi

    backup_image "$infile"

    local convert_base_opts=(
        -filter Triangle -define filter:support=2
        -thumbnail "$(identify -ping -format '%wx%h' "$infile")"
        -strip -unsharp 0.25x0.08+8.3+0.045 -dither None -posterize 136 -quality 82
        -define jpeg:fancy-upsampling=off -auto-level -enhance -interlace none
        -colorspace sRGB
    )

    if ! convert "$infile" "${convert_base_opts[@]}" -sampling-factor 2x2 -limit area 0 "$mpc_file"; then
        [[ "$verbose_mode" -eq 1 ]] && log "Error: First attempt failed, retrying without '-sampling-factor 2x2 -limit area 0'..."
        if ! convert "$infile" "${convert_base_opts[@]}" "$mpc_file"; then
            [[ "$verbose_mode" -eq 1 ]] && log "Error: Second attempt failed as well."
            return 1
        fi
    fi

    if convert "$mpc_file" "$outfile"; then
        echo "Processed: $outfile_name"
        if [[ $overwrite_mode -eq 1 ]]; then
            mv "$outfile" "$infile"
        fi
    else
        echo "Failed to process: $outfile_name"
    fi

    rm -fr "$temp_dir"
}

export -f backup_image
export -f log
export -f process_image
export overwrite_mode
export verbose_mode
export dry_run
export backup_mode
export backup_dir
export target_format

# Determine the number of parallel jobs
num_jobs=$(nproc --all)
log "Starting image processing with $num_jobs parallel jobs..."

if [[ $recursive_mode -eq 1 ]]; then
    find "$working_dir" -type f -name "*.jpg" | sort -V | parallel -j "$num_jobs" process_image
else
    find "$working_dir" -maxdepth 1 -type f -name "*.jpg" | sort -V | parallel -j "$num_jobs" process_image
fi
