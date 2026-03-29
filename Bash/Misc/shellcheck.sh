#!/usr/bin/env bash

# Default values
recursive=false
verbose=false
output_file=""
install_shellcheck=false
arg_exclusions=""
move_files=false
move_directory=""
show_summary=false
color_output=false

# Shellcheck exclusion codes set in the script
script_exclusions=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to display colored output
colored_echo() {
    if [[ "$color_output" = true ]]; then
        echo -e "$1$2${NC}"
    else
        echo "$2"
    fi
}

# Function to display the help menu
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo
    echo "  -h, --help                   Display this help menu"
    echo "  -c, --color                  Enable color output"
    echo "  -d, --directory <dir>        Specify the working directory (default: current directory)"
    echo "  -e, --exclusions <codes>     Specify additional exclusion codes (comma-separated)"
    echo "  -i, --install                Install shellcheck if not already installed"
    echo "  -m, --move-files <dir>       Move files with no errors to the specified directory (full path required)"
    echo "  -o, --output <file>          Specify the output file to store the shellcheck results"
    echo "  -r, --recursive              Enable recursive searching"
    echo "  -s, --summary                Show a summary of the shellcheck results"
    echo "  -v, --verbose                Enable verbose output"
}

# Function to install shellcheck based on the package manager
install_shellcheck() {
    local package_managers=("apt-get" "dnf" "yum" "pacman" "zypper")
    local package_manager_found=false

    for package_manager in "${package_managers[@]}"; do
        if command -v "$package_manager" &>/dev/null; then
            sudo "$package_manager" install -y shellcheck
            package_manager_found=true
            break
        fi
    done

    if [[ "$package_manager_found" = false ]]; then
        colored_echo "$RED" "Unsupported package manager. Please install shellcheck manually."
        exit 1
    fi
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
                colored_echo "$RED" "Error: The move file argument requires a full path."
                exit 1
            fi
            shift 2
            ;;
        -s|--summary)
            show_summary=true
            shift
            ;;
        -c|--color)
            color_output=true
            shift
            ;;
        -h|--help)
            display_help
            exit 0
            ;;
        *)
            colored_echo "$RED" "Unknown option: $1"
            display_help
            exit 1
            ;;
    esac
done

# Set cwd to the current directory if not specified
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
        install_shellcheck
    else
        colored_echo "$RED" "Shellcheck is not installed. Use the -i or --install option to install it."
        exit 1
    fi
fi

# Ensure the working directory exists
if [[ ! -d "$cwd" ]]; then
    colored_echo "$RED" "Working directory does not exist: $cwd"
    exit 1
fi

# Function to print a separator line
print_separator() {
    colored_echo "$BLUE" "================================================================================"
}

# The script's basename for exclusion
script_name=$(basename "$0")

# Arrays to store files with errors, warnings, and no errors
error_files=()
warning_files=()
no_error_files=()

# Execute shellcheck on a file
execute_shellcheck() {
    local file=$1
    if [[ "$verbose" = true ]]; then
        colored_echo "$YELLOW" "Checking file: $file"
    fi
    
    local shellcheck_output
    shellcheck_output=$(shellcheck -f gcc -e "$exclusions" "$file")
    
    if [[ -n "$shellcheck_output" ]]; then
        if echo "$shellcheck_output" | grep -q 'error:'; then
            error_files+=("$file")
        else
            warning_files+=("$file")
        fi
        
        if [[ -n "$output_file" ]]; then
            echo "Checking file: $file" >> "$output_file"
            echo "$shellcheck_output" >> "$output_file"
            print_separator >> "$output_file"
        else
            colored_echo "$YELLOW" "Checking file: $file"
            echo "$shellcheck_output"
            print_separator
        fi
    else
        no_error_files+=("$file")
    fi
}

# Run shellcheck on each file with specified exclusions, excluding this script
if [[ "$recursive" = true ]]; then
    while IFS= read -r -d $'\0' file; do
        execute_shellcheck "$file"
    done < <(find "$cwd" -type f \( -name '*.sh' -o -name '*.bash' \) -not -name "$script_name" -print0 | sort -zV)
else
    while IFS= read -r -d $'\0' file; do
        execute_shellcheck "$file"
    done < <(find "$cwd" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.bash' \) -not -name "$script_name" -print0 | sort -zV)
fi

echo
colored_echo "$GREEN" "Shellcheck completed."

# Output files with no errors
if [[ ${#no_error_files[@]} -gt 0 ]]; then
    echo
    colored_echo "$GREEN" "Files with no errors:"
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
            colored_echo "$GREEN" "Files with no errors moved to: $move_directory"
        else
            echo
            colored_echo "$RED" "No directory specified to move files with no errors."
        fi
    fi
else
    echo
    colored_echo "$RED" "No files found with zero errors."
fi

# Show summary if requested
if [[ "$show_summary" = true ]]; then
    total_files=$((${#error_files[@]} + ${#warning_files[@]} + ${#no_error_files[@]}))
    echo
    echo "Summary:"
    echo "Total files checked: $total_files"
    
    colored_echo "$RED" "Files with errors: ${#error_files[@]}"
    for file in "${error_files[@]}"; do
        echo "  - $file"
    done
    
    colored_echo "$YELLOW" "Files with warnings: ${#warning_files[@]}"
    for file in "${warning_files[@]}"; do
        echo "  - $file"
    done
    
    colored_echo "$GREEN" "Files with no errors: ${#no_error_files[@]}"
    for file in "${no_error_files[@]}"; do
        echo "  - $file"
    done
fi
