#!/usr/bin/env bash

# Define usage function
usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "    -h, --help                Display this help message and exit."
    echo "    -b, --backup <path>       Specify a folder to backup the original files."
    echo "    -d, --dir <path>          Specify the working directory where images are located."
    echo "    -n, --dry-run             Perform a dry run without actually processing the images."
    echo "    -o, --overwrite           Enable overwrite mode. Original images will be overwritten."
    echo "    -r, --recursive           Enable recursive processing of subdirectories."
    echo "    -s, --size <dimensions>   Resize images to specified dimensions (e.g., 800x600)."
    echo "    -t, --type <type>         Specify file type to process (e.g., jpg, png, bmp)."
    echo "    -v, --verbose             Enable verbose output."
    echo
    echo "Example:"
    echo "    $0 -d pictures -s 1024x768 -b original_images -o  Overwrite and optimize images in 'pictures' directory with 1024x768 size and backup originals to 'original_images'."
}

# Initialize script options
backup_dir=""
dry_run=0
file_type="jpg"
overwrite_mode=0
recursive_mode=0
size=""
verbose_mode=0
working_dir="."

log() { [[ $verbose_mode -eq 1 ]] && echo "$@"; }

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)     usage; exit ;;
        -b|--backup)   backup_dir="$2"; shift 2 ;;
        -d|--dir)      working_dir="$2"; shift 2 ;;
        -n|--dry-run)  dry_run=1; shift ;;
        -o|--overwrite) overwrite_mode=1; shift ;;
        -r|--recursive) recursive_mode=1; shift ;;
        -s|--size)     size="$2"; shift 2 ;;
        -t|--type)     file_type="$2"; shift 2 ;;
        -v|--verbose)  verbose_mode=1; shift ;;
        *)             usage; exit 1 ;;
    esac
done

# Convert relative paths to absolute paths
working_dir="$(realpath "$working_dir")"
[[ -n "$backup_dir" ]] && backup_dir="$(realpath "$backup_dir")"

echo "Backup directory: $backup_dir"
echo "Dry run: $dry_run"
echo "File type: $file_type"
echo "Overwrite mode: $overwrite_mode"
echo "Recursive mode: $recursive_mode"
echo "Size: $size"
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
    local outfile="${base_name}-IM.${extension}"
    local outfile_name="${outfile##*/}"
    local backup_file="$backup_dir/${infile##*/}"

# Check if the file has already been processed
    if [[ "$infile" == *"-IM."* ]]; then
        echo "Skipping already processed file: $infile"
        return 0
    fi

    local convert_opts=(-filter Triangle -define filter:support=2
        -strip -unsharp 0.25x0.08+8.3+0.045 -dither None -posterize 136
        -quality 82 -define jpeg:fancy-upsampling=off -auto-level
        -enhance -interlace none -colorspace sRGB)
        
    [[ -n "$size" ]] && convert_opts+=(-resize "$size")
    
    if [[ $dry_run -eq 0 ]]; then
        [[ -n "$backup_dir" ]] && { mkdir -p "$backup_dir"; cp "$infile" "$backup_file"; }
        
        convert "$infile" "${convert_opts[@]}" -sampling-factor 2x2 -limit memory 0 -limit disk 0 -limit area 0 "$mpc_file" \
            || { log "Error: First attempt failed, retrying..."; convert "$infile" "${convert_opts[@]}" "$mpc_file"; } \
            || { log "Error: Second attempt failed."; return 1; }
            
        convert "$mpc_file" "$outfile" && echo "Processed: $outfile_name" || echo "Failed to process: $outfile_name"
        
        [[ $overwrite_mode -eq 1 ]] && rm -f "$infile"
        rm -fr "$temp_dir"
    else
        echo "Dry run: Skipping processing of $infile"
    fi
}

export -f process_image log
export backup_dir dry_run overwrite_mode size verbose_mode

# Determine number of parallel jobs and start processing
num_jobs=$(nproc --all)
echo; echo "Starting image processing with $num_jobs parallel jobs..."

# Get list of files and total count
if [[ $recursive_mode -eq 1 ]]; then
    file_list=$(find "$working_dir" -type f -name "*.$file_type" | sort -V)
else 
    file_list=$(find "$working_dir" -maxdepth 1 -type f -name "*.$file_type" | sort -V)
fi

# Process files in parallel
echo "$file_list" | parallel -j "$num_jobs" 'process_image {}'

echo "Image processing completed."
