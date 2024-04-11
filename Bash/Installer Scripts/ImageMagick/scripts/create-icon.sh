#!/usr/bin/env bash

# Color and logging setup
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Converting images to icons.${NC}"

# Sizes for the icon
SIZES="256,128,64,48,32,16"

# Cleanup old output directory and create a new one
[[ -d "output" ]] && rm -fr "output"
mkdir "output"

# Convert images
find ./ -type f \( -iname "*.jpg" -o -iname "*.png" \) -print0 |
while IFS= read -r -d $'\0' file; do
    filename="${file##*/}"
    no_ext="${filename%.*}"
    outpath="Output/${no_ext}.ico"

    if convert -background none "$file" -define icon:auto-resize="$SIZES" "$outpath"; then
        echo -e "${GREEN}Convert success: ${file}${NC}"
    else
        echo -e "${RED}Convert failed: ${file}${NC}"
    fi
done

echo
read -p "Do you want to delete in input JPG and/or PNG file? (y/n): " choice
case "$choice" in
    [yY]*) sudo rm -f *.jpg *.png ;;
    [nN]*) ;;
esac
