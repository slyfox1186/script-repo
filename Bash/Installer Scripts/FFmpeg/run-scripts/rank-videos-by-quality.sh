#!/usr/bin/env bash

# Function to display help
show_help() {
    echo "Usage: $0 [OPTION]... DIRECTORY"
    echo "Recursively searches the specified DIRECTORY for MP4 files and ranks them by video quality."
    echo
    echo "Options:"
    echo "  -d, --display-values  Include quality values in the output log."
    echo "  -h, --help            Display this help message and exit."
}

# Parse arguments
display_values=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--display-values)
            display_values=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            search_dir="$1"
            shift
            ;;
    esac
done

# Ensure the search directory is provided
if [[ -z "$search_dir" ]]; then
    show_help
    exit 1
fi

log_file="video_quality_log.txt"
declare -A video_qualities

# Function to get video quality
get_video_quality() {
    local video_file="$1"
    local width height bit_rate frame_rate codec quality codec_weight

    # Get video properties using ffprobe
    IFS=',' read -r codec width height frame_rate bit_rate <<< $(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate,bit_rate -of csv=p=0 "$video_file")

    # Calculate frame rate (it may be in the format "30000/1001")
    if [[ "$frame_rate" == */* ]]; then
        frame_rate=$(awk -F'/' '{if ($2 != 0) print $1/$2; else print 0}' <<< "$frame_rate")
    fi

    # Assign codec weights (example: H.264=1, H.265=1.5)
    codec_weight=1
    case "$codec" in
        h264) codec_weight=1 ;;
        hevc) codec_weight=1.5 ;;
        vp9) codec_weight=1.3 ;;
        av1) codec_weight=1.4 ;;
        *) codec_weight=1 ;;
    esac

    # Ensure all values are valid numbers
    width=${width:-0}
    height=${height:-0}
    bit_rate=${bit_rate:-0}
    frame_rate=${frame_rate:-1}

    # Calculate quality (considering frame rate and codec weight)
    quality=$(awk -v width="$width" -v height="$height" -v bit_rate="$bit_rate" -v frame_rate="$frame_rate" -v codec_weight="$codec_weight" 'BEGIN { print width * height * bit_rate * frame_rate * codec_weight }')
    # Convert quality to a whole integer
    quality=$(printf "%.0f" "$quality")

    echo "$quality"
}

# Recursively find all mp4 files and calculate their quality
while IFS= read -r -d '' file; do
    quality=$(get_video_quality "$file")
    video_qualities["$file"]=$quality
done < <(find "$search_dir" -type f -iname "*.mp4" -print0)

# Sort videos by quality (highest first)
sorted_videos=$(for file in "${!video_qualities[@]}"; do echo "${video_qualities[$file]} $file"; done | sort -g -r -k1)

# Write sorted video paths to log file
{
    echo "Video files sorted by quality (best to worst):"
    echo
    while IFS= read -r line; do
        quality=$(cut -d' ' -f1 <<< "$line")
        video=$(cut -d' ' -f2- <<< "$line")
        if [ "$display_values" = true ]; then
            echo "Weighted Rank: $quality Path: $video"
        else
            echo "Path: $video"
        fi
    done <<< "$sorted_videos"
} > "$log_file"

echo "Log file generated: $log_file"
