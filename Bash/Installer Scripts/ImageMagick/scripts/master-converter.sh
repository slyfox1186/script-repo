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
    echo "This script converts image files to various formats using ImageMagick and ffmpeg."
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
    local dependencies=(ffmpeg convert)
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

# Function to convert image files
convert_files() {
    local input_type="$1"
    local output_types=("$@")
    output_types=("${output_types[@]:1}")
    
    local files=(*."$input_type")
    local convert_success=0
    local convert_fail=0
    
    for file in "${files[@]}"; do
        for output_type in "${output_types[@]}"; do
            local output_file="output/${file%.*}.$output_type"
            
            if [[ "$input_type" == "$output_type" ]]; then
                echo -e "${RED}[ERROR]${NC} Skipping conversion of $file to the same format."
                convert_fail=$((convert_fail + 1))
                continue
            fi
            
            case "$output_type" in
                jpg|jfif|tiff|bmp|gif)
                    convert "$file" -quality 90 -colorspace RGB -strip "$output_file"
                    ;;
                png|webp)
                    ffmpeg -y -i "$file" -vf "format=rgb24" -update 1 "$output_file"
                    ;;
                ico)
                    convert -background none "$file" -define icon:auto-resize="$ICON_SIZES" "$output_file"
                    ;;
                *)
                    echo -e "${RED}[ERROR]${NC} Unsupported output format: $output_type"
                    convert_fail=$((convert_fail + 1))
                    continue
                    ;;
            esac
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[INFO]${NC} Convert success: $file to $output_file"
                convert_success=$((convert_success + 1))
            else
                echo -e "${RED}[ERROR]${NC} Convert failed: $file to $output_file"
                convert_fail=$((convert_fail + 1))
            fi
        done
    done
    
    echo -e "${GREEN}[INFO]${NC} Conversion completed. Success: $convert_success, Failed: $convert_fail"
}

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
    mkdir -p output
    
    # Determine input file types
    local input_types=()
    [[ -n "$(ls *.png 2>/dev/null)" ]] && input_types+=("png")
    [[ -n "$(ls *.jpg 2>/dev/null)" ]] && input_types+=("jpg")
    [[ -n "$(ls *.webp 2>/dev/null)" ]] && input_types+=("webp")
    [[ -n "$(ls *.jfif 2>/dev/null)" ]] && input_types+=("jfif")
    [[ -n "$(ls *.tiff 2>/dev/null)" ]] && input_types+=("tiff")
    [[ -n "$(ls *.bmp 2>/dev/null)" ]] && input_types+=("bmp")
    [[ -n "$(ls *.gif 2>/dev/null)" ]] && input_types+=("gif")
    
    if [ ${#input_types[@]} -eq 0 ]; then
        echo -e "${RED}[ERROR]${NC} No supported input files found (PNG, JPG, WEBP, JFIF, TIFF, BMP, GIF)."
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
    
    # Convert files for each input type
    for input_type in "${input_types[@]}"; do
        convert_files "$input_type" "${output_types[@]}"
    done
    
    # Prompt to delete input files
    echo
    read -p "Do you want to delete the input files? [y/N]: " delete_choice
    if [[ "$delete_choice" =~ ^[Yy]$ ]]; then
        for input_type in "${input_types[@]}"; do
            rm *."$input_type"
        done
        echo -e "${GREEN}[INFO]${NC} Input files deleted."
    else
        echo -e "${GREEN}[INFO]${NC} Input files not deleted."
    fi
}

main "$@"
