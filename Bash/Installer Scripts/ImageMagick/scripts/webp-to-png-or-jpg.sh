#!/usr/bin/env bash

# Set colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Define logging functions
fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warn() {
    echo -e "${RED}[WARNING]${NC} $1"
}

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Check dependencies
dependencies=(ffmpeg convert)
missing_deps=()

for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        missing_deps+=("$dep")
    fi
done

if [ ${#missing_deps[@]} -gt 0 ]; then
    fail "Missing dependencies: ${missing_deps[*]}"
fi

# Change working directory to the script's directory
cd "$(dirname "$0")" || fail "Failed to change directory"

# Set variable for icon sizes
ICON_SIZES="16,20,32,48,64,96,128,256"

# Delete any leftover .ico files from previous runs
if ls *.ico >/dev/null 2>&1; then
    log "ICO file(s) found. Choose the next steps:"
    echo "1. Delete file(s)"
    echo "2. Keep file(s)"
    echo "3. Exit script"
    read -p "Enter your choice [1-3]: " choice
    case $choice in
        1) rm -f *.ico ;;
        2) ;;
        3) exit 0 ;;
        *) fail "Invalid choice. Exiting." ;;
    esac
fi

# Convert WEBP to PNG
for file in *.webp; do
    ffmpeg -y -hide_banner -i "$file" "${file%.*}.png" || warn "Failed to convert $file to PNG"
done

# Convert PNG to JPG
for file in *.png; do
    convert -colorspace sRGB -resize 256x256 -define jpeg:auto-resize="$ICON_SIZES" \
        "$file" "${file%.*}.jpg" || warn "Failed to convert $file to JPG"
done

echo
read -p "Do you want to delete in input webp file? (y/n): " choice
case "$choice" in
    [yY]*) sudo rm -f *.webp ;;
    [nN]*) ;;
esac
