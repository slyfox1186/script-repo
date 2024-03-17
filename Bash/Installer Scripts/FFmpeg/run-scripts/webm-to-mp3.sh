#!/Usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'

if ! command -v ffmpeg &> /dev/null; then
    echo -e "$REDffmpeg could not be found. Please install ffmpeg first.$NC"
    exit 1
fi

echo -e "$GREENStarting batch conversion of webm files to mp3...$NC"

for file in *.webm; do
    if [ ! -f "$file" ]; then
        continue
    fi

    newfile="$file%.webm.mp3"

    echo "Converting $file to $newfile..."
    ffmpeg -i "$file" -vn -q:a 0 -map a "$newfile"
done

echo -e "$GREENBatch conversion complete.$NC"
