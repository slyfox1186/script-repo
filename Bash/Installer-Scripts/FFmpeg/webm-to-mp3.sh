#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if ! command -v ffmpeg &>/dev/null; then
    echo -e "${RED}ffmpeg could not be found. Please install ffmpeg first.${NC}"
    exit 1
fi

shopt -s nullglob
webm_files=(*.webm)
shopt -u nullglob

if [[ ${#webm_files[@]} -eq 0 ]]; then
    echo -e "${RED}No .webm files found in the current directory.${NC}"
    exit 1
fi

echo -e "${GREEN}Starting batch conversion of ${#webm_files[@]} webm file(s) to mp3...${NC}"

fail_count=0
for file in "${webm_files[@]}"; do
    newfile="${file%.webm}.mp3"
    echo "Converting $file to $newfile..."
    if ! ffmpeg -y -hide_banner -i "$file" -vn -q:a 0 -map a "$newfile"; then
        echo -e "${RED}Failed to convert: $file${NC}" >&2
        ((fail_count++))
    fi
done

if [[ $fail_count -gt 0 ]]; then
    echo -e "${RED}Batch conversion complete with $fail_count failure(s).${NC}"
    exit 1
else
    echo -e "${GREEN}Batch conversion complete. All files converted successfully.${NC}"
fi
