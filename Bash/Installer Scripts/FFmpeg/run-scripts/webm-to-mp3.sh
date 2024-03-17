#!/Usr/bin/env bash

# Adding colorization for outputs
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No color

# Check if ffmpeg is installed
if ! command -v ffmpeg &> /dev/null; then
    echo -e "$REDffmpeg could not be found. Please install ffmpeg first.$NC"
    exit 1
fi

echo -e "$GREENStarting batch conversion of webm files to mp3...$NC"

for file in *.webm; do
# Skip if not a file
    if [ ! -f "$file" ]; then
        continue
    fi

# Constructing new file name with mp3 extension
    newfile="$file%.webm.mp3"

    echo "Converting $file to $newfile..."
    ffmpeg -i "$file" -vn -q:a 0 -map a "$newfile"
done

echo -e "$GREENBatch conversion complete.$NC"
