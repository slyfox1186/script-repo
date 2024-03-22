#!/usr/bin/env bash

# Required dependencies: imagemagick

# Color and logging setup
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}Converting images to ICONS...${NC}"

# Navigate to the script's directory
cd "$PWD"

# Sizes for the icon
SIZES="256,128,64,48,32,16"

# Cleanup old output directory and create a new one
[ -d "output" ] && rm -fr "output"
mkdir "output"

# Convert images
find ./ -type f \( -iname "*.jpg" -o -iname "*.png" \) -print0 |
while IFS= read -r -d $'\0' file; do
    filename="${file##*/}"          # Extracts the basename (filename.extension)
    filename_without_ext="${filename%.*}"  # Removes the extension
    output_path="Output/${filename_without_ext}.ico"

    convert -background none "$file" -define icon:auto-resize="$SIZES" "$output_path"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Convert success: ${file}${NC}"
    else
        echo -e "${RED}Convert failed: ${file}${NC}"
    fi
done
