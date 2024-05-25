#!/usr/bin/env bash

# Color setup
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Icon sizes
ICON_SIZES="256,128,96,64,48,32,20,16"

# Function to display the help menu
display_help() {
    echo "Purpose:"
    echo "This script converts image files to various formats using ImageMagick and GNU Parallel."
    echo "It supports conversions between PNG, JPG, WEBP, JFIF, ICO, TIFF, BMP, and GIF formats."
    echo
    echo "Usage: $0"
    echo
    echo "Example:"
    echo "  $0              Convert image files in the current directory"
    echo "  $0 --help       Display the help menu"
}

# Function to check for required dependencies
check_dependencies() {
    local dependencies=(parallel convert identify)
    local missing_deps=()
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}[ERROR]${NC} Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

# Function to determine file type
get_file_type() {
    identify -format '%m' "$1" | tr '[:upper:]' '[:lower:]'
}

# Function to convert image files
convert_file() {
    local file="$1"
    local output_type="$2"
    local output_file="$3"

    case "$output_type" in
        jpg|jfif|tiff|bmp|gif|png|webp)
            convert "$file" -quality 90 -strip "$output_file"
            ;;
        ico)
            convert -background none "$file" -define icon:auto-resize="$ICON_SIZES" "$output_file"
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unsupported output format: $output_type"
            return 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[INFO]${NC} Convert success: $file to $output_file"
        return 0
    else
        echo -e "${RED}[ERROR]${NC} Convert failed: $file to $output_file"
        return 1
    fi
}
export -f convert_file

# Main script
main() {
    # Check if help is requested
    if [[ "$1" == "--help" ]]; then
        display_help
        exit 0
    fi
    
    # Check for dependencies
    check_dependencies

    # Create output directory
    output_dir="output"
    mkdir -p "$output_dir"
    
    # Determine input files
    mapfile -t files < <(find . -type f -name "*.png" -o -name "*.jpg" -o -name "*.webp" -o -name "*.jfif" -o -name "*.tiff" -o -name "*.bmp" -o -name "*.gif")
    
    if [ ${#files[@]} -eq 0 ]; then
        echo -e "${RED}[ERROR]${NC} No supported input files found."
        exit 1
    fi
    
    # Prompt user for output file types
    echo "Select output file types (comma-separated, e.g., jpg,png,ico,tiff,bmp,gif):"
    read -p "Enter your choices: " output_choices
    IFS=',' read -ra output_types <<< "$output_choices"
    
    # Validate output types
    for output_type in "${output_types[@]}"; do
        case "$output_type" in
            jpg|png|ico|jfif|webp|tiff|bmp|gif) ;;
            *)
                echo -e "${RED}[ERROR]${NC} Invalid output type: $output_type"
                exit 1
                ;;
        esac
    done
    
    # Convert files using GNU Parallel
    for file in "${files[@]}"; do
        input_type=$(get_file_type "$file")
        for output_type in "${output_types[@]}"; do
            output_file="$output_dir/${file%.*}.$output_type"
            if [[ "$input_type" == "$output_type" ]]; then
                echo -e "${GREEN}[INFO]${NC} Skipping conversion of $file to the same format."
                continue
            fi
            parallel convert_file ::: "$file" ::: "$output_type" ::: "$output_file"
        done
    done
    
    # Prompt to delete input files
    echo
    read -p "Do you want to delete the input files? [y/N]: " delete_choice
    if [[ ${delete_choice,,} == "y" ]]; then
        rm -f "${files[@]}"
        echo -e "${GREEN}[INFO]${NC} Input files deleted."
    else
        echo -e "${GREEN}[INFO]${NC} Input files not deleted."
    fi
}

main "$@"
