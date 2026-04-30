#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <input_video> [output_video]"
    echo "  If output_video is omitted, writes to <input_basename>_normalized.<ext>"
    exit 1
fi

input_video="$1"

if [[ ! -f "$input_video" ]]; then
    echo "Error: Input file not found: $input_video"
    exit 1
fi

if [[ $# -eq 2 ]]; then
    output_video="$2"
else
    base="${input_video%.*}"
    ext="${input_video##*.}"
    output_video="${base}_normalized.${ext}"
fi

# loudnorm filter parameters:
#   I=-23:  target integrated loudness in LUFS (broadcast standard)
#   LRA=7:  loudness range target in LU
#   TP=-2:  true peak target in dBTP (prevents clipping)
# -c:v copy copies the video stream without re-encoding
ffmpeg -i "$input_video" -c:v copy -af "loudnorm=I=-23:LRA=7:TP=-2" "$output_video"

echo "Normalized audio written to: $output_video"
