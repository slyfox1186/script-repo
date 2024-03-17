#!/Usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'

if ! command -v ffmpeg &> /dev/null; then
    echo -e "$REDffmpeg could not be found. Please install ffmpeg first.$NC"
    exit 1
fi

echo -e "$GREENStarting conversion of MVC 3D files to MV-HEVC...$NC"

for file in *.MTS; do
    if [ ! -f "$file" ]; then
        continue
    fi

    newfile="$file%.MTS.mp4"

    echo "Converting $file to $newfile..."
    ffmpeg -i "$file" -c:v libx265 -preset medium -x265-params crf=28 -c:a aac -b:a 128k "$newfile"
done

echo -e "$GREENConversion complete.$NC"
