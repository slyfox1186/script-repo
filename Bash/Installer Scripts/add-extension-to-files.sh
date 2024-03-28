#!/bin/bash

# Function to display the usage instructions
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "  -a <ext>    Extension to add to files (default: set in the script)"
    echo "  -s <ext>    Additional extension to skip (can be used multiple times)"
    echo "  -e <ext>    Additional extension to add (can be used multiple times)"
    echo "  -i <ext>    Extension to ignore (files with this extension will not be modified)"
    echo "  -r          Enable recursive searching in subdirectories"
    echo
    exit 1
}

# Default extension to add (can be overridden by command line argument)
DEFAULT_EXTENSION="sh"

# Arrays to store additional extensions to skip and add
SKIP_EXTENSIONS=()
ADD_EXTENSIONS=()
IGNORE_EXTENSION=""

# Flag to enable recursive searching
RECURSIVE=false

# Parse command line arguments
while getopts ":a:s:e:i:r" opt; do
    case $opt in
        a) DEFAULT_EXTENSION="$OPTARG";;
        s) SKIP_EXTENSIONS+=("$OPTARG");;
        e) ADD_EXTENSIONS+=("$OPTARG");;
        i) IGNORE_EXTENSION="$OPTARG";;
        r) RECURSIVE=true;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage;;
        :) echo "Option -$OPTARG requires an argument." >&2; usage;;
    esac
done

# Get the directory of the script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Function to process files in a directory
process_files() {
    local dir="$1"

    # Loop through all files in the directory
    for file in "$dir"/*; do
        # Check if the file is a regular file
        if [ -f "$file" ]; then
            # Get the file extension
            extension="${file##*.}"

            # Check if the file should be ignored based on the ignore extension
            if [ -n "$IGNORE_EXTENSION" ] && [ "$extension" == "$IGNORE_EXTENSION" ]; then
                continue
            fi

            # Check if the file already has the default extension or any of the additional extensions to skip
            if [ "$extension" == "$DEFAULT_EXTENSION" ] || [[ " ${SKIP_EXTENSIONS[@]} " =~ " $extension " ]]; then
                continue
            fi

            # Add the default extension and any additional extensions to the file
            new_filename="$file.$DEFAULT_EXTENSION"
            for ext in "${ADD_EXTENSIONS[@]}"; do
                new_filename="$new_filename.$ext"
            done

            # Rename the file with the new extension(s)
            mv "$file" "$new_filename"
            echo "Renamed $file to $new_filename"
        fi
    done
}

# Process files in the script directory
process_files "$SCRIPT_DIR"

# If recursive searching is enabled, process files in subdirectories
if [ "$RECURSIVE" = true ]; then
    # Loop through all subdirectories recursively
    while IFS= read -r -d '' subdir; do
        process_files "$subdir"
    done < <(find "$SCRIPT_DIR" -type d -print0)
fi
