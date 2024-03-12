#!/usr/bin/env bash

# Adding colorization for outputs
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Check if ffmpeg is installed
if ! command -v ffmpeg &> /dev/null; then
    echo -e "${RED}ffmpeg could not be found. Please install ffmpeg first.${NC}"
    exit 1
fi

echo -e "${GREEN}Starting conversion of MVC 3D files to MV-HEVC...${NC}"

for file in *.MTS; do
    # Skip if not a file
    if [ ! -f "$file" ]; then
        continue
    fi

    # Constructing new file name with mp4 extension
    newfile="${file%.MTS}.mp4"

    echo "Converting $file to $newfile..."
    ffmpeg -i "$file" -c:v libx265 -preset medium -x265-params crf=28 -c:a aac -b:a 128k "$newfile"
done

echo -e "${GREEN}Conversion complete.${NC}"
