#!/usr/bin/env bash
clear

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
    if [[ $verbose_mode -eq 1 ]]; then
        echo -e "${GREEN}[LOG]${NC} $1"
    fi
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

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

log "Initialization complete."

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

log "Script configuration:"
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
        if cp "$1" "$backup_dir"; then
            log "Backed up: $1 to $backup_dir"
        else
            log_warning "Failed to backup: $1 to $backup_dir"
        fi
    fi
}

process_image() {
    infile="$1"
    local base_name="${infile%.*}"
    local extension="${infile##*.}"
    local temp_dir=$(mktemp -d)
    local outfile_name
    # Ensure outfile_name handles no extension correctly
    if [[ "$infile" == *.* ]]; then
        outfile_name="${base_name##*/}-IM.${target_format:-$extension}"
    else
        outfile_name="${infile}-IM"
    fi
    local mpc_file="$temp_dir/${outfile_name}.mpc"
    local outfile
    if [[ -n "$target_format" ]]; then
        outfile="${base_name}-IM.${target_format}"
    else
        outfile="${base_name}-IM.${extension}"
    fi

    if [[ $dry_run -eq 1 ]]; then
        log "Dry run: Processing $infile would generate $outfile"
        return 0
    fi

    backup_image "$infile"

    # First attempt to process with full options
    if ! convert "$infile" "${convert_base_opts[@]}" -sampling-factor 2x2 -limit area 0 "$mpc_file"; then
        log_warning "Error: First attempt failed, retrying without '-sampling-factor 2x2 -limit area 0'..."
        # Retry without the specific options if the first attempt fails
        if ! convert "$infile" "${convert_base_opts[@]}" "$mpc_file"; then
            log_error "Error: Second attempt failed as well."
            return 1
        fi
    fi

    # Final convert from MPC to output image
    if convert "$mpc_file" "$outfile"; then
        log "Processed: $outfile"
    else
        log_error "Failed to process: $outfile"
    fi

    # Cleanup
    if [[ "$overwrite_mode" -eq 1 ]]; then
        rm -f "$infile"
    fi

    rm -fr "$temp_dir"
}

export -f backup_image
export -f log
export -f log_warning
export -f log_error
export -f process_image
export overwrite_mode
export verbose_mode
export dry_run
export backup_mode
export backup_dir
export target_format
export recursive_mode
export RED
export GREEN
export YELLOW
export NC

# Determine the number of parallel jobs
num_jobs=$(nproc --all)
log "Starting image processing with $num_jobs parallel jobs..."

if [[ $recursive_mode -eq 1 ]]; then
    find "$working_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" \) | sort -V | parallel -j "$num_jobs" process_image
else
    find "$working_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" \) | sort -V | parallel -j "$num_jobs" process_image
fi
