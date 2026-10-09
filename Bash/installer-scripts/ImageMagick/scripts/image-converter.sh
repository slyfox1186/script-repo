#!/usr/bin/env bash

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ICON_SIZES="256,128,96,64,48,32,20,16"

output_dir="output"
quality=83
additional_args=""

display_help() {
    cat <<EOF
Purpose:
This script converts image files to various formats using ImageMagick.
It supports conversions between PNG, JPG, WEBP, JFIF, ICO, TIFF, BMP, and GIF formats.

Usage: $0 [options]

Options:
  -h, --help              Display the help menu
  -q, --quality [value]   Set the quality level (default is 83)
  -o, --output [dir]      Set the output directory (default is 'output')
  -a, --additional [args] Set additional command-line arguments for ImageMagick
EOF
}

check_dependencies() {
    local missing_deps=()
    for dep in convert identify; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

get_file_type() {
    identify -format '%m' "$1" 2>/dev/null | tr '[:upper:]' '[:lower:]'
}

convert_file() {
    local file="$1"
    local output_type="$2"
    local output_file="$3"
    local qual="$4"
    local extra_args="$5"

    echo -e "${GREEN}[INFO]${NC} Converting $file to $output_file"

    local result=0
    case "$output_type" in
        jpg|jfif|tiff|bmp|gif|png|webp)
            # shellcheck disable=SC2086
            convert "$file" -quality "$qual" $extra_args "$output_file" || result=$?
            ;;
        ico)
            # shellcheck disable=SC2086
            convert -background none "$file" -define icon:auto-resize="$ICON_SIZES" $extra_args "$output_file" || result=$?
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unsupported output format: $output_type"
            return 1
            ;;
    esac

    if [[ $result -eq 0 ]]; then
        echo -e "${GREEN}[INFO]${NC} Convert success: $file -> $output_file"
    else
        echo -e "${RED}[ERROR]${NC} Convert failed: $file -> $output_file"
        return 1
    fi
}

main() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help)       display_help; exit 0 ;;
            -q|--quality)    quality="$2"; shift ;;
            -o|--output)     output_dir="$2"; shift ;;
            -a|--additional) additional_args="$2"; shift ;;
            *)
                echo -e "${RED}[ERROR]${NC} Invalid option: $1"
                display_help
                exit 1
                ;;
        esac
        shift
    done

    check_dependencies

    mkdir -p "$output_dir"

    mapfile -t files < <(find . -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.webp" -o -iname "*.jfif" -o -iname "*.tiff" -o -iname "*.bmp" -o -iname "*.gif" \) ! -path "./$output_dir/*")

    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${RED}[ERROR]${NC} No supported input files found."
        exit 1
    fi

    echo "Found ${#files[@]} image(s). Select output file types (comma-separated, e.g., jpg,png,ico,tiff,bmp,gif,webp):"
    read -rp "Enter your choices: " output_choices
    IFS=',' read -ra output_types <<< "$output_choices"

    for output_type in "${output_types[@]}"; do
        case "$output_type" in
            jpg|png|ico|jfif|webp|tiff|bmp|gif) ;;
            *)
                echo -e "${RED}[ERROR]${NC} Invalid output type: $output_type"
                exit 1
                ;;
        esac
    done

    local fail_count=0
    for file in "${files[@]}"; do
        input_type=$(get_file_type "$file")
        for output_type in "${output_types[@]}"; do
            if [[ "$input_type" == "$output_type" ]]; then
                echo -e "${GREEN}[INFO]${NC} Skipping $file (already $output_type)"
                continue
            fi
            output_file="$output_dir/$(basename "${file%.*}").$output_type"
            convert_file "$file" "$output_type" "$output_file" "$quality" "$additional_args" || ((fail_count++))
        done
    done

    if [[ $fail_count -gt 0 ]]; then
        echo -e "${RED}[WARNING]${NC} $fail_count conversion(s) failed."
    fi

    echo
    read -rp "Do you want to delete the input files? [y/N]: " delete_choice
    if [[ "${delete_choice,,}" == "y" ]]; then
        rm -f "${files[@]}"
        echo -e "${GREEN}[INFO]${NC} Input files deleted."
    fi
}

main "$@"
