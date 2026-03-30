#!/usr/bin/env bash

set -euo pipefail

output_dir="${YTDL_OUTPUT_DIR:-.}"
filename="$output_dir/%(title)s.%(ext)s"
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
format='bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4] / bv*+ba/b'
logfile='yt-dlp.log'

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <URL|batch_file.txt> [URL...]"
    echo "  Set YTDL_OUTPUT_DIR to change the download directory (default: current dir)"
    echo "  Set YTDL_FFMPEG to override the ffmpeg path"
    exit 1
fi

# Find ffmpeg
ff="${YTDL_FFMPEG:-}"
if [[ -z "$ff" ]]; then
    ff="$(command -v ffmpeg)" || { echo "Error: ffmpeg not found. Set YTDL_FFMPEG or install ffmpeg."; exit 1; }
fi

for cmd in aria2c yt-dlp; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is not installed."
        exit 1
    fi
done

mkdir -p "$output_dir"
rm -f "$logfile"

common_args=(
    --ffmpeg-location "$ff"
    --audio-quality 3
    -f "$format"
    --embed-thumbnail
    --windows-filenames
    --user-agent "$user_agent"
    --progress
    --abort-on-error
    --force-ipv4
    --no-cookies-from-browser
    --no-write-comments
    --continue
    --retry-sleep fragment:exp=1:20
    --downloader aria2c
)

if [[ "$1" =~ \.txt$ ]]; then
    if [[ ! -f "$1" ]]; then
        echo "Error: Batch file not found: $1"
        exit 1
    fi
    yt-dlp "${common_args[@]}" \
        --paths "$output_dir" \
        --print-traffic \
        --batch-file "$1" >> "$logfile"
else
    yt-dlp "${common_args[@]}" \
        --verbose \
        --print-traffic \
        -o "$filename" \
        "$@" >> "$logfile"
fi
