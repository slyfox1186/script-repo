#!/usr/bin/env bash

# Default values
recursive=false
verbose=false
output_file=""
install_shellcheck=false
arg_exclusions=""
move_files=false
move_directory=""

# Shellcheck exclusion codes set in the script
# Add your shellcheck exclusion codes here
script_exclusions="SC2001,SC2034,SC2046,SC2068,SC2086,SC2115,SC2155,SC2162,SC2164,SC2295"

# Function to display the help menu
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help               Display this help menu"
    echo "  -d, --directory <dir>    Specify the working directory (default: script's directory)"
    echo "  -e, --exclusions <codes> Specify additional exclusion codes (comma-separated)"
    echo "  -i, --install            Install shellcheck if not already installed"
    echo "  -m, --move-files <dir>   Move files with no errors to the specified directory (full path required)"
    echo "  -o, --output <file>      Specify the output file for shellcheck results"
    echo "  -r, --recursive          Enable recursive searching"
    echo "  -v, --verbose            Enable verbose output"
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -d|--directory)
            cwd="$2"
            shift 2
            ;;
        -r|--recursive)
            recursive=true
            shift
            ;;
        -v|--verbose)
            verbose=true
            shift
            ;;
        -o|--output)
            output_file="$2"
            shift 2
            ;;
        -i|--install)
            install_shellcheck=true
            shift
            ;;
        -e|--exclusions)
            arg_exclusions="$2"
            shift 2
            ;;
        -m|--move-files)
            move_files=true
            move_directory="$2"
            if [[ "$move_directory" != /* ]]; then
                echo "Error: The move file argument requires a full path."
                exit 1
            fi
            shift 2
            ;;
        -h|--help)
            display_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            display_help
            exit 1
            ;;
    esac
done

# Set cwd to the script's directory if not specified
if [[ -z "$cwd" ]]; then
    cwd="$(pwd)"
fi

# Combine script exclusions and argument exclusions
exclusions="$script_exclusions"
if [[ -n "$arg_exclusions" ]]; then
    exclusions="$exclusions,$arg_exclusions"
fi

# Check if shellcheck is installed, and install if requested
if ! command -v shellcheck &>/dev/null; then
    if [[ "$install_shellcheck" = true ]]; then
        sudo apt-get -y install shellcheck
    else
        echo "Shellcheck is not installed. Use the -i or --install option to install it."
        exit 1
    fi
fi

# Ensure the working directory exists
if [[ ! -d "$cwd" ]]; then
    echo "Working directory does not exist: $cwd"
    exit 1
fi

# Function to print a separator line
print_separator() {
    echo
    echo "================================================================================"
}

# The script's basename for exclusion
script_name=$(basename "$0")

# Array to store files with no errors
no_error_files=()

# Execute shellcheck on a file
execute_shellcheck() {
    local file=$1
    if [[ "$verbose" = true ]]; then
        echo "Checking file: $file"
    fi
    
    local shellcheck_output
    shellcheck_output=$(shellcheck -e "$exclusions" "$file")
    
    # Check if shellcheck_output is not empty, indicating errors or warnings
    if [[ -n "$shellcheck_output" ]]; then
        if [[ -n "$output_file" ]]; then
            echo "Checking file: $file" >> "$output_file"
            echo "$shellcheck_output" >> "$output_file"
            print_separator >> "$output_file"
        else
            echo "Checking file: $file"
            echo "$shellcheck_output"
            print_separator
        fi
    else
        # Add the file to the no_error_files array
        no_error_files+=("$file")
    fi
}

# Run shellcheck on each file with specified exclusions, excluding this script
if [[ "$recursive" = true ]]; then
    while IFS= read -r -d $'\0' file; do
        execute_shellcheck "$file"
    done < <(find "$cwd" -type f \( -not -name '*.*' -o -name '*.sh' \) -not -name "$script_name" -print0 | sort -zV)
else
    while IFS= read -r -d $'\0' file; do
        execute_shellcheck "$file"
    done < <(find "$cwd" -maxdepth 1 -type f \( -not -name '*.*' -o -name '*.sh' \) -not -name "$script_name" -print0 | sort -zV)
fi

echo
echo "Shellcheck completed."

# Output files with no errors
if [[ ${#no_error_files[@]} -gt 0 ]]; then
    echo
    echo "Files with no errors:"
    for file in "${no_error_files[@]}"; do
        echo "$file"
    done
    
    # Move files with no errors to the specified directory if requested
    if [[ "$move_files" = true ]]; then
        if [[ -n "$move_directory" ]]; then
            mkdir -p "$move_directory"
            for file in "${no_error_files[@]}"; do
                mv -f "$file" "$move_directory"
            done
            echo
            echo "Files with no errors moved to: $move_directory"
        else
            echo
            echo "No directory specified to move files with no errors."
        fi
    fi
else
    echo
    echo "No files found with zero errors."
fi
