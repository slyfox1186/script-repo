#!/usr/bin/env bash

# Color setup
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Icon sizes
ICON_SIZES="256,128,96,64,48,32,20,16"

# Default values
output_dir="output"
quality=83
additional_args=""
max_file_size=0

# Function to display the help menu
display_help() {
    echo "Purpose:"
    echo "This script converts image files to various formats using ImageMagick."
    echo "It supports conversions between BMP, GIF, ICO, JPG, PNG, TIFF, and WEBP formats."
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -h, --help                    Display the help menu"
    echo "  -q, --quality <value>         Set the quality level (default is 83)"
    echo "  -o, --output <dir>            Set the output directory (default is 'output')"
    echo "  -a, --additional <args>       Set additional command-line arguments for ImageMagick"
    echo "  -m, --max-size <size>         Set the maximum output file size (e.g., 500KB or 1.5MB)"
}

# Function to check for required dependencies
check_dependencies() {
    local -a missing_deps=() dependencies=()
    dependencies=(convert identify)

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
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
    local quality="$4"
    local additional_args="$5"
    local max_size="$6"

    echo -e "${GREEN}[INFO]${NC} Converting $file to $output_file with quality $quality and additional args $additional_args"

    case "$output_type" in
        bmp|gif|jfif|jpg|png|tiff|webp)
            convert "$file" -quality "$quality" $additional_args "$output_file"
            ;;
        ico)
            convert -background none "$file" -define icon:auto-resize="$ICON_SIZES" $additional_args "$output_file"
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unsupported output format: $output_type"
            return 1
            ;;
    esac

    if [[ $? -eq 0 ]]; then
        # Check if the output file exceeds the max size
        if [[ "$max_size" -gt 0 ]]; then
            local file_size_kb
            file_size_kb=$(du -k "$output_file" | cut -f1)
            if [[ "$file_size_kb" -gt "$max_size" ]]; then
                echo -e "${RED}[ERROR]${NC} Output file exceeds the maximum size: $output_file"
                rm -f "$output_file"
                return 1
            fi
        fi
        echo -e "${GREEN}[INFO]${NC} Convert success: $file to $output_file"
        return 0
    else
        echo -e "${RED}[ERROR]${NC} Convert failed: $file to $output_file"
        return 1
    fi
}

# Main script
main() {
    # Parse arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -h|--help)
                display_help
                exit 0
                ;;
            -q|--quality)
                quality="$2"
                shift
                ;;
            -o|--output)
                output_dir="$2"
                shift
                ;;
            -a|--additional)
                additional_args="$2"
                shift
                ;;
            -m|--max-size)
                if [[ "$2" =~ MB$ ]]; then
                    max_file_size=$(echo "$2" | sed 's/MB$//;s/[[:space:]]//g')
                    max_file_size=$(echo "$max_file_size * 1024" | bc)
                else
                    max_file_size=$(echo "$2" | sed 's/KB$//;s/[[:space:]]//g')
                fi
                shift
                ;;
            *)
                echo -e "${RED}[ERROR]${NC} Invalid option: $1"
                display_help
                exit 1
                ;;
        esac
        shift
    done

    # Check for dependencies
    check_dependencies

    # Create output directory if it doesn't exist
    mkdir -p "$output_dir"

    # Determine input files
    mapfile -t files < <(find . -maxdepth 1 -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.webp" -o -name "*.jfif" -o -name "*.tiff" -o -name "*.bmp" -o -name "*.gif" \) ! -path "./$output_dir/*")

    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${RED}[ERROR]${NC} No supported input files found."
        exit 1
    fi

    # Prompt user for output file types
    echo "Select output file types (comma-separated, e.g., bmp,gif,ico,jpg,png,tiff,webp):"
    read -p "Enter your choices: " output_choices
    IFS=',' read -ra output_types <<< "$output_choices"

    # Validate output types
    for output_type in "${output_types[@]}"; do
        case "$output_type" in
            bmp|gif|ico|jfif|jpg|png|tiff|webp) ;;
            *)
                echo -e "${RED}[ERROR]${NC} Invalid output type: $output_type"
                exit 1
                ;;
        esac
    done

    # Convert files
    for file in "${files[@]}"; do
        input_type=$(get_file_type "$file")
        for output_type in "${output_types[@]}"; do
            if [[ "$input_type" == "$output_type" ]]; then
                echo -e "${GREEN}[INFO]${NC} Skipping conversion of $file to the same format."
                continue
            fi
            output_file="$output_dir/$(basename "${file%.*}").$output_type"
            convert_file "$file" "$output_type" "$output_file" "$quality" "$additional_args" "$max_file_size"
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
