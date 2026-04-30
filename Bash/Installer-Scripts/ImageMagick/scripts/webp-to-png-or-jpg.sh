#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

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
for dep in ffmpeg convert; do
    if ! command -v "$dep" &>/dev/null; then
        fail "Missing dependency: $dep"
    fi
done

cd "$(dirname "$0")" || fail "Failed to change directory"

ICON_SIZES="16,20,32,48,64,96,128,256"

# Handle leftover .ico files
shopt -s nullglob
ico_files=(*.ico)
shopt -u nullglob

if [[ ${#ico_files[@]} -gt 0 ]]; then
    log "ICO file(s) found. Choose the next steps:"
    echo "1. Delete file(s)"
    echo "2. Keep file(s)"
    echo "3. Exit script"
    read -rp "Enter your choice [1-3]: " choice
    case "$choice" in
        1) rm -f "${ico_files[@]}" ;;
        2) ;;
        3) exit 0 ;;
        *) fail "Invalid choice. Exiting." ;;
    esac
fi

# Convert WEBP to PNG
shopt -s nullglob
webp_files=(*.webp)
shopt -u nullglob

if [[ ${#webp_files[@]} -eq 0 ]]; then
    fail "No .webp files found in $(pwd)"
fi

for file in "${webp_files[@]}"; do
    ffmpeg -y -hide_banner -i "$file" "${file%.*}.png" || warn "Failed to convert $file to PNG"
done

# Convert PNG to JPG
shopt -s nullglob
png_files=(*.png)
shopt -u nullglob

for file in "${png_files[@]}"; do
    convert -colorspace sRGB -resize 256x256 -define jpeg:auto-resize="$ICON_SIZES" \
        "$file" "${file%.*}.jpg" || warn "Failed to convert $file to JPG"
done

echo
read -rp "Do you want to delete the input webp files? (y/n): " choice
case "$choice" in
    [yY]*) rm -f "${webp_files[@]}" ;;
    [nN]*) ;;
esac
