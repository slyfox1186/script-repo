#!/usr/bin/env bash

set -euo pipefail

display_help() {
    cat <<EOF
Usage: $0 [options]
Options:
  -h, --help           Display this help menu
  -i, --input          Input video path (full or relative)
  -o, --output         Output video path (full or relative)
  -t, --target-size    Target size in megabytes (MB) (default: 500)
  --original-size      Original size in megabytes (MB) (default: 1000)
  -a, --audio-rate     Audio bitrate in kilobits per second (kbps) (default: 128)
  -d, --duration       Duration in seconds (default: 3600)
  -l, --log-file       Log file path (default: resize.log)
EOF
}

# Default values
target_size_mb=1500
original_size_mb=2480
audio_bitrate_kbps=128
duration_seconds=1410
log_file="resize.log"
input_file=""
output_file=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)       display_help; exit 0 ;;
        -i|--input)      input_file="$2"; shift 2 ;;
        -o|--output)     output_file="$2"; shift 2 ;;
        -t|--target-size) target_size_mb="$2"; shift 2 ;;
        --original-size) original_size_mb="$2"; shift 2 ;;
        -a|--audio-rate) audio_bitrate_kbps="$2"; shift 2 ;;
        -d|--duration)   duration_seconds="$2"; shift 2 ;;
        -l|--log-file)   log_file="$2"; shift 2 ;;
        *)               echo "Unknown parameter: $1"; display_help; exit 1 ;;
    esac
done

# Prompt for missing required values
if [[ -z "$input_file" ]]; then
    read -rp "Enter the input video path: " input_file
fi
if [[ -z "$output_file" ]]; then
    read -rp "Enter the output video path: " output_file
fi

echo "Confirmed Values:"
echo "  Input File: $input_file"
echo "  Output File: $output_file"
echo "  Target Size (MB): $target_size_mb"
echo "  Original Size (MB): $original_size_mb"
echo "  Audio Bitrate (kbps): $audio_bitrate_kbps"
echo "  Duration (seconds): $duration_seconds"
echo "  Log File: $log_file"
echo

if [[ ! -f "$input_file" ]]; then
    echo "Input file does not exist: $input_file" >&2
    exit 1
fi

if [[ $target_size_mb -le 0 || $original_size_mb -le 0 || $audio_bitrate_kbps -le 0 || $duration_seconds -le 0 ]]; then
    echo "Invalid argument values. Please provide positive numbers." >&2
    exit 1
fi

get_video_stats() {
    local video_file="$1"

    local size_mb audio_bitrate video_bitrate

    size_mb=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "$video_file" | awk '{printf "%.2f", $1 / 1024 / 1024}')
    audio_bitrate=$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null | awk '{printf "%d", $1 / 1000}')
    video_bitrate=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null | awk '{printf "%d", $1 / 1000}')

    # Default to 0 if probing failed
    echo "${size_mb:-0} ${audio_bitrate:-0} ${video_bitrate:-0}"
}

read -r size_mb audio_bitrate video_bitrate <<< "$(get_video_stats "$input_file")"

if [[ "$audio_bitrate" -eq 0 || "$video_bitrate" -eq 0 ]]; then
    echo "Warning: Could not detect bitrates from input file. Using defaults." >&2
    [[ "$audio_bitrate" -eq 0 ]] && audio_bitrate="$audio_bitrate_kbps"
    [[ "$video_bitrate" -eq 0 ]] && video_bitrate=2000
fi

total_bitrate_kbps=$((audio_bitrate + video_bitrate))
target_total_bitrate_kbps=$(echo "scale=0; $total_bitrate_kbps * $target_size_mb / $size_mb" | bc)
target_video_bitrate_kbps=$(( target_total_bitrate_kbps - audio_bitrate_kbps ))

if [[ $target_video_bitrate_kbps -le 0 ]]; then
    echo "Calculated video bitrate is negative. Adjusting to minimum feasible value."
    target_video_bitrate_kbps=100
fi

echo "Input Video Stats:"
echo "  Size: ${size_mb} MB"
echo "  Audio Bitrate: ${audio_bitrate} kbps"
echo "  Video Bitrate: ${video_bitrate} kbps"
echo
echo "Target Video Stats:"
echo "  Size: ${target_size_mb} MB"
echo "  Audio Bitrate: ${audio_bitrate_kbps} kbps"
echo "  Video Bitrate: ${target_video_bitrate_kbps} kbps"
echo

size_diff_percent=$(echo "scale=2; (($target_size_mb - $size_mb) / $size_mb) * 100" | bc)
audio_diff_percent=$(echo "scale=2; (($audio_bitrate_kbps - $audio_bitrate) / $audio_bitrate) * 100" | bc)
video_diff_percent=$(echo "scale=2; (($target_video_bitrate_kbps - $video_bitrate) / $video_bitrate) * 100" | bc)

echo "Percentage Differences:"
echo "  Size: ${size_diff_percent}%"
echo "  Audio Bitrate: ${audio_diff_percent}%"
echo "  Video Bitrate: ${video_diff_percent}%"
echo

read -rp "Do you want to proceed with the FFmpeg processing? (y/n): " confirmation

if [[ "$confirmation" =~ ^[Yy]$ ]]; then
    echo -e "\nFFmpeg Command:\n"
    echo "ffmpeg -i \"$input_file\" -b:v ${target_video_bitrate_kbps}k -b:a ${audio_bitrate_kbps}k -t $duration_seconds \"$output_file\""
    echo

    echo "Resizing video..."
    echo
    ffmpeg -i "$input_file" \
        -b:v "${target_video_bitrate_kbps}k" \
        -b:a "${audio_bitrate_kbps}k" \
        -t "$duration_seconds" \
        "$output_file" 2>&1 | tee "$log_file"
    echo "Video resizing completed. Log file: $log_file"
else
    echo "FFmpeg processing aborted."
    exit 0
fi
