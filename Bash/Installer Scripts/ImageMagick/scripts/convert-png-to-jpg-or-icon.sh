#!/bin/bash

# Function to display the help menu
display_help() {
    echo "Purpose:"
    echo "This script converts PNG files to optimized JPG files, ICO files, or both using ImageMagick."
    echo "It processes PNG files located in the same directory as the script and optionally in its subdirectories."
    echo
    echo "Usage: $0 [OPTION]"
    echo
    echo "Options:"
    echo "  -h, --help      Display this help menu"
    echo "  -r, --recurse   Recursively process PNG files in subdirectories"
    echo
    echo "Example:"
    echo "  $0              Convert PNG files in the current directory"
    echo "  $0 -r           Convert PNG files in the current directory and its subdirectories"
    echo "  $0 --help       Display the help menu"
}

# Function to convert PNG files to JPG
convert_png_to_jpg() {
    local file="$1"
    local filename=$(basename "$file" .png)
    local directory=$(dirname "$file")
    
    # Convert PNG to JPG using ImageMagick with optimization
    convert "$file" -quality 90 -colorspace RGB -strip "${directory}/${filename%.*}.jpg"
    
    printf "\n%s\n\n" "Converted $file to ${directory}/${filename%.*}.jpg"
}

# Function to convert PNG files to ICO
convert_png_to_ico() {
    local file="$1"
    local filename=$(basename "$file" .png)
    local directory=$(dirname "$file")
    
    # Convert PNG to ICO using ImageMagick
    convert -background none "$file" -define icon:auto-resize='256,128,64,48,32,16' "${directory}/${filename%.*}.ico"

    printf "\n%s\n\n" "Converted $file to ${directory}/${filename%.*}.ico"
}

# Function to process PNG files
process_png_files() {
    local directory="$1"
    local choice="$2"

    # Process PNG files in the given directory
    for file in "$directory"/*.png; do
        # Check if the file exists
        if [ -e "$file" ]; then
            if [[ "$choice" == "1" ]]; then
                convert_png_to_jpg "$file"
            elif [[ "$choice" == "2" ]]; then
                convert_png_to_ico "$file"
            elif [[ "$choice" == "3" ]]; then
                convert_png_to_jpg "$file"
                convert_png_to_ico "$file"
            else
                printf "\n%s\n\n" "Invalid choice. Skipping file: $file"
            fi
        fi
    done
}

# Check if the help option is provided
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    display_help
    exit 0
fi

# Prompt the user to choose the conversion option
echo "Select the conversion option:"
echo "1. Convert PNG to JPG only"
echo "2. Convert PNG to ICO only"
echo "3. Convert PNG to both JPG and ICO"
read -p "Enter your choice [1-3]: " choice

# Check if the recurse option is provided
if [[ "$1" == "-r" || "$1" == "--recurse" ]]; then
    # Recursively process PNG files in subdirectories
    while IFS= read -r -d '' directory; do
        process_png_files "$directory" "$choice"
    done < <(find . -type d -print0)
else
    # Process PNG files in the current directory
    process_png_files "." "$choice"
fi

# Prompt the user to delete the input PNG files
read -p "Do you want to delete the input PNG files? [y/N]: " delete_choice

if [[ "$delete_choice" =~ ^[Yy]$ ]]; then
    # Delete the input PNG files
    if [[ "$1" == "-r" || "$1" == "--recurse" ]]; then
        find . -type f -name "*.png" -delete
    else
        rm *.png
    fi
    printf "\n%s\n\n" "Input PNG files deleted."
else
    printf "\n%s\n\n" "Input PNG files not deleted."
fi
